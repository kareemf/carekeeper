import SwiftUI
import SwiftData
import Combine

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCaree = false
    @State private var careeToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false
    @State private var error: Error?

    // Pure CloudKit architecture: Cache service as source of truth
    @State private var cacheService: LocalCacheService?
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()

    // Combined list of all carees from cache
    private var allCarees: [Caree] {
        guard let cacheService = cacheService else { return [] }
        return cacheService.myCarees + cacheService.sharedCarees
    }
    
    var body: some View {
        NavigationView {
            Group {
                if allCarees.isEmpty {
                    emptyStateView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    careeListView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: allCarees.isEmpty)
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusIndicator()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingAddCaree = true
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showingAddCaree) {
                CareeEditView()
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                NSLocalizedString("Delete Caree?", comment: "Delete caree confirmation title"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    if let offsets = careeToDelete {
                        Task { @MainActor in
                            await deleteCarees(offsets: offsets)
                            careeToDelete = nil
                        }
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                    careeToDelete = nil
                }
            } message: {
                Text(NSLocalizedString("This will delete all activity types and activities. This cannot be undone.", comment: "Delete caree confirmation message"))
            }
            .task {
                // Initialize cache service with model context
                if cacheService == nil {
                    cacheService = LocalCacheService(modelContext: modelContext)
                    cloudKitService.setCacheService(cacheService!)
                }

                // Initial data load
                await refreshAllCarees()
            }
            .onReceive(sharedRecordsService.$error) { newError in
                if let newError = newError {
                    error = newError
                }
            }
            .onReceive(cacheService?.objectWillChange ?? Just(()).eraseToAnyPublisher()) { _ in
                // Trigger UI update when cache changes
            }
            .errorAlert($error)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .symbolEffect(.bounce, value: allCarees.isEmpty)

            Text(NSLocalizedString("No Carees", comment: "Empty state title"))
                .font(.title2)
                .fontWeight(.medium)

            Text(NSLocalizedString("Create your first caree and set up activity types to start tracking.",
                                 comment: "Empty state description"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(NSLocalizedString("Add Caree", comment: "CTA button in empty state")) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showingAddCaree = true
                }
            }
            .buttonStyle(.borderedProminent)
            .scaleEffect(showingAddCaree ? 0.95 : 1.0)
        }
        .padding()
    }
    
    private var careeListView: some View {
        List {
            ForEach(allCarees) { caree in
                NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                    CareeListRowView(
                        caree: caree,
                        isShared: caree.isShared  // Use cache metadata
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
            .onDelete { offsets in
                careeToDelete = offsets
                showingDeleteConfirmation = true
            }
            .onMove(perform: moveCarees)
        }
        .refreshable {
            await refreshAllCarees()
        }
        .animation(.easeInOut(duration: 0.3), value: allCarees.map { $0.id })
    }

    private func refreshAllCarees() async {
        guard let cacheService = cacheService else { return }

        // Fetch shared carees from CloudKit and update cache
        await sharedRecordsService.fetchSharedCarees()

        // Cache shared carees
        for sharedCaree in sharedRecordsService.sharedCarees {
            do {
                try await cacheService.cacheCaree(sharedCaree, isShared: true)
            } catch {
                self.error = error
            }
        }

        // Refresh cache to update published properties
        try? await cacheService.refreshCache()
    }
    
    @MainActor
    private func deleteCarees(offsets: IndexSet) async {
        let sharingService = CloudKitSharingService()

        // Resolve indices to concrete Caree instances first
        let itemsToConsider = offsets.compactMap { index in
            allCarees.indices.contains(index) ? allCarees[index] : nil
        }

        // Check permissions asynchronously (owner can delete)
        var deletable: [Caree] = []
        for caree in itemsToConsider {
            let allowed = await sharingService.canDelete(caree: caree, in: modelContext)
            if allowed {
                deletable.append(caree)
            } else {
                // Show error - user doesn't have permission to delete
                error = AppError.invalidInput("You don't have permission to delete this caree")
            }
        }

        // Pure CloudKit: Delete from CloudKit first, then cache
        withAnimation(.easeInOut(duration: 0.3)) {
            for caree in deletable {
                Task {
                    do {
                        // Determine if this is a shared caree
                        let isShared = caree.isShared

                        // Delete from CloudKit
                        try await cloudKitService.deleteCaree(caree, isShared: isShared)

                        // Cache is automatically updated by CloudKitDataService
                    } catch {
                        self.error = error
                    }
                }
            }
        }
    }
    
    private func moveCarees(from source: IndexSet, to destination: Int) {
        // Only allow reordering of my carees (not shared carees)
        // Shared carees maintain the owner's listOrder
        withAnimation(.easeInOut(duration: 0.3)) {
            var updatedCarees = myCarees
            updatedCarees.move(fromOffsets: source, toOffset: destination)

            for (index, caree) in updatedCarees.enumerated() {
                caree.listOrder = index
            }
        }
    }
}

#Preview {
    NavigationView {
        CareeListView()
    }
    .modelContainer(PreviewContainer.shared)
}
