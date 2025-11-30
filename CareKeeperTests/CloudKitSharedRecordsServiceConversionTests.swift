@testable import CareKeeper
import CloudKit
import XCTest

@MainActor
final class CloudKitSharedRecordsServiceConversionTests: XCTestCase {
    func testConvertRecordsOffMainBuildsRelationships() async throws {
        let service = CloudKitSharedRecordsService(container: CKContainer(identifier: CloudKitConfig.containerID))

        let sample = makeSampleRecords()
        let payload = try await service.convertRecordsOffMain(
            sample.careeRecords,
            activityTypeRecords: sample.activityTypeRecords,
            activityRecords: sample.activityRecords
        )

        let (carees, typesByCaree, activitiesByCaree, mapping) = service.makeModels(from: payload)

        XCTAssertEqual(carees.count, 1)
        let caree = try XCTUnwrap(carees.first)
        XCTAssertEqual(caree.id, sample.careeID)
        XCTAssertEqual(caree.activityTypes?.count, 1)
        XCTAssertEqual(caree.activities?.count, 1)

        let type = try XCTUnwrap(typesByCaree[sample.careeID]?.first)
        XCTAssertEqual(type.id, sample.activityTypeID)
        XCTAssertEqual(type.caree?.id, sample.careeID)

        let activity = try XCTUnwrap(activitiesByCaree[sample.careeID]?.first)
        XCTAssertEqual(activity.id, sample.activityID)
        XCTAssertEqual(activity.activityType?.id, sample.activityTypeID)
        XCTAssertEqual(mapping[activity.id], sample.activityTypeID)
    }

    func testConvertRecordsToPayloadRunsOffMainThread() async throws {
        let sample = makeSampleRecords()

        let ranOffMain = try await Task.detached(priority: .utility) { () throws -> Bool in
            _ = try CloudKitSharedRecordsService.convertRecordsToPayload(
                sample.careeRecords,
                activityTypeRecords: sample.activityTypeRecords,
                activityRecords: sample.activityRecords
            )
            return !Thread.isMainThread
        }.value

        XCTAssertTrue(ranOffMain, "convertRecordsSync should be usable from a background thread")
    }
}

// MARK: - Helpers

private extension CloudKitSharedRecordsServiceConversionTests {
    struct SampleRecords {
        let careeID: UUID
        let activityTypeID: UUID
        let activityID: UUID
        let careeRecords: [CKRecord]
        let activityTypeRecords: [CKRecord]
        let activityRecords: [CKRecord]
    }

    func makeSampleRecords() -> SampleRecords {
        let careeID = UUID()
        let activityTypeID = UUID()
        let activityID = UUID()

        let careeRecord = CKRecord(
            recordType: "CD_Caree",
            recordID: CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)")
        )
        careeRecord["CD_id"] = careeID.uuidString as CKRecordValue
        careeRecord["CD_name"] = "Sample Caree" as CKRecordValue
        careeRecord["CD_listOrder"] = 1 as CKRecordValue
        careeRecord["CD_dateCreated"] = Date() as CKRecordValue

        let careeReference = CKRecord.Reference(recordID: careeRecord.recordID, action: .none)

        let activityTypeRecord = CKRecord(
            recordType: "CD_ActivityType",
            recordID: CKRecord.ID(recordName: "CD_ActivityType/\(activityTypeID.uuidString)")
        )
        activityTypeRecord["CD_id"] = activityTypeID.uuidString as CKRecordValue
        activityTypeRecord["CD_name"] = "Type" as CKRecordValue
        activityTypeRecord["CD_icon"] = "⭐️" as CKRecordValue
        activityTypeRecord["CD_hasQuantity"] = 1 as CKRecordValue
        activityTypeRecord["CD_hasLocation"] = 0 as CKRecordValue
        activityTypeRecord["CD_listOrder"] = 0 as CKRecordValue
        activityTypeRecord["CD_dateCreated"] = Date() as CKRecordValue
        activityTypeRecord["CD_caree"] = careeReference

        let activityTypeReference = CKRecord.Reference(recordID: activityTypeRecord.recordID, action: .none)

        let activityRecord = CKRecord(
            recordType: "CD_Activity",
            recordID: CKRecord.ID(recordName: "CD_Activity/\(activityID.uuidString)")
        )
        activityRecord["CD_id"] = activityID.uuidString as CKRecordValue
        activityRecord["CD_dateTime"] = Date() as CKRecordValue
        activityRecord["CD_notes"] = "note" as CKRecordValue
        activityRecord["CD_quantity"] = 2.0 as CKRecordValue
        activityRecord["CD_latitude"] = 10.0 as CKRecordValue
        activityRecord["CD_longitude"] = 20.0 as CKRecordValue
        activityRecord["CD_dateCreated"] = Date() as CKRecordValue
        activityRecord["CD_caree"] = careeReference
        activityRecord["CD_activityType"] = activityTypeReference

        return SampleRecords(
            careeID: careeID,
            activityTypeID: activityTypeID,
            activityID: activityID,
            careeRecords: [careeRecord],
            activityTypeRecords: [activityTypeRecord],
            activityRecords: [activityRecord]
        )
    }
}
