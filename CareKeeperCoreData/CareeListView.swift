import SwiftUI
import CoreData

struct CareeListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var watchConnectivity = WatchConnectivityController.shared
    
    @State private var isPresentingNewCareeView = false
    @State private var name = ""

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Caree.name, ascending: false)],
        animation: .default)
    private var carees: FetchedResults<Caree>

    var body: some View {
        NavigationView {
            List {
                ForEach(carees) { caree in
                    NavigationLink {
                        CareeDetailView(caree: caree, viewContext: viewContext)
                    } label: {
                        Text(caree.name ?? "")
                    }
                }
                .onDelete(perform: deleteCarees)
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: {
                        isPresentingNewCareeView = true
                    }) {
                        Label("Add Caree", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("In My Care")
            .alert(item: $watchConnectivity.notificationMessageRecived) { message in
                 Alert(title: Text(message.text),
                       dismissButton: .default(Text("Dismiss")))
            }
            .sheet(isPresented: $isPresentingNewCareeView) {
                NavigationView {
                    VStack {
                        TextField("Name", text: $name)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isPresentingNewCareeView = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Add") {
                                        isPresentingNewCareeView = false
                                        addCaree()
                                    }.disabled(name.isEmpty)
                                }
                            }
                    }
                }
            }
        }
    }

    private func addCaree() {
        withAnimation {
            let newCaree = Caree(context: viewContext)
            newCaree.dateCreated = Date()
            newCaree.name = name
            
            do {
                try viewContext.save()
                name = ""
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteCarees(offsets: IndexSet) {
        withAnimation {
            offsets.map { carees[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
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
