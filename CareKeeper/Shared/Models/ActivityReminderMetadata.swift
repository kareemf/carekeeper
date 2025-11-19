import Foundation

struct ActivityReminderMetadata: Codable, Sendable {
    let activityID: UUID
    var reminderDueDate: Date?
    var reminderSource: ReminderSource?
    var ekReminderIdentifier: String?
    var unNotificationIdentifier: String?

    init(
        activityID: UUID,
        reminderDueDate: Date? = nil,
        reminderSource: ReminderSource? = nil,
        ekReminderIdentifier: String? = nil,
        unNotificationIdentifier: String? = nil
    ) {
        self.activityID = activityID
        self.reminderDueDate = reminderDueDate
        self.reminderSource = reminderSource
        self.ekReminderIdentifier = ekReminderIdentifier
        self.unNotificationIdentifier = unNotificationIdentifier
    }

    var reminderIdentifier: String? {
        ekReminderIdentifier ?? unNotificationIdentifier
    }

    func identifier(for owner: ReminderSource) -> String? {
        owner == .phone ? ekReminderIdentifier : unNotificationIdentifier
    }

    mutating func setIdentifier(_ identifier: String?, for owner: ReminderSource) {
        if owner == .phone {
            ekReminderIdentifier = identifier
        } else {
            unNotificationIdentifier = identifier
        }
    }
}
