import EventKit
import Foundation

/// Thin wrapper around EKEventStore so both iOS and watchOS can create local reminders.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private let logger = AppLogger.app
    private let store: EKEventStore
    private let authorizationStatusProvider: () -> EKAuthorizationStatus
    private let requestAuthorizationHandler: (() async -> Bool)?

    init(
        store: EKEventStore = EKEventStore(),
        authorizationStatusProvider: @escaping () -> EKAuthorizationStatus = {
            EKEventStore.authorizationStatus(for: .reminder)
        },
        requestAuthorizationHandler: (() async -> Bool)? = nil
    ) {
        self.store = store
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestAuthorizationHandler = requestAuthorizationHandler
    }

    func ensureAuthorization() async -> Bool {
        let status = authorizationStatusProvider()
        logger.info("🔐 EventKit reminder authorization status: \(status.rawValue, privacy: .public)")
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            if let requestAuthorizationHandler {
                return await requestAuthorizationHandler()
            }
            return await requestReminderAuthorization()
        default:
            logger.warning("🔐 EventKit reminder status denied")
            return false
        }
    }

    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String? = nil
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
        reminder.title = "\(careeName): \(activityTypeName)"
        reminder.notes = reminderBody(activityTypeName: activityTypeName, dueDate: dueDate, note: note)
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: dueDate))

        try await save(reminder: reminder)
        logger.info("🔔 Scheduled reminder \(reminder.calendarItemIdentifier, privacy: .public) for \(careeName, privacy: .public)")
        return (reminder.calendarItemIdentifier, dueDate)
    }

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String? = nil
    ) async throws -> (identifier: String, dueDate: Date) {
        if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            if reminder.isCompleted {
                AppLogger.app.info("🔔 Existing reminder completed, creating a new one for \(identifier, privacy: .public)")
                do {
                    try await remove(reminder: reminder)
                } catch {
                    AppLogger.app.warning("⚠️ Failed to remove completed reminder before recreating: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                reminder.title = "\(careeName): \(activityTypeName)"
                reminder.notes = reminderBody(activityTypeName: activityTypeName, dueDate: dueDate, note: note)
                reminder.alarms?.forEach { reminder.removeAlarm($0) }
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
                try await save(reminder: reminder)
                logger.info("🔔 Updated reminder \(identifier, privacy: .public)")
                return (identifier, dueDate)
            }
        } else {
            return try await scheduleReminder(
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate,
                note: note
            )
        }
        return try await scheduleReminder(
            careeName: careeName,
            activityTypeName: activityTypeName,
            dueDate: dueDate,
            note: note
        )
    }

    func deleteReminder(with identifier: String?) {
        guard let identifier,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder
        else {
            return
        }
        Task {
            do {
                try await remove(reminder: reminder)
            } catch {
                // Swallow – failure to delete a reminder shouldn't block UI.
            }
        }
    }

    private func ensureDefaultCalendarAvailable() async throws -> Bool {
        if store.defaultCalendarForNewReminders() != nil {
            return true
        }
        // Try reloading calendars; sometimes the default is nil until calendars() is called.
        if store.calendars(for: .reminder).first != nil {
            _ = store.defaultCalendarForNewReminders()
            return true
        }
        return false
    }

    private func requestReminderAuthorization() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, watchOS 10.0, *) {
            do {
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    store.requestFullAccessToReminders { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            AppLogger.app.info("🔐 requestFullAccessToReminders granted? \(granted, privacy: .public)")
                            continuation.resume(returning: granted)
                        }
                    }
                }
            } catch {
                return false
            }
        } else {
            do {
                let granted = try await store.requestAccess(to: .reminder)
                AppLogger.app.info("🔐 requestAccess(to:) granted? \(granted, privacy: .public)")
                return granted
            } catch {
                return false
            }
        }
    }

    private func relativeDescription(for dueDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }

    private func reminderBody(activityTypeName: String, dueDate: Date, note: String?) -> String {
        var components = ["\(activityTypeName) | \(relativeDescription(for: dueDate))"]
        if let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            components.append(trimmed)
        }
        return components.joined(separator: "\n")
    }

    private func save(reminder: EKReminder) async throws {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            try await store.save(reminder)
        } else {
            try store.save(reminder, commit: true)
        }
    }

    private func remove(reminder: EKReminder) async throws {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            try await store.remove(reminder)
        } else {
            try store.remove(reminder, commit: true)
        }
    }
}
