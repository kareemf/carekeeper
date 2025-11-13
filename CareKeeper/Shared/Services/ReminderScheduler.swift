import EventKit
import Foundation

enum ReminderSource: String, Codable, Sendable {
    case phone
    case watch

    static var current: ReminderSource {
        #if os(watchOS)
            return .watch
        #else
            return .phone
        #endif
    }

    var glyph: String {
        switch self {
        case .phone:
            "📱"
        case .watch:
            "⌚️"
        }
    }
}

/// Thin wrapper around EKEventStore so both iOS and watchOS can create local reminders.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let store = EKEventStore()

    private init() {}

    var authorizationStatus: EKAuthorizationStatus {
        store.authorizationStatus(for: .reminder)
    }

    func ensureAuthorization() async -> Bool {
        switch authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            do {
                return try await store.requestAccess(to: .reminder)
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date
    ) async throws -> (identifier: String, dueDate: Date) {
        guard try await ensureDefaultCalendarAvailable() else {
            throw NSError(domain: "ReminderScheduler", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No reminders calendar available. Open the Reminders app once to create the default list.",
            ])
        }

        let reminder = EKReminder(eventStore: store)
        guard let calendar = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first else {
            throw NSError(domain: "ReminderScheduler", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unable to locate reminders calendar.",
            ])
        }
        reminder.calendar = calendar
        let relativeString = relativeDescription(for: dueDate)
        reminder.title = "\(careeName): \(activityTypeName)"
        reminder.notes = "\(activityTypeName) | \(relativeString)"
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())

        try store.save(reminder, commit: true)
        return (reminder.calendarItemIdentifier, dueDate)
    }

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date
    ) async throws -> (identifier: String, dueDate: Date) {
        if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.title = "\(careeName): \(activityTypeName)"
            reminder.notes = "\(activityTypeName) | \(relativeDescription(for: dueDate))"
            try store.save(reminder, commit: true)
            return (identifier, dueDate)
        } else {
            return try await scheduleReminder(
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate
            )
        }
    }

    func deleteReminder(with identifier: String?) {
        guard let identifier,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder
        else {
            return
        }
        do {
            try store.remove(reminder, commit: true)
        } catch {
            // Swallow – failure to delete a reminder shouldn't block UI.
        }
    }

    private func ensureDefaultCalendarAvailable() async throws -> Bool {
        if store.defaultCalendarForNewReminders() != nil {
            return true
        }
        // Try reloading calendars; sometimes the default is nil until calendars() is called.
        if let calendar = store.calendars(for: .reminder).first {
            store.defaultCalendarForNewReminders()
            return calendar != nil
        }
        return false
    }

    private func relativeDescription(for dueDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }
}
