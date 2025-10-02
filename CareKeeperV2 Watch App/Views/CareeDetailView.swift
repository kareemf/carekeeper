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

    @State private var showingTrackActivity = false

    init(careeID: UUID) {
        self.careeID = careeID
    }

    var body: some View {
        Group {
            if let caree = caree {
                ScrollView {
                    VStack(spacing: 16) {
                        // Track activity button (only if activity types exist)
                        if !caree.sortedActivityTypes.isEmpty {
                            trackActivityButton(for: caree)
                        }

                        // Activity types section
                        activityTypesSection(for: caree)

                        // Recent activities section
                        recentActivitiesSection(for: caree)
                    }
                    .padding()
                }
                .navigationTitle(caree.name)
                .sheet(isPresented: $showingTrackActivity) {
                    TrackActivityView(caree: caree)
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func trackActivityButton(for caree: Caree) -> some View {
        Button(action: { showingTrackActivity = true }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(NSLocalizedString("Track", comment: "Track activity button"))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .cornerRadius(8)
        }
        .disabled(caree.activityTypes.isEmpty)
    }

    private func activityTypesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Activity Types", comment: "Activity types section title"))
                .font(.headline)

            if caree.sortedActivityTypes.isEmpty {
                Text(NSLocalizedString("Add on iPhone", comment: "Empty activity types"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(caree.sortedActivityTypes) { activityType in
                    HStack {
                        Text(activityType.displayIcon)
                            .font(.title3)

                        Text(activityType.name)
                            .font(.subheadline)

                        Spacer()

                        Text("\(activityType.totalActivitiesCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func recentActivitiesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Recent", comment: "Recent activities section title"))
                .font(.headline)

            if caree.recentActivities.isEmpty {
                Text(NSLocalizedString("No activities yet", comment: "Empty activities message"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(caree.recentActivities.prefix(3))) { activity in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(activity.activityType?.displayIcon ?? "⭐")
                                .font(.caption)

                            Text(activity.activityType?.name ?? NSLocalizedString("Unknown", comment: "Unknown activity type"))
                                .font(.caption)

                            Spacer()

                            Text(activity.formattedDateTime)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let notes = activity.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CareeDetailView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
