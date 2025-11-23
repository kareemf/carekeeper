@testable import CareKeeper
import CloudKit
import XCTest

@MainActor
final class CloudKitSharedRecordsServiceZoneNotificationTests: XCTestCase {
    func testHandleSharedZoneNotificationTriggersFetchAndRefresh() async {
        let service = TestSharedRecordsService()
        let zoneID = CKRecordZone.ID(zoneName: "shared-test", ownerName: "owner")
        let notification = CKRecordZoneNotification(fromRemoteNotificationDictionary: [
            "ck": [
                "qid": zoneID.zoneName,
                "sid": "shared-zone-\(zoneID.zoneName)-\(zoneID.ownerName)",
            ],
        ])!
        notification.setValue(zoneID, forKey: "recordZoneID")

        await service.handleSharedZoneNotification(notification)

        XCTAssertEqual(service.fetchedZoneID, zoneID)
        XCTAssertTrue(service.fetchSharedChangesCalled)
        XCTAssertTrue(service.fetchSharedCareesCalled)
    }
}

@MainActor
private final class TestSharedRecordsService: CloudKitSharedRecordsService {
    var fetchedZoneID: CKRecordZone.ID?
    var fetchSharedChangesCalled = false
    var fetchSharedCareesCalled = false

    init() {
        super.init(container: CKContainer(identifier: CloudKitConfig.containerID))
    }

    override func fetchSharedChanges(for zoneID: CKRecordZone.ID, existingActivityIDs: Set<UUID>) async {
        fetchedZoneID = zoneID
        fetchSharedChangesCalled = true
    }

    override func fetchSharedCarees(force: Bool, reason: String) async {
        fetchSharedCareesCalled = true
    }

    override func fetchSharedCarees() async {
        fetchSharedCareesCalled = true
    }
}
