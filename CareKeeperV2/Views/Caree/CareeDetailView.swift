import SwiftUI
import SwiftData

struct CareeDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let careeID: UUID
    @Query private var allCarees: [Caree]

    // Computed property to get the specific caree
    private var caree: Caree? {
        allCarees.first { $0.id == careeID }
    }

    @State private var showingEditCaree = false
    @State private var showingAddActivityType = false
    @State private var showingTrackActivity = false
    @State private var activityTypeToDelete: ActivityType?
    @State private var showingDeleteActivityTypeConfirmation = false
    @State private var activityToDelete: Activity?
    @State private var showingDeleteActivityConfirmation = false

    init(careeID: UUID) {
        self.careeID = careeID
    }
    
    var body: some View {
        Group {
            if let caree = caree {
                List {
                    Section {
                        headerSection(for: caree)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // Only show track activity button if activity types exist
                    if !caree.sortedActivityTypes.isEmpty {
                        Section {
                            trackActivityButton(for: caree)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    // Only show recent activities section if activity types exist
                    if !caree.sortedActivityTypes.isEmpty {
                        Section(header: recentActivitiesSectionHeader(for: caree)) {
                            if caree.recentActivities.isEmpty {
                                emptyActivitiesView
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(Array(caree.recentActivities.prefix(5))) { activity in
                                    ActivityRowView(activity: activity)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                activityToDelete = activity
                                                showingDeleteActivityConfirmation = true
                                            } label: {
                                                Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .textCase(nil)
                    }

                    Section(header: activityTypesSectionHeader) {
                        if !caree.sortedActivityTypes.isEmpty {
                            ForEach(caree.sortedActivityTypes) { activityType in
                                ActivityTypeRowView(activityType: activityType)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            activityTypeToDelete = activityType
                                            showingDeleteActivityTypeConfirmation = true
                                        } label: {
                                            Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove(perform: moveActivityTypes)
                        }
                    }
                    .textCase(nil)

                    if caree.sortedActivityTypes.isEmpty {
                        Section {
                            noActivityTypesGuidance
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .navigationTitle(caree.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            #if os(iOS)
                            CareeShareButton(caree: caree)
                            #endif

                            Button(NSLocalizedString("Edit", comment: "Edit button")) {
                                showingEditCaree = true
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingEditCaree) {
                    CareeEditView(caree: caree)
                }
                .sheet(isPresented: $showingAddActivityType) {
                    ActivityTypeEditView(caree: caree)
                }
                .sheet(isPresented: $showingTrackActivity) {
                    TrackActivityView(caree: caree)
                }
                .confirmationDialog(
                    NSLocalizedString("Delete Activity Type?", comment: "Delete activity type confirmation title"),
                    isPresented: $showingDeleteActivityTypeConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                        if let activityType = activityTypeToDelete {
                            deleteActivityType(activityType)
                        }
                    }
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                        activityTypeToDelete = nil
                    }
                } message: {
                    Text(NSLocalizedString("This will also delete all associated activities. This cannot be undone.", comment: "Delete activity type confirmation message"))
                }
                .confirmationDialog(
                    NSLocalizedString("Delete Activity?", comment: "Delete activity confirmation title"),
                    isPresented: $showingDeleteActivityConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                        if let activity = activityToDelete {
                            deleteActivity(activity)
                        }
                    }
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                        activityToDelete = nil
                    }
                } message: {
                    Text(NSLocalizedString("This cannot be undone.", comment: "Delete activity confirmation message"))
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func deleteActivityType(_ activityType: ActivityType) {
        modelContext.delete(activityType)
        activityTypeToDelete = nil
    }

    private func deleteActivity(_ activity: Activity) {
        modelContext.delete(activity)
        activityToDelete = nil
    }

    private func moveActivityTypes(from source: IndexSet, to destination: Int) {
        guard let caree = caree else { return }

        var updatedActivityTypes = caree.sortedActivityTypes
        updatedActivityTypes.move(fromOffsets: source, toOffset: destination)

        for (index, activityType) in updatedActivityTypes.enumerated() {
            activityType.listOrder = index
        }
    }

    private func headerSection(for caree: Caree) -> some View {
        HStack {
            profileImageView(for: caree)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("\(caree.activityTypes?.count ?? 0) Activity Types",
                                     comment: "Activity types count"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("\(caree.activities?.count ?? 0) Total Activities",
                                     comment: "Total activities count"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func profileImageView(for caree: Caree) -> some View {
        Group {
            if let imageData = caree.image, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
    }

    private func trackActivityButton(for caree: Caree) -> some View {
        Button(action: { showingTrackActivity = true }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)

                Text(NSLocalizedString("Track Activity", comment: "Track activity button"))
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.8))
            .cornerRadius(12)
        }
        .disabled(caree.activityTypes?.isEmpty ?? true)
    }

    private var activityTypesSectionHeader: some View {
        HStack {
            Text(NSLocalizedString("Activity Types", comment: "Activity types section title"))

            Spacer()

            Button(NSLocalizedString("Add", comment: "Add activity type button")) {
                showingAddActivityType = true
            }
            .font(.subheadline)
        }
    }

    private func recentActivitiesSectionHeader(for caree: Caree) -> some View {
        HStack {
            Text(NSLocalizedString("Recent Activities", comment: "Recent activities section title"))

            Spacer()

            if !caree.recentActivities.isEmpty {
                NavigationLink(destination: ActivityListView(careeID: caree.id)) {
                    Text(NSLocalizedString("View All", comment: "View all activities button"))
                        .font(.subheadline)
                }
            }
        }
    }

    private var emptyActivitiesView: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "clock.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("No activities yet", comment: "Empty activities message"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("This list will be populated once you start tracking activities.",
                                     comment: "Empty activities description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            Spacer()
        }
    }

    private var noActivityTypesGuidance: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.circle")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text(NSLocalizedString("Getting Started", comment: "Getting started title"))
                .font(.headline)

            Text(NSLocalizedString("Once you've configured your first activity type, you'll be able to track new activities and view recent ones here.",
                                 comment: "No activity types guidance"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(NSLocalizedString("Add Activity Type", comment: "Add activity type CTA")) {
                showingAddActivityType = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        CareeDetailView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}