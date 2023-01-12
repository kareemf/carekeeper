import SwiftUI
import CoreData
import CloudKit

struct CareeDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject private var errorHandling: ErrorHandling

    @ObservedObject private var caree: Caree

    @State private var name: String = ""

    @State private var activities: [Activity] = []
    @State private var behaviors: [Behavior] = []
    @State private var activeSheet: ActiveSheet?
    @State private var nextSheet: ActiveSheet?

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
#if os(iOS)
        if profileImageModel.imageSelection != nil {
            do {
                let photo = try profileImageModel.createPhotoFromSelection(context: viewContext)
                caree.photo = photo
            } catch {
                errorHandling.handle(error: error)
            }
        }
#endif
        saveAction()
    }

    @StateObject var profileImageModel = ProfileImageModel()

    var body: some View {
        List {
            profileImageView().frame(width: 1000, alignment: .center)
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
                    activeSheet = .activityTracking1
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

            Section(header: ActivitySectionHeader(caree: caree, activities: $activities).foregroundColor(.red)) {
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

                }.onDelete(perform: deleteActivities)
            }
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
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                    .onChange(of: editMode?.wrappedValue, perform: { _ in
                        guard let isEditing = editMode?.wrappedValue.isEditing else { return }

                        if isEditing == false {
                            saveEditForm()
                        }
                    })
                    .disabled((editMode?.wrappedValue.isEditing ?? false) && name.isEmpty)
            
                CareeShareButton(caree: caree, activeSheet: $activeSheet, nextSheet: $nextSheet)
            }
#endif
        }
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
    private func profileImageView() -> some View {
#if os(iOS)
        // Design choice: don't show profile image on watch to cut down on visual clutter

        if editMode?.wrappedValue.isEditing == true {
            EditableCircularProfileImage(model: profileImageModel)
                .onAppear {
                    if let image = caree.image() {
                        profileImageModel.imageState = .success(image)
                    }
                }
        } else {
            if let image = caree.image() {
                CircularProfileImage(imageState: .success(image))
                    .onTapGesture {
                        activeSheet = .fullImage
                    }
            } else {
                CircularProfileImage(imageState: .empty)
            }
        }
#else
        EmptyView()
#endif
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
        case .activityTracking1:
            ActivityTrackingViewStep1(
                caree: caree,
                activeSheet: $activeSheet,
                behaviors: behaviors
            )
        case .activityTracking2(let behavior):
            NavigationView {
                ActivityTrackingViewStep2(caree: behavior.caree!, behavior: behavior, activeSheet: $activeSheet)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                activeSheet = nil
                            }
                        }
                    }
            }
#if os(iOS)
        case .fullImage:
            FullImageView(activeSheet: $activeSheet, photo: caree.photo)
                .onDisappear { activeSheet = nil }
#endif
        case .sharePicker(let caree):
            AddToExistingShareView(activeSheet: $activeSheet, caree: caree)
        case .participantView(let share):
            ParticipantView(activeSheet: $activeSheet, share: share)
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
