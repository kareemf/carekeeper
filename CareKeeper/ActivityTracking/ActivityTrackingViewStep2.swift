import SwiftUI

struct ActivityTrackingViewStep2: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var errorHandling: ErrorHandling
    
    @StateObject private var locationController = LocationController.shared
    
    @ObservedObject var caree: Caree
    var behavior: Behavior
    
    @Binding var activeSheet: ActiveSheet?
    var onSave: (Activity) -> Void
    
    @State private var notes = ""
    @State private var trackLocation = false
    @State private var useCustomDate = false
    @State private var when: Date = Date()
    
    private func saveAction() {
        do {
            try viewContext.save()
        } catch {
            errorHandling.handle(error: error, description: "Error saving activity")
        }
    }
    
    private func handleSavePress() {
        let newActivity = Activity(context: viewContext)
        
        newActivity.caree = caree
        newActivity.behavior = behavior
        newActivity.notes = notes
        newActivity.when = useCustomDate ? when : Date()
        
        if trackLocation {
            let location = locationController.location
            
            if location != nil {
                let coordinate = location!.coordinate
                newActivity.latitude = coordinate.latitude
                newActivity.longitude = coordinate.longitude
            }
        }
        
        activeSheet = nil
        saveAction()
        onSave(newActivity)
    }
    
    var body: some View {
        VStack {
            Form {
                Section {
                    TextField("Notes", text: $notes)
                    
                    if behavior.enableLocations {
                        Toggle(isOn: $trackLocation) {
                            Text("Pin Location")
                        }
                        .onAppear {
                            if trackLocation {
                                locationController.startUpdating()
                            }
                        }
                        .onDisappear {
                            if trackLocation {
                                locationController.stopUpdating()
                            }
                        }
                        .onChange(of: trackLocation) { _ in
                            if trackLocation {
                                locationController.startUpdating()
                            } else {
                                locationController.stopUpdating()
                            }
                        }
                    }}
#if !os(watchOS)
                Section {
                    Toggle(isOn: $useCustomDate) {
                        Text("Set Time")
                    }
                    
                    if useCustomDate {
                        DatePicker(
                            "When",
                            selection: $when,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
#endif
                Section {
                    Button("Done") {
                        handleSavePress()
                        locationController.stopUpdating()
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.red)
                    
                }
            }
#if !os(watchOS)
            Section {
                if trackLocation {
                    UserLocationMap(location: $locationController.location, dropPinAtLocation: false)
                }
            }
#endif
        }
#if os(watchOS)
        .navigationTitle("\(behavior.icon ?? "")\(behavior.name ?? "")")
#else
        .navigationTitle("\(caree.name ?? "") - \(behavior.icon ?? "")\(behavior.name ?? "")")
#endif
    }
}

struct ActivityTrackingViewStep2_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchCareeRequest = Caree.fetchRequest()
    // swiftlint:disable:next force_try
    static let carees = try! viewContext.fetch(fetchCareeRequest)
    
    static var previews: some View {
        ActivityTrackingViewStep2(
            caree: carees[0],
            // swiftlint:disable:next force_cast
            behavior: carees[0].behaviors!.allObjects.first(where: {($0 as! Behavior).enableLocations}) as! Behavior,
            activeSheet: .constant(.activityTracking1),
            onSave: {_ in }
        )
        .environment(\.managedObjectContext, viewContext)
    }
}
