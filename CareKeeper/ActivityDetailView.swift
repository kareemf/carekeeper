import SwiftUI
import MapKit
import CoreData

struct ActivityDetailView: View {
    @StateObject private var locationController = LocationController.shared
    @ObservedObject var activity: Activity

    @State private var latitude: String = ""
    @State private var longitude: String = ""
    @State private var when: Date = Date()

    var hasLocation: Bool {
        activity.latitude != 0 || activity.longitude != 0
    }

    var location: CLLocation {
        CLLocation(latitude: activity.latitude, longitude: activity.longitude)
    }

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Notes")) {
                    TextField("Notes", text: $activity.notes ?? "")
                }

                Section(header: Text("Behavior")) {
                    BehaviorListItemView(behavior: activity.behavior!)
                }

                Section(header: Text("When")) {
#if os(watchOS)
                    Text("\(activity.when?.formatted(date: .abbreviated, time: .shortened) ?? "")")
#else

                    DatePicker(
                        "When",
                        selection: $when,
                        displayedComponents: [.date, .hourAndMinute]
                    ).onChange(of: when, perform: { newValue in
                        activity.when = newValue
                    })
#endif
                }
                if hasLocation {
                    Section(header: Text("Location")) {
                        TextField("Lat", text: $latitude)
                            .onAppear(perform: {
                                latitude = String(format: "%.02f", activity.latitude)
                            })
                            .onChange(of: latitude, perform: {
                                if let value = NumberFormatter().number(from: $0) {
                                    activity.latitude = value.doubleValue
                                }
                            })
                        TextField("Lon", text: $longitude)
                            .onAppear(perform: {
                                longitude = String(format: "%.02f", activity.longitude)
                            })
                            .onChange(of: longitude, perform: {
                                if let value = NumberFormatter().number(from: $0) {
                                    activity.longitude = value.doubleValue
                                }
                            })
                    }
                }
            }

#if !os(watchOS)
            if hasLocation {
                UserLocationMap(location: .constant(location), showsUserLocation: false, dropPinAtLocation: true)
            }
#endif

        }
    }
}

struct ActivityDetailView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Activity.fetchRequest()
    // swiftlint:disable:next force_try
    static let activities = try! viewContext.fetch(fetchRequest)

    static var previews: some View {
        NavigationView {
            ActivityDetailView(activity: activities[0])
                .environment(\.managedObjectContext, viewContext)
        }
    }
}
