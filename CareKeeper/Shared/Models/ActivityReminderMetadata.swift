import Foundation

struct ActivityReminderMetadata: Codable, Sendable {
    let activityID: UUID
    var reminderIdentifier: String?
    var reminderDueDate: Date?
    var reminderSource: ReminderSource?
}
