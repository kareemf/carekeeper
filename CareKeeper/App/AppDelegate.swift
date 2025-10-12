// https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app

import UIKit
import CloudKit
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate {
    private let logger = AppLogger.cloudkit

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications to receive CloudKit notifications
        application.registerForRemoteNotifications()

        // Set up user notification center delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting
        connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions) -> UISceneConfiguration {

        // Create a scene configuration object for the
        // specified session role.
        let config = UISceneConfiguration(name: nil,
            sessionRole: connectingSceneSession.role)

        // Set the configuration's delegate class to the
        // scene delegate that implements the share
        // acceptance method.
        config.delegateClass = SceneDelegate.self

        return config
    }
    
    // MARK: - CloudKit Notifications
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Handle CloudKit notifications
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            logger.info("📨 Received CloudKit notification: \(notification.notificationType.rawValue)")

            // Post notification for CloudKitSharedRecordsService to observe
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitNotificationReceived"),
                object: notification
            )

            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("✅ Successfully registered for remote notifications")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound, .badge]
    }

    /// Called when the user interacts with a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        logger.info("📱 User tapped notification")

        // Handle notification tap via UserNotificationService
        let service = await UserNotificationService.shared
        if let ids = await service.handleNotificationTap(response) {
            logger.info("🔗 Deep linking to activity: \(ids.activityID ?? UUID()) for caree: \(ids.careeID ?? UUID())")

            // Post notification for deep linking
            // The app will handle this in the appropriate view
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenActivityDetail"),
                    object: nil,
                    userInfo: [
                        "activityID": ids.activityID as Any,
                        "careeID": ids.careeID as Any
                    ]
                )
            }
        }
    }
}
