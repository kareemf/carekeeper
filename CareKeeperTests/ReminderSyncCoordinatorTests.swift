@testable import CareKeeper
import XCTest

@MainActor
final class ReminderSyncCoordinatorTests: XCTestCase {
    func testSynchronizeSchedulesPhoneReminderWhenMissing() async {
        // Given an activity whose reminder exists only on the watch (no iOS identifier yet)
        let scheduler = MockReminderScheduler()
        let metadataStore = MockReminderMetadataStore()
        let coordinator = ReminderSyncCoordinator(scheduler: scheduler, metadataStore: metadataStore)

        let activityID = UUID()
        let dueDate = Date().addingTimeInterval(300)
        let metadata = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: dueDate,
            reminderSource: .watch,
            ekReminderIdentifier: nil,
            unNotificationIdentifier: "watch-id"
        )
        let payload = ReminderSyncPayload(
            activityID: activityID,
            careeName: "Infant",
            activityTypeName: "Feeding",
            note: "4 oz",
            metadata: metadata
        )

        // When the phone processes the metadata and tries to synchronize reminders
        let updates = await coordinator.synchronize(owner: .phone, payloads: [payload])

        // Then a new EK reminder is scheduled and the metadata gains an ekReminderIdentifier while preserving the watch identifier
        XCTAssertEqual(scheduler.scheduledReminders.count, 1)
        XCTAssertEqual(metadataStore.savedMetadata[activityID]?.ekReminderIdentifier, scheduler.scheduleResultIdentifier)
        XCTAssertEqual(updates[activityID], scheduler.scheduleResultIdentifier)
    }

    func testSynchronizeUpdatesExistingReminder() async {
        // Given an activity whose phone reminder already exists with a valid identifier
        let scheduler = MockReminderScheduler()
        let metadataStore = MockReminderMetadataStore()
        let coordinator = ReminderSyncCoordinator(scheduler: scheduler, metadataStore: metadataStore)

        let activityID = UUID()
        let dueDate = Date().addingTimeInterval(900)
        let metadata = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: dueDate,
            reminderSource: .phone,
            ekReminderIdentifier: "existing-id",
            unNotificationIdentifier: nil
        )
        let payload = ReminderSyncPayload(
            activityID: activityID,
            careeName: "Infant",
            activityTypeName: "Medication",
            note: nil,
            metadata: metadata
        )

        // When synchronization runs on the phone again
        let updates = await coordinator.synchronize(owner: .phone, payloads: [payload])

        // Then the reminder is simply updated in place without rescheduling or saving new metadata
        XCTAssertTrue(updates.isEmpty)
        XCTAssertEqual(scheduler.updatedIdentifiers, ["existing-id"])
        XCTAssertTrue(metadataStore.savedMetadata.isEmpty)
    }

    func testSynchronizeSchedulesWatchReminderWhenMissing() async {
        // Given an activity whose reminder exists only on the phone (watch identifier missing)
        let scheduler = MockReminderScheduler()
        let metadataStore = MockReminderMetadataStore()
        let coordinator = ReminderSyncCoordinator(scheduler: scheduler, metadataStore: metadataStore)

        let activityID = UUID()
        let dueDate = Date().addingTimeInterval(1200)
        let metadata = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: dueDate,
            reminderSource: .phone,
            ekReminderIdentifier: "phone-id",
            unNotificationIdentifier: nil
        )
        let payload = ReminderSyncPayload(
            activityID: activityID,
            careeName: "Jordan",
            activityTypeName: "Therapy",
            note: "Follow-up",
            metadata: metadata
        )

        // When the watch synchronizes that metadata
        let updates = await coordinator.synchronize(owner: .watch, payloads: [payload])

        // Then the watch schedules its own notification and writes the resulting unNotificationIdentifier back to metadata
        XCTAssertEqual(scheduler.scheduledReminders.count, 1)
        XCTAssertEqual(metadataStore.savedMetadata[activityID]?.unNotificationIdentifier, scheduler.scheduleResultIdentifier)
        XCTAssertEqual(updates[activityID], scheduler.scheduleResultIdentifier)
    }
}

private final class MockReminderScheduler: ReminderScheduling {
    struct ScheduledCall: Equatable {
        let careeName: String
        let activityTypeName: String
        let dueDate: Date
        let note: String?
    }

    var scheduledReminders: [ScheduledCall] = []
    var updatedIdentifiers: [String] = []
    var scheduleResultIdentifier = UUID().uuidString

    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String?
    ) async throws -> (identifier: String, dueDate: Date) {
        scheduledReminders.append(
            ScheduledCall(careeName: careeName, activityTypeName: activityTypeName, dueDate: dueDate, note: note)
        )
        return (scheduleResultIdentifier, dueDate)
    }

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String?
    ) async throws -> (identifier: String, dueDate: Date) {
        updatedIdentifiers.append(identifier)
        return (identifier, dueDate)
    }

    func deleteReminder(with identifier: String?) {}
}
