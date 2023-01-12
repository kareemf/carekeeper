import SwiftUI
import CoreData
import CloudKit

struct CareeDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var errorHandling: ErrorHandling

    @ObservedObject private var caree: Caree

    @State private var name: String = ""

    @State private var activities: [Activity] = []
    @State private var behaviors: [Behavior] = []
    @State private var activeSheet: ActiveSheet?
    @State private var nextSheet: ActiveSheet?
    
    enum TabViewTags {
        case trackActivity
        case activities
        case behaviors
    }
    @State private var selectedTab: TabViewTags = .trackActivity

    // swiftlint:disable:next identifier_name
    static let ACTIVITY_FETCH_LIMIT = 5
    
    let persistenceController = PersistenceController.shared

    private func saveAction() {
        do {
            try viewContext.save()
            try activities = caree.fetchActivities()
            try behaviors = caree.fetchBehaviors()

        } catch {
            errorHandling.handle(error: error)
        }
    }

    init(caree: Caree) {
        self.caree = caree
    }

    private func saveEditForm() {
        caree.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAction()
    }

    @StateObject var profileImageModel = ProfileImageModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            ActivityTrackingViewStep1(
                caree: caree,
                activeSheet: $activeSheet,
//                TODO: organizational defect that onSave needs to be passed. See sheetView logic\
//                SOLUTION: split ActivityTrackingViewStep1 by platform/linking behavior
                onSave: {_ in},
                behaviors: behaviors
            )
            .tabItem {
                Text("Track Activity")
            }
            .tag(TabViewTags.trackActivity)
            
            List {
                if activities.isEmpty {
                    Text("No activities tracked yet")
                }

                ForEach(activities) { activity in
                    Button(action: {
                        activeSheet = .activityDetail(activity)
                    }) {
                        ActivityListItem(activity: activity)
                    }
                    .foregroundColor(.red)

                }
                .onDelete(perform: deleteActivities)
            }
            .navigationTitle("Activities")
            .tabItem {
                //TODO: simplify on watch
                ActivitySectionHeader(caree: caree, activities: $activities).foregroundColor(.red)
            }
            .tag(TabViewTags.activities)

            List {
                Button(action: {
                    let newBehavior = Behavior(context: viewContext)
                    newBehavior.caree = caree

                    activeSheet = .behaviorDetail(newBehavior)
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
                        activeSheet = .behaviorDetail(behavior)
                    }) {
                        BehaviorListItemView(behavior: behavior)
                    }
                    .foregroundColor(.mint)

                }
                .onDelete(perform: deleteBehaviors)
                .onMove(perform: moveBehaviors)
            }
            .navigationTitle("Behaviors")
            .tabItem {
                Text("Behaviors").foregroundColor(.mint)
            }
            .tag(TabViewTags.behaviors)

        }
        .onAppear(perform: {
            do {
                try activities = caree.fetchActivities()
                try behaviors = caree.fetchBehaviors()
            } catch {
                errorHandling.handle(error: error)
            }
        })
        .navigationTitle(caree.name ?? "")
        .sheet(item: $activeSheet, onDismiss: sheetOnDismiss) { item in
            sheetView(with: item)
        }
        .onChange(of: activeSheet, perform: { newValue in
            // Workaround to ensure that new activities are displayed after using main tracking button
            if newValue == nil {
                do {
                    try activities = caree.fetchActivities()
                } catch {
                    errorHandling.handle(error: error)
                }
            }
        })
    }

    @ViewBuilder
    private func sheetView(with item: ActiveSheet) -> some View {
        switch item {
        case .behaviorDetail(let behavior):
            BehavioDetailView(behavior: behavior, activeSheet: $activeSheet, onSave: saveAction)
        case .activityDetail(let activity):
            NavigationView {
                ActivityDetailView(activity: activity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                activeSheet = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                saveAction()
                                activeSheet = nil
                            }
                        }
                    }
            }
        case .activityTracking2(let behavior):
            NavigationView {
                ActivityTrackingViewStep2(caree: behavior.caree!, behavior: behavior, activeSheet: $activeSheet, onSave: { activity in
                    nextSheet = .activityDetail(activity)
                })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                activeSheet = nil
                            }
                        }
                    }
            }
        default:
            EmptyView()
        }
    }
    
    /**
     Present the next active sheet, if necessary.
     Dispatch asynchronously to the next run loop so the presentation occurs after the current sheet's dismissal.
     */
    private func sheetOnDismiss() {
        guard let nextActiveSheet = nextSheet else {
            return
        }
        
        DispatchQueue.main.async {
            activeSheet = nextActiveSheet
        }

        nextSheet = nil
    }

    private func deleteBehaviors(offsets: IndexSet) {
        withAnimation {
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
        Text("Activities")
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
