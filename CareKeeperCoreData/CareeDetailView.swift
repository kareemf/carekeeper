import SwiftUI
import CoreData

struct CareeDetailView: View {
    @ObservedObject
    private var caree: Caree
    private var viewContext: NSManagedObjectContext
    private var activities: [Activity]
    private var behaviors: [Behavior]
    
    init(caree: Caree, viewContext: NSManagedObjectContext) {
        self.caree = caree
        self.viewContext = viewContext
        
        let predicate = NSPredicate(format: "caree == %@", caree)
        
        let fetchActivities = NSFetchRequest<NSFetchRequestResult>(entityName: "Activity")
        fetchActivities.predicate = predicate
        
        activities = try! viewContext.fetch(fetchActivities) as? [Activity] ?? []
        
        let fetchBehaviors = NSFetchRequest<NSFetchRequestResult>(entityName: "Behavior")
        fetchBehaviors.predicate = predicate
        
        behaviors = try! viewContext.fetch(fetchBehaviors) as? [Behavior] ?? []
    }
    
    var body: some View {
        List {
            Section(header: Text("Activity")) {
                NavigationLink {
                    Text("Track Activity")
                } label: {
                    Button(action: {
                        
                    }) {
                        Label("Track Activity", systemImage: "timer")
                            .font(.headline)
                    }
                    .foregroundColor(.green)
                }
            }
            Section(header: Text("Behaviors")) {
                ForEach(behaviors) {behavior in
                    BehaviorListItemView(behavior: behavior)
                }
            }
            Section(header: Text("Activities")) {
                if activities.count == 0 {
                    Text("No activities tracked yet")
                }
                
                ForEach(activities){ activity in
                    VStack(alignment: .leading) {
                        BehaviorListItemView(behavior: activity.behavior!)
                        Text("🗓 \(activity.when?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                        
                        if !(activity.notes?.isEmpty ?? true) {
                            Text("🗒 \(activity.notes!)")
                        }
                    }
                }
            }
        }
            .navigationTitle(caree.name ?? "")
    }
}

struct BehaviorListItemView: View {
    let behavior: Behavior
    
    var body: some View {
        HStack {
            if !(behavior.icon?.isEmpty ?? true) {
                Text("\(behavior.icon!)")
            }
            
            Text("\(behavior.name ?? "")")
        }
    }
}

struct CareeDetailView_Previews: PreviewProvider {
    static var previews: some View {
//        CareeDetailView()
        Text("")
    }
}
