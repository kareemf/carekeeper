@testable import CareKeeper
import XCTest

final class ActivityReminderMetadataTests: XCTestCase {
    func testIdentifierAccessorsReturnPerDeviceValues() {
        var metadata = ActivityReminderMetadata(
            activityID: UUID(),
            reminderDueDate: Date(),
            reminderSource: .phone,
            phoneReminderIdentifier: "phone-id",
            watchReminderIdentifier: "watch-id"
        )

        XCTAssertEqual(metadata.identifier(for: .phone), "phone-id")
        XCTAssertEqual(metadata.identifier(for: .watch), "watch-id")
        XCTAssertEqual(metadata.reminderIdentifier, "phone-id")

        metadata.setIdentifier("updated", for: .watch)
        XCTAssertEqual(metadata.identifier(for: .watch), "updated")
    }

    func testIdentifierFallsBackToOtherDeviceWhenMissing() {
        var metadata = ActivityReminderMetadata(activityID: UUID())
        XCTAssertNil(metadata.reminderIdentifier)

        metadata.setIdentifier("only-watch", for: .watch)
        XCTAssertEqual(metadata.reminderIdentifier, "only-watch")
        XCTAssertNil(metadata.identifier(for: .phone))
    }
}
