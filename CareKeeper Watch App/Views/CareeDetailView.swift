import SwiftUI
import SwiftData

struct CareeDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let careeID: UUID
    @Query private var myCarees: [Caree]  // Only private database records

    // Service for fetching shared records
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()

    // Combined list of all carees (private + shared)
    private var allCarees: [Caree] {
        return myCarees + sharedRecordsService.sharedCarees
    }

    // Computed property to get the specific caree
    private var caree: Caree? {
        allCarees.first { $0.id == careeID }
    }

    @State private var showingTrackActivity = false
    @State private var isLoadingSharedCaree = false

    init(careeID: UUID) {
        self.careeID = careeID
    }

    var body: some View {
        Group {
            if isLoadingSharedCaree {
                // Show loading state while fetching shared caree
                VStack(spacing: 12) {
                    ProgressView()
                    Text(NSLocalizedString("Loading...", comment: "Loading shared caree message"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let caree = caree {
                if !caree.sortedActivityTypes.isEmpty {
                    TabView {
                        // Track tab
                        VStack {
                            Spacer()
                            trackActivityButton(for: caree)
                            Spacer()
                        }
                        .containerBackground(.background, for: .tabView)

                        // Today tab
                        todayActivitiesSection(for: caree)
                            .containerBackground(.background, for: .tabView)
                    }
                    .tabViewStyle(.verticalPage)
                    .navigationTitle(caree.name)
                    .sheet(isPresented: $showingTrackActivity) {
                        TrackActivityView(caree: caree)
                    }
                } else {
                    ScrollView {
                        gettingStartedView
                    }
                    .navigationTitle(caree.name)
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // Only fetch shared carees if this caree is not in myCarees
            let isMyCaree = myCarees.contains(where: { $0.id == careeID })

            if !isMyCaree {
                isLoadingSharedCaree = true
                await sharedRecordsService.fetchSharedCarees()
                isLoadingSharedCaree = false
            }
        }
        .onChange(of: sharedRecordsService.sharedCarees) {
            // Trigger UI update when shared carees change
            isLoadingSharedCaree = false
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
            .padding(.vertical, 24)
            .foregroundColor(.white)
            .background(Color.green.opacity(0.8))
            .cornerRadius(12)
        }
        .padding(.horizontal, 12)
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

    private func todayActivities(for caree: Caree) -> [Activity] {
        let allActivities = caree.activities ?? []
        return allActivities
            .filter { Calendar.current.isDateInToday($0.dateTime) }
            .sorted { $0.dateTime > $1.dateTime }
    }

    private func todayActivitiesSection(for caree: Caree) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Today", comment: "Today's activities section title"))
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            if todayActivities(for: caree).isEmpty {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("No activities recorded today", comment: "Empty today's activities message"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(todayActivities(for: caree)) { activity in
                        NavigationLink(destination: ActivityDetailView(activityID: activity.id)) {
                            activityRow(for: activity)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func activityRow(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activity.activityType?.displayIcon ?? "⭐")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.activityType?.name ?? NSLocalizedString("Unknown", comment: "Unknown activity type"))
                        .font(.headline)

                    Text(activity.formattedDateTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if let formattedQuantity = activity.formattedQuantity {
                Text(formattedQuantity)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = activity.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CareeDetailView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
