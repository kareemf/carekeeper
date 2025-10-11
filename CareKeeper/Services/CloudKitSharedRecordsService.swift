import SwiftUI
import SwiftUI
import SwiftData
import CloudKit

/// Service for managing shared CloudKit records using AcceptedShare tracking
/// This approach works around SwiftData sharing limitations by tracking accepted shares
/// and fetching their root records from CloudKit's shared database
@MainActor
class CloudKitSharedRecordsService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    
    @Published var sharedCarees: [Caree] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var modelContext: ModelContext?
    
    /// Set the model context for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        setupNotificationObservers()
    }
    
    /// Setup notification observers for share acceptance
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShareAcceptedForTracking"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let shareRecordID = userInfo["shareRecordID"] as? CKRecord.ID,
                  let rootRecordID = userInfo["rootRecordID"] as? CKRecord.ID else {
                print("❌ Invalid share acceptance notification")
                return
            }
            
            let shareTitle = userInfo["shareTitle"] as? String
            print("🔔 Received share acceptance notification for tracking")
            self?.trackAcceptedShare(shareRecordID: shareRecordID, rootRecordID: rootRecordID, shareTitle: shareTitle)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitNotificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let ckNotification = notification.object as? CKNotification {
                print("🔔 Processing CloudKit notification in shared records service")
                Task {
                    await self?.handleCloudKitNotification(ckNotification)
                }
            }
        }
    }
    
    private func handleCloudKitNotification(_ notification: CKNotification) async {
        print("📨 Processing CloudKit notification: \(notification.notificationType)")

        switch notification.notificationType {
        case .database:
            await handleDatabaseNotification(notification as! CKDatabaseNotification)
        case .query:
            await handleQueryNotification(notification as! CKQueryNotification)
        case .recordZone:
            await handleRecordZoneNotification(notification as! CKRecordZoneNotification)
        default:
            print("⚠️ Unhandled notification type: \(notification.notificationType)")
        }

        // Refresh shared carees after any CloudKit change
        await fetchSharedCarees()
    }

    /// Handle database-level notifications (shared database changes)
    private func handleDatabaseNotification(_ notification: CKDatabaseNotification) async {
        print("🔄 Database notification - databaseScope: \(notification.databaseScope)")

        if notification.databaseScope == .shared {
            print("📤 Shared database changed - likely new share accepted")
            // The fetchSharedCarees call at the end of handleCloudKitNotification will handle this
        }
    }

    /// Handle query notifications (share record changes)
    /// This provides proactive cleanup when shares are deleted by the owner
    private func handleQueryNotification(_ notification: CKQueryNotification) async {
        guard let recordID = notification.recordID else {
            print("⚠️ Query notification without record ID")
            return
        }

        print("🔍 Query notification - recordID: \(recordID), reason: \(notification.queryNotificationReason)")

        switch notification.queryNotificationReason {
        case .recordCreated:
            print("➕ Share record created: \(recordID)")
        case .recordDeleted:
            print("🗑️ Share record deleted: \(recordID)")
            // Proactively remove from tracking - don't wait for fetch to fail
            removeAcceptedShare(shareRecordID: recordID)
        case .recordUpdated:
            print("✏️ Share record updated: \(recordID)")
        @unknown default:
            print("❓ Unknown query notification reason")
        }
    }

    /// Handle record zone notifications
    private func handleRecordZoneNotification(_ notification: CKRecordZoneNotification) async {
        print("🏷️ Record zone notification - zoneID: \(notification.recordZoneID?.zoneName ?? "unknown")")
        // Generally handled by database notifications, but can provide more specific info
    }
    
    /// Fetch shared Caree records by:
    /// 1. Querying AcceptedShare table for tracked shares
    /// 2. Fetching the actual records from CloudKit shared database
    /// 3. Converting them to temporary Caree objects
    func fetchSharedCarees() async {
        await MainActor.run { 
            isLoading = true
            error = nil
        }
        
        guard let modelContext = modelContext else {
            await MainActor.run {
                self.error = NSError(domain: "CloudKitSharedRecordsService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
                self.isLoading = false
            }
            return
        }
        
        do {
            // Step 1: Get all accepted shares from SwiftData
            let descriptor = FetchDescriptor<AcceptedShare>(
                sortBy: [SortDescriptor(\AcceptedShare.dateAccepted, order: .reverse)]
            )
            let acceptedShares = try modelContext.fetch(descriptor)
            
            print("📱 Found \(acceptedShares.count) tracked accepted shares")
            
            if acceptedShares.isEmpty {
                await MainActor.run {
                    self.sharedCarees = []
                    self.isLoading = false
                }
                return
            }
            
            // Step 2: Fetch the actual records from CloudKit shared database
            let sharedRecords = try await fetchSharedRecords(for: acceptedShares)
            
            // Step 3: Convert to temporary Caree objects
            let carees = try await convertRecordsToCarees(sharedRecords)
            
            await MainActor.run {
                self.sharedCarees = carees
                self.isLoading = false
                print("✅ Successfully fetched \(carees.count) shared carees")
            }
            
            // Step 4: Clean up orphaned AcceptedShare records
            await cleanupOrphanedShares(acceptedShares: acceptedShares, fetchedRecords: sharedRecords, modelContext: modelContext)
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
                print("❌ Failed to fetch shared carees: \(error)")
            }
        }
    }
    
    /// Fetch actual CloudKit records from shared database using AcceptedShare tracking
    private func fetchSharedRecords(for acceptedShares: [AcceptedShare]) async throws -> [CKRecord] {
        let sharedDatabase = container.sharedCloudDatabase
        let recordIDs = acceptedShares.map { $0.ckRootRecordID }
        
        var records: [CKRecord] = []
        
        // Fetch records in batches to avoid CloudKit limits
        let batchSize = 400 // CloudKit limit is typically 400 records per operation
        for batchStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, recordIDs.count)
            let batchIDs = Array(recordIDs[batchStart..<batchEnd])
            
            let results = try await sharedDatabase.records(for: batchIDs)
            
            for (recordID, result) in results {
                switch result {
                case .success(let record):
                    if record.recordType == "CD_Caree" {
                        records.append(record)
                    }
                case .failure(let error):
                    print("⚠️ Failed to fetch shared record \(recordID): \(error)")
                    // Don't throw here - just log and continue with other records
                }
            }
        }
        
        return records
    }
    
    /// Convert CloudKit records to temporary Caree objects for display
    private func convertRecordsToCarees(_ records: [CKRecord]) async throws -> [Caree] {
        var carees: [Caree] = []
        
        for record in records {
            // Extract data from CloudKit record
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["name"] as? String else {
                print("⚠️ Skipping record with missing required fields: \(record.recordID)")
                continue
            }
            
            // Create a temporary Caree object (not persisted in SwiftData)
            let caree = Caree(
                name: name,
                listOrder: record["listOrder"] as? Int ?? 0
            )
            caree.id = uuid
            
            // Set other properties if they exist
            if let imageAsset = record["image"] as? CKAsset,
               let imageURL = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageURL) {
                caree.image = imageData
            }
            
            if let dateCreated = record["dateCreated"] as? Date {
                caree.dateCreated = dateCreated
            }
            
            carees.append(caree)
        }
        
        return carees.sorted { $0.listOrder < $1.listOrder }
    }
    
    /// Clean up AcceptedShare records whose corresponding CloudKit records no longer exist
    /// This handles cases where shares were revoked or deleted by the owner
    private func cleanupOrphanedShares(acceptedShares: [AcceptedShare], fetchedRecords: [CKRecord], modelContext: ModelContext) async {
        let fetchedRecordIDs = Set(fetchedRecords.map { $0.recordID.storageString })
        
        for acceptedShare in acceptedShares {
            if !fetchedRecordIDs.contains(acceptedShare.rootRecordID) {
                print("🧹 Cleaning up orphaned AcceptedShare: \(acceptedShare.rootRecordID)")
                modelContext.delete(acceptedShare)
            }
        }
        
        // Save changes if any orphaned records were removed
        if modelContext.hasChanges {
            do {
                try modelContext.save()
                print("✅ Cleaned up orphaned AcceptedShare records")
            } catch {
                print("❌ Failed to save AcceptedShare cleanup: \(error)")
            }
        }
    }
    
    // MARK: - Share Tracking Methods
    
    /// Track when a share is accepted (to be called from CloudKit notifications)
    func trackAcceptedShare(shareRecordID: CKRecord.ID, rootRecordID: CKRecord.ID, shareTitle: String? = nil) {
        guard let modelContext = modelContext else {
            print("❌ Cannot track share: Model context not set")
            return
        }
        
        // Capture the value outside the macro to avoid predicate expression issues
        let shareIDString = shareRecordID.storageString
        
        // Check if we already have this share tracked
        let predicate = #Predicate<AcceptedShare> { share in
            share.shareRecordID == shareIDString
        }
        let descriptor = FetchDescriptor<AcceptedShare>(predicate: predicate)
        
        do {
            let existing = try modelContext.fetch(descriptor)
            if !existing.isEmpty {
                print("📝 Share already tracked: \(rootRecordID.recordName)")
                return
            }
            
            // Create new AcceptedShare record
            let acceptedShare = AcceptedShare(
                shareRecordID: shareIDString,
                rootRecordID: rootRecordID.storageString,
                shareTitle: shareTitle
            )
            
            modelContext.insert(acceptedShare)
            try modelContext.save()
            
            print("✅ Tracked new accepted share: \(rootRecordID.recordName)")
            
            // Refresh shared carees to include the new one
            Task {
                await fetchSharedCarees()
            }
            
        } catch {
            print("❌ Failed to track accepted share: \(error)")
        }
    }
    
    /// Remove tracking when a share is no longer available
    func removeAcceptedShare(shareRecordID: CKRecord.ID) {
        guard let modelContext = modelContext else {
            print("❌ Cannot remove share: Model context not set")
            return
        }
        
        let shareIDString = shareRecordID.storageString
        
        let predicate = #Predicate<AcceptedShare> { share in
            share.shareRecordID == shareIDString
        }
        let descriptor = FetchDescriptor<AcceptedShare>(predicate: predicate)
        
        do {
            let shares = try modelContext.fetch(descriptor)
            for share in shares {
                modelContext.delete(share)
            }
            
            if !shares.isEmpty {
                try modelContext.save()
                print("✅ Removed tracked share: \(shareRecordID.recordName)")
                
                // Refresh shared carees to remove the deleted one
                Task {
                    await fetchSharedCarees()
                }
            }
        } catch {
            print("❌ Failed to remove accepted share: \(error)")
        }
    }
    
    /// Get count of tracked shares (for debugging/info purposes)
    var trackedSharesCount: Int {
        guard let modelContext = modelContext else { return 0 }
        
        do {
            let descriptor = FetchDescriptor<AcceptedShare>()
            return try modelContext.fetch(descriptor).count
        } catch {
            return 0
        }
    }
}
