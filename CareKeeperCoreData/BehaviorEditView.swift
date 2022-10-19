
import SwiftUI

struct BehaviorEditView: View {
    @ObservedObject var behavior: Behavior
    @State private var newTag = ""

    var body: some View {
        Form {
            Section(header: Text("Info")) {
                TextField("Name", text: $behavior.name ?? "")
//                TODO: limit to emojis?
//                TODO: limit to single char
                TextField("Icon", text: $behavior.icon ?? "")
            }
        }
    }
}

struct BehaviorEditView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchCareeRequest = Behavior.fetchRequest()
    static let behaviors = try! viewContext.fetch(fetchCareeRequest)
    
    static var previews: some View {
        BehaviorEditView(behavior: behaviors[0])
    }
}
