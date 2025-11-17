@testable import CareKeeper
import EventKit
import XCTest

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    func testEnsureAuthorizationWhenAlreadyAuthorizedReturnsTrue() async {
        let scheduler = ReminderScheduler(
            store: MockEventStore(),
            authorizationStatusProvider: { .authorized }
        )

        let result = await scheduler.ensureAuthorization()

        XCTAssertTrue(result)
    }

    func testEnsureAuthorizationWhenDeniedReturnsFalse() async {
        let scheduler = ReminderScheduler(
            store: MockEventStore(),
            authorizationStatusProvider: { .denied }
        )

        let result = await scheduler.ensureAuthorization()

        XCTAssertFalse(result)
    }

    func testEnsureAuthorizationRequestsAccessWhenNotDeterminedAndGrants() async {
        var requested = 0
        let scheduler = ReminderScheduler(
            store: MockEventStore(),
            authorizationStatusProvider: { .notDetermined },
            requestAuthorizationHandler: {
                requested += 1
                return true
            }
        )

        let result = await scheduler.ensureAuthorization()

        XCTAssertTrue(result)
        XCTAssertEqual(requested, 1)
    }

    func testEnsureAuthorizationRequestsAccessWhenNotDeterminedAndDenies() async {
        var requested = 0
        let scheduler = ReminderScheduler(
            store: MockEventStore(),
            authorizationStatusProvider: { .notDetermined },
            requestAuthorizationHandler: {
                requested += 1
                return false
            }
        )

        let result = await scheduler.ensureAuthorization()

        XCTAssertFalse(result)
        XCTAssertEqual(requested, 1)
    }

    func testEnsureAuthorizationReturnsFalseForRestrictedStatus() async {
        let scheduler = ReminderScheduler(
            store: MockEventStore(),
            authorizationStatusProvider: { .restricted }
        )

        let result = await scheduler.ensureAuthorization()

        XCTAssertFalse(result)
    }
}

private final class MockEventStore: EKEventStore {}
