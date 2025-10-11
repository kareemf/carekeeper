import SwiftUI
import SwiftData
import CloudKit

struct SharingView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Query private database (my own records)
    @Query(sort: \Caree.listOrder) private var myCarees: [Caree]
    
    @State private var careeToStopSharing: Caree?
    @State private var showingStopSharingConfirmation = false
    @State private var error: Error?

    // Cache of CKShare by Caree.id so UI can compute synchronously
    @State private var sharesByCareeID: [UUID: CKShare] = [:]

    private let sharingService = CloudKitSharingService()
    
    // Service for fetching shared records
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    
    // Combined list of all carees (private + shared)
    private var allCarees: [Caree] {
        return myCarees + sharedRecordsService.sharedCarees
    }

    var body: some View {
        NavigationView {
            List {
                // Shared by Me section
                if !sharedByMe.isEmpty {
                    Section {
                        ForEach(sharedByMe) { caree in
                            NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                                SharedByMeRowView(
                                    caree: caree,
                                    share: sharesByCareeID[caree.id]
                                )
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("Shared by Me", comment: "Shared by me section header"))
                    }
                } else {
                    Section {
                        emptyStateView(
                            icon: "person.2",
                            message: NSLocalizedString("You haven't shared any carees yet", comment: "Empty shared by me message")
                        )
                    } header: {
                        Text(NSLocalizedString("Shared by Me", comment: "Shared by me section header"))
                    }
                }

                // Shared with Me section
                if !sharedWithMe.isEmpty {
                    Section {
                        ForEach(sharedWithMe) { caree in
                            NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                                SharedWithMeRowView(
                                    caree: caree,
                                    share: sharesByCareeID[caree.id]
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    careeToStopSharing = caree
                                    showingStopSharingConfirmation = true
                                } label: {
                                    Label(NSLocalizedString("Stop Sharing", comment: "Stop sharing button"), systemImage: "xmark.circle")
                                }
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("Shared with Me", comment: "Shared with me section header"))
                    }
                } else {
                    Section {
                        emptyStateView(
                            icon: "person.crop.circle.badge.questionmark",
                            message: NSLocalizedString("No one has shared a caree with you yet", comment: "Empty shared with me message")
                        )
                    } header: {
                        Text(NSLocalizedString("Shared with Me", comment: "Shared with me section header"))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Sharing", comment: "Sharing view title"))
            .confirmationDialog(
                NSLocalizedString("Stop Sharing?", comment: "Stop sharing confirmation title"),
                isPresented: $showingStopSharingConfirmation,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("Stop Sharing", comment: "Stop sharing button"), role: .destructive) {
                    if let caree = careeToStopSharing {
                        Task {
                            await stopSharing(caree)
                        }
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                    careeToStopSharing = nil
                }
            } message: {
                Text(NSLocalizedString("You will no longer have access to this caree and its activities.", comment: "Stop sharing confirmation message"))
            }
        }
        .task {
            sharedRecordsService.setModelContext(modelContext)
            await sharedRecordsService.fetchSharedCarees()
            await refreshShares()
        }
        .onChange(of: myCarees) {
            Task { 
                sharedRecordsService.setModelContext(modelContext)
                await sharedRecordsService.fetchSharedCarees()
                await refreshShares() 
            }
        }
        .onReceive(sharedRecordsService.$error) { newError in
            if let newError = newError {
                error = newError
            }
        }
        .errorAlert($error)
    }

    // MARK: - Computed Properties

    private var sharedByMe: [Caree] {
        allCarees.filter { caree in
            guard let share = sharesByCareeID[caree.id] else { return false }
            return sharingService.isOwner(of: share)
        }
    }

    private var sharedWithMe: [Caree] {
        allCarees.filter { caree in
            guard let share = sharesByCareeID[caree.id] else { return false }
            return !sharingService.isOwner(of: share)
        }
    }

    // MARK: - Views

    private func emptyStateView(icon: String, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func refreshShares() async {
        var next: [UUID: CKShare] = [:]
        for caree in allCarees {
            do {
                if let share = try await sharingService.getShare(for: caree, in: modelContext) {
                    next[caree.id] = share
                }
            } catch {
                // Non-fatal for UI; just skip this caree
            }
        }
        await MainActor.run {
            self.sharesByCareeID = next
        }
    }

    private func stopSharing(_ caree: Caree) async {
        do {
            try await sharingService.stopSharing(caree: caree, in: modelContext)
            await MainActor.run {
                careeToStopSharing = nil
                // Remove from cache so UI updates immediately
                sharesByCareeID[caree.id] = nil
            }
        } catch {
            await MainActor.run {
                self.error = AppError.deleteFailed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Row Views

private struct SharedByMeRowView: View {
    let caree: Caree
    let share: CKShare?

    private let sharingService = CloudKitSharingService()

    var body: some View {
        HStack {
            // Profile image
            if let imageData = caree.image, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(caree.name)
                    .font(.headline)

                if let share {
                    let participantCount = sharingService.fetchParticipants(for: share).count
                    Text(participantCount == 1
                         ? NSLocalizedString("1 person", comment: "Participant count singular")
                         : String(format: NSLocalizedString("%d people", comment: "Participant count plural"), participantCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct SharedWithMeRowView: View {
    let caree: Caree
    let share: CKShare?

    var body: some View {
        HStack {
            // Profile image
            if let imageData = caree.image, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(caree.name)
                    .font(.headline)

                if let share {
                    let owner = share.owner
                    let ownerName = owner.userIdentity.nameComponents?.formatted(.name(style: .short)) ?? NSLocalizedString("Unknown", comment: "Unknown owner")
                    Text(String(format: NSLocalizedString("Shared by %@", comment: "Shared by owner name"), ownerName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SharingView()
        .modelContainer(PreviewContainer.shared)
}
