import SwiftUI

struct ActivityTrackingViewStep2: View {
    @ObservedObject var caree: Caree
    var behavior: Behavior
    @Binding var isPresentingView: Bool
    @State var notes = ""
    @Environment(\.managedObjectContext) private var viewContext
    
    let saveAction: () -> Void
//
//
//    private func saveAction() {
//        do {
//            try viewContext.save()
//        } catch {
//            // Replace this implementation with code to handle the error appropriately.
//            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//            let nsError = error as NSError
//            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//        }
//    }

    var body: some View {
        VStack {
            Text("\(caree.name ?? "") - \(behavior.icon ?? "")\(behavior.name ?? "")")
            Form {
                TextField("Notes", text: $notes)
            }
            Button("Save") {
                let newActivity = Activity(context: viewContext)
                
                newActivity.caree = caree
                newActivity.behavior = behavior
                newActivity.notes = notes
                newActivity.when = Date()
                                
                saveAction()
                isPresentingView = false
            }
        }
    }
}

struct ActivityTrackingViewStep2_Previews: PreviewProvider {
    static var previews: some View {
        Text("TODO")
//        ActivityTrackingViewStep2(
//            caree: .constant(Caree.sampleData[0]),
//            behavior: .constant(Caree.sampleData[0].behaviors[0]),
//            isPresentingView: .constant(true),
//            saveAction: {}
//        )
    }
}
