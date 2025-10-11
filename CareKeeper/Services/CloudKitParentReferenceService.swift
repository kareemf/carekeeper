import CloudKit
import SwiftData

/// Service to set CloudKit parent references for SwiftData cascade relationships
/// SwiftData doesn't automatically set CKRecord.parent for @Relationship(cascade)
/// This service ensures parent-child relationships are established at the CloudKit level
/// so that CKShare includes child records (ActivityTypes, Activities)
@MainActor
class CloudKitParentReferenceService: ObservableObject {
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let logger = AppLogger.cloudkit

    init(containerIdentifier: String = CloudKitConfig.containerID) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
    }

    // MARK: - Public API

    /// Ensure all ActivityTypes and Activities for a Caree have proper parent references
    /// Call this before creating a CKShare to ensure child records are included
    func ensureParentReferences(for caree: Caree) async throws {
        logger.info("🔧 Ensuring parent references for Caree: \(caree.name)")

        // Find the parent Caree's CKRecord
        guard let parentRecord = try await findCareeRecord(caree) else {
            throw AppError.invalidInput("Caree record not found in CloudKit. Ensure it's synced first.")
        }

        logger.info("   Found parent Caree record: \(parentRecord.recordID.recordName)")

        // Fix ActivityType parent references
        let activityTypeCount = try await fixActivityTypeParents(caree: caree, parentRecord: parentRecord)
        logger.info("   Fixed \(activityTypeCount) ActivityType parent references")

        // Fix Activity parent references
        let activityCount = try await fixActivityParents(caree: caree, parentRecord: parentRecord)
        logger.info("   Fixed \(activityCount) Activity parent references")

        logger.info("✅ Parent references complete: \(activityTypeCount) ActivityTypes, \(activityCount) Activities")
    }

    // MARK: - Private Helpers

    /// Find the CKRecord for a Caree
    private func findCareeRecord(_ caree: Caree) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_Caree", predicate: predicate)

        let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        if let first = results.first {
            let (_, result) = first
            switch result {
            case .success(let record):
                return record
            case .failure(let error):
                throw error
            }
        }

        return nil
    }

    /// Fix parent references for all ActivityTypes belonging to a Caree
    private func fixActivityTypeParents(caree: Caree, parentRecord: CKRecord) async throws -> Int {
        // Query for ActivityTypes that belong to this Caree
        let predicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_ActivityType", predicate: predicate)

        let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var recordsToSave: [CKRecord] = []

        for (_, result) in results {
            switch result {
            case .success(let record):
                // Check if parent is already set correctly
                if record.parent?.recordID != parentRecord.recordID {
                    logger.info("     Setting parent for ActivityType: \(record["CD_name"] as? String ?? "Unknown")")

                    // Set the parent reference
                    record.setParent(parentRecord)
                    recordsToSave.append(record)
                } else {
                    logger.info("     ActivityType already has correct parent: \(record["CD_name"] as? String ?? "Unknown")")
                }
            case .failure(let error):
                logger.warning("     Failed to fetch ActivityType record: \(error.localizedDescription)")
            }
        }

        // Save all modified records
        if !recordsToSave.isEmpty {
            let saveResults = try await container.privateCloudDatabase.modifyRecords(
                saving: recordsToSave,
                deleting: []
            )

            // Check for save errors
            for (recordID, result) in saveResults.saveResults {
                switch result {
                case .success:
                    logger.info("     ✅ Saved parent reference for: \(recordID.recordName)")
                case .failure(let error):
                    logger.error("     ❌ Failed to save parent reference for \(recordID.recordName): \(error.localizedDescription)")
                }
            }
        }

        return recordsToSave.count
    }

    /// Fix parent references for all Activities belonging to a Caree
    private func fixActivityParents(caree: Caree, parentRecord: CKRecord) async throws -> Int {
        // Query for Activities that belong to this Caree
        let predicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_Activity", predicate: predicate)

        let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var recordsToSave: [CKRecord] = []

        for (_, result) in results {
            switch result {
            case .success(let record):
                // Check if parent is already set correctly
                if record.parent?.recordID != parentRecord.recordID {
                    logger.info("     Setting parent for Activity: \(record["CD_dateTime"] as? Date ?? Date())")

                    // Set the parent reference
                    record.setParent(parentRecord)
                    recordsToSave.append(record)
                } else {
                    logger.info("     Activity already has correct parent: \(record["CD_dateTime"] as? Date ?? Date())")
                }
            case .failure(let error):
                logger.warning("     Failed to fetch Activity record: \(error.localizedDescription)")
            }
        }

        // Save all modified records
        if !recordsToSave.isEmpty {
            let saveResults = try await container.privateCloudDatabase.modifyRecords(
                saving: recordsToSave,
                deleting: []
            )

            // Check for save errors
            for (recordID, result) in saveResults.saveResults {
                switch result {
                case .success:
                    logger.info("     ✅ Saved parent reference for: \(recordID.recordName)")
                case .failure(let error):
                    logger.error("     ❌ Failed to save parent reference for \(recordID.recordName): \(error.localizedDescription)")
                }
            }
        }

        return recordsToSave.count
    }

    // MARK: - Verification

    /// Verify that all child records have correct parent references
    /// Useful for diagnostics
    func verifyParentReferences(for caree: Caree) async throws -> (activityTypes: Int, activities: Int, missingParents: Int) {
        guard let parentRecord = try await findCareeRecord(caree) else {
            throw AppError.invalidInput("Caree record not found in CloudKit")
        }

        var activityTypeCount = 0
        var activityCount = 0
        var missingParents = 0

        // Check ActivityTypes
        let activityTypePredicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let activityTypeQuery = CKQuery(recordType: "CD_ActivityType", predicate: activityTypePredicate)
        let (activityTypeResults, _) = try await container.privateCloudDatabase.records(matching: activityTypeQuery, inZoneWith: zoneID)

        for (_, result) in activityTypeResults {
            if case .success(let record) = result {
                activityTypeCount += 1
                if record.parent?.recordID != parentRecord.recordID {
                    missingParents += 1
                    logger.warning("⚠️ ActivityType missing parent: \(record["CD_name"] as? String ?? "Unknown")")
                }
            }
        }

        // Check Activities
        let activityPredicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let activityQuery = CKQuery(recordType: "CD_Activity", predicate: activityPredicate)
        let (activityResults, _) = try await container.privateCloudDatabase.records(matching: activityQuery, inZoneWith: zoneID)

        for (_, result) in activityResults {
            if case .success(let record) = result {
                activityCount += 1
                if record.parent?.recordID != parentRecord.recordID {
                    missingParents += 1
                    logger.warning("⚠️ Activity missing parent: \(record["CD_dateTime"] as? Date ?? Date())")
                }
            }
        }

        logger.info("📊 Verification complete:")
        logger.info("   ActivityTypes: \(activityTypeCount)")
        logger.info("   Activities: \(activityCount)")
        logger.info("   Missing parents: \(missingParents)")

        return (activityTypeCount, activityCount, missingParents)
    }
}
