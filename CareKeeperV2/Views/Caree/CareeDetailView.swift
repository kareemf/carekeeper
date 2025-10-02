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

    init(careeID: UUID) {
        self.careeID = careeID
    }
    
    var body: some View {
        Group {
            if let caree = caree {
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection(for: caree)

                        // Only show track activity button if activity types exist
                        if !caree.sortedActivityTypes.isEmpty {
                            trackActivityButton(for: caree)
                        }

                        activityTypesSection(for: caree)

                        // Only show recent activities section if activity types exist
                        if !caree.sortedActivityTypes.isEmpty {
                            recentActivitiesSection(for: caree)
                        } else {
                            noActivityTypesGuidance
                        }
                    }
                    .padding()
                }
                .navigationTitle(caree.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Edit", comment: "Edit button")) {
                            showingEditCaree = true
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
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func headerSection(for caree: Caree) -> some View {
        HStack {
            profileImageView(for: caree)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("\(caree.activityTypes.count) activity types",
                                     comment: "Activity types count"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("\(caree.activities.count) total activities",
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
        .disabled(caree.activityTypes.isEmpty)
    }

    private func activityTypesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Activity Types", comment: "Activity types section title"))
                    .font(.headline)

                Spacer()

                Button(NSLocalizedString("Add", comment: "Add activity type button")) {
                    showingAddActivityType = true
                }
                .font(.subheadline)
            }

            if !caree.sortedActivityTypes.isEmpty {
                activityTypesList(for: caree)
            }
        }
    }

    private func activityTypesList(for caree: Caree) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(caree.sortedActivityTypes) { activityType in
                ActivityTypeRowView(activityType: activityType)
            }
        }
    }

    private func recentActivitiesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Recent Activities", comment: "Recent activities section title"))
                .font(.headline)

            if caree.recentActivities.isEmpty {
                emptyActivitiesView
            } else {
                recentActivitiesList(for: caree)
            }
        }
    }

    private var emptyActivitiesView: some View {
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
    }

    private func recentActivitiesList(for caree: Caree) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(caree.recentActivities.prefix(5))) { activity in
                ActivityRowView(activity: activity)
            }

            if caree.recentActivities.count > 5 {
                Button(NSLocalizedString("View All Activities", comment: "View all activities button")) {
                    // Navigate to full activities list
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
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