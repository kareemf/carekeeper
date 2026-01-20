@testable import CareKeeper
import CloudKit
import XCTest

@MainActor
final class CloudKitUserIdentityServiceTests: XCTestCase {
    func testCurrentUserRecordNameCachesValue() async {
        let service = CloudKitUserIdentityService(testing: ())
        let fetcher = FakeUserRecordFetcher(recordName: "user-123")

        let first = await service.currentUserRecordName(fetcher: fetcher)
        let second = await service.currentUserRecordName(fetcher: fetcher)

        XCTAssertEqual(first, "user-123")
        XCTAssertEqual(second, "user-123")
        XCTAssertEqual(fetcher.callCount, 1, "Fetcher should only be called once due to caching.")
    }
}

private final class FakeUserRecordFetcher: CloudKitUserRecordIDFetching {
    private(set) var callCount = 0
    private let recordID: CKRecord.ID

    init(recordName: String) {
        recordID = CKRecord.ID(recordName: recordName)
    }

    func fetchUserRecordID(_ completionHandler: @escaping (CKRecord.ID?, Error?) -> Void) {
        callCount += 1
        completionHandler(recordID, nil)
    }
}
