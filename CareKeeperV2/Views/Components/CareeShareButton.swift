#if os(iOS)
import SwiftUI
import SwiftData
import CloudKit

struct CareeShareButton: View {
    let caree: Caree
    @Environment(\.modelContext) private var modelContext

    @State private var showingShareSheet = false
    @State private var share: CKShare?
    @State private var error: Error?
    @State private var isLoading = false

    private let sharingService = CloudKitSharingService()
    private let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCK")

    var body: some View {
        Button {
            Task {
                await prepareShare()
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

        // Check if already shared
        if let existingShare = sharingService.getShare(for: caree, in: modelContext) {
            share = existingShare
        } else {
            // New share - will be created by UICloudSharingController's preparation handler
            share = nil
        }

        showingShareSheet = true
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree)
        .modelContainer(PreviewContainer.shared)
}
#endif
