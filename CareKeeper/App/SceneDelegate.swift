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
                
                broadcastAcceptedShare(acceptedShare, metadata: cloudKitShareMetadata)
                
                // Notify SwiftUI to present an app-wide alert (see ShareAcceptanceNotifier)
                NotificationCenter.default.post(name: .cloudKitShareAccepted, object: acceptedShare)
            } catch {
                print("❌ Failed to accept share: \(error.localizedDescription)")
                
                // Notify SwiftUI to present an app-wide alert (see ShareAcceptanceNotifier)
                NotificationCenter.default.post(name: .cloudKitShareAcceptanceFailed, object: error)
            }
        }
    }
    
    /// Broad the accepted share so it appears in CloudKitSharedRecordsService to be tracked/persisted
    private func broadcastAcceptedShare(_ share: CKShare, metadata: CKShare.Metadata) {
        let rootRecordID = metadata.hierarchicalRootRecordID
        
        let shareTitle = share[CKShare.SystemFieldKey.title] as? String
        print("📝 Tracking accepted share: \(rootRecordID?.recordName ?? "No root record ID") - '\(shareTitle ?? "No title")'")
        
        // Post notification that can be observed by CloudKitSharedRecordsService
        NotificationCenter.default.post(
            name: NSNotification.Name("ShareAcceptedForTracking"),
            object: nil,
            userInfo: [
                "shareRecordID": share.recordID,
                "rootRecordID": rootRecordID,
                "shareTitle": shareTitle as Any
            ]
        )
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
