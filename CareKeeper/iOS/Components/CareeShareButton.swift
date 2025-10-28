import SwiftUI
import SwiftData
import CloudKit

struct CareeShareButton: View {
    let caree: Caree
    let isSynced: Bool
    let isMyCaree: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService

    @State private var showingShareSheet = false
    @State private var share: CKShare?
    @State private var error: Error?
    @State private var isLoading = false
    @State private var showingSyncAlert = false
    @State private var isShared = false

    private let sharingService = CloudKitSharingService()
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

    var body: some View {
        Button {
            // Pre-share validation
            if !isMyCaree {
                isShared = true
               Task {
                    await prepareNonOwnedShare()
                } 
            } else if !isSynced {
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
                Image(systemName: isShared
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
                        // Refresh share status on dismiss
                        Task {
                            self.isShared = await sharingService.isShared(caree, in: modelContext)
                        }
                    }
                )
            }
        }
        .task(id: caree.id) {
            // Load/refresh share status when the view appears or caree changes
            self.isShared = await sharingService.isShared(caree, in: modelContext)
        }
        .errorAlert($error)
    }

    private func prepareShare() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let finalShare = try await sharingService.createOrGetShare(for: caree, in: modelContext)
            self.share = finalShare
            self.isShared = true
            self.showingShareSheet = true
        } catch {
            self.error = error
        }
    }

    private func prepareNonOwnedShare() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch shared carees to get the share
        await sharedRecordsService.fetchSharedCarees()

        // Get the share for this caree
        if let finalShare = sharedRecordsService.sharesByCareeID[caree.id] {
            self.share = finalShare
            self.isShared = true
            self.showingShareSheet = true
        } else {
            self.error = AppError.invalidInput("Could not find share for this caree")
        }
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree, isSynced: true, isMyCaree: true)
        .modelContainer(PreviewContainer.shared)
}
