// @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app

import UIKit
import CloudKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        print("✅ userDidAcceptCloudKitShareWith: \(cloudKitShareMetadata)")
        
        let container = CKContainer(identifier: CloudKitConfig.containerID)

        container.accept(cloudKitShareMetadata) { acceptedShare, error in
            if let error = error {
                print("❌ Failed to accept share: \(error.localizedDescription)")
                // TODO: enable
                //self.alert(error.localizedDescription)
                return
            }

            if let acceptedShare = acceptedShare {
                print("✅ Successfully accepted share: \(acceptedShare.recordID)")
                // The shared data will automatically sync to the local store
                // SwiftData + CloudKit handles the rest

                //TODO: Update your app's data model with the shared data?
            }
        }
    }
    
    private func alert(_ message: String) {
        
        let alert = UIAlertController(
            title: NSLocalizedString("Failed To Accept Share", comment: "Failed To Accept Share alert title"),
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dismiss button"), style: .default, handler: nil))
        
        // Present the alert
        // TODO: "Call must be made on main thread", find the proper way to do this
        if let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
    
}
