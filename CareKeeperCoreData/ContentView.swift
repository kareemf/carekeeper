import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Caree.name, ascending: false)],
        animation: .default)
    private var carees: FetchedResults<Caree>

    var body: some View {
        NavigationView {
            List {
                ForEach(carees) { caree in
                    NavigationLink {
                        //Text("Caree \(caree.name ?? "")")
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
                    Button(action: addCaree) {
                        Label("Add Caree", systemImage: "plus")
                    }
                }
            }
            Text("Select an item")
        }
        .navigationTitle("In My Care")
    }

    private func addCaree() {
        withAnimation {
            let newCaree = Caree(context: viewContext)
            newCaree.dateCreated = Date()
            newCaree.name = "foo"
            
            let behavior = Behavior(context: viewContext)
            
            behavior.caree = newCaree
            behavior.name = "behave"
            newCaree.dateCreated = Date()
            
            let activity = Activity(context: viewContext)
            activity.caree = newCaree
            activity.behavior = behavior
            activity.when = Date()
            

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
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
