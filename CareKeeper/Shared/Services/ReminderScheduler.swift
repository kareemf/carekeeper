import EventKit
import Foundation
#if os(watchOS)
    import UserNotifications
#endif

/// Thin wrapper around EKEventStore so both iOS and watchOS can create local reminders.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private let logger = AppLogger.app
    #if os(watchOS)
        private init() {}
    #else
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
    #endif

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
                                self.logger.info("🔐 UNUserNotificationCenter granted? \(granted, privacy: .public)")
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
        #endif
    }

    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String? = nil
    ) async throws -> (identifier: String, dueDate: Date) {
        #if os(watchOS)
            return try await scheduleNotification(
                identifier: nil,
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate,
                note: note
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
            reminder.title = "\(careeName): \(activityTypeName)"
            reminder.notes = reminderBody(activityTypeName: activityTypeName, dueDate: dueDate, note: note)
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))

            try await save(reminder: reminder)
            logger.info("🔔 Scheduled reminder \(reminder.calendarItemIdentifier, privacy: .public) for \(careeName, privacy: .public)")
            return (reminder.calendarItemIdentifier, dueDate)
        #endif
    }

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String? = nil
    ) async throws -> (identifier: String, dueDate: Date) {
        #if os(watchOS)
            return try await scheduleNotification(
                identifier: identifier,
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate,
                note: note
            )
        #else
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
            }
            return try await scheduleReminder(
                careeName: careeName,
                activityTypeName: activityTypeName,
                dueDate: dueDate,
                note: note
            )
        #endif
    }

    func deleteReminder(with identifier: String?) {
        #if os(watchOS)
            guard let identifier else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        #else
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
        #endif
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
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, tvOS 17.0, *) {
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

    private func save(reminder: EKReminder) async throws {
        try store.save(reminder, commit: true)
    }

    private func remove(reminder: EKReminder) async throws {
        try store.remove(reminder, commit: true)
    }
    #endif

    #if os(watchOS)
        private func notificationSettings() async -> UNNotificationSettings {
            await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings)
                }
            }
        }

        private func scheduleNotification(
            identifier: String?,
            careeName: String,
            activityTypeName: String,
            dueDate: Date,
            note: String?
        ) async throws -> (identifier: String, dueDate: Date) {
            let content = UNMutableNotificationContent()
            content.title = "\(careeName): \(activityTypeName)"
            content.body = reminderBody(activityTypeName: activityTypeName, dueDate: dueDate, note: note)
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

protocol ReminderScheduling {
    func scheduleReminder(
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String?
    ) async throws -> (identifier: String, dueDate: Date)

    func updateReminder(
        identifier: String,
        careeName: String,
        activityTypeName: String,
        dueDate: Date,
        note: String?
    ) async throws -> (identifier: String, dueDate: Date)

    func deleteReminder(with identifier: String?)
}

extension ReminderScheduler: ReminderScheduling {}

struct ReminderSyncPayload: Sendable {
    let activityID: UUID
    let careeName: String
    let activityTypeName: String
    let note: String?
    let metadata: ActivityReminderMetadata
}

protocol ReminderSyncCoordinating: AnyObject {
    func synchronize(owner: ReminderSource, payloads: [ReminderSyncPayload]) async -> [UUID: String]
}

@MainActor
final class ReminderSyncCoordinator: ReminderSyncCoordinating {
    static let shared = ReminderSyncCoordinator()

    private let scheduler: ReminderScheduling
    private let metadataStore: ReminderMetadataStoreProtocol
    private let logger = AppLogger.app
    private var pendingIdentifiers: [ReminderSource: Set<UUID>] = [
        .phone: [],
        .watch: [],
    ]

    init(
        scheduler: ReminderScheduling = ReminderScheduler.shared,
        metadataStore: ReminderMetadataStoreProtocol = ActivityReminderMetadataStore.shared
    ) {
        self.scheduler = scheduler
        self.metadataStore = metadataStore
    }

    func synchronize(owner: ReminderSource, payloads: [ReminderSyncPayload]) async -> [UUID: String] {
        guard !payloads.isEmpty else { return [:] }

        var updates: [UUID: String] = [:]
        for payload in payloads {
            guard let dueDate = payload.metadata.reminderDueDate else { continue }

            do {
                if let identifier = payload.metadata.identifier(for: owner) {
                    pendingIdentifiers[owner]?.remove(payload.activityID)
                    _ = try await scheduler.updateReminder(
                        identifier: identifier,
                        careeName: payload.careeName,
                        activityTypeName: payload.activityTypeName,
                        dueDate: dueDate,
                        note: payload.note
                    )
                } else {
                    if pendingIdentifiers[owner, default: []].contains(payload.activityID) {
                        logger.info("🔔 Reminder sync already pending for \(payload.activityID.uuidString, privacy: .public); skipping duplicate schedule")
                        continue
                    }
                    let result = try await scheduler.scheduleReminder(
                        careeName: payload.careeName,
                        activityTypeName: payload.activityTypeName,
                        dueDate: dueDate,
                        note: payload.note
                    )
                    pendingIdentifiers[owner, default: []].insert(payload.activityID)
                    var updatedMetadata = payload.metadata
                    updatedMetadata.setIdentifier(result.identifier, for: owner)
                    try await metadataStore.save(metadata: updatedMetadata)
                    updates[payload.activityID] = result.identifier
                }
            } catch {
                pendingIdentifiers[owner]?.remove(payload.activityID)
                logger.warning(
                    "⚠️ Failed syncing reminder \(payload.activityID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return updates
    }
}
