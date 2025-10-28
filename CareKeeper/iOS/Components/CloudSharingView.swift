import SwiftUI
import CloudKit
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDismiss: () -> Void

    init(share: CKShare, container: CKContainer, onDismiss: @escaping () -> Void) {
        self.share = share
        self.container = container
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
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void
        private let logger = AppLogger.sharing

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            logger.error("Failed to save share: \(error.localizedDescription)")
            onDismiss()
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "Caree"
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss()
        }
    }
}
