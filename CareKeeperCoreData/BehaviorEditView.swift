
import SwiftUI

struct BehaviorEditView: View {
    @ObservedObject var behavior: Behavior
    @State private var isPresentingActivityTrackingView = false
    
    private var isNew: Bool {
        behavior.objectID.isTemporaryID
    }
    
    private var navTitle: String {
        return isNew ? "New Behavior" : "Behavior - \(behavior.name ?? "")"
    }
    
    var body: some View {
            Form {
                Section(header: Text("Info")) {
                    TextField("Name", text: $behavior.name ?? "")
                    //                TODO: limit to emojis?
                    //                TODO: limit to single char
                    TextField("Icon", text: $behavior.icon ?? "")
                }
                
                Section(header: Text("Properties")) {
                    Toggle(isOn: $behavior.enableLocations) {
                        Text("Allow Locations Requests")
                    }
                }
                
                if !isNew {
                    Section(header: Text("Activity").foregroundColor(.green)) {
                        NavigationLink(destination: ActivityTrackingViewStep2(caree: behavior.caree!, behavior: behavior, isPresentingView: $isPresentingActivityTrackingView)) {
                            Button(action: {
                                self.isPresentingActivityTrackingView = true
                            }) {
                                Label("Track Activity", systemImage: "timer")
                                    .font(.headline)
                            }
                            .foregroundColor(.green)
                        }
                    }
                }
            }
        .navigationTitle(.constant(navTitle))
    }
}

struct BehaviorEditView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchCareeRequest = Behavior.fetchRequest()
    static let behaviors = try! viewContext.fetch(fetchCareeRequest)
    
    static var previews: some View {
        NavigationView {            
            BehaviorEditView(behavior: behaviors[0])
        }
    }
}
