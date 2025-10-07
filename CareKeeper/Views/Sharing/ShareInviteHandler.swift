import SwiftUI
import CloudKit

class ShareInviteHandler {
    static let shared = ShareInviteHandler()
    
    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    
    func handleIncomingShareURL(_ url: URL) {
        // Fetch the share metadata from the URL
        container.fetchShareMetadata(with: url) { metadata, error in
            if let error = error {
                print("❌ Failed to fetch share metadata: \(error.localizedDescription)")
                // --
                // Create an error alert
                let alert = UIAlertController(
                    title: NSLocalizedString("Failed to fetch share metadata", comment: "Share error title"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismiss button"), style: .cancel, handler: nil))
                
                // Present the alert
                if let rootViewController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    rootViewController.present(alert, animated: true, completion: nil)
                }
                // --
                return
            }

            guard let metadata = metadata else {
                print("❌ No metadata found for share")

                // --
                let alert = UIAlertController(
                    title: NSLocalizedString("No metadata found for share", comment: "Share error title"),
                    message: "No metadata found for share",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismiss button"), style: .cancel, handler: nil))
                
                // Present the alert
                if let rootViewController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    rootViewController.present(alert, animated: true, completion: nil)
                }
                // --
                return
            }
            
            // Present UI to accept the share
            self.presentShareAcceptanceUI(metadata: metadata)
        }
    }
    
    private func presentShareAcceptanceUI(metadata: CKShare.Metadata) {
        // Create an alert to accept the share
        let alert = UIAlertController(
            title: NSLocalizedString("Share Invitation", comment: "Share invitation title"),
            message: String(format: NSLocalizedString("You have been invited to share: %@", comment: "Share invitation message"), metadata.hierarchicalRootRecordID?.recordName ?? "Caree"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Accept", comment: "Accept button"), style: .default) { _ in
            self.acceptShare(metadata: metadata)
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel, handler: nil))
        
        // Present the alert
        if let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
    
    private func acceptShare(metadata: CKShare.Metadata) {
        Task {
            do {
                container.accept(metadata) { acceptedShare, error in
                    if let error = error {
                        print("❌ Failed to accept share: \(error.localizedDescription)")
                        return
                    }

                    if let acceptedShare = acceptedShare {
                        print("✅ Successfully accepted share: \(acceptedShare.recordID)")
                        // The shared data will automatically sync to the local store
                        // SwiftData + CloudKit handles the rest

                        //TODO: Update your app's data model with the shared data
                    }
                }
            }
        }
    }
}
