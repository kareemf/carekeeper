import SwiftUI
import CoreData

struct CareeDetailView: View {
    @ObservedObject private var caree: Caree
    private var viewContext: NSManagedObjectContext
    
    @State private var name: String
    @State private var isPresentingEditView = false
    
    @State private var activities: [Activity]
    @State private var selectedActivity: Activity?
    @State private var isPresentingActivityTrackingView = false
    @State private var isPresentingActivityDetailView = false
    
    @State private var behaviors: [Behavior]
    @State private var selectedBehavior: Behavior?
    @State private var isPresentingBehaviorEditView = false
    
    private var isPresentingSheet: Bool {
        isPresentingBehaviorEditView || isPresentingActivityDetailView
    }
    
    private func saveAction() {
        do {
            try viewContext.save()
            activities = CareeDetailView.fetchActivities(caree, viewContext)
            behaviors = CareeDetailView.fetchBehaviors(caree, viewContext)
            
            
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    init(caree: Caree, viewContext: NSManagedObjectContext) {
        self.caree = caree
        self.viewContext = viewContext
        self.name = caree.name ?? ""
        
        activities = CareeDetailView.fetchActivities(caree, viewContext)
        behaviors = CareeDetailView.fetchBehaviors(caree, viewContext)
    }
    
    private static func fetchActivities(_ caree: Caree, _ viewContext: NSManagedObjectContext) -> [Activity] {
        let predicate = NSPredicate(format: "caree == %@", caree)
        
        let fetchActivitiesRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Activity")
        fetchActivitiesRequest.predicate = predicate
        
        return try! viewContext.fetch(fetchActivitiesRequest) as? [Activity] ?? []
        
    }
    
    private static func fetchBehaviors(_ caree: Caree, _ viewContext: NSManagedObjectContext) -> [Behavior] {
        let predicate = NSPredicate(format: "caree == %@", caree)
        
        let fetchBehaviorsRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Behavior")
        fetchBehaviorsRequest.predicate = predicate
        
        return try! viewContext.fetch(fetchBehaviorsRequest) as? [Behavior] ?? []
    }
    
    var body: some View {
        List {
            if isPresentingEditView == true {
                Section("Info") {
                    TextField("Name", text: $name)
                        .onAppear {
                            name = caree.name ?? ""
                        }
                        .onSubmit {
                            caree.name = name
                            saveAction()
                        }
                }
            }
            Section(header: Text("Activity")) {
                NavigationLink(destination: ActivityTrackingViewStep1(caree: caree, isPresentingView: $isPresentingActivityTrackingView, behaviors: behaviors, saveAction: saveAction), isActive: $isPresentingActivityTrackingView) {
                    Button(action: {
                        self.isPresentingActivityTrackingView = true
                    }) {
                        Label("Track Activity", systemImage: "timer")
                            .font(.headline)
                    }
                    .foregroundColor(.green)
                }
            }
            
            
            Section(header: Text("Behaviors")) {
                Button(action: {
                    let newBehavior = Behavior(context: viewContext)
                    newBehavior.caree = caree
                    
                    self.selectedBehavior = newBehavior
                    self.isPresentingBehaviorEditView = true
                }) {
                    Label("Create Behavior To Track", systemImage: "plus")
                        .font(.headline)
                }
                .foregroundColor(.mint)
                
                if behaviors.isEmpty {
                    Text("No behaviors configured yet")
                }
                
                ForEach(behaviors) { behavior in
                    Button(action: {
                        self.selectedBehavior = behavior
                        self.isPresentingBehaviorEditView = true
                    }) {
                        BehaviorListItemView(behavior: behavior)
                    }
                    .foregroundColor(.mint)
                }.onDelete(perform: deleteBehaviors)
            }
            
            Section(header: Text("Activities")) {
                if activities.isEmpty {
                    Text("No activities tracked yet")
                }
                
                ForEach(activities){ activity in
                    Button(action: {
                        self.selectedActivity = activity
                        self.isPresentingActivityDetailView = true
                    }) {
                        VStack(alignment: .leading) {
                            
                            BehaviorListItemView(behavior: activity.behavior!)
                            Text("🗓 \(activity.when?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                            
                            
                            if !(activity.notes?.isEmpty ?? true) {
                                Text("🗒 \(activity.notes!)")
                            }
                        }
                    }
                }.onDelete(perform: deleteActivities)
            }
        }
        .navigationTitle(caree.name ?? "")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isPresentingEditView == true {
                    Button("Done") {
                        isPresentingEditView = false
                    }
                } else {
                    Button("Edit") {
                        isPresentingEditView = true
                    }
                }
                
            }
        }
        .sheet(isPresented: .constant(isPresentingSheet)) {
            NavigationView {
                if isPresentingBehaviorEditView {
                    BehaviorEditView(data: selectedBehavior!)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    let isNew = selectedBehavior?.objectID.isTemporaryID ?? false
                                    if ( isNew) {
                                        viewContext.delete(selectedBehavior!)
                                    }
                                    isPresentingBehaviorEditView = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    let isNew = selectedBehavior?.objectID.isTemporaryID ?? false
                                    if ( isNew) {
                                        selectedBehavior?.dateCreated = Date()
                                    }
                                    saveAction()
                                    isPresentingBehaviorEditView = false
                                }
                            }
                        }
                    
                }
                else if isPresentingActivityDetailView {
                    ActivityDetailView(data: selectedActivity!)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    isPresentingActivityDetailView = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    saveAction()
                                    isPresentingActivityDetailView = false
                                }
                            }
                        }
                }
            }
        }
    }
    
    private func deleteBehaviors(offsets: IndexSet) {
        withAnimation {
            offsets.map { behaviors[$0] }.forEach(viewContext.delete)
            saveAction()
        }
    }
    
    private func deleteActivities(offsets: IndexSet) {
        withAnimation {
            offsets.map { activities[$0] }.forEach(viewContext.delete)
            saveAction()
        }
    }
}

struct CareeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        //        CareeDetailView()
        Text("")
    }
}
