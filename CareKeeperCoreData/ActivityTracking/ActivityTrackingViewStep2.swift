import SwiftUI

struct ActivityTrackingViewStep2: View {
    @StateObject private var locationController = LocationController.shared

    @ObservedObject var caree: Caree
    var behavior: Behavior

    @Binding var isPresentingView: Bool

    @State var notes = ""
    @State private var trackLocation = false
    @State private var trackQuantity = true
    @State private var quantity = 0
    @State private var unit = "Oz"

    @Environment(\.managedObjectContext) private var viewContext

    private func saveAction() {
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    private func handleSavePress() {
        let newActivity = Activity(context: viewContext)

        newActivity.caree = caree
        newActivity.behavior = behavior
        newActivity.notes = notes
        newActivity.when = Date()

        if trackLocation {
            let location = locationController.location

            if location != nil {
                let coordinate = location!.coordinate
                newActivity.latitude = coordinate.latitude
                newActivity.longitude = coordinate.longitude
            }
        }

        isPresentingView = false
        saveAction()
    }

    var body: some View {
            VStack {
                Form {
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
                    }
                }
#if !os(watchOS)
                if trackLocation {
                    UserLocationMap(location: $locationController.location, dropPinAtLocation: false)
                }
#endif

                Button("Done") {
                    handleSavePress()
                    locationController.stopUpdating()
                }
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.red)
            }
        .navigationTitle("\(caree.name ?? "") - \(behavior.icon ?? "")\(behavior.name ?? "")")
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
            isPresentingView: .constant(true)
//            isPresentingView: true
        )
        .environment(\.managedObjectContext, viewContext)
    }
}
