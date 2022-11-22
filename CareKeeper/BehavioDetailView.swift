import SwiftUI

struct BehavioDetailView: View {
    @ObservedObject var behavior: Behavior
    @State private var activeSheet: ActiveSheet?
    @State private var name = ""
    @State private var icon = ""

    private var isNew: Bool {
        behavior.objectID.isTemporaryID
    }

    private var navTitle: String {
        return isNew ? "New Behavior" : "Behavior - \(behavior.name ?? "")"
    }

    var body: some View {
            Form {
                Section(header: Text("Info")) {
                    TextField("Name", text: $name)
                        .onAppear(perform: {
                            if let realName = behavior.name {
                                name = realName
                            }
                        })
                        .onChange(of: name, perform: { _ in
                            behavior.name = name
                        })
                    // TODO: limit to emojis?
                    // TODO: limit to single char
                    TextField("Icon", text: $icon)
                        .onAppear(perform: {
                            if let realIcon = behavior.icon {
                                name = realIcon
                            }
                        })
                        .onChange(of: icon, perform: { _ in
                            behavior.icon = icon
                        })
                }

                Section(header: Text("Properties")) {
                    Toggle(isOn: $behavior.enableLocations) {
                        Text("Allow Locations Requests")
                    }
                }

                if !isNew {
                    Section(header: Text("Activity").foregroundColor(.green)) {
                        Button(action: {
                            activeSheet = .activityTracking
                        }) {
                            Label("Track Activity", systemImage: "timer")
                                .font(.headline)
                        }
                        .foregroundColor(.green)                    }
                }
            }
        .navigationTitle(.constant(navTitle))
        .sheet(item: $activeSheet) { _ in
            ActivityTrackingViewStep2(caree: behavior.caree!, behavior: behavior, activeSheet: $activeSheet)
        }
    }
}

struct BehaviorEditView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Behavior.fetchRequest()

    // swiftlint:disable:next force_try
    static let behaviors = try! viewContext.fetch(fetchRequest)

    static var previews: some View {
        NavigationView {
            BehavioDetailView(behavior: behaviors[0])
        }
    }
}
