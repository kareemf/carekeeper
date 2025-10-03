import SwiftUI
import SwiftData

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Caree.listOrder) private var carees: [Caree]
    @State private var showingAddCaree = false
    
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
            .onDelete(perform: deleteCarees)
            .onMove(perform: moveCarees)
        }
        .animation(.easeInOut(duration: 0.3), value: carees.map { $0.id })
    }
    
    private func deleteCarees(offsets: IndexSet) {
        let sharingService = CloudKitSharingService()

        withAnimation(.easeInOut(duration: 0.3)) {
            for index in offsets {
                let caree = carees[index]

                // Check if user has permission to delete (owner only)
                guard sharingService.canDelete(caree: caree, in: modelContext) else {
                    // Skip deletion if not owner
                    // In production, should show an alert to the user
                    continue
                }

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