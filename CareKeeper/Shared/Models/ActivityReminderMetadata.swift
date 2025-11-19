import Foundation

struct ActivityReminderMetadata: Codable, Sendable {
    let activityID: UUID
    var reminderDueDate: Date?
    var reminderSource: ReminderSource?
    var phoneReminderIdentifier: String?
    var watchReminderIdentifier: String?

    init(
        activityID: UUID,
        reminderDueDate: Date? = nil,
        reminderSource: ReminderSource? = nil,
        phoneReminderIdentifier: String? = nil,
        watchReminderIdentifier: String? = nil
    ) {
        self.activityID = activityID
        self.reminderDueDate = reminderDueDate
        self.reminderSource = reminderSource
        self.phoneReminderIdentifier = phoneReminderIdentifier
        self.watchReminderIdentifier = watchReminderIdentifier
    }

    var reminderIdentifier: String? {
        phoneReminderIdentifier ?? watchReminderIdentifier
    }

    func identifier(for owner: ReminderSource) -> String? {
        switch owner {
        case .phone:
            phoneReminderIdentifier
        case .watch:
            watchReminderIdentifier
        }
    }

    mutating func setIdentifier(_ identifier: String?, for owner: ReminderSource) {
        switch owner {
        case .phone:
            phoneReminderIdentifier = identifier
        case .watch:
            watchReminderIdentifier = identifier
        }
    }
}
