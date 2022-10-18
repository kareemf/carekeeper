
import SwiftUI

struct BehaviorEditView: View {
    @ObservedObject var data: Behavior
    @State private var newTag = ""

    var body: some View {
        Form {
            Section(header: Text("Info")) {
                TextField("Name", text: $data.name ?? "")
//                TODO: limit to emojis?
//                TODO: limit to single char
                TextField("Icon", text: $data.icon ?? "")
            }
        }
    }
}

struct BehaviorEditView_Previews: PreviewProvider {
    static var previews: some View {
//        BehaviorEditView(data: .constant(Behavior()))
        Text("TODO")
    }
}
