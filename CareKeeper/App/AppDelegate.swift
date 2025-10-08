// https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
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
}
