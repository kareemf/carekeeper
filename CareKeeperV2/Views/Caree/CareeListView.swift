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
                } else {
                    careeListView
                }
            }
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusIndicator()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddCaree = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCaree) {
                CareeEditView()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(NSLocalizedString("No Carees", comment: "Empty state title"))
                .font(.title2)
                .fontWeight(.medium)
            
            Text(NSLocalizedString("Create your first caree and set up activity types to start tracking.", 
                                 comment: "Empty state description"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button(NSLocalizedString("Add Caree", comment: "CTA button in empty state")) {
                showingAddCaree = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var careeListView: some View {
        List {
            ForEach(carees) { caree in
                NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                    CareeListRowView(caree: caree)
                }
            }
            .onDelete(perform: deleteCarees)
            .onMove(perform: moveCarees)
        }
    }
    
    private func deleteCarees(offsets: IndexSet) {
        let sharingService = CloudKitSharingService()

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
    
    private func moveCarees(from source: IndexSet, to destination: Int) {
        var updatedCarees = carees
        updatedCarees.move(fromOffsets: source, toOffset: destination)
        
        for (index, caree) in updatedCarees.enumerated() {
            caree.listOrder = index
        }
    }
}

#Preview {
    NavigationView {
        CareeListView()
    }
    .modelContainer(PreviewContainer.shared)
}