import CloudKit
import SwiftUI
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let caree: Caree?
    let onDismiss: () -> Void

    init(share: CKShare, container: CKContainer, caree: Caree? = nil, onDismiss: @escaping () -> Void) {
        self.share = share
        self.container = container
        self.caree = caree
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: container
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(caree: caree, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let caree: Caree?
        let onDismiss: () -> Void
        private let logger = AppLogger.sharing

        init(caree: Caree?, onDismiss: @escaping () -> Void) {
            self.caree = caree
            self.onDismiss = onDismiss
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            logger.error("Failed to save share: \(error.localizedDescription)")
            onDismiss()
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            caree?.name ?? "Caree"
        }

        func itemThumbnailImage(for csc: UICloudSharingController) -> UIImage? {
            ShareThumbnailProvider.thumbnailImage(for: caree)
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            ShareThumbnailProvider.thumbnailData(for: caree)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss()
        }
    }
}
