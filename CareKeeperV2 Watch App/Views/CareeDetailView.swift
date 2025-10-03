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
                            // Recent activities section
                            recentActivitiesSection(for: caree)
                        } else {
                            gettingStartedView
                        }
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
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                Text(NSLocalizedString("Track", comment: "Track activity button"))
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .foregroundColor(.white)
            .background(Color.green.opacity(0.8))
            .cornerRadius(12)
        }
        .disabled(caree.activityTypes?.isEmpty ?? true)
    }

    private var gettingStartedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb.circle")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text(NSLocalizedString("Getting Started", comment: "Getting started title"))
                .font(.headline)

            Text(NSLocalizedString("Activity types must be created on iPhone before you can track activities on Apple Watch.", comment: "Getting started message"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func recentActivitiesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Recent Activities", comment: "Recent activities section title"))
                .font(.headline)

            if caree.recentActivities.isEmpty {
                Text(NSLocalizedString("No activities yet", comment: "Empty activities message"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(caree.recentActivities.prefix(3))) { activity in
                    NavigationLink(destination: ActivityDetailView(activityID: activity.id)) {
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
                    .buttonStyle(.plain)
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
