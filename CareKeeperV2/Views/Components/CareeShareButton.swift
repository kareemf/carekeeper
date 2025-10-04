#if os(iOS)
import SwiftUI
import SwiftData
import CloudKit

struct CareeShareButton: View {
    let caree: Caree
    let isSynced: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var showingShareSheet = false
    @State private var share: CKShare?
    @State private var error: Error?
    @State private var isLoading = false
    @State private var showingSyncAlert = false

    private let sharingService = CloudKitSharingService()
    private let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCloudKit")

    var body: some View {
        Button {
            // Pre-share validation
            if !isSynced {
                showingSyncAlert = true
            } else {
                Task {
                    await prepareShare()
                }
            }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: sharingService.isShared(caree, in: modelContext)
                      ? "person.crop.circle.badge.checkmark"
                      : "square.and.arrow.up")
            }
        }
        .disabled(isLoading)
        .alert(
            NSLocalizedString("Not Synced to iCloud", comment: "Sync alert title"),
            isPresented: $showingSyncAlert
        ) {
            Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("This caree hasn't synced to iCloud yet. Please wait a moment or pull down to refresh, then try again.", comment: "Sync alert message"))
        }
        .sheet(isPresented: $showingShareSheet) {
            if let share = share {
                // Existing share
                CloudSharingView(
                    share: share,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                        self.share = nil
                    }
                )
            } else {
                // New share - use preparation handler
                CloudSharingView(
                    careeID: caree.id.uuidString,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                    }
                )
            }
        }
        .errorAlert($error)
    }

    private func prepareShare() async {
        isLoading = true
        defer { isLoading = false }

        print("📤 Share button tapped for caree: \(caree.name) (ID: \(caree.id.uuidString))")

        // Check if already shared
        if let existingShare = sharingService.getShare(for: caree, in: modelContext) {
            print("✅ Found existing share for caree")
            share = existingShare
        } else {
            print("🆕 No existing share found - will create new share")

            // Check if caree has synced to CloudKit
            do {
                let recordID = CKRecord.ID(recordName: caree.id.uuidString)
                let database = container.privateCloudDatabase
                _ = try await database.record(for: recordID)
                print("✅ Caree record found in CloudKit - ready to share")
            } catch {
                print("⚠️ Caree record not yet synced to CloudKit")
                print("⚠️ Error: \(error.localizedDescription)")
                if let ckError = error as? CKError {
                    print("⚠️ CKError code: \(ckError.code.rawValue)")
                }
            }

            // New share - will be created by UICloudSharingController's preparation handler
            share = nil
        }

        showingShareSheet = true
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree, isSynced: true)
        .modelContainer(PreviewContainer.shared)
}
#endif
