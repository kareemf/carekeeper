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
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

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
                CloudSharingView(
                    share: share,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                        self.share = nil
                    }
                )
            }
        }
        .errorAlert($error)
    }

    private func prepareShare() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let finalShare = try await sharingService.createOrGetShare(for: caree, in: modelContext)
            self.share = finalShare
            self.showingShareSheet = true
        } catch {
            self.error = error
        }
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree, isSynced: true)
        .modelContainer(PreviewContainer.shared)
}
#endif
