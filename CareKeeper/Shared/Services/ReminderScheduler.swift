import EventKit
import Foundation
#if os(watchOS)
    import UserNotifications
#endif

/// Thin wrapper around EKEventStore so both iOS and watchOS can create local reminders.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    #if !os(watchOS)
        private let store = EKEventStore()
    #endif

    private init() {}

    func ensureAuthorization() async -> Bool {
        #if os(watchOS)
            let center = UNUserNotificationCenter.current()
            let settings = await notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined:
                do {
                    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                AppLogger.app.info("🔐 UNUserNotificationCenter granted? \(granted, privacy: .public)")
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                } catch {
                    return false
                }
            default:
                return false
            }
        #else
            let status = EKEventStore.authorizationStatus(for: .reminder)
            switch status {
            case .authorized:
                return true
            case .notDetermined:
                return await requestReminderAuthorization()
            default:
                AppLogger.app.warning("🔐 EventKit reminder status: \(status.rawValue, privacy: .public)")
                return false
            }
        #endif
    }

    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date
    ) async throws -> (identifier: String, dueDate: Date) {
        #if os(watchOS)
            return try await scheduleNotification(
                identifier: nil,
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate
            )
        #else
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
        AppLogger.app.info("🔔 Scheduled reminder \(reminder.calendarItemIdentifier, privacy: .public) for \(careeName, privacy: .public)")
        return (reminder.calendarItemIdentifier, dueDate)
        #endif
    }

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date
    ) async throws -> (identifier: String, dueDate: Date) {
        #if os(watchOS)
            return try await scheduleNotification(
                identifier: identifier,
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate
            )
        #else
        if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.title = "\(careeName): \(activityTypeName)"
            reminder.notes = "\(activityTypeName) | \(relativeDescription(for: dueDate))"
            try store.save(reminder, commit: true)
            AppLogger.app.info("🔔 Updated reminder \(identifier, privacy: .public)")
            return (identifier, dueDate)
        } else {
            return try await scheduleReminder(
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate
            )
        }
        #endif
    }

    func deleteReminder(with identifier: String?) {
        #if os(watchOS)
            guard let identifier else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        #else
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
        #endif
    }

    #if !os(watchOS)
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
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
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
    #endif

    private func relativeDescription(for dueDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }

    #if os(watchOS)
        private func notificationSettings() async -> UNNotificationSettings {
            await withCheckedContinuation { (continuation: CheckedContinuation<UNNotificationSettings, Never>) in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings)
                }
            }
        }

        private func scheduleNotification(
            identifier: String?,
            careeName: String,
            activityTypeName: String,
            dueDate: Date
        ) async throws -> (identifier: String, dueDate: Date) {
            let content = UNMutableNotificationContent()
            content.title = "\(careeName): \(activityTypeName)"
            content.body = "\(activityTypeName) | \(relativeDescription(for: dueDate))"
            content.sound = .default

            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let identifier = identifier ?? UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                UNUserNotificationCenter.current().add(request) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }

            return (identifier, dueDate)
        }
    #endif
}
