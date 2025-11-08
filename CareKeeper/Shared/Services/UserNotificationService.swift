import Foundation
import UserNotifications
#if os(iOS)
    import UIKit
#endif

/// Service for managing user-facing push notifications
@MainActor
class UserNotificationService: ObservableObject {
    // MARK: - Shared Instance

    static let shared = UserNotificationService()

    // MARK: - Published Properties

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Notification Center

    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Notification Categories

    private enum Categories {
        static let newActivity = "NEW_ACTIVITY"
    }

    // MARK: - Notification Actions

    private enum Actions {
        static let view = "VIEW_ACTIVITY"
    }

    // MARK: - User Info Keys

    enum UserInfoKeys {
        static let activityID = "activityID"
        static let careeID = "careeID"
        static let type = "type"
    }

    // MARK: - Notification Types

    enum NotificationType: String {
        case newActivity
    }

    // MARK: - Initialization

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Permission Management

    /// Request notification permissions from the user
    /// - Returns: true if permission granted, false otherwise
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await checkAuthorizationStatus()

            if granted {
                // Register notification categories
                await registerCategories()
            }

            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Open iOS Settings app to notification settings
    func openSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        #endif
    }

    // MARK: - Notification Categories

    /// Register notification categories and actions
    private func registerCategories() async {
        let viewAction = UNNotificationAction(
            identifier: Actions.view,
            title: "View",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Categories.newActivity,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
    }

    // MARK: - Notification Presentation

    /// Present a local notification for a new activity on a shared caree
    /// - Parameters:
    ///   - activityID: The activity's UUID
    ///   - careeID: The caree's UUID
    ///   - careeName: The caree's name
    ///   - activityTypeName: The activity type name
    ///   - creatorName: The creator's name (or "Another caregiver")
    ///   - timestamp: When the activity occurred
    func presentNewActivityNotification(
        activityID: UUID,
        careeID: UUID,
        careeName: String,
        activityTypeName: String,
        creatorName: String = "Another caregiver",
        timestamp: Date
    ) async {
        // Check authorization status
        await checkAuthorizationStatus()
        guard authorizationStatus == .authorized else {
            print("Notification authorization not granted")
            return
        }

        // Format timestamp
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: timestamp)

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "New activity for \(careeName)"
        content.body = "\(creatorName) logged \(activityTypeName) at \(timeString)"
        content.sound = .default
        content.categoryIdentifier = Categories.newActivity

        // Add user info for deep linking
        content.userInfo = [
            UserInfoKeys.activityID: activityID.uuidString,
            UserInfoKeys.careeID: careeID.uuidString,
            UserInfoKeys.type: NotificationType.newActivity.rawValue,
        ]

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "activity-\(activityID.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        // Add notification
        do {
            try await notificationCenter.add(request)
            print("Notification presented for activity: \(activityID)")
        } catch {
            print("Error presenting notification: \(error)")
        }
    }

    /// Handle notification tap - extract activity ID for deep linking
    /// - Parameter response: The notification response
    /// - Returns: The activity ID if available
    func handleNotificationTap(_ response: UNNotificationResponse) -> (activityID: UUID?, careeID: UUID?)? {
        let userInfo = response.notification.request.content.userInfo

        guard let activityIDString = userInfo[UserInfoKeys.activityID] as? String,
              let activityID = UUID(uuidString: activityIDString),
              let careeIDString = userInfo[UserInfoKeys.careeID] as? String,
              let careeID = UUID(uuidString: careeIDString)
        else {
            return nil
        }

        return (activityID, careeID)
    }

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// Remove delivered notifications for a specific activity
    /// - Parameter activityID: The activity's UUID
    func removeNotification(for activityID: UUID) {
        notificationCenter.removeDeliveredNotifications(
            withIdentifiers: ["activity-\(activityID.uuidString)"]
        )
    }
}
