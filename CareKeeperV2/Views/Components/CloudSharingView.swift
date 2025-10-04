#if os(iOS)
import SwiftUI
import CloudKit
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare?
    let container: CKContainer
    let careeID: String?
    let onDismiss: () -> Void

    // Initializer for existing share
    init(share: CKShare, container: CKContainer, onDismiss: @escaping () -> Void) {
        self.share = share
        self.container = container
        self.careeID = nil
        self.onDismiss = onDismiss
    }

    // Initializer for new share with preparation handler
    init(careeID: String, container: CKContainer, onDismiss: @escaping () -> Void) {
        self.share = nil
        self.container = container
        self.careeID = careeID
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        if let share = share {
            // Existing share
            let controller = UICloudSharingController(
                share: share,
                container: container
            )
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            controller.modalPresentationStyle = .formSheet
            return controller
        } else {
            // New share with preparation handler
            // NOTE: UICloudSharingController.init(preparationHandler:) is deprecated in iOS 17.0,
            // but remains the standard approach for CloudKit sharing with SwiftData.
            // The suggested alternative (UIActivityViewController) is not appropriate for CloudKit-specific sharing.
            // This is a known limitation until Apple provides native SwiftData/SwiftUI CloudKit sharing APIs.
            let controller = UICloudSharingController { controller, completion in
                Task {
                    await context.coordinator.prepareShare(container: container, careeID: careeID, completion: completion)
                }
            }
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            controller.modalPresentationStyle = .formSheet
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func prepareShare(container: CKContainer, careeID: String?, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) async {
            guard let careeID = careeID else {
                completion(nil, nil, NSError(domain: "CloudSharingView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Caree ID not provided"]))
                return
            }

            do {
                // Check iCloud account status
                let accountStatus = try await container.accountStatus()
                print("☁️ iCloud account status: \(accountStatus.rawValue)")

                guard accountStatus == .available else {
                    let errorMessage: String
                    switch accountStatus {
                    case .couldNotDetermine:
                        errorMessage = "Could not determine iCloud account status"
                    case .noAccount:
                        errorMessage = "No iCloud account found. Please sign in to iCloud in Settings."
                    case .restricted:
                        errorMessage = "iCloud account is restricted"
                    case .temporarilyUnavailable:
                        errorMessage = "iCloud is temporarily unavailable"
                    default:
                        errorMessage = "iCloud account not available"
                    }
                    throw NSError(domain: "CloudSharingView", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }

                // Query CloudKit for the Caree record
                // SwiftData creates records with type "CD_EntityName"
                let recordID = CKRecord.ID(recordName: careeID)
                let database = container.privateCloudDatabase

                print("🔍 Attempting to fetch CloudKit record with ID: \(careeID)")

                // Fetch the record
                let record = try await database.record(for: recordID)

                print("✅ Successfully fetched record: \(record.recordID.recordName)")

                // Create a share for this record
                let share = CKShare(rootRecord: record)
                share[CKShare.SystemFieldKey.title] = record["name"] ?? "Caree" as CKRecordValue
                share.publicPermission = .none

                // Save the share
                print("💾 Saving share to CloudKit...")
                try await database.save(share)

                print("✅ Share saved successfully")
                completion(share, container, nil)
            } catch {
                print("❌ Failed to prepare share: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                if let ckError = error as? CKError {
                    print("❌ CKError code: \(ckError.code.rawValue)")
                    print("❌ CKError user info: \(ckError.userInfo)")
                }
                completion(nil, nil, error)
            }
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error.localizedDescription)")
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
#endif
