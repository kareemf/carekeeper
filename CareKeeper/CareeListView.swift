import SwiftUI
import CoreData

struct CareeListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var errorHandling: ErrorHandling

    @State private var isPresentingNewCareeView = false

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Caree.listOrder, ascending: true),
            NSSortDescriptor(keyPath: \Caree.name, ascending: false)
        ],
        animation: .default)
    private var carees: FetchedResults<Caree>

    var body: some View {
        NavigationView {
            List {
                if carees.isEmpty {
                    Text("Add persons, places, or things in your care")
                }
                ForEach(carees) { caree in
                    NavigationLink {
                        CareeDetailView(caree: caree)
                    } label: {
                        CareeListItem(caree: caree)
                            .frame(height: 100.0)
                    }
                }
                .onDelete(perform: deleteCarees)
                .onMove(perform: moveCarees)
#if os(watchOS)
                CareeAddButton(isPresentingNewCareeView: $isPresentingNewCareeView)
#endif
            }
#if os(watchOS)
            .listStyle(CarouselListStyle())
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }

                ToolbarItem(placement: .primaryAction) {
                    CareeAddButton(isPresentingNewCareeView: $isPresentingNewCareeView)
                }
#endif
            }
            .navigationTitle("In My Care")
            .sheet(isPresented: $isPresentingNewCareeView) {
                CareeAddView(isPresenting: $isPresentingNewCareeView)
            }
            .refreshable {
                viewContext.refreshAllObjects()
            }
        }
    }

    private func deleteCarees(offsets: IndexSet) {
        withAnimation {
            offsets.map { carees[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                self.errorHandling.handle(error: error)
            }
        }
    }

    private func moveCarees(from source: IndexSet, to destination: Int) {
        var reorderedCarees: [Caree] = carees.map { $0 }

        reorderedCarees.move(fromOffsets: source, toOffset: destination )

        // swiftlint:disable:next identifier_name
        for i in stride( from: reorderedCarees.count - 1,
                         through: 0,
                         by: -1 ) {
            reorderedCarees[i].listOrder = Int64(i)
        }

        do {
            try viewContext.save()
        } catch {
            self.errorHandling.handle(error: error)
        }
    }
}

struct CareeAddButton: View {
    @Binding var isPresentingNewCareeView: Bool

    var body: some View {
        Button(action: {
            isPresentingNewCareeView = true
        }) {
            Label("Add Caree", systemImage: "plus")
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CareeListView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
