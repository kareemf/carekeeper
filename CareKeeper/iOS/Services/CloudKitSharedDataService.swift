import CloudKit
import SwiftData
import SwiftUI

/// Service for CRUD operations on ActivityTypes and Activities in CloudKit shared database
/// Used when non-owners need to create/edit/delete data on shared carees
@MainActor
class CloudKitSharedDataService: ObservableObject {
    private let container: CKContainer
    private let logger = AppLogger.cloudkit
    private let converter = CloudKitRecordConverter()
    private let zoneDiscovery: CloudKitZoneDiscoveryService
    private let retryService: CloudKitRetryService
    private let reminderMetadataStore: any ReminderMetadataStoreProtocol

    // Optional local cache for immediate UI updates after successful mutations
    private var cacheService: LocalCacheService?

    init(
        containerIdentifier: String = CloudKitConfig.containerID,
        reminderMetadataStore: (any ReminderMetadataStoreProtocol)? = nil
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneDiscovery = CloudKitZoneDiscoveryService(containerIdentifier: containerIdentifier)
        self.retryService = CloudKitRetryService()
        self.reminderMetadataStore = reminderMetadataStore ?? ActivityReminderMetadataStore.shared
    }

    func setCacheService(_ cacheService: LocalCacheService) {
        self.cacheService = cacheService
    }

    // MARK: - ActivityType Operations

    /// Create a new ActivityType in the shared database
    func createActivityType(
        for caree: Caree,
        name: String,
        icon: String?,
        hasQuantity: Bool,
        quantityUnit: String?,
        hasLocation: Bool,
        listOrder: Int
    ) async throws -> ActivityType {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Create the ActivityType object
        let activityType = ActivityType(
            name: name,
            icon: icon,
            hasQuantity: hasQuantity,
            quantityUnit: quantityUnit,
            hasLocation: hasLocation,
            listOrder: listOrder,
            caree: caree
        )

        // Convert to CKRecord
        let record = try await convertActivityTypeToRecord(activityType, caree: caree, zoneID: zoneID)

        // Save to shared database with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "createActivityType(\(name))") {
                try await sharedDatabase.save(record)
            }
            logger.info("✅ Created ActivityType in shared database: \(name)")

            // Optimistically update local cache
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.cacheActivityType(activityType, for: caree)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }

            return activityType
        } catch {
            logger.error("❌ Failed to create ActivityType: \(error.localizedDescription)")
            throw error
        }
    }

    /// Update an existing ActivityType in the shared database
    func updateActivityType(
        _ activityType: ActivityType,
        caree: Caree
    ) async throws {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Fetch the existing record
        guard let record = try await findActivityTypeRecord(activityType, in: zoneID) else {
            throw AppError.invalidInput("Could not find ActivityType record in shared database")
        }

        // Update record fields (normalize Int 0/1 for hasQuantity/hasLocation to match schema)
        record["CD_name"] = activityType.name
        record["CD_icon"] = activityType.icon
        record["CD_hasQuantity"] = (activityType.hasQuantity ? 1 : 0) as CKRecordValue
        record["CD_quantityUnit"] = activityType.quantityUnit
        record["CD_hasLocation"] = (activityType.hasLocation ? 1 : 0) as CKRecordValue
        record["CD_listOrder"] = activityType.listOrder

        // Save updated record with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "updateActivityType(\(activityType.name))") {
                try await sharedDatabase.save(record)
            }
            logger.info("✅ Updated ActivityType in shared database: \(activityType.name)")

            // Optimistically update local cache
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.cacheActivityType(activityType, for: caree)
                }
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }
        } catch {
            logger.error("❌ Failed to update ActivityType: \(error.localizedDescription)")
            throw error
        }
    }

    /// Delete an ActivityType from the shared database
    func deleteActivityType(_ activityType: ActivityType, caree: Caree) async throws {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Fetch the existing record
        guard let record = try await findActivityTypeRecord(activityType, in: zoneID) else {
            // ActivityType not found in shared database - probably already deleted by another participant
            logger
                .info(
                    "ℹ️ ActivityType not found in shared database (likely already deleted by another participant): \(activityType.name)"
                )

            // Remove from local cache to ensure consistency
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.removeCachedActivityType(activityType)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }

            // Return successfully without throwing error (graceful handling for collaborative deletions)
            return
        }

        // Delete record with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "deleteActivityType(\(activityType.name))") {
                try await sharedDatabase.deleteRecord(withID: record.recordID)
            }
            logger.info("✅ Deleted ActivityType from shared database: \(activityType.name)")

            // Remove from local cache
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.removeCachedActivityType(activityType)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }
        } catch {
            logger.error("❌ Failed to delete ActivityType: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Activity Operations

    /// Create a new Activity in the shared database
    func createActivity(
        for caree: Caree,
        activityType: ActivityType,
        dateTime: Date,
        notes: String?,
        quantity: Double?,
        latitude: Double?,
        longitude: Double?
    ) async throws -> Activity {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Create the Activity object
        let activity = Activity(
            dateTime: dateTime,
            notes: notes,
            quantity: quantity,
            latitude: latitude,
            longitude: longitude,
            activityType: activityType,
            caree: caree
        )

        // Convert to CKRecord
        let record = try await convertActivityToRecord(activity, caree: caree, activityType: activityType, zoneID: zoneID)

        // Save to shared database with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "createActivity(\(dateTime))") {
                try await sharedDatabase.save(record)
            }
            logger.info("✅ Created Activity in shared database at: \(dateTime)")

            // Optimistically update local cache
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.cacheActivity(activity, for: caree, activityTypeID: activityType.id)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }

            return activity
        } catch {
            logger.error("❌ Failed to create Activity: \(error.localizedDescription)")
            throw error
        }
    }

    /// Update an existing Activity in the shared database
    func updateActivity(
        _ activity: Activity,
        caree: Caree
    ) async throws {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Fetch the existing record
        guard let record = try await findActivityRecord(activity, in: zoneID) else {
            throw AppError.invalidInput("Could not find Activity record in shared database")
        }

        // Update record fields
        record["CD_dateTime"] = activity.dateTime
        record["CD_notes"] = activity.notes
        record["CD_quantity"] = activity.quantity
        record["CD_latitude"] = activity.latitude
        record["CD_longitude"] = activity.longitude

        // Save updated record with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "updateActivity(\(activity.dateTime))") {
                try await sharedDatabase.save(record)
            }
            logger.info("✅ Updated Activity in shared database at: \(activity.dateTime)")

            // Optimistically update local cache
            if let cache = cacheService, let activityType = activity.activityType {
                try? await cache.withBatch {
                    try await cache.cacheActivity(activity, for: caree, activityTypeID: activityType.id)
                }
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }
        } catch {
            logger.error("❌ Failed to update Activity: \(error.localizedDescription)")
            throw error
        }
    }

    /// Delete an Activity from the shared database
    func deleteActivity(_ activity: Activity, caree: Caree) async throws {
        let sharedDatabase = container.sharedCloudDatabase

        // Find the zone for this caree
        guard let zoneID = try await findZoneID(for: caree) else {
            throw AppError.invalidInput("Could not find shared zone for caree")
        }

        // Fetch the existing record
        guard let record = try await findActivityRecord(activity, in: zoneID) else {
            // Activity not found in shared database - probably already deleted by another participant
            logger
                .info(
                    "ℹ️ Activity not found in shared database (likely already deleted by another participant): \(activity.dateTime)"
                )

            // Remove from local cache to ensure consistency
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.removeCachedActivity(activity)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }

            // Return successfully without throwing error (graceful handling for collaborative deletions)
            return
        }

        // Delete record with retry logic
        do {
            _ = try await retryService.retryableRequest(operation: "deleteActivity(\(activity.dateTime))") {
                try await sharedDatabase.deleteRecord(withID: record.recordID)
            }
            logger.info("✅ Deleted Activity from shared database at: \(activity.dateTime)")

            // Remove from local cache
            if let cache = cacheService {
                try? await cache.withBatch {
                    try await cache.removeCachedActivity(activity)
                }
                // Force immediate refresh of published properties so views see the update
                await cache.refreshPublishedProperties()
                // Post notification for immediate UI update
                NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)
            }

            await reminderMetadataStore.deleteMetadata(for: activity.id)
        } catch {
            logger.error("❌ Failed to delete Activity: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Find the zone ID for a shared caree
    private func findZoneID(for caree: Caree) async throws -> CKRecordZone.ID? {
        try await zoneDiscovery.findZone(for: caree.id)
    }

    /// Find an existing ActivityType record in the shared database
    private func findActivityTypeRecord(_ activityType: ActivityType, in zoneID: CKRecordZone.ID) async throws -> CKRecord? {
        let sharedDatabase = container.sharedCloudDatabase
        let query = CKQuery(
            recordType: "CD_ActivityType",
            predicate: NSPredicate(format: "CD_id == %@", activityType.id.uuidString)
        )

        do {
            let (results, _) = try await sharedDatabase.records(matching: query, inZoneWith: zoneID)
            if let first = results.first {
                let (_, result) = first
                switch result {
                case let .success(record):
                    return record
                case let .failure(error):
                    throw error
                }
            }
        } catch {
            logger.error("Failed to find ActivityType record: \(error.localizedDescription)")
            throw error
        }

        return nil
    }

    /// Find an existing Activity record in the shared database
    private func findActivityRecord(_ activity: Activity, in zoneID: CKRecordZone.ID) async throws -> CKRecord? {
        let sharedDatabase = container.sharedCloudDatabase
        let query = CKQuery(
            recordType: "CD_Activity",
            predicate: NSPredicate(format: "CD_id == %@", activity.id.uuidString)
        )

        do {
            let (results, _) = try await sharedDatabase.records(matching: query, inZoneWith: zoneID)
            if let first = results.first {
                let (_, result) = first
                switch result {
                case let .success(record):
                    return record
                case let .failure(error):
                    throw error
                }
            }
        } catch {
            logger.error("Failed to find Activity record: \(error.localizedDescription)")
            throw error
        }

        return nil
    }

    /// Convert ActivityType to CKRecord with parent reference (CRITICAL for sharing)
    private func convertActivityTypeToRecord(
        _ activityType: ActivityType,
        caree: Caree,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord {
        // Fetch the parent Caree record from shared database (needed for parent reference)
        let sharedDatabase = container.sharedCloudDatabase
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)

        let parentCareeRecord = try await retryService.retryableRequest(operation: "fetchCareeRecord(\(caree.id))") {
            try await sharedDatabase.record(for: careeRecordID)
        }

        // Build the record directly in the correct zone via the converter
        let record = try converter.activityTypeToRecord(
            activityType,
            parentCaree: parentCareeRecord,
            zoneID: zoneID,
            existingRecord: nil
        )

        logger.info("✅ Created ActivityType record with parent for shared database: \(activityType.name)")
        return record
    }

    /// Convert Activity to CKRecord with parent reference (CRITICAL for sharing)
    private func convertActivityToRecord(
        _ activity: Activity,
        caree: Caree,
        activityType: ActivityType,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord {
        // Fetch parent records from shared database (needed for parent references)
        let sharedDatabase = container.sharedCloudDatabase
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
        let activityTypeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)

        let parentCareeRecord = try await retryService.retryableRequest(operation: "fetchCareeRecord(\(caree.id))") {
            try await sharedDatabase.record(for: careeRecordID)
        }
        let activityTypeRecord = try await retryService
            .retryableRequest(operation: "fetchActivityTypeRecord(\(activityType.id))") {
                try await sharedDatabase.record(for: activityTypeRecordID)
            }

        // Build the record directly in the correct zone via the converter
        let record = try converter.activityToRecord(
            activity,
            parentCaree: parentCareeRecord,
            activityTypeRecord: activityTypeRecord,
            zoneID: zoneID,
            existingRecord: nil
        )

        logger.info("✅ Created Activity record with parent for shared database at: \(activity.dateTime)")
        return record
    }
}
