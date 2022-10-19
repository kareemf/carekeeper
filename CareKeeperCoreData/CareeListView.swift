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
                        CareeDetailView(caree: caree)
                            .frame(height: 100.0)
                    } label: {
                        // Text(caree.name ?? "")
                        CareeListItem(caree: caree)
                    }
                }
                .onDelete(perform: deleteCarees)
            }
#if os(watchOS)
            .listStyle(CarouselListStyle())
#endif
//            TODO: fix inactive toolbar after edit
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
//                TODO: fix height and focus
                NavigationView {
                    Form {
                        TextField("Name", text: $name)
                    }
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
//            TODO: cascade delete to behaviors and activities
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

struct CareeListItem: View {
    var caree: Caree

    var body: some View {
        HStack {
            // Text(caree.emoji)
            //     .font(.title)
            VStack(alignment: .leading) {
                Text(caree.name ?? "")
                    .font(.system(.headline, design: .rounded))
                Text("\(caree.behaviors?.count ?? 0) behaviors")
                Text("\(caree.activities?.count ?? 0) activities")

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
