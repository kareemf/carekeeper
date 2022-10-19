import SwiftUI

struct ActivityTrackingViewStep2: View {
    @ObservedObject var caree: Caree
    var behavior: Behavior
    @Binding var isPresentingView: Bool
    @State var notes = ""
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    let saveAction: () -> Void
    
    func handleSavePress() {
        let newActivity = Activity(context: viewContext)
        
        newActivity.caree = caree
        newActivity.behavior = behavior
        newActivity.notes = notes
        newActivity.when = Date()
        
        isPresentingView = false
        saveAction()
//                TODO: not needed if isPresentingView works as intended
        dismiss()
    }

    var body: some View {
        VStack {
            Text("\(caree.name ?? "") - \(behavior.icon ?? "")\(behavior.name ?? "")")
            Form {
                TextField("Notes", text: $notes)
            }
            Button("Done") {
                handleSavePress()
            }
            .font(.system(.headline, design: .rounded))
            .foregroundColor(.red)
        }
    }
}

struct ActivityTrackingViewStep2_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchCareeRequest = Caree.fetchRequest()
    static let carees = try! viewContext.fetch(fetchCareeRequest)
    
    static var previews: some View {
        ActivityTrackingViewStep2(
            caree: carees[0],
            behavior: carees[0].behaviors!.allObjects[0] as! Behavior,
            isPresentingView: .constant(true),
            saveAction: {}
        )
        .environment(\.managedObjectContext, viewContext)
    }
}
