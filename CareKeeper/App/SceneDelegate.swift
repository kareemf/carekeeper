// @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app

import UIKit
import CloudKit

extension Notification.Name {
    static let cloudKitShareAccepted = Notification.Name("CloudKitShareAccepted")
    static let cloudKitShareAcceptanceFailed = Notification.Name("CloudKitShareAcceptanceFailed")
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        let container = CKContainer(identifier: CloudKitConfig.containerID)

        Task {
            do {
                let acceptedShare = try await acceptShare(with: cloudKitShareMetadata, in: container)
                print("✅ Successfully accepted share: \(acceptedShare.recordID)")

                // Notify SwiftUI to present an app-wide alert (see ShareAcceptanceNotifier)
                NotificationCenter.default.post(name: .cloudKitShareAccepted, object: acceptedShare)
            } catch {
                print("❌ Failed to accept share: \(error.localizedDescription)")

                // Notify SwiftUI to present an app-wide alert (see ShareAcceptanceNotifier)
                NotificationCenter.default.post(name: .cloudKitShareAcceptanceFailed, object: error)
            }
        }
    }

    // Wrap CKContainer.accept in async/await.
    // @see https://developer.apple.com/documentation/uikit/uicloudsharingcontroller
    private func acceptShare(with metadata: CKShare.Metadata, in container: CKContainer) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            container.accept(metadata) { acceptedShare, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let share = acceptedShare {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SceneDelegate",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown share acceptance state"]
                    ))
                }
            }
        }
    }
}
