import SwiftUI
import CoreData

struct CareeDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject private var errorHandling: ErrorHandling

    @ObservedObject private var caree: Caree

    @State private var name: String = ""

    @State private var activities: [Activity] = []
    @State private var selectedActivity: Activity?
    @State private var isPresentingActivityTrackingView = false
    @State private var isPresentingActivityDetailView = false

    @State private var behaviors: [Behavior] = []
    @State private var selectedBehavior: Behavior?
    @State private var isPresentingBehaviorEditView = false

    // swiftlint:disable:next identifier_name
    static let ACTIVITY_FETCH_LIMIT = 5

    private var isPresentingSheet: Bool {
        isPresentingBehaviorEditView || isPresentingActivityDetailView || isPresentingActivityTrackingView
    }

    private func saveAction() {
        do {
            try viewContext.save()
            try activities = CareeDetailView.fetchActivities(caree, viewContext)
            try behaviors = CareeDetailView.fetchBehaviors(caree, viewContext)

        } catch {
            errorHandling.handle(error: error)
        }
    }

    init(caree: Caree) {
        self.caree = caree
    }

    private static func fetchActivities(_ caree: Caree, _ viewContext: NSManagedObjectContext) throws -> [Activity] {
        let predicate = NSPredicate(format: "caree == %@", caree)

        let fetchRequest = Activity.fetchRequest()

        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Activity.when, ascending: false)]
        fetchRequest.fetchLimit = ACTIVITY_FETCH_LIMIT

        do {
            return try viewContext.fetch(fetchRequest) as [Activity]
        } catch {
            throw error
        }
    }

    private static func fetchBehaviors(_ caree: Caree, _ viewContext: NSManagedObjectContext) throws -> [Behavior] {
        let predicate = NSPredicate(format: "caree == %@", caree)

        let fetchRequest = Behavior.fetchRequest()

        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Behavior.listOrder, ascending: true),
            NSSortDescriptor(keyPath: \Behavior.dateCreated, ascending: false)
        ]

        do {
            return try viewContext.fetch(fetchRequest) as [Behavior]
        } catch {
            throw error
        }
    }

    private func saveEditForm() {
            caree.name = name
            saveAction()
    }

    var body: some View {
        List {
#if os(iOS)
            if editMode?.wrappedValue.isEditing == true {
                Section("Info") {
                    TextField("Name", text: $name)
                        .onAppear {
                            name = caree.name ?? ""
                        }
                        .onSubmit {
                            saveEditForm()
                        }

                }
                .animation(nil, value: editMode?.wrappedValue)
            }
#endif
            Section {
                Button(action: {
                        self.isPresentingActivityTrackingView = true
                    }) {
                        Label("Track Activity", systemImage: "timer")
                            .font(.headline)
                    }
                    .foregroundColor(.green)
                    .frame(height: 100.0)
            }

            Section(header: Text("Behaviors").foregroundColor(.mint)) {
                Button(action: {
                    let newBehavior = Behavior(context: viewContext)
                    newBehavior.caree = caree

                    self.selectedBehavior = newBehavior
                    self.isPresentingBehaviorEditView = true
                }) {
                    Label("Create Behavior", systemImage: "plus")
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

                }
                .onDelete(perform: deleteBehaviors)
                .onMove(perform: moveBehaviors)
            }

            Section(header: ActivitySectionHeader(caree: caree, activities: $activities).foregroundColor(.red)) {
                if activities.isEmpty {
                    Text("No activities tracked yet")
                }

                ForEach(activities) { activity in
                    Button(action: {
                        self.selectedActivity = activity
                        self.isPresentingActivityDetailView = true
                    }) {
                        ActivityListItem(activity: activity)
                    }
                    .foregroundColor(.red)

                }.onDelete(perform: deleteActivities)
            }
        }
        .onAppear(perform: {
            do {
                try activities = CareeDetailView.fetchActivities(caree, viewContext)
                try behaviors = CareeDetailView.fetchBehaviors(caree, viewContext)
            } catch {
                errorHandling.handle(error: error)
            }
        })
        .navigationTitle(caree.name ?? "")
        .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .onChange(of: editMode?.wrappedValue, perform: { _ in
                            guard let isEditing = editMode?.wrappedValue.isEditing else { return }

                            if isEditing == false {
                                saveEditForm()
                            }
                        })
                }
#endif
        }
        .sheet(isPresented: .constant(isPresentingSheet)) {
            NavigationView {
                if isPresentingBehaviorEditView {
                    BehavioDetailView(behavior: selectedBehavior!)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    let isNew = selectedBehavior?.objectID.isTemporaryID ?? false
                                    if  isNew {
                                        viewContext.delete(selectedBehavior!)
                                    }
                                    isPresentingBehaviorEditView = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    let isNew = selectedBehavior?.objectID.isTemporaryID ?? false
                                    if  isNew {
                                        selectedBehavior?.dateCreated = Date()
                                    }
                                    saveAction()
                                    isPresentingBehaviorEditView = false
                                }
                            }
                        }

                } else if isPresentingActivityDetailView {
                    ActivityDetailView(activity: selectedActivity!)
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
                } else if isPresentingActivityTrackingView {
                    ActivityTrackingViewStep1(
                        caree: caree,
                        isPresentingView: $isPresentingActivityTrackingView,
                        behaviors: behaviors
                    )
                    .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    isPresentingActivityTrackingView = false
                                }
                            }
                    }
                }
            }
        }
        .onChange(of: isPresentingActivityTrackingView, perform: { newValue in
            // Workaround to ensure that new activities are displayed after using main tracking button
            if newValue == false {
                do {
                    try activities = CareeDetailView.fetchActivities(caree, viewContext)
                } catch {
                    errorHandling.handle(error: error)
                }
            }
        })
    }

    private func deleteBehaviors(offsets: IndexSet) {
        withAnimation {
            //            TODO: soft delete behaviors that still have activities
            offsets.map { behaviors[$0] }.forEach(viewContext.delete)
            saveAction()
        }
    }

    private func moveBehaviors(from source: IndexSet, to destination: Int) {
        var reorderedBehaviors: [Behavior] = behaviors.map { $0 }

        reorderedBehaviors.move(fromOffsets: source, toOffset: destination )

        // swiftlint:disable:next identifier_name
        for i in stride( from: reorderedBehaviors.count - 1,
                         through: 0,
                         by: -1 ) {
            reorderedBehaviors[i].listOrder = Int64(i)
        }

        saveAction()
    }

    private func deleteActivities(offsets: IndexSet) {
        withAnimation {
            offsets.map { activities[$0] }.forEach(viewContext.delete)
            saveAction()
        }
    }
}

struct ActivitySectionHeader: View {
    @ObservedObject var caree: Caree
    @Binding var activities: [Activity]

    var body: some View {
#if os(watchOS)
        Text("Activities")
#else
        HStack {
            Text("Activities")
            if caree.activities?.count ?? 0 > CareeDetailView.ACTIVITY_FETCH_LIMIT {
                NavigationLink(
                    destination: ActivityListView(caree: caree),
                    label: { Text("Show More") }
                )
            }
        }
#endif
    }
}

struct CareeDetailView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Caree.fetchRequest()
    // swiftlint:disable:next force_try
    static let carees = try! viewContext.fetch(fetchRequest)

    static var previews: some View {
        NavigationView {
            CareeDetailView(caree: carees[0])
                .environment(\.managedObjectContext, viewContext)
        }
    }
}
