import CloudKit
import Combine
import SwiftData
import SwiftUI

struct SharingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitDataService

    // Populated via dual publisher: subscribes to cacheService becoming available
    // AND to cacheService.myCarees changes (handles nil cacheService at view init)
    @State private var myCarees: [Caree] = []


    @StateObject private var displayNameService = CaregiverDisplayNameService.shared

    @State private var careeToStopSharing: Caree?
    @State private var showingStopSharingConfirmation = false
    @State private var error: Error?
    @State private var isInitialLoad = true
    @State private var isRefreshingShares = false

    // Cache of CKShare by Caree.id so UI can compute synchronously
    @State private var sharesByCareeID: [UUID: CKShare] = [:]

    private let sharingService = CloudKitSharingService()
    
    // Service for fetching shared records
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService
    
    // Combined list of all carees (private + shared)
    private var allCarees: [Caree] {
        myCarees + sharedRecordsService.sharedCarees
    }

    var body: some View {
        NavigationView {
            Group {
                if isInitialLoad, allCarees.isEmpty {
                    // Show full-screen loading only on first load with empty cache
                    // Otherwise, show cached content and refresh in background
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(NSLocalizedString("Loading shared carees...", comment: "Loading shared carees message"))
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        // Your Identity section
                        Section {
                            HStack {
                                Text(NSLocalizedString("Your Display Name", comment: "Display name label"))
                                Spacer()
                                TextField(
                                    NSLocalizedString("Enter your name", comment: "Display name placeholder"),
                                    text: Binding(
                                        get: { displayNameService.displayName ?? "" },
                                        set: { displayNameService.displayName = $0.isEmpty ? nil : $0 }
                                    )
                                )
                                .multilineTextAlignment(.trailing)
                                .textContentType(.name)
                            }
                        } header: {
                            Text(NSLocalizedString("Your Identity", comment: "Your identity section header"))
                        } footer: {
                            Text(NSLocalizedString(
                                "This name is shown to other caregivers in activity notifications.",
                                comment: "Display name footer"
                            ))
                        }

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
                                    message: NSLocalizedString(
                                        "You haven't shared any carees yet",
                                        comment: "Empty shared by me message"
                                    )
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
                                            Label(
                                                NSLocalizedString("Stop Sharing", comment: "Stop sharing button"),
                                                systemImage: "xmark.circle"
                                            )
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
                                    message: NSLocalizedString(
                                        "No one has shared a caree with you yet",
                                        comment: "Empty shared with me message"
                                    )
                                )
                            } header: {
                                Text(NSLocalizedString("Shared with Me", comment: "Shared with me section header"))
                            }
                        }
                    }
                }
            }
            .refreshable {
                isRefreshingShares = true
                await sharedRecordsService.fetchSharedCarees()
                await refreshShares()
                isRefreshingShares = false
            }
            .navigationTitle(NSLocalizedString("Sharing", comment: "Sharing view title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusIndicator()
                }
            }
            .overlay {
                if isRefreshingShares, !isInitialLoad {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("Refreshing...", comment: "Refreshing message"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .padding(.bottom, 40)
                    }
                }
            }
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
                Text(NSLocalizedString(
                    "You will no longer have access to this caree and its activities.",
                    comment: "Stop sharing confirmation message"
                ))
            }
        }
        .task {
            isInitialLoad = true
            await sharedRecordsService.fetchSharedCarees()
            await refreshShares()
            isInitialLoad = false
        }
        .onReceive(cloudKitService.$cacheService.compactMap { $0 }) { cache in
            myCarees = cache.myCarees.sorted { $0.listOrder < $1.listOrder }
        }
        .onReceive(
            cloudKitService.cacheService?.$myCarees.eraseToAnyPublisher()
                ?? Empty().eraseToAnyPublisher()
        ) { carees in
            myCarees = carees.sorted { $0.listOrder < $1.listOrder }
        }
        .onChange(of: myCarees) {
            Task {
                await sharedRecordsService.fetchSharedCarees()
                await refreshShares()
            }
        }
        .onChange(of: sharedRecordsService.sharedCarees) {
            Task {
                await refreshShares()
            }
        }
        .onReceive(sharedRecordsService.$error) { newError in
            if let newError {
                error = newError
            }
        }
        .errorAlert($error)
    }

    // MARK: - Computed Properties

    private var sharedByMe: [Caree] {
        // Only my carees (from private database) that have shares
        myCarees.filter { caree in
            guard let share = sharesByCareeID[caree.id] else { return false }
            return sharingService.isOwner(of: share)
        }
    }

    private var sharedWithMe: [Caree] {
        // Shared carees (from shared database) where I'm not the owner
        sharedRecordsService.sharedCarees.filter { caree in
            guard let share = sharedRecordsService.sharesByCareeID[caree.id] else { return false }
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
        // Only fetch shares for my carees (from private database)
        // Shared carees' shares are already fetched by sharedRecordsService
        var next: [UUID: CKShare] = [:]
        for caree in myCarees {
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
                    let ownerName = owner.userIdentity.nameComponents?.formatted(.name(style: .short)) ?? NSLocalizedString(
                        "Unknown",
                        comment: "Unknown owner"
                    )
                    Text(String(format: NSLocalizedString("Shared by %@", comment: "Shared by owner name"), ownerName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    SharingView()
        .environmentObject(CloudKitDataService())
        .environmentObject(CloudKitSharedRecordsService())
        .modelContainer(PreviewContainer.shared)
}
