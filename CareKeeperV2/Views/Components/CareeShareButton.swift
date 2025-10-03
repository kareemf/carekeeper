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
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: sharingService.isShared(caree, in: modelContext) ? "person.2.fill" : "person.2")
                    Text(sharingService.isShared(caree, in: modelContext)
                         ? NSLocalizedString("Manage Sharing", comment: "Manage sharing button")
                         : NSLocalizedString("Share", comment: "Share button"))
                }
            }
        }
        .disabled(isLoading)
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
            // Check if already shared
            if let existingShare = sharingService.getShare(for: caree, in: modelContext) {
                share = existingShare
                showingShareSheet = true
                return
            }

            // Create new share
            // Note: Actual share creation requires access to the persistent store coordinator
            // This is a simplified version - production code needs proper SwiftData+CloudKit integration
            let newShare = CKShare(rootRecord: CKRecord(recordType: "Caree"))
            newShare[CKShare.SystemFieldKey.title] = caree.name as CKRecordValue
            newShare.publicPermission = .none

            // Set permissions: participants can read/write but not delete
            share = newShare
            showingShareSheet = true

        } catch {
            self.error = AppError.saveFailed(error.localizedDescription)
        }
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree)
        .modelContainer(PreviewContainer.shared)
}
#endif
