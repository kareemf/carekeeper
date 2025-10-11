import SwiftUI
import SwiftData
import CloudKit

@MainActor
class CloudKitSharingService: ObservableObject {
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let logger = AppLogger.sharing
    private let parentReferenceService: CloudKitParentReferenceService

    init(containerIdentifier: String = CloudKitConfig.containerID) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
        self.parentReferenceService = CloudKitParentReferenceService(containerIdentifier: containerIdentifier)
    }

    // MARK: - Share Status

    /// Get the CKShare for a Caree by checking if the record has a share reference
    func getShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare? {
        // First, find the actual CloudKit record for this Caree
        guard let careeCKRecord = try await findCKRecord(for: caree) else {
            return nil // Record not found, not an error - just means not synced yet
        }
        
        // Check if the record has a share reference
        guard let shareReference = careeCKRecord.share else {
            // Record is not shared
            return nil
        }
        
        do {
            // Fetch the actual share record
            let shareRecord = try await container.privateCloudDatabase.record(for: shareReference.recordID)
            return shareRecord as? CKShare
        } catch {
            logger.error("Failed to fetch share record: \(error.localizedDescription)")
            throw error
        }
    }

    func isShared(_ caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            return try await getShare(for: caree, in: modelContext) != nil
        } catch {
            logger.error("Failed to check share status: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Create Share

    /// Create a new CKShare for the Caree's CloudKit record
    func createOrGetShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare {
        // Check if share already exists
        if let existingShare = try await getShare(for: caree, in: modelContext) {
            return existingShare
        }
        
        // Find the CloudKit record for this Caree
        guard let careeCKRecord = try await findCKRecord(for: caree) else {
            throw AppError.invalidInput("Caree not found in CloudKit. Make sure it's synced first.")
        }

        // Log record details for diagnostics
        logger.info("🔍 Creating share for Caree record:")
        logger.info("   RecordID: \(careeCKRecord.recordID.recordName)")
        logger.info("   Parent: \(String(describing: careeCKRecord.parent?.recordID.recordName ?? "nil"))")
        logger.info("   Share: \(String(describing: careeCKRecord.share?.recordID.recordName ?? "nil"))")
        logger.info("   Record type: \(careeCKRecord.recordType)")

        // Query for child records to verify they exist
        await logChildRecords(for: caree)

        // CRITICAL FIX: Ensure parent references are set before creating share
        // SwiftData doesn't automatically set CKRecord.parent for cascade relationships
        // Without parent references, child records won't be included in the share
        logger.info("🔧 Fixing parent references before creating share...")
        try await parentReferenceService.ensureParentReferences(for: caree)

        // Verify fix was successful
        let (activityTypes, activities, missing) = try await parentReferenceService.verifyParentReferences(for: caree)
        if missing > 0 {
            logger.warning("⚠️ Warning: \(missing) child records still missing parent references")
        } else {
            logger.info("✅ All \(activityTypes + activities) child records have correct parent references")
        }

        // Create a new share
        let share = CKShare(rootRecord: careeCKRecord)
        share[CKShare.SystemFieldKey.title] = caree.name
        share.publicPermission = .none
        
        do {
            // Save both the updated root record and the share
            let recordsToSave = [careeCKRecord, share]
            let saveResults = try await container.privateCloudDatabase.modifyRecords(
                saving: recordsToSave,
                deleting: []
            )
            
            // Check if save was successful
            if let shareResult = saveResults.saveResults[share.recordID],
               case .success(let savedShare) = shareResult,
               let finalShare = savedShare as? CKShare {
                return finalShare
            } else {
                throw AppError.invalidInput("Failed to save share to CloudKit")
            }
        } catch {
            logger.error("Failed to create share: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Permission Checks

    func isOwner(of share: CKShare) -> Bool {
        return share.owner == share.currentUserParticipant
    }

    func canDelete(caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            guard let share = try await getShare(for: caree, in: modelContext) else {
                // No share means user owns it locally
                return true
            }
            return isOwner(of: share)
        } catch {
            logger.error("Failed to determine delete permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Share Management

    func stopSharing(caree: Caree, in modelContext: ModelContext) async throws {
        // To stop sharing, delete the share from the owner's private database.
        guard let share = try await getShare(for: caree, in: modelContext) else {
            return // Not shared
        }

        // Only the owner can stop sharing; callers should check, but we enforce as well.
        guard isOwner(of: share) else {
            throw AppError.invalidInput("Only the owner can stop sharing this item.")
        }

        do {
            try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        } catch {
            logger.error("Failed to delete share: \(error.localizedDescription)")
            throw error
        }
    }

    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) async throws {
        guard participant != share.owner else {
            throw AppError.invalidInput("Cannot remove the owner from a share")
        }

        // Remove the participant from the share
        share.removeParticipant(participant)

        // Save the updated share to the owner's private database
        do {
            _ = try await container.privateCloudDatabase.save(share)
        } catch {
            logger.error("Failed to save share: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchParticipants(for share: CKShare) -> [CKShare.Participant] {
        return share.participants.filter { $0 != share.owner }
    }

    // MARK: - Share URL

    func getShareURL(for share: CKShare) -> URL? {
        return share.url
    }

    // MARK: - Auto Parent Reference Handling

    /// Ensure parent references for newly created child records if Caree is shared
    /// Call this after creating new ActivityTypes or Activities in SwiftData
    /// This handles the edge case where the owner creates new child records after sharing
    func ensureParentReferencesIfShared(for caree: Caree, in modelContext: ModelContext) async {
        // Only run if Caree is shared
        guard await isShared(caree, in: modelContext) else {
            logger.debug("Caree not shared, skipping parent reference check")
            return
        }

        logger.info("📝 Caree is shared, ensuring parent references for newly created child records...")

        // Fix parent references for any new child records
        do {
            try await parentReferenceService.ensureParentReferences(for: caree)
            logger.info("✅ Parent references ensured for newly created child records")
        } catch {
            logger.error("Failed to ensure parent references for newly created child records: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Log child records for diagnostics
    private func logChildRecords(for caree: Caree) async {
        logger.info("🔍 Checking for child records:")

        // Query for ActivityTypes
        let activityTypePredicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let activityTypeQuery = CKQuery(recordType: "CD_ActivityType", predicate: activityTypePredicate)

        do {
            let (results, _) = try await container.privateCloudDatabase.records(matching: activityTypeQuery, inZoneWith: zoneID)
            logger.info("   Found \(results.count) ActivityType records")

            for (_, result) in results {
                if case .success(let record) = result {
                    logger.info("     - \(record["CD_name"] as? String ?? "Unknown")")
                    logger.info("       Parent: \(String(describing: record.parent?.recordID.recordName ?? "nil"))")
                }
            }
        } catch {
            logger.error("   Failed to query ActivityTypes: \(error.localizedDescription)")
        }

        // Query for Activities
        let activityPredicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let activityQuery = CKQuery(recordType: "CD_Activity", predicate: activityPredicate)

        do {
            let (results, _) = try await container.privateCloudDatabase.records(matching: activityQuery, inZoneWith: zoneID)
            logger.info("   Found \(results.count) Activity records")

            for (_, result) in results {
                if case .success(let record) = result {
                    logger.info("     - \(record["CD_dateTime"] as? Date ?? Date())")
                    logger.info("       Parent: \(String(describing: record.parent?.recordID.recordName ?? "nil"))")
                }
            }
        } catch {
            logger.error("   Failed to query Activities: \(error.localizedDescription)")
        }
    }

    /// Find the CloudKit record for a SwiftData Caree
    /// This uses the same approach as your CloudKitSyncService
    private func findCKRecord(for caree: Caree) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_Caree", predicate: predicate)
        
        do {
            let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)
            
            if let firstMatch = results.first {
                let (_, result) = firstMatch
                switch result {
                case .success(let record):
                    return record
                case .failure(let error):
                    throw error
                }
            }

            return nil
        } catch {
            logger.error("Failed to find CloudKit record for caree: \(error.localizedDescription)")
            throw error
        }
    }
}
