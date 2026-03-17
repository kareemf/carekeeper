import CloudKit
import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Single source of truth for all CloudKit data operations
/// Replaces direct SwiftData+CloudKit sync with explicit CRUD operations
@MainActor
class CloudKitDataService: ObservableObject {
    // MARK: - Published Properties

    @Published var isSyncing = false
    @Published var lastSyncError: Error?
    @Published var syncStatus: SyncStatus = .idle
    @Published var deletionProgress: DeletionProgress = .idle

    // MARK: - Zone Configuration (Pure CloudKit)

    /// Use a custom zone for owner records to enable CloudKit sharing.
    private static let zoneName = CloudKitConfig.zoneName
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitDataService.zoneName)

    // MARK: - Private Properties

    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let converter = CloudKitRecordConverter()
    private let logger = AppLogger.cloudkit
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    private let reminderMetadataStore: any ReminderMetadataStoreProtocol
    private let privateZoneChangeTokenStore = PrivateZoneChangeTokenStore()
    /// Set of activity IDs we've already notified about (to prevent duplicates)
    private var notifiedActivityIDs: Set<UUID> = []
    #if canImport(UIKit)
        private let careeImageMaxDimension: CGFloat = 256
    #endif

    // MARK: - Public Services (for unified API)

    @Published private(set) var cacheService: LocalCacheService?
    private(set) var sharedDataService: CloudKitSharedDataService?
    private var pendingActivityBuffer: PendingActivityBuffer?

    // MARK: - Refresh Coalescing

    /// Currently running refresh task, if any. Concurrent callers await this
    /// instead of starting a duplicate CloudKit fetch.
    private var activeRefreshTask: Task<Void, Error>?
    /// Set to `true` while `activeRefreshTask` is running if another caller
    /// requests a refresh. When the active task finishes it will start one more
    /// run to pick up any changes made since the query began.
    private var refreshRequestedDuringRun = false

    // MARK: - Initialization

    init(
        reminderMetadataStore: (any ReminderMetadataStoreProtocol)? = nil
    ) {
        self.reminderMetadataStore = reminderMetadataStore ?? ActivityReminderMetadataStore.shared
        // Observe CloudKit push notifications and refresh owned data (private DB) reactively.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitNotificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                // Check for activities from share participants (owner notifications)
                // This uses change tokens to efficiently detect new activities from other users
                if let ckNotification = notification.object as? CKNotification,
                   let dbNotification = ckNotification as? CKDatabaseNotification,
                   dbNotification.databaseScope == .private
                {
                    await self.fetchPrivateZoneChangesAndNotify()
                }

                do {
                    try await self.refreshOwnedCareesFromCloudKit()
                } catch {
                    self.logger.warning("⚠️ Owned refresh failed after push: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Cache Integration

    /// Set the cache service for automatic caching of CloudKit operations
    func setCacheService(_ cacheService: LocalCacheService) {
        guard self.cacheService !== cacheService else {
            logger.info("Cache service already configured; skipping reassignment")
            return
        }

        self.cacheService = cacheService
        logger.info("Cache service integrated with CloudKitDataService")

        Task {
            await cacheService.refreshPublishedProperties()
        }
    }

    /// Set the shared data service for routing shared caree operations
    func setSharedDataService(_ sharedDataService: CloudKitSharedDataService) {
        self.sharedDataService = sharedDataService
        logger.info("Shared data service integrated with CloudKitDataService")
    }

    func setPendingActivityBuffer(_ pendingActivityBuffer: PendingActivityBuffer) {
        self.pendingActivityBuffer = pendingActivityBuffer
        logger.info("Pending activity buffer integrated with CloudKitDataService")
    }

    private func fetchCurrentUserRecordName() async -> String? {
        await CloudKitUserIdentityService.shared.currentUserRecordName(in: container)
    }

    // MARK: - Sync Status

    enum SyncStatus {
        case idle
        case syncing
        case synced
        case failed(Error)

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    enum DeletionProgress: Equatable {
        case idle
        case deleting(Double) // Progress from 0.0 to 1.0

        var progress: Double {
            switch self {
            case .idle:
                0.0
            case let .deleting(value):
                value
            }
        }

        var isDeleting: Bool {
            if case .deleting = self { return true }
            return false
        }
    }

    // MARK: - Database Selection

    /// Get the appropriate database for a record based on whether it's shared
    private func database(for isShared: Bool) -> CKDatabase {
        isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    // MARK: - Zone Management

    /// Ensure the custom zone exists in the private database
    private func ensureCustomZoneExists() async throws {
        do {
            let zones = try await container.privateCloudDatabase.allRecordZones()
            if zones.contains(where: { $0.zoneID == self.zoneID }) {
                return
            }
        } catch {
            // If fetching zones fails, attempt to create zone anyway
            logger.warning("Failed to list zones, attempting to create: \(error.localizedDescription)")
        }

        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await container.privateCloudDatabase.save(zone)
            logger.info("✅ Created custom zone: \(self.zoneID.zoneName)")
        } catch let error as CKError where error.code == .serverRecordChanged {
            logger.info("Custom zone already exists")
        } catch {
            logger.error("❌ Failed to create custom zone: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Caree Operations

    /// Create a new Caree in CloudKit
    func createCaree(name: String, imageData: Data?, listOrder: Int) async throws -> Caree {
        logger.info("Creating Caree: \(name)")
        syncStatus = .syncing

        do {
            // Ensure zone exists (required for sharing)
            try await ensureCustomZoneExists()

            // Create domain model
            let normalizedImageData = downsampleImageIfNeeded(imageData)

            let caree = Caree(name: name, listOrder: listOrder)
            caree.image = normalizedImageData

            // Convert to CKRecord in custom zone
            let record = try await converter.careeToRecord(caree, imageData: normalizedImageData, zoneID: zoneID)

            // Save to CloudKit private database
            let savedRecord = try await saveWithRetry(record, to: container.privateCloudDatabase)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: container.privateCloudDatabase)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model with any CloudKit modifications
            let syncedCaree = try await converter.recordToCaree(savedRecord)

            // Cache the caree if cache service is available
            if let cacheService {
                try await cacheService.cacheCaree(syncedCaree, isShared: false)
                logger.info("✅ Caree cached locally")
                await cacheService.refreshPublishedProperties()
                logger.info("✅ Cache published properties refreshed after create")
            }

            logger.info("✅ Caree created and verified: \(syncedCaree.id)")
            syncStatus = .synced
            return syncedCaree

        } catch {
            logger.error("❌ Failed to create Caree: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Update an existing Caree in CloudKit
    func updateCaree(
        _ caree: Caree,
        name: String? = nil,
        imageData: Data? = nil,
        listOrder: Int? = nil,
        isShared: Bool = false
    ) async throws {
        logger.info("Updating Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("updateCaree for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name {
                existingRecord["CD_name"] = name as CKRecordValue
            }

            if let imageData {
                let normalizedImageData: Data = downsampleImageIfNeeded(imageData) ?? imageData
                let asset = try converter.createImageAsset(from: normalizedImageData)
                existingRecord["CD_image_ckAsset"] = asset
                caree.image = normalizedImageData
            }

            if let listOrder {
                existingRecord["CD_listOrder"] = listOrder as CKRecordValue
            }

            // Save updated record
            let savedRecord = try await saveWithRetry(existingRecord, to: db)

            // Convert saved record back and apply updates to in-memory model
            let updatedCaree = try await converter.recordToCaree(savedRecord)
            caree.applyScalarUpdates(from: updatedCaree)

            // Update cache if available
            if let cacheService {
                try await cacheService.updateCachedCaree(caree)
                logger.info("✅ Caree cache updated")
            }

            logger.info("✅ Caree updated: \(caree.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update Caree: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Delete a Caree from CloudKit with manual cascade deletion
    func deleteCaree(_ caree: Caree, isShared: Bool = false) async throws {
        logger.info("Deleting Caree: \(caree.id)")
        syncStatus = .syncing
        deletionProgress = .deleting(0.0)

        do {
            if isShared {
                throw AppError
                    .invalidInput("deleteCaree for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Step 1: Query for all ActivityTypes belonging to this Caree
            deletionProgress = .deleting(0.1)
            let careeRef = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID),
                action: .none
            )
            let activityTypeQuery = CKQuery(
                recordType: "CD_ActivityType",
                predicate: NSPredicate(format: "CD_caree == %@", careeRef)
            )

            let (activityTypeResults, _) = try await db.records(matching: activityTypeQuery, inZoneWith: zoneID)
            var activityTypeIDs: [CKRecord.ID] = []
            var allActivityIDs: [CKRecord.ID] = []

            deletionProgress = .deleting(0.2)

            // Collect all activities across all activity types
            for (_, result) in activityTypeResults {
                if case let .success(record) = result {
                    activityTypeIDs.append(record.recordID)

                    // Step 2: Query for all Activities belonging to this ActivityType
                    let activityTypeRef = CKRecord.Reference(recordID: record.recordID, action: .none)
                    let activityQuery = CKQuery(
                        recordType: "CD_Activity",
                        predicate: NSPredicate(format: "CD_activityType == %@", activityTypeRef)
                    )

                    let (activityResults, _) = try await db.records(matching: activityQuery, inZoneWith: zoneID)

                    for (_, activityResult) in activityResults {
                        if case let .success(activityRecord) = activityResult {
                            allActivityIDs.append(activityRecord.recordID)
                        }
                    }
                }
            }

            // Step 3: Delete all Activities with progress tracking
            deletionProgress = .deleting(0.3)
            let totalActivities = allActivityIDs.count
            if totalActivities > 0 {
                for (index, activityID) in allActivityIDs.enumerated() {
                    try await deleteWithRetry(recordID: activityID, from: db)
                    logger.info("  Deleted Activity: \(activityID.recordName)")

                    // Update progress: activities take 0.3 to 0.6 of total progress
                    let activityProgress = 0.3 + (0.3 * Double(index + 1) / Double(totalActivities))
                    deletionProgress = .deleting(activityProgress)
                }
            }

            // Step 4: Delete all ActivityTypes with progress tracking
            deletionProgress = .deleting(0.6)
            let totalActivityTypes = activityTypeIDs.count
            if totalActivityTypes > 0 {
                for (index, activityTypeID) in activityTypeIDs.enumerated() {
                    try await deleteWithRetry(recordID: activityTypeID, from: db)
                    logger.info("  Deleted ActivityType: \(activityTypeID.recordName)")

                    // Update progress: activity types take 0.6 to 0.8 of total progress
                    let activityTypeProgress = 0.6 + (0.2 * Double(index + 1) / Double(totalActivityTypes))
                    deletionProgress = .deleting(activityTypeProgress)
                }
            }

            // Step 5: Finally delete the Caree
            deletionProgress = .deleting(0.8)
            let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            try await deleteWithRetry(recordID: careeRecordID, from: db)

            // Remove from cache if cache service is available
            deletionProgress = .deleting(0.9)
            if let cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id)
            {
                try await cacheService.removeCachedCaree(cachedCaree)
                logger.info("✅ Caree removed from cache")
            }

            logger.info("✅ Caree deleted with cascade: \(caree.id)")
            deletionProgress = .deleting(1.0)

            // Small delay to show completion before resetting
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            deletionProgress = .idle
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete Caree: \(error.localizedDescription)")
            deletionProgress = .idle
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Fetch a specific Caree from CloudKit
    func fetchCaree(id: UUID, isShared: Bool = false) async throws -> Caree? {
        logger.info("Fetching Caree: \(id)")

        let db = database(for: isShared)
        let recordID = isShared
            ? CKRecord.ID(recordName: "CD_Caree/\(id.uuidString)") // shared path handled elsewhere
            : CKRecord.ID(recordName: "CD_Caree/\(id.uuidString)", zoneID: zoneID)

        do {
            let record = try await fetchWithRetry(recordID: recordID, from: db)
            let caree = try await converter.recordToCaree(record)
            logger.info("✅ Caree fetched: \(id)")
            return caree
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Caree not found: \(id)")
            return nil
        } catch {
            logger.error("❌ Failed to fetch Caree: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch all Carees from private database
    func fetchAllCarees() async throws -> [Caree] {
        logger.info("Fetching all Carees from private database")

        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        let (matchResults, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var carees: [Caree] = []
        for (_, result) in matchResults {
            switch result {
            case let .success(record):
                do {
                    let caree = try await converter.recordToCaree(record)
                    carees.append(caree)
                } catch {
                    logger.warning("Failed to convert Caree record: \(error.localizedDescription)")
                }
            case let .failure(error):
                logger.warning("Failed to fetch Caree record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Fetched \(carees.count) Carees")
        return carees
    }

    // MARK: - ActivityType Operations

    func createActivityType(
        for caree: Caree,
        name: String,
        icon: String?,
        hasQuantity: Bool,
        quantityUnit: String?,
        hasLocation: Bool,
        listOrder: Int,
        isShared: Bool = false
    ) async throws -> ActivityType {
        logger.info("Creating ActivityType: \(name) for Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("createActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch parent Caree record (needed for parent reference)
            let parentRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            let parentRecord = try await fetchWithRetry(recordID: parentRecordID, from: db)

            // Create domain model
            let activityType = ActivityType(
                name: name,
                icon: icon,
                hasQuantity: hasQuantity,
                quantityUnit: quantityUnit,
                hasLocation: hasLocation,
                listOrder: listOrder
            )

            // Convert to CKRecord with parent reference in custom zone
            let record = try converter.activityTypeToRecord(activityType, parentCaree: parentRecord, zoneID: zoneID)

            // Save to CloudKit
            let savedRecord = try await saveWithRetry(record, to: db)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: db)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model
            let syncedActivityType = try converter.recordToActivityType(savedRecord)

            // Cache the activity type if cache service is available
            if let cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id)
            {
                try await cacheService.cacheActivityType(syncedActivityType, for: cachedCaree)
                logger.info("✅ ActivityType cached locally")
            }

            logger.info("✅ ActivityType created and verified: \(syncedActivityType.id)")
            syncStatus = .synced
            return syncedActivityType

        } catch {
            logger.error("❌ Failed to create ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    func updateActivityType(
        _ activityType: ActivityType,
        caree: Caree,
        name: String? = nil,
        icon: String? = nil,
        hasQuantity: Bool? = nil,
        quantityUnit: String? = nil,
        hasLocation: Bool? = nil,
        listOrder: Int? = nil,
        isShared: Bool = false
    ) async throws {
        logger.info("Updating ActivityType: \(activityType.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("updateActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name {
                existingRecord["CD_name"] = name as CKRecordValue
            }
            if let icon {
                existingRecord["CD_icon"] = icon as CKRecordValue
            }
            if let hasQuantity {
                existingRecord["CD_hasQuantity"] = (hasQuantity ? 1 : 0) as CKRecordValue
            }
            if let quantityUnit {
                existingRecord["CD_quantityUnit"] = quantityUnit as CKRecordValue
            }
            if let hasLocation {
                existingRecord["CD_hasLocation"] = (hasLocation ? 1 : 0) as CKRecordValue
            }
            if let listOrder {
                existingRecord["CD_listOrder"] = listOrder as CKRecordValue
            }

            // Save updated record
            let savedRecord = try await saveWithRetry(existingRecord, to: db)

            // Convert saved record back and apply updates to in-memory model
            let updatedActivityType = try converter.recordToActivityType(savedRecord)
            activityType.applyScalarUpdates(from: updatedActivityType)

            // Update cache if available - first get the cached caree
            if let cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id)
            {
                try await cacheService.cacheActivityType(activityType, for: cachedCaree)
                logger.info("✅ ActivityType cache updated")
            }

            logger.info("✅ ActivityType updated: \(activityType.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    func deleteActivityType(_ activityType: ActivityType, isShared: Bool = false) async throws {
        logger.info("Deleting ActivityType: \(activityType.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("deleteActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)

            try await deleteWithRetry(recordID: recordID, from: db)

            // Remove from cache if cache service is available
            if let cacheService {
                try await cacheService.removeCachedActivityType(activityType)
                logger.info("✅ ActivityType removed from cache")
            }

            logger.info("✅ ActivityType deleted: \(activityType.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    // MARK: - Activity Operations

    func createActivity(
        for caree: Caree,
        activityType: ActivityType,
        dateTime: Date,
        notes: String?,
        quantity: Double?,
        latitude: Double?,
        longitude: Double?,
        isShared: Bool = false
    ) async throws -> Activity {
        logger.info("Creating Activity for Caree: \(caree.id)")
        syncStatus = .syncing

        var pendingActivityID: UUID?
        var didSaveToCloudKit = false

        do {
            if isShared {
                throw AppError
                    .invalidInput("createActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            let activity = Activity(
                dateTime: dateTime,
                notes: notes,
                quantity: quantity,
                latitude: latitude,
                longitude: longitude,
                activityType: activityType,
                caree: caree
            )
            pendingActivityID = activity.id

            if let pendingActivityBuffer {
                let mutation = PendingActivityBuffer.PendingActivityMutation(
                    id: activity.id,
                    careeID: caree.id,
                    activityTypeID: activityType.id,
                    activity: activity,
                    createdAt: Date()
                )
                pendingActivityBuffer.enqueue(mutation)
            }

            // Fetch parent records
            let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            let careeRecord = try await fetchWithRetry(recordID: careeRecordID, from: db)

            let activityTypeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
            let activityTypeRecord = try await fetchWithRetry(recordID: activityTypeRecordID, from: db)

            // Convert to CKRecord with parent references in custom zone
            let creatorRecordName = await fetchCurrentUserRecordName()
            let record = try converter.activityToRecord(
                activity,
                parentCaree: careeRecord,
                activityTypeRecord: activityTypeRecord,
                zoneID: zoneID,
                creatorRecordName: creatorRecordName,
                creatorDisplayName: CaregiverDisplayNameService.shared.resolvedDisplayName
            )

            // Save to CloudKit
            let savedRecord = try await saveWithRetry(record, to: db)
            didSaveToCloudKit = true

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: db)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model
            let syncedActivity = try converter.recordToActivity(savedRecord)

            // Cache the activity if cache service is available
            // Note: pending buffer entry is NOT removed here — it stays until the next
            // refreshOwnedCareesFromCloudKit() confirms the activity exists in cache via
            // applyPendingActivityMutations(). This prevents dropped writes when a concurrent
            // refresh's replaceCaree() wipes the cache before the CloudKit query sees the new record.
            if let cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id)
            {
                let cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
                if let cachedActivityType = cachedActivityTypes.first(where: { $0.id == activityType.id }) {
                    do {
                        try await cacheService.cacheActivity(syncedActivity, for: cachedCaree, activityTypeID: cachedActivityType.id)
                        logger.debug("✅ Activity \(syncedActivity.id) cached locally (pending retained until next refresh)")
                    } catch {
                        logger.warning("⚠️ Failed to cache activity \(syncedActivity.id) locally: \(error.localizedDescription)")
                    }
                }
            }

            logger.info("✅ Activity created and verified: \(syncedActivity.id)")
            syncStatus = .synced
            return syncedActivity

        } catch {
            if let pendingActivityID, !didSaveToCloudKit {
                pendingActivityBuffer?.remove(activityID: pendingActivityID, careeID: caree.id)
            }
            logger.error("❌ Failed to create Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    func updateActivity(
        _ activity: Activity,
        caree: Caree,
        activityType: ActivityType,
        dateTime: Date? = nil,
        notes: String? = nil,
        quantity: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isShared: Bool = false
    ) async throws {
        logger.info("Updating Activity: \(activity.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("updateActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let dateTime {
                existingRecord["CD_dateTime"] = dateTime as CKRecordValue
            }
            if let notes {
                existingRecord["CD_notes"] = notes as CKRecordValue
            }
            if let quantity {
                existingRecord["CD_quantity"] = quantity as CKRecordValue
            }
            if let latitude {
                existingRecord["CD_latitude"] = latitude as CKRecordValue
            }
            if let longitude {
                existingRecord["CD_longitude"] = longitude as CKRecordValue
            }

            // Save updated record
            let savedRecord = try await saveWithRetry(existingRecord, to: db)

            // Convert saved record back and apply updates to in-memory model
            let updatedActivity = try converter.recordToActivity(savedRecord)
            activity.applyScalarUpdates(from: updatedActivity)

            // Update cache if available
            if let cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id)
            {
                let cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
                if let cachedActivityType = cachedActivityTypes.first(where: { $0.id == activityType.id }) {
                    try await cacheService.cacheActivity(activity, for: cachedCaree, activityTypeID: cachedActivityType.id)
                    logger.info("✅ Activity cache updated")
                }
            }

            logger.info("✅ Activity updated: \(activity.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    func deleteActivity(_ activity: Activity, isShared: Bool = false) async throws {
        logger.info("Deleting Activity: \(activity.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError
                    .invalidInput("deleteActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)

            try await deleteWithRetry(recordID: recordID, from: db)

            // Remove from cache if cache service is available
            if let cacheService {
                try await cacheService.removeCachedActivity(activity)
                logger.info("✅ Activity removed from cache")
            }

            await reminderMetadataStore.deleteMetadata(for: activity.id)
            ReminderScheduler.shared.deleteReminder(with: activity.reminderIdentifier)

            logger.info("✅ Activity deleted: \(activity.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    // MARK: - Unified CRUD API (routes shared vs owned internally)

    /// Unified createActivityType that routes based on caree.isShared
    func createActivityType(
        caree: Caree,
        name: String,
        icon: String?,
        hasQuantity: Bool,
        quantityUnit: String?,
        hasLocation: Bool,
        listOrder: Int
    ) async throws -> ActivityType {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            return try await sharedDataService.createActivityType(
                for: caree,
                name: name,
                icon: icon,
                hasQuantity: hasQuantity,
                quantityUnit: quantityUnit,
                hasLocation: hasLocation,
                listOrder: listOrder
            )
        } else {
            return try await createActivityType(
                for: caree,
                name: name,
                icon: icon,
                hasQuantity: hasQuantity,
                quantityUnit: quantityUnit,
                hasLocation: hasLocation,
                listOrder: listOrder,
                isShared: false
            )
        }
    }

    /// Unified updateActivityType that routes based on caree.isShared
    func updateActivityType(activityType: ActivityType, caree: Caree) async throws {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            try await sharedDataService.updateActivityType(activityType, caree: caree)
        } else {
            // Extract field values from object before calling owned implementation
            try await updateActivityType(
                activityType,
                caree: caree,
                name: activityType.name,
                icon: activityType.icon,
                hasQuantity: activityType.hasQuantity,
                quantityUnit: activityType.quantityUnit,
                hasLocation: activityType.hasLocation,
                listOrder: activityType.listOrder,
                isShared: false
            )
        }
    }

    /// Unified deleteActivityType that routes based on caree.isShared
    func deleteActivityType(activityType: ActivityType, caree: Caree) async throws {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            try await sharedDataService.deleteActivityType(activityType, caree: caree)
        } else {
            try await deleteActivityType(activityType, isShared: false)
        }
    }

    /// Unified createActivity that routes based on caree.isShared
    func createActivity(
        caree: Caree,
        activityType: ActivityType,
        dateTime: Date,
        notes: String?,
        quantity: Double?,
        latitude: Double?,
        longitude: Double?
    ) async throws -> Activity {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            return try await sharedDataService.createActivity(
                for: caree,
                activityType: activityType,
                dateTime: dateTime,
                notes: notes,
                quantity: quantity,
                latitude: latitude,
                longitude: longitude
            )
        } else {
            return try await createActivity(
                for: caree,
                activityType: activityType,
                dateTime: dateTime,
                notes: notes,
                quantity: quantity,
                latitude: latitude,
                longitude: longitude,
                isShared: false
            )
        }
    }

    /// Unified updateActivity that routes based on caree.isShared
    func updateActivity(activity: Activity, caree: Caree, activityType: ActivityType) async throws {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            try await sharedDataService.updateActivity(activity, caree: caree)
        } else {
            // Extract field values from object before calling owned implementation
            try await updateActivity(
                activity,
                caree: caree,
                activityType: activityType,
                dateTime: activity.dateTime,
                notes: activity.notes,
                quantity: activity.quantity,
                latitude: activity.latitude,
                longitude: activity.longitude,
                isShared: false
            )
        }
    }

    /// Unified deleteActivity that routes based on caree.isShared
    func deleteActivity(activity: Activity, caree: Caree) async throws {
        guard let sharedDataService else {
            throw AppError.invalidInput("Shared data service not configured")
        }

        if caree.isShared {
            try await sharedDataService.deleteActivity(activity, caree: caree)
        } else {
            try await deleteActivity(activity, isShared: false)
        }

        pendingActivityBuffer?.remove(activityID: activity.id, careeID: caree.id)
    }

    // MARK: - Reactive owned refresh (private DB)

    /// Fetch all owned (private DB) carees, activity types, and activities and update LocalCacheService.
    /// Posts "CloudKitBackgroundRefreshFinished" when done so AppDelegate can finish the background task.
    ///
    /// Concurrent calls are coalesced: if a refresh is already running, the caller awaits
    /// the active task and a follow-up run is scheduled to pick up any changes made since
    /// the active query began. This prevents redundant CloudKit fetches during cold start
    /// (where `.task`, `.onReceive(cacheService)`, and the initial seed all fire at once).
    func refreshOwnedCareesFromCloudKit() async throws {
        // If a refresh is already in flight, mark that we want another run after it
        // finishes, then just await the active task.
        if let active = activeRefreshTask {
            refreshRequestedDuringRun = true
            logger.info("🔄 Refresh already in flight — coalescing (will run again after current)")
            try await active.value
            return
        }

        // Launch the actual refresh and store the task handle.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performOwnedRefresh()

            // If another caller arrived while we were running, do one more pass.
            if self.refreshRequestedDuringRun {
                self.refreshRequestedDuringRun = false
                self.logger.info("🔄 Running coalesced follow-up refresh")
                try await self.performOwnedRefresh()
            }
        }
        activeRefreshTask = task

        defer {
            activeRefreshTask = nil
            refreshRequestedDuringRun = false
        }

        try await task.value
    }

    /// Internal implementation of the owned-records refresh.
    private func performOwnedRefresh() async throws {
        logger.info("🔄 Refreshing owned records from private database (reactive)")

        // Ensure zone exists
        try? await ensureCustomZoneExists()

        // Query all three record types in the custom zone
        let privateDB = container.privateCloudDatabase

        // Carees
        let careeQuery = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        let careeRecords = try await fetchAllRecords(
            query: careeQuery,
            database: privateDB,
            zoneID: zoneID,
            recordType: "CD_Caree"
        )

        // ActivityTypes
        let atQuery = CKQuery(recordType: "CD_ActivityType", predicate: NSPredicate(value: true))
        let atRecords = try await fetchAllRecords(
            query: atQuery,
            database: privateDB,
            zoneID: zoneID,
            recordType: "CD_ActivityType"
        )

        // Activities
        let aQuery = CKQuery(recordType: "CD_Activity", predicate: NSPredicate(value: true))
        let aRecords = try await fetchAllRecords(
            query: aQuery,
            database: privateDB,
            zoneID: zoneID,
            recordType: "CD_Activity"
        )

        // Convert and cache
        guard let cacheService else {
            logger.info("ℹ️ No cacheService; skipping cache update")
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
            return
        }

        // Convert carees first
        var careesByID: [UUID: Caree] = [:]
        var activityTypesByCaree: [UUID: [ActivityType]] = [:]
        var activitiesByCaree: [UUID: [Activity]] = [:]
        for record in careeRecords {
            do {
                let caree = try await converter.recordToCaree(record)
                caree.isShared = false
                caree.isOwned = true
                careesByID[caree.id] = caree
            } catch {
                logger.warning("⚠️ Convert caree failed: \(error.localizedDescription)")
            }
        }

        // Convert activity types and attach to carees
        var activityTypesByID: [UUID: ActivityType] = [:]
        var activityTypeIDByActivity: [UUID: UUID] = [:]
        for record in atRecords {
            do {
                let at = try converter.recordToActivityType(record)
                activityTypesByID[at.id] = at

                // Attach to parent via CD_caree reference
                if let careeRef = record["CD_caree"] as? CKRecord.Reference,
                   let careeIDStr = careeRef.recordID.recordName.split(separator: "/").last,
                   let careeID = UUID(uuidString: String(careeIDStr)),
                   careesByID[careeID] != nil
                {
                    activityTypesByCaree[careeID, default: []].append(at)
                }
            } catch {
                logger.warning("⚠️ Convert activity type failed: \(error.localizedDescription)")
            }
        }

        // Convert activities and attach to both
        for record in aRecords {
            do {
                let activity = try converter.recordToActivity(record)

                // Attach to activity type
                if let atRef = record["CD_activityType"] as? CKRecord.Reference,
                   let atIDStr = atRef.recordID.recordName.split(separator: "/").last,
                   let atID = UUID(uuidString: String(atIDStr)),
                   activityTypesByID[atID] != nil
                {
                    activityTypeIDByActivity[activity.id] = atID
                }

                // Attach to caree
                if let careeRef = record["CD_caree"] as? CKRecord.Reference,
                   let careeIDStr = careeRef.recordID.recordName.split(separator: "/").last,
                   let careeID = UUID(uuidString: String(careeIDStr)),
                   careesByID[careeID] != nil
                {
                    activitiesByCaree[careeID, default: []].append(activity)
                }
            } catch {
                logger.warning("⚠️ Convert activity failed: \(error.localizedDescription)")
            }
        }

        // Populate relationships for transient objects used outside the cache.
        for (careeID, caree) in careesByID {
            let types = activityTypesByCaree[careeID] ?? []
            caree.activityTypes = types
            let activities = activitiesByCaree[careeID] ?? []
            caree.activities = activities

            for activityType in types {
                activityType.caree = caree
            }

            for activity in activities {
                if let activityTypeID = activityTypeIDByActivity[activity.id],
                   let activityType = activityTypesByID[activityTypeID]
                {
                    activity.activityType = activityType
                    var activitiesForType = activityType.activities ?? []
                    activitiesForType.append(activity)
                    activityType.activities = activitiesForType
                }
                activity.caree = caree
            }
        }

        do {
            let metadata = try await reminderMetadataStore.fetchMetadata(for: Array(activityTypeIDByActivity.keys))
            logger.info("🔔 Overlaying reminder metadata for \(metadata.count, privacy: .public) owned activities.")
            applyReminderMetadata(metadata, to: &activitiesByCaree)
        } catch {
            logger.warning("⚠️ Failed to fetch reminder metadata for owned carees: \(error.localizedDescription)")
        }

        // Collect all activity IDs that CloudKit returned in this refresh.
        // Only remove pending entries for activities that appear in these results,
        // since that proves CloudKit has propagated the record and future refreshes
        // will include it. Otherwise, concurrent refreshes would wipe re-applied
        // pending activities that CloudKit hasn't returned yet.
        let fetchedActivityIDs = Set(activitiesByCaree.values.flatMap { $0 }.map(\.id))

        // Perform cache mutations in a single coalesced batch to avoid per-write refreshes.
        await cacheService.withBatch {
            // Remove owned carees from cache that no longer exist remotely
            let fetchedOwnedIDs = Set(careesByID.keys)
            let existingOwned = cacheService.myCarees
            for cached in existingOwned where !fetchedOwnedIDs.contains(cached.id) {
                do {
                    logger.info("🧹 Removing deleted owned caree from cache: \(cached.name)")
                    try await cacheService.removeCachedCaree(cached)
                } catch {
                    logger.warning("⚠️ Failed removing cached owned caree: \(error.localizedDescription)")
                }
            }

            // Upsert everything into cache
            for caree in careesByID.values.sorted(by: { $0.listOrder < $1.listOrder }) {
                do {
                    let cacheCaree = cloneCareeForCaching(caree, isShared: false)
                    let types = activityTypesByCaree[caree.id] ?? []
                    let activities = activitiesByCaree[caree.id] ?? []
                    let mapping = Dictionary(uniqueKeysWithValues: activities.compactMap { activity in
                        activityTypeIDByActivity[activity.id].map { (activity.id, $0) }
                    })
                    try await cacheService.replaceCaree(
                        cacheCaree,
                        activityTypes: types,
                        activities: activities,
                        activityTypeIDsByActivity: mapping
                    )
                } catch {
                    logger.warning("⚠️ Failed caching owned records: \(error.localizedDescription)")
                }
            }

            // Apply pending mutations inside the batch so they appear in the same
            // cacheRevision as the refresh — preventing a window where replaceCaree
            // wiped the cache but pending entries haven't been re-applied yet.
            await applyPendingActivityMutations(fetchedActivityIDs: fetchedActivityIDs)
        }

        // No explicit refreshPublishedProperties call needed; the batch coalesces a single refresh.
        NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
        logger.info("✅ Owned records refreshed and cache updated")
    }

    /// Re-apply pending activity mutations to the cache after a `replaceCaree` wipe.
    ///
    /// - Parameter fetchedActivityIDs: Activity IDs that CloudKit returned in this refresh.
    ///   A pending entry is only removed when its ID appears in this set, proving CloudKit
    ///   has propagated the record. Until then, the entry stays in the buffer so that
    ///   subsequent concurrent refreshes will keep re-applying it.
    @MainActor
    private func applyPendingActivityMutations(fetchedActivityIDs: Set<UUID> = []) async {
        guard let pendingActivityBuffer, let cacheService else { return }

        let pendingCareeIDs = pendingActivityBuffer.pendingCareeIDs
        guard !pendingCareeIDs.isEmpty else { return }

        for careeID in pendingCareeIDs {
            guard let cachedCaree = cacheService.getCachedCaree(id: careeID) else {
                logger.warning("Caree \(careeID) not found in cache — skipping pending mutations")
                continue
            }
            let cachedTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
            let typeByID: [UUID: ActivityType] = Dictionary(uniqueKeysWithValues: cachedTypes.map { ($0.id, $0) })
            let mutations = pendingActivityBuffer.pendingMutations(for: careeID)

            if mutations.isEmpty { continue }

            await cacheService.withBatch {
                for mutation in mutations {
                    if fetchedActivityIDs.contains(mutation.id) {
                        pendingActivityBuffer.remove(activityID: mutation.id, careeID: careeID)
                        continue
                    }

                    guard let cachedType = typeByID[mutation.activityTypeID] else {
                        logger.warning("Pending activity \(mutation.id): activityType \(mutation.activityTypeID) not in cache — skipping")
                        continue
                    }
                    do {
                        try await cacheService.cacheActivity(
                            mutation.activity,
                            for: cachedCaree,
                            activityTypeID: cachedType.id
                        )
                    } catch {
                        logger.warning("⚠️ Failed to cache pending activity \(mutation.id): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func fetchAllRecords(
        query: CKQuery,
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        recordType: String,
        desiredKeys: [String]? = nil,
        resultsLimit: Int = CKQueryOperation.maximumResults
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        var batchIndex = 0

        repeat {
            let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
            let nextCursor: CKQueryOperation.Cursor?

            if let cursor {
                (matchResults, nextCursor) = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: desiredKeys,
                    resultsLimit: resultsLimit
                )
            } else {
                (matchResults, nextCursor) = try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: desiredKeys,
                    resultsLimit: resultsLimit
                )
            }

            for (_, result) in matchResults {
                switch result {
                case let .success(record):
                    records.append(record)
                case let .failure(error):
                    logger.warning("⚠️ Failed \(recordType) record fetch: \(error.localizedDescription)")
                }
            }

            batchIndex += 1
            cursor = nextCursor
        } while cursor != nil

        logger.info("📥 Fetched \(records.count) \(recordType) records (\(batchIndex) batch\(batchIndex == 1 ? "" : "es"))")
        return records
    }

    private func cloneCareeForCaching(_ caree: Caree, isShared: Bool) -> Caree {
        let clone = Caree(name: caree.name, image: caree.image, listOrder: caree.listOrder)
        clone.id = caree.id
        clone.dateCreated = caree.dateCreated
        clone.isShared = isShared
        clone.isOwned = !isShared
        clone.lastSyncedAt = caree.lastSyncedAt
        clone.cloudKitRecordID = caree.cloudKitRecordID
        return clone
    }

    // MARK: - Zone Management (for Migration)

    func deleteCustomZone() async throws {
        logger.warning("⚠️ Deleting custom CloudKit zone - all data will be destroyed")

        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: self.zoneID)
            logger.info("✅ Custom zone deleted: \(Self.zoneName)")
        } catch let error as CKError where error.code == .zoneNotFound {
            logger.info("Zone already deleted or doesn't exist")
        } catch {
            logger.error("❌ Failed to delete zone: \(error.localizedDescription)")
            throw error
        }
    }

    func recreateCustomZone() async throws {
        logger.info("Creating custom CloudKit zone: \(Self.zoneName)")

        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await container.privateCloudDatabase.save(zone)
            logger.info("✅ Custom zone created: \(Self.zoneName)")
        } catch let error as CKError where error.code == .serverRecordChanged {
            logger.info("Zone already exists, continuing")
        } catch {
            logger.error("❌ Failed to create zone: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sync Verification

    func verifySynced(recordID: CKRecord.ID, in database: CKDatabase) async throws -> Bool {
        do {
            _ = try await database.record(for: recordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw error
        }
    }

    func waitForSync(
        recordID: CKRecord.ID,
        in database: CKDatabase,
        timeout: TimeInterval = 10.0,
        pollInterval: TimeInterval = 0.5
    ) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if try await verifySynced(recordID: recordID, in: database) {
                logger.info("✅ Record synced: \(recordID.recordName)")
                return true
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        logger.warning("⏱️ Sync verification timeout for: \(recordID.recordName)")
        return false
    }

    // MARK: - Retry Logic

    private func saveWithRetry(_ record: CKRecord, to database: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                let savedRecord = try await database.save(record)
                if attempt > 0 {
                    logger.info("✅ Save succeeded after \(attempt) retries")
                }
                return savedRecord
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Save failed (attempt \(attempt)/\(self.maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(self.retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                logger.error("Save failed with non-retryable error: \(error, privacy: .public)")
                throw error
            }
        }

        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    private func fetchWithRetry(recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                let record = try await database.record(for: recordID)
                if attempt > 0 {
                    logger.info("✅ Fetch succeeded after \(attempt) retries")
                }
                return record
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Fetch failed (attempt \(attempt)/\(self.maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(self.retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                logger.error("Fetch failed with non-retryable error: \(error, privacy: .public)")
                throw error
            }
        }

        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    private func deleteWithRetry(recordID: CKRecord.ID, from database: CKDatabase) async throws {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                _ = try await database.deleteRecord(withID: recordID)
                if attempt > 0 {
                    logger.info("✅ Delete succeeded after \(attempt) retries")
                }
                return
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Delete failed (attempt \(attempt)/\(self.maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(self.retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                logger.error("Delete failed with non-retryable error: \(error, privacy: .public)")
                throw error
            }
        }

        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    // MARK: - Image Handling

    private func downsampleImageIfNeeded(_ data: Data?) -> Data? {
        guard let data else { return nil }
        #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return data }

            let maxDimension = max(image.size.width, image.size.height)
            guard maxDimension > careeImageMaxDimension else { return data }

            let scale = careeImageMaxDimension / maxDimension
            let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            let rendererFormat = UIGraphicsImageRendererFormat.default()
            rendererFormat.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
            let resizedData = renderer.jpegData(withCompressionQuality: 0.75) { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return resizedData
        #else
            return data
        #endif
    }

    private func applyReminderMetadata(
        _ metadata: [UUID: ActivityReminderMetadata],
        to activitiesByCaree: inout [UUID: [Activity]]
    ) {
        guard !metadata.isEmpty else { return }
        logger.info("🔔 Overlaying reminder metadata for \(metadata.count, privacy: .public) activities")
        for (careeID, activities) in activitiesByCaree {
            let updated = activities.map { activity -> Activity in
                if let entry = metadata[activity.id] {
                    activity.reminderIdentifier = entry.identifier(for: .phone)
                    activity.reminderDueDate = entry.reminderDueDate
                    activity.reminderSource = entry.reminderSource
                }
                return activity
            }
            activitiesByCaree[careeID] = updated
        }
    }

    // MARK: - Private Zone Change Tracking for Owner Notifications

    /// Fetch changes in the private database zone and notify for new activities from other users.
    /// This is called after a push notification to detect activities created by share participants.
    func fetchPrivateZoneChangesAndNotify() async {
        logger.info("🔍 Fetching private zone changes to check for activities from other users")

        let previousToken = privateZoneChangeTokenStore.token(for: zoneID)
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = previousToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config]
        )

        var newActivityRecords: [CKRecord] = []
        var latestToken: CKServerChangeToken?
        var fetchError: Error?

        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case let .success(record):
                // Only track CD_Activity records for notifications
                if record.recordType == "CD_Activity" {
                    newActivityRecords.append(record)
                }
            case let .failure(error):
                self.logger.warning("⚠️ Failed record change in private zone: \(recordID.recordName, privacy: .public): \(error.localizedDescription)")
            }
        }

        operation.recordZoneFetchResultBlock = { [self] _, result in
            switch result {
            case let .success(fetchResult):
                latestToken = fetchResult.serverChangeToken
            case let .failure(error):
                fetchError = error
                logger.warning("⚠️ Zone fetch failed: \(error.localizedDescription)")
            }
        }

        await withCheckedContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { _ in
                continuation.resume()
            }
            container.privateCloudDatabase.add(operation)
        }

        // Handle token expiration
        if let error = fetchError {
            if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                logger.warning("⚠️ Private zone change token expired; clearing and will refetch on next push")
                privateZoneChangeTokenStore.clear(for: zoneID)
            }
            return
        }

        // Save the new token
        if let token = latestToken {
            privateZoneChangeTokenStore.save(token, for: zoneID)
        }

        // Check each new activity record and notify if from another user
        let currentUserID = await fetchCurrentUserRecordName()

        for record in newActivityRecords {
            await notifyForPrivateActivityIfNeeded(record, currentUserID: currentUserID)
        }

        if !newActivityRecords.isEmpty {
            logger.info("🔔 Processed \(newActivityRecords.count) activity changes in private zone")
        }
    }

    /// Check if an activity record was created by another user and present a notification if so.
    private func notifyForPrivateActivityIfNeeded(_ record: CKRecord, currentUserID: String?) async {
        // Extract creator ID
        let creatorIDField = record["CD_creatorUserRecordID"] as? String
        let creatorRecordID = record.creatorUserRecordID?.recordName

        // Skip if created by current user
        if !CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: creatorRecordID,
            creatorIDField: creatorIDField,
            currentUserRecordName: currentUserID
        ) {
            logger.debug("🔕 Skipping notification for self-authored activity in private zone")
            return
        }

        // Extract activity ID
        guard let cdId = record["CD_id"] as? String,
              let activityID = UUID(uuidString: cdId)
        else {
            logger.warning("⚠️ Activity record missing CD_id field")
            return
        }

        // Skip if already notified
        if notifiedActivityIDs.contains(activityID) {
            logger.debug("🔕 Already notified for activity: \(activityID)")
            return
        }

        // Extract required fields
        guard let dateTime = record["CD_dateTime"] as? Date else {
            logger.warning("⚠️ Activity record missing CD_dateTime field")
            return
        }

        // Extract caree ID
        guard let careeReference = record["CD_caree"] as? CKRecord.Reference,
              let careeIDFromRef = careeReference.recordID.recordName.components(separatedBy: "/").last,
              let careeID = UUID(uuidString: careeIDFromRef)
        else {
            logger.warning("⚠️ Could not extract caree ID from activity")
            return
        }

        // Check notification preferences
        let prefs = UserNotificationPreferences.shared
        guard prefs.isEnabled(for: careeID) else {
            logger.debug("🔕 Notifications disabled for caree \(careeID)")
            return
        }

        // Fetch caree and activity type names
        do {
            let database = container.privateCloudDatabase
            let careeRecord = try await database.record(for: careeReference.recordID)
            let careeName = careeRecord["CD_name"] as? String ?? "Unknown"

            var activityTypeName = "Activity"
            if let activityTypeRef = record["CD_activityType"] as? CKRecord.Reference {
                if let activityTypeRecord = try? await database.record(for: activityTypeRef.recordID) {
                    activityTypeName = activityTypeRecord["CD_name"] as? String ?? "Activity"
                }
            }

            // Mark as notified
            notifiedActivityIDs.insert(activityID)

            // Present the notification
            let creatorDisplayName = record["CD_creatorDisplayName"] as? String ?? "A caregiver"
            let notificationService = UserNotificationService.shared
            await notificationService.presentNewActivityNotification(
                activityID: activityID,
                careeID: careeID,
                careeName: careeName,
                activityTypeName: activityTypeName,
                creatorName: creatorDisplayName,
                timestamp: dateTime
            )

            logger.info("🔔 Presented notification for activity from share participant: \(activityID)")

        } catch {
            logger.error("❌ Failed to present notification for private zone activity: \(error.localizedDescription)")
        }
    }

}

// MARK: - Private Zone Change Token Store

private struct PrivateZoneChangeTokenStore {
    private let defaults = UserDefaults.standard

    func token(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: key(for: zoneID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func save(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return
        }
        defaults.set(data, forKey: key(for: zoneID))
    }

    func clear(for zoneID: CKRecordZone.ID) {
        defaults.removeObject(forKey: key(for: zoneID))
    }

    private func key(for zoneID: CKRecordZone.ID) -> String {
        "privateZoneToken-\(zoneID.zoneName)-\(zoneID.ownerName)"
    }
}

// MARK: - Data Service Errors

enum DataServiceError: LocalizedError {
    case syncVerificationFailed(recordID: String)
    case maxRetriesExceeded
    case parentRecordNotFound(careeID: UUID)

    var errorDescription: String? {
        switch self {
        case let .syncVerificationFailed(recordID):
            "Failed to verify sync for record: \(recordID)"
        case .maxRetriesExceeded:
            "Maximum retry attempts exceeded. Please check your network connection."
        case let .parentRecordNotFound(careeID):
            "Parent caree record not found: \(careeID)"
        }
    }
}
