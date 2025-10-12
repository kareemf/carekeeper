import SwiftUI
import SwiftData
import CloudKit

/// Service for CRUD operations on ActivityTypes and Activities in CloudKit shared database
/// Used when non-owners need to create/edit/delete data on shared carees
@MainActor
class CloudKitSharedDataService: ObservableObject {
    private let container: CKContainer
    private let logger = AppLogger.cloudkit

    init(containerIdentifier: String = CloudKitConfig.containerID) {
        self.container = CKContainer(identifier: containerIdentifier)
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

        // Save to shared database
        do {
            _ = try await sharedDatabase.save(record)
            logger.info("✅ Created ActivityType in shared database: \(name)")
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

        // Update record fields
        record["CD_name"] = activityType.name
        record["CD_icon"] = activityType.icon
        record["CD_hasQuantity"] = activityType.hasQuantity
        record["CD_quantityUnit"] = activityType.quantityUnit
        record["CD_hasLocation"] = activityType.hasLocation
        record["CD_listOrder"] = activityType.listOrder

        // Save updated record
        do {
            _ = try await sharedDatabase.save(record)
            logger.info("✅ Updated ActivityType in shared database: \(activityType.name)")
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
            throw AppError.invalidInput("Could not find ActivityType record in shared database")
        }

        // Delete record
        do {
            _ = try await sharedDatabase.deleteRecord(withID: record.recordID)
            logger.info("✅ Deleted ActivityType from shared database: \(activityType.name)")
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

        // Save to shared database
        do {
            _ = try await sharedDatabase.save(record)
            logger.info("✅ Created Activity in shared database at: \(dateTime)")
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

        // Save updated record
        do {
            _ = try await sharedDatabase.save(record)
            logger.info("✅ Updated Activity in shared database at: \(activity.dateTime)")
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
            throw AppError.invalidInput("Could not find Activity record in shared database")
        }

        // Delete record
        do {
            _ = try await sharedDatabase.deleteRecord(withID: record.recordID)
            logger.info("✅ Deleted Activity from shared database at: \(activity.dateTime)")
        } catch {
            logger.error("❌ Failed to delete Activity: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Find the zone ID for a shared caree
    private func findZoneID(for caree: Caree) async throws -> CKRecordZone.ID? {
        let sharedDatabase = container.sharedCloudDatabase
        let zones = try await sharedDatabase.allRecordZones()

        // Find the zone that contains this caree
        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                continue
            }

            let query = CKQuery(
                recordType: "CD_Caree",
                predicate: NSPredicate(format: "CD_id == %@", caree.id.uuidString)
            )

            do {
                let (results, _) = try await sharedDatabase.records(matching: query, inZoneWith: zone.zoneID)
                if !results.isEmpty {
                    return zone.zoneID
                }
            } catch {
                logger.warning("Failed to query zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
            }
        }

        return nil
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
                case .success(let record):
                    return record
                case .failure(let error):
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
                case .success(let record):
                    return record
                case .failure(let error):
                    throw error
                }
            }
        } catch {
            logger.error("Failed to find Activity record: \(error.localizedDescription)")
            throw error
        }

        return nil
    }

    /// Convert ActivityType to CKRecord
    private func convertActivityTypeToRecord(_ activityType: ActivityType, caree: Caree, zoneID: CKRecordZone.ID) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "CD_ActivityType", recordID: recordID)

        // Set all fields with CD_ prefix
        record["CD_id"] = activityType.id.uuidString
        record["CD_name"] = activityType.name
        record["CD_icon"] = activityType.icon
        record["CD_hasQuantity"] = activityType.hasQuantity
        record["CD_quantityUnit"] = activityType.quantityUnit
        record["CD_hasLocation"] = activityType.hasLocation
        record["CD_listOrder"] = activityType.listOrder
        record["CD_dateCreated"] = activityType.dateCreated

        // Create reference to caree
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
        record["CD_caree"] = CKRecord.Reference(recordID: careeRecordID, action: .deleteSelf)

        return record
    }

    /// Convert Activity to CKRecord
    private func convertActivityToRecord(_ activity: Activity, caree: Caree, activityType: ActivityType, zoneID: CKRecordZone.ID) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "CD_Activity", recordID: recordID)

        // Set all fields with CD_ prefix
        record["CD_id"] = activity.id.uuidString
        record["CD_dateTime"] = activity.dateTime
        record["CD_notes"] = activity.notes
        record["CD_quantity"] = activity.quantity
        record["CD_latitude"] = activity.latitude
        record["CD_longitude"] = activity.longitude
        record["CD_dateCreated"] = activity.dateCreated

        // Track the creator's CloudKit user record ID for notification filtering
        // This allows us to identify who created the activity and avoid showing notifications for our own actions
        record["CD_creatorUserRecordID"] = CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName

        // Create references
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
        record["CD_caree"] = CKRecord.Reference(recordID: careeRecordID, action: .deleteSelf)

        let activityTypeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
        record["CD_activityType"] = CKRecord.Reference(recordID: activityTypeRecordID, action: .deleteSelf)

        return record
    }
}
