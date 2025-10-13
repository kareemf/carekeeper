import SwiftUI
import SwiftData

struct CareeDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let careeID: UUID

    // Pure CloudKit architecture: Cache service as source of truth
    @State private var cacheService: LocalCacheService?
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()

    // Get the specific caree from cache
    private var caree: Caree? {
        cacheService?.getCachedCaree(id: careeID)
    }

    @State private var showingTrackActivity = false
    @State private var isLoadingSharedCaree = false

    @StateObject private var notificationPrefs = UserNotificationPreferences.shared
    @StateObject private var notificationService = UserNotificationService.shared

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
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                toggleNotifications(for: caree)
                            } label: {
                                Image(systemName: notificationPrefs.isEnabled(for: caree.id) ? "bell.fill" : "bell.slash")
                                    .foregroundColor(notificationPrefs.isEnabled(for: caree.id) ? .blue : .gray)
                            }
                        }
                    }
                    .sheet(isPresented: $showingTrackActivity) {
                        TrackActivityView(caree: caree)
                    }
                } else {
                    ScrollView {
                        gettingStartedView
                    }
                    .navigationTitle(caree.name)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                toggleNotifications(for: caree)
                            } label: {
                                Image(systemName: notificationPrefs.isEnabled(for: caree.id) ? "bell.fill" : "bell.slash")
                                    .foregroundColor(notificationPrefs.isEnabled(for: caree.id) ? .blue : .gray)
                            }
                        }
                    }
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // Initialize cache service with model context
            if cacheService == nil {
                cacheService = LocalCacheService(modelContext: modelContext)
                cloudKitService.setCacheService(cacheService!)
            }

            // Refresh cache to load caree
            try? await cacheService?.refreshCache()

            // Only fetch shared carees if this caree is not in cache yet or is shared
            if caree == nil || caree?.isShared == true {
                isLoadingSharedCaree = true
                await sharedRecordsService.fetchSharedCarees()

                // Cache shared carees
                for sharedCaree in sharedRecordsService.sharedCarees {
                    try? await cacheService?.cacheCaree(sharedCaree, isShared: true)
                }

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

    private func toggleNotifications(for caree: Caree) {
        Task {
            // Check current authorization status
            await notificationService.checkAuthorizationStatus()

            if notificationService.authorizationStatus == .notDetermined {
                // Request permission if not yet determined
                let granted = await notificationService.requestPermission()
                if granted {
                    // Enable notifications for this caree
                    notificationPrefs.setEnabled(true, for: caree.id)
                }
            } else if notificationService.authorizationStatus == .authorized {
                // Toggle the preference
                notificationPrefs.toggle(for: caree.id)
            }
            // Note: watchOS doesn't have Settings deep linking like iOS,
            // so we silently fail if permission is denied
        }
    }
}

#Preview {
    NavigationStack {
        CareeDetailView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
