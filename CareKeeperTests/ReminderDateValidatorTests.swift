@testable import CareKeeper
import XCTest

final class ReminderDateValidatorTests: XCTestCase {
    func testValidateAllowsFutureDates() throws {
        let now = Date()
        let future = now.addingTimeInterval(60)

        XCTAssertNoThrow(try ReminderDateValidator.validate(dueDate: future, now: now))
    }

    func testValidateRejectsPastDates() {
        let now = Date()
        let past = now.addingTimeInterval(-60)

        XCTAssertThrowsError(try ReminderDateValidator.validate(dueDate: past, now: now)) { error in
            XCTAssertEqual(error as? ReminderDateValidationError, .dueDateInPast)
        }
    }
}
