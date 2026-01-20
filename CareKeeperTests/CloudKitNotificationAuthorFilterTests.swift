@testable import CareKeeper
import CloudKit
import XCTest

final class CloudKitNotificationAuthorFilterTests: XCTestCase {
    func testShouldNotifyWhenCreatorFieldIsDefaultOwnerButCurrentUserIsRealRecordID() {
        let creatorIDField = CKCurrentUserDefaultName
        let creatorRecordID: String? = nil
        let currentUserRecordName = "real-user-record-id"

        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: creatorRecordID,
            creatorIDField: creatorIDField,
            currentUserRecordName: currentUserRecordName
        )

        XCTAssertTrue(
            shouldNotify,
            "Using CKCurrentUserDefaultName should not suppress notifications when the real user record ID differs."
        )
    }

    func testShouldNotNotifyWhenCreatorRecordIDMatchesCurrentUser() {
        let creatorRecordID = "user-123"
        let currentUserRecordName = "user-123"

        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: creatorRecordID,
            creatorIDField: nil,
            currentUserRecordName: currentUserRecordName
        )

        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotNotifyWhenCreatorFieldMatchesCurrentUserAndRecordIDMissing() {
        let currentUserRecordName = "user-456"

        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: nil,
            creatorIDField: currentUserRecordName,
            currentUserRecordName: currentUserRecordName
        )

        XCTAssertFalse(shouldNotify)
    }

    func testShouldNotifyWhenCreatorRecordIDMatchesCurrentUserButFieldDiffers() {
        let creatorRecordID = "owner-123"
        let creatorIDField = "participant-999"
        let currentUserRecordName = "owner-123"

        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: creatorRecordID,
            creatorIDField: creatorIDField,
            currentUserRecordName: currentUserRecordName
        )

        XCTAssertTrue(
            shouldNotify,
            "Prefer the explicit creator field when it differs from the current user."
        )
    }
}
