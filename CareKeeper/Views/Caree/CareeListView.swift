import SwiftUI
import SwiftData

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Caree.listOrder) private var carees: [Caree]
    @State private var showingAddCaree = false
    @State private var careeToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false

    @StateObject private var syncService = CloudKitSyncService()
    
    var body: some View {
        NavigationView {
            Group {
                if carees.isEmpty {
                    emptyStateView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    careeListView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: carees.isEmpty)
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
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .symbolEffect(.bounce, value: carees.isEmpty)

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
            ForEach(carees) { caree in
                NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                    CareeListRowView(caree: caree)
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
        .animation(.easeInOut(duration: 0.3), value: carees.map { $0.id })
    }

    private func refreshAllCarees() async {
        // Check sync status for all carees
        // This refreshes the general CloudKit state
        // Individual sync status is checked in CareeDetailView
        for caree in carees {
            _ = await syncService.isSynced(caree: caree)
        }
    }
    
    @MainActor
    private func deleteCarees(offsets: IndexSet) async {
        let sharingService = CloudKitSharingService()

        // Resolve indices to concrete Caree instances first
        let itemsToConsider = offsets.compactMap { index in
            carees.indices.contains(index) ? carees[index] : nil
        }

        // Check permissions asynchronously (owner can delete)
        var deletable: [Caree] = []
        for caree in itemsToConsider {
            let allowed = await sharingService.canDelete(caree: caree, in: modelContext)
            if allowed {
                deletable.append(caree)
            } else {
                // Optionally surface a user-facing message here
            }
        }

        // Perform deletions with animation on the main actor
        withAnimation(.easeInOut(duration: 0.3)) {
            for caree in deletable {
                modelContext.delete(caree)
            }
        }
    }
    
    private func moveCarees(from source: IndexSet, to destination: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            var updatedCarees = carees
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
