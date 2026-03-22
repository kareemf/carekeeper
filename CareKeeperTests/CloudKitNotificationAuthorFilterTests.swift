@testable import CareKeeper
import CloudKit
import XCTest

final class CloudKitNotificationAuthorFilterTests: XCTestCase {
    // MARK: - No current user

    func testShouldNotifyWhenCurrentUserIsNil() {
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: "user-123",
            creatorIDField: "user-123",
            currentUserRecordName: nil
        )

        XCTAssertTrue(shouldNotify, "Cannot filter without knowing the current user.")
    }

    // MARK: - Explicit field matches current user

    func testShouldNotNotifyWhenCreatorFieldMatchesCurrentUser() {
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: nil,
            creatorIDField: "user-456",
            currentUserRecordName: "user-456"
        )

        XCTAssertFalse(shouldNotify, "Suppress when explicit field identifies current user.")
    }

    // MARK: - Explicit field differs (real participant ID)

    func testShouldNotifyWhenCreatorFieldIsRealParticipantDifferentFromCurrentUser() {
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: "owner-123",
            creatorIDField: "participant-999",
            currentUserRecordName: "owner-123"
        )

        XCTAssertTrue(
            shouldNotify,
            "When explicit field is a real participant ID that differs from current user, trust the field and notify."
        )
    }

    // MARK: - CloudKit metadata matches current user

    func testShouldNotNotifyWhenCreatorRecordIDMatchesCurrentUser() {
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: "user-123",
            creatorIDField: nil,
            currentUserRecordName: "user-123"
        )

        XCTAssertFalse(shouldNotify, "Suppress when CloudKit metadata identifies current user.")
    }

    // MARK: - CKCurrentUserDefaultName fallback (watchOS)

    func testShouldNotNotifyWhenFieldIsDefaultOwnerButRecordIDMatchesCurrentUser() {
        // This is the watchOS case: fetchCurrentUserRecordName() returned nil,
        // so the watch wrote __defaultOwner__ as CD_creatorUserRecordID.
        // CloudKit metadata correctly identifies the real user.
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: "real-user-record-id",
            creatorIDField: CKCurrentUserDefaultName,
            currentUserRecordName: "real-user-record-id"
        )

        XCTAssertFalse(
            shouldNotify,
            "When field is __defaultOwner__ (unreliable fallback), fall through to CloudKit metadata which correctly identifies current user."
        )
    }

    func testShouldNotifyWhenFieldIsDefaultOwnerAndRecordIDDiffersFromCurrentUser() {
        // Another user's activity with a fallback field value
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: "other-user-456",
            creatorIDField: CKCurrentUserDefaultName,
            currentUserRecordName: "current-user-123"
        )

        XCTAssertTrue(
            shouldNotify,
            "When field is __defaultOwner__ and CloudKit metadata shows a different user, notify."
        )
    }

    func testShouldNotifyWhenFieldIsDefaultOwnerAndRecordIDIsNil() {
        // Field is __defaultOwner__, no CloudKit metadata available
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: nil,
            creatorIDField: CKCurrentUserDefaultName,
            currentUserRecordName: "current-user-123"
        )

        XCTAssertTrue(
            shouldNotify,
            "When field is __defaultOwner__ and no CloudKit metadata, default to notify."
        )
    }

    // MARK: - Both identifiers nil

    func testShouldNotifyWhenBothIdentifiersAreNil() {
        let shouldNotify = CloudKitNotificationAuthorFilter.shouldNotify(
            creatorRecordID: nil,
            creatorIDField: nil,
            currentUserRecordName: "user-123"
        )

        XCTAssertTrue(shouldNotify, "Cannot determine creator, default to notify.")
    }
}
