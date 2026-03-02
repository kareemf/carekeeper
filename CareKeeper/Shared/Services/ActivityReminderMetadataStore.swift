import CloudKit
import Foundation

protocol ReminderMetadataStoreProtocol: AnyObject {
    func save(metadata: ActivityReminderMetadata) async throws
    func deleteMetadata(for activityID: UUID) async
    func fetchMetadata(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata]
}

final class ActivityReminderMetadataStore: ReminderMetadataStoreProtocol {
    static let shared: any ReminderMetadataStoreProtocol = ActivityReminderMetadataStore()

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
    private let recordType = "CD_ActivityReminderMetadata"
    private var zoneEnsured = false

    init(containerID: String = CloudKitConfig.containerID) {
        container = CKContainer(identifier: containerID)
        database = container.privateCloudDatabase
    }

    private func recordID(for activityID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(recordType)/\(activityID.uuidString)", zoneID: zoneID)
    }

    private func ensureZoneExists() async throws {
        guard !zoneEnsured else { return }
        do {
            let zones = try await database.allRecordZones()
            if zones.contains(where: { $0.zoneID == zoneID }) {
                zoneEnsured = true
                return
            }
        } catch {
            AppLogger.cloudkit
                .warning("⚠️ Failed to list zones for reminder metadata: \(error.localizedDescription)")
        }

        do {
            let zone = CKRecordZone(zoneID: zoneID)
            try await database.save(zone)
            zoneEnsured = true
        } catch let error as CKError where error.code == .serverRecordChanged {
            zoneEnsured = true
        } catch {
            zoneEnsured = false
            throw error
        }
    }

    func save(metadata: ActivityReminderMetadata) async throws {
        try await ensureZoneExists()
        let recordID = recordID(for: metadata.activityID)
        var mergedMetadata = metadata
        let record: CKRecord

        do {
            record = try await database.record(for: recordID)
            if mergedMetadata.ekReminderIdentifier == nil {
                mergedMetadata.ekReminderIdentifier = record["CD_ekReminderIdentifier"] as? String
            }
            if mergedMetadata.unNotificationIdentifier == nil {
                mergedMetadata.unNotificationIdentifier = record["CD_unNotificationIdentifier"] as? String
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
            record["CD_activityID"] = metadata.activityID.uuidString as CKRecordValue
        } catch {
            throw error
        }

        record["CD_reminderDueDate"] = mergedMetadata.reminderDueDate
        record["CD_reminderSourceRawValue"] = mergedMetadata.reminderSource?.rawValue
        record["CD_ekReminderIdentifier"] = mergedMetadata.ekReminderIdentifier
        record["CD_unNotificationIdentifier"] = mergedMetadata.unNotificationIdentifier

        _ = try await database.save(record)
        AppLogger.cloudkit
            .info("💾 Saved reminder metadata for activity \(metadata.activityID.uuidString, privacy: .public)")
    }

    func deleteMetadata(for activityID: UUID) async {
        do {
            try await ensureZoneExists()
        } catch {
            AppLogger.cloudkit
                .warning("⚠️ Failed to ensure zone before deleting reminder metadata: \(error.localizedDescription)")
        }
        let recordID = recordID(for: activityID)
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Ignore if already removed
        } catch {
            AppLogger.cloudkit.warning("⚠️ Failed to delete reminder metadata: \(error.localizedDescription)")
        }
    }

    func fetchMetadata(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata] {
        guard !activityIDs.isEmpty else { return [:] }
        try await ensureZoneExists()

        let batchSize = 400
        var allMetadata: [UUID: ActivityReminderMetadata] = [:]
        for batchStart in stride(from: 0, to: activityIDs.count, by: batchSize) {
            let batch = Array(activityIDs[batchStart..<min(batchStart + batchSize, activityIDs.count)])
            let result = try await fetchMetadataBatch(for: batch)
            allMetadata.merge(result) { _, new in new }
        }
        return allMetadata
    }

    private func fetchMetadataBatch(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata] {
        return try await withCheckedThrowingContinuation { continuation in
            let recordIDs = activityIDs.map(self.recordID(for:))
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.desiredKeys = [
                "CD_activityID",
                "CD_reminderDueDate",
                "CD_reminderSourceRawValue",
                "CD_ekReminderIdentifier",
                "CD_unNotificationIdentifier",
            ]

            let lock = NSLock()
            var metadata: [UUID: ActivityReminderMetadata] = [:]

            operation.perRecordResultBlock = { _, result in
                switch result {
                case let .success(record):
                    guard let idString = record["CD_activityID"] as? String,
                          let activityID = UUID(uuidString: idString)
                    else { return }
                    let entry = ActivityReminderMetadata(
                        activityID: activityID,
                        reminderDueDate: record["CD_reminderDueDate"] as? Date,
                        reminderSource: (record["CD_reminderSourceRawValue"] as? String).flatMap { ReminderSource(rawValue: $0) },
                        ekReminderIdentifier: record["CD_ekReminderIdentifier"] as? String,
                        unNotificationIdentifier: record["CD_unNotificationIdentifier"] as? String,
                        changeTag: record.recordChangeTag
                    )
                    lock.lock()
                    metadata[activityID] = entry
                    lock.unlock()
                case let .failure(error):
                    if case CKError.unknownItem = error {
                        return
                    }
                    AppLogger.cloudkit
                        .warning("⚠️ Failed to fetch reminder metadata record: \(error.localizedDescription)")
                }
            }

            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: metadata)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            self.database.add(operation)
        }
    }
}
