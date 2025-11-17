import CloudKit
import Foundation

@MainActor
final class ActivityReminderMetadataStore {
    static let shared = ActivityReminderMetadataStore()

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "CD_ActivityReminderMetadata"

    init(containerID: String = CloudKitConfig.containerID) {
        container = CKContainer(identifier: containerID)
        database = container.privateCloudDatabase
    }

    private func recordID(for activityID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(recordType)/\(activityID.uuidString)")
    }

    func save(metadata: ActivityReminderMetadata) async throws {
        let recordID = recordID(for: metadata.activityID)
        let record: CKRecord

        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
            record["CD_activityID"] = metadata.activityID.uuidString as CKRecordValue
        } catch {
            throw error
        }

        record["CD_reminderIdentifier"] = metadata.reminderIdentifier
        record["CD_reminderDueDate"] = metadata.reminderDueDate
        record["CD_reminderSourceRawValue"] = metadata.reminderSource?.rawValue

        _ = try await database.save(record)
    }

    func deleteMetadata(for activityID: UUID) async {
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

        let recordIDs = activityIDs.map(recordID(for:))
        let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
        operation.desiredKeys = [
            "CD_activityID",
            "CD_reminderIdentifier",
            "CD_reminderDueDate",
            "CD_reminderSourceRawValue",
        ]

        var metadata: [UUID: ActivityReminderMetadata] = [:]

        operation.perRecordResultBlock = { _, result in
            switch result {
            case let .success(record):
                guard let idString = record["CD_activityID"] as? String,
                      let activityID = UUID(uuidString: idString)
                else { return }
                let entry = ActivityReminderMetadata(
                    activityID: activityID,
                    reminderIdentifier: record["CD_reminderIdentifier"] as? String,
                    reminderDueDate: record["CD_reminderDueDate"] as? Date,
                    reminderSource: (record["CD_reminderSourceRawValue"] as? String).flatMap { ReminderSource(rawValue: $0) }
                )
                metadata[activityID] = entry
            case let .failure(error):
                if case CKError.unknownItem = error {
                    return
                }
                AppLogger.cloudkit
                    .warning("⚠️ Failed to fetch reminder metadata record: \(error.localizedDescription)")
            }
        }

        try await database.add(operation)
        return metadata
    }
}
