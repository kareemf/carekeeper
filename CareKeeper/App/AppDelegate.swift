// https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app

import UIKit
import CloudKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications to receive CloudKit notifications
        application.registerForRemoteNotifications()
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
            print("📨 Received CloudKit notification: \(notification.notificationType)")

            // Post notification for CloudKitSharedRecordsService to observe
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let contentView = window.rootViewController?.view {

                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitNotificationReceived"),
                    object: notification
                )
                
                completionHandler(.newData)
            } else {
                completionHandler(.noData)
            }
        } else {
            completionHandler(.noData)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ Successfully registered for remote notifications")
    }
}
