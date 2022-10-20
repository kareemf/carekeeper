import SwiftUI
import MapKit
import CoreData

struct ActivityDetailView: View {
    @StateObject private var locationController = LocationController.shared
    @ObservedObject var activity: Activity
        
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Notes")) {
                    TextField("Notes", text: $activity.notes ?? "")
                }
                
                Section(header: Text("Behavior")) {
                    BehaviorListItemView(behavior: activity.behavior!)
                }
            }
#if !os(watchOS)
            if activity.behavior?.enableLocations ?? false {
//                TODO: pass location
                UserLocationMap()
            }
#endif

        }
    }
}

struct ActivityDetailView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Activity.fetchRequest()
    static let activities = try! viewContext.fetch(fetchRequest)
    
    static var previews: some View {
        NavigationView {
            ActivityDetailView(activity: activities[0])
                .environment(\.managedObjectContext, viewContext)
        }
    }
}
