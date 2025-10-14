import Foundation
import CloudKit
import SwiftUI

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

    // MARK: - Public Cache Service (for view observation)

    private(set) var cacheService: LocalCacheService?

    // MARK: - Cache Integration

    /// Set the cache service for automatic caching of CloudKit operations
    func setCacheService(_ cacheService: LocalCacheService) {
        self.cacheService = cacheService
        logger.info("Cache service integrated with CloudKitDataService")
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
        case deleting(Double)  // Progress from 0.0 to 1.0

        var progress: Double {
            switch self {
            case .idle:
                return 0.0
            case .deleting(let value):
                return value
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
        return isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
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
    /// - Parameters:
    ///   - name: Caree name
    ///   - imageData: Optional profile image
    ///   - listOrder: Display order
    /// - Returns: Created Caree with CloudKit sync confirmed
    func createCaree(name: String, imageData: Data?, listOrder: Int) async throws -> Caree {
        logger.info("Creating Caree: \(name)")
        syncStatus = .syncing

        do {
            // Ensure zone exists (required for sharing)
            try await ensureCustomZoneExists()

            // Create domain model
            let caree = Caree(name: name, listOrder: listOrder)
            caree.image = imageData

            // Convert to CKRecord in custom zone
            let record = try await converter.careeToRecord(caree, imageData: imageData, zoneID: zoneID)

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
            if let cacheService = cacheService {
                try await cacheService.cacheCaree(syncedCaree, isShared: false)
                logger.info("✅ Caree cached locally")
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
    /// - Parameters:
    ///   - caree: Caree to update
    ///   - name: New name (optional)
    ///   - imageData: New image data (optional)
    ///   - listOrder: New display order (optional)
    ///   - isShared: Whether this is a shared caree
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
                throw AppError.invalidInput("updateCaree for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name = name {
                existingRecord["CD_name"] = name as CKRecordValue
            }

            if let imageData = imageData {
                let asset = try converter.createImageAsset(from: imageData)
                existingRecord["CD_image_ckAsset"] = asset
            }

            if let listOrder = listOrder {
                existingRecord["CD_listOrder"] = listOrder as CKRecordValue
            }

            // Save updated record
            _ = try await saveWithRetry(existingRecord, to: db)

            // Update the caree object with new values
            if let name = name {
                caree.name = name
            }
            if let imageData = imageData {
                caree.image = imageData
            }
            if let listOrder = listOrder {
                caree.listOrder = listOrder
            }

            // Update cache if available
            if let cacheService = cacheService {
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
    /// Since parent references use .none action, we must manually delete children first
    /// - Parameters:
    ///   - caree: Caree to delete
    ///   - isShared: Whether this is a shared caree
    func deleteCaree(_ caree: Caree, isShared: Bool = false) async throws {
        logger.info("Deleting Caree: \(caree.id)")
        syncStatus = .syncing
        deletionProgress = .deleting(0.0)

        do {
            if isShared {
                throw AppError.invalidInput("deleteCaree for shared records is not supported here. Use CloudKitSharedDataService.")
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
                if case .success(let record) = result {
                    activityTypeIDs.append(record.recordID)

                    // Step 2: Query for all Activities belonging to this ActivityType
                    let activityTypeRef = CKRecord.Reference(recordID: record.recordID, action: .none)
                    let activityQuery = CKQuery(
                        recordType: "CD_Activity",
                        predicate: NSPredicate(format: "CD_activityType == %@", activityTypeRef)
                    )

                    let (activityResults, _) = try await db.records(matching: activityQuery, inZoneWith: zoneID)

                    for (_, activityResult) in activityResults {
                        if case .success(let activityRecord) = activityResult {
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
            if let cacheService = cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id) {
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
    /// - Parameters:
    ///   - id: Caree UUID
    ///   - isShared: Whether to query shared database
    /// - Returns: Caree if found
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
    /// - Returns: Array of Carees
    func fetchAllCarees() async throws -> [Caree] {
        logger.info("Fetching all Carees from private database")

        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        let (matchResults, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var carees: [Caree] = []
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                do {
                    let caree = try await converter.recordToCaree(record)
                    carees.append(caree)
                } catch {
                    logger.warning("Failed to convert Caree record: \(error.localizedDescription)")
                }
            case .failure(let error):
                logger.warning("Failed to fetch Caree record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Fetched \(carees.count) Carees")
        return carees
    }

    // MARK: - ActivityType Operations

    /// Create a new ActivityType for a Caree
    /// - Returns: Created ActivityType
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
                throw AppError.invalidInput("createActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
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
            if let cacheService = cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id) {
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

    /// Update an existing ActivityType
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
                throw AppError.invalidInput("updateActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name = name {
                existingRecord["CD_name"] = name as CKRecordValue
            }
            if let icon = icon {
                existingRecord["CD_icon"] = icon as CKRecordValue
            }
            if let hasQuantity = hasQuantity {
                existingRecord["CD_hasQuantity"] = (hasQuantity ? 1 : 0) as CKRecordValue
            }
            if let quantityUnit = quantityUnit {
                existingRecord["CD_quantityUnit"] = quantityUnit as CKRecordValue
            }
            if let hasLocation = hasLocation {
                existingRecord["CD_hasLocation"] = (hasLocation ? 1 : 0) as CKRecordValue
            }
            if let listOrder = listOrder {
                existingRecord["CD_listOrder"] = listOrder as CKRecordValue
            }

            // Save updated record
            _ = try await saveWithRetry(existingRecord, to: db)

            // Update the activityType object with new values
            if let name = name {
                activityType.name = name
            }
            if let icon = icon {
                activityType.icon = icon
            }
            if let hasQuantity = hasQuantity {
                activityType.hasQuantity = hasQuantity
            }
            if let quantityUnit = quantityUnit {
                activityType.quantityUnit = quantityUnit
            }
            if let hasLocation = hasLocation {
                activityType.hasLocation = hasLocation
            }
            if let listOrder = listOrder {
                activityType.listOrder = listOrder
            }

            // Update cache if available - first get the cached caree
            if let cacheService = cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id) {
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

    /// Delete an ActivityType from CloudKit
    func deleteActivityType(_ activityType: ActivityType, isShared: Bool = false) async throws {
        logger.info("Deleting ActivityType: \(activityType.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError.invalidInput("deleteActivityType for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)

            try await deleteWithRetry(recordID: recordID, from: db)

            // Remove from cache if cache service is available
            if let cacheService = cacheService {
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

    /// Create a new Activity
    /// - Returns: Created Activity
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

        do {
            if isShared {
                throw AppError.invalidInput("createActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch parent records
            let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            let careeRecord = try await fetchWithRetry(recordID: careeRecordID, from: db)

            let activityTypeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
            let activityTypeRecord = try await fetchWithRetry(recordID: activityTypeRecordID, from: db)

            // Create domain model
            let activity = Activity(
                dateTime: dateTime,
                notes: notes,
                quantity: quantity,
                latitude: latitude,
                longitude: longitude
            )

            // Convert to CKRecord with parent references in custom zone
            let record = try converter.activityToRecord(
                activity,
                parentCaree: careeRecord,
                activityTypeRecord: activityTypeRecord,
                zoneID: zoneID
            )

            // Save to CloudKit
            let savedRecord = try await saveWithRetry(record, to: db)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: db)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model
            let syncedActivity = try converter.recordToActivity(savedRecord)

            // Cache the activity if cache service is available
            if let cacheService = cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id) {
                // Find cached activity type
                let cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
                if let cachedActivityType = cachedActivityTypes.first(where: { $0.id == activityType.id }) {
                    try await cacheService.cacheActivity(syncedActivity, for: cachedCaree, activityType: cachedActivityType)
                    logger.info("✅ Activity cached locally")
                }
            }

            logger.info("✅ Activity created and verified: \(syncedActivity.id)")
            syncStatus = .synced
            return syncedActivity

        } catch {
            logger.error("❌ Failed to create Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Update an existing Activity
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
                throw AppError.invalidInput("updateActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let dateTime = dateTime {
                existingRecord["CD_dateTime"] = dateTime as CKRecordValue
            }
            if let notes = notes {
                existingRecord["CD_notes"] = notes as CKRecordValue
            }
            if let quantity = quantity {
                existingRecord["CD_quantity"] = quantity as CKRecordValue
            }
            if let latitude = latitude {
                existingRecord["CD_latitude"] = latitude as CKRecordValue
            }
            if let longitude = longitude {
                existingRecord["CD_longitude"] = longitude as CKRecordValue
            }

            // Save updated record
            _ = try await saveWithRetry(existingRecord, to: db)

            // Update the activity object with new values
            if let dateTime = dateTime {
                activity.dateTime = dateTime
            }
            if let notes = notes {
                activity.notes = notes
            }
            if let quantity = quantity {
                activity.quantity = quantity
            }
            if let latitude = latitude {
                activity.latitude = latitude
            }
            if let longitude = longitude {
                activity.longitude = longitude
            }

            // Update cache if available
            if let cacheService = cacheService,
               let cachedCaree = cacheService.getCachedCaree(id: caree.id) {
                let cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
                if let cachedActivityType = cachedActivityTypes.first(where: { $0.id == activityType.id }) {
                    try await cacheService.cacheActivity(activity, for: cachedCaree, activityType: cachedActivityType)
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

    /// Delete an Activity from CloudKit
    func deleteActivity(_ activity: Activity, isShared: Bool = false) async throws {
        logger.info("Deleting Activity: \(activity.id)")
        syncStatus = .syncing

        do {
            if isShared {
                throw AppError.invalidInput("deleteActivity for shared records is not supported here. Use CloudKitSharedDataService.")
            }
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)

            try await deleteWithRetry(recordID: recordID, from: db)

            // Remove from cache if cache service is available
            if let cacheService = cacheService {
                try await cacheService.removeCachedActivity(activity)
                logger.info("✅ Activity removed from cache")
            }

            logger.info("✅ Activity deleted: \(activity.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    // MARK: - Zone Management (for Migration)

    /// Delete the custom CloudKit zone (destroys all records)
    /// WARNING: This permanently deletes all data in the zone
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

    /// Recreate the custom CloudKit zone
    func recreateCustomZone() async throws {
        logger.info("Creating custom CloudKit zone: \(Self.zoneName)")

        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await container.privateCloudDatabase.save(zone)
            logger.info("✅ Custom zone created: \(Self.zoneName)")
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists, which is fine
            logger.info("Zone already exists, continuing")
        } catch {
            logger.error("❌ Failed to create zone: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sync Verification

    /// Verify that a record exists in CloudKit
    /// - Returns: true if record exists
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

    /// Wait for a record to sync to CloudKit with timeout
    /// - Returns: true if record found before timeout
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

    /// Save a record with automatic retry on network failures
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
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    /// Fetch a record with automatic retry on network failures
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
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    /// Delete a record with automatic retry on network failures
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
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }
}

// MARK: - CKError Extension

extension CKError {
    /// Determine if error is retryable
    var isRetryable: Bool {
        switch code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }
}

// MARK: - Data Service Errors

enum DataServiceError: LocalizedError {
    case syncVerificationFailed(recordID: String)
    case maxRetriesExceeded
    case parentRecordNotFound(careeID: UUID)

    var errorDescription: String? {
        switch self {
        case .syncVerificationFailed(let recordID):
            return "Failed to verify sync for record: \(recordID)"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded. Please check your network connection."
        case .parentRecordNotFound(let careeID):
            return "Parent caree record not found: \(careeID)"
        }
    }
}
