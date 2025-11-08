import CloudKit
import Foundation
import SwiftUI

@MainActor
final class ShareAcceptanceNotifier: ObservableObject {
    @Published var isPresentingAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""

    private var acceptedObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?

    init(center: NotificationCenter = .default) {
        acceptedObserver = center.addObserver(
            forName: .cloudKitShareAccepted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.alertTitle = NSLocalizedString("Share Accepted", comment: "Share accepted title")
                self.alertMessage = NSLocalizedString("The shared data will sync shortly.", comment: "Share accepted message")
                self.isPresentingAlert = true
            }
        }

        failedObserver = center.addObserver(
            forName: .cloudKitShareAcceptanceFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract needed info before hopping to avoid capturing non-Sendable values
            let error = notification.object as? Error
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.alertTitle = NSLocalizedString("Failed To Accept Share", comment: "Failed To Accept Share alert title")
                self.alertMessage = error?.localizedDescription
                    ?? NSLocalizedString("An unknown error occurred.", comment: "Unknown error")
                self.isPresentingAlert = true
            }
        }
    }

    deinit {
        if let acceptedObserver { NotificationCenter.default.removeObserver(acceptedObserver) }
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
    }
}
