import SwiftUI
import SwiftData
import Combine

struct CareeDetailView: View {
    let careeID: UUID

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Keep a resilient, last-known reference to the Caree while refreshes occur
    @State private var resolvedCaree: Caree?
    // Refresh trigger to force view updates when relationships change
    @State private var refreshID = UUID()

    // Fast accessor to try resolving from cache
    private func resolveCareeFromCache() -> Caree? {
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
            } else if let caree = resolvedCaree {
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
                    .id(refreshID) // Refresh TabView content without re-running .task blocks
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
                // Keep a benign placeholder instead of an empty view to avoid navigation pop
                VStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("Preparing...", comment: "Placeholder while resolving caree"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            // Initial resolve
            resolvedCaree = resolveCareeFromCache()

            // Light-weight cache refresh (debounced/coalesced)
            try? await cacheService?.refreshCache()

            // If this caree is missing or shared, fetch shared carees (service will update cache in batch)
            if resolvedCaree == nil || resolvedCaree?.isShared == true {
                isLoadingSharedCaree = true
                await sharedRecordsService.fetchSharedCarees()
                // Re-resolve after fetch completes
                resolvedCaree = resolveCareeFromCache()
                isLoadingSharedCaree = false
            }
        }
        .task(id: careeID) {
            // Refresh when caree ID changes
            resolvedCaree = resolveCareeFromCache()
            try? await cacheService?.refreshCache()

            if resolvedCaree == nil || resolvedCaree?.isShared == true {
                isLoadingSharedCaree = true
                await sharedRecordsService.fetchSharedCarees()
                resolvedCaree = resolveCareeFromCache()
                isLoadingSharedCaree = false
            }
        }
        // Re-resolve after any shared refresh completes (both services post this)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitBackgroundRefreshFinished"))) { _ in
            resolvedCaree = resolveCareeFromCache()
            isLoadingSharedCaree = false
        }
        // Also re-resolve when the in-memory shared list changes
        .onChange(of: sharedRecordsService.sharedCarees) { _ in
            resolvedCaree = resolveCareeFromCache()
            isLoadingSharedCaree = false
        }
        // REACTIVE: Re-resolve when cache publishers update (for inline CRUD reactivity)
        .onReceive(cacheService?.$myCarees.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if let current = resolvedCaree, !current.isShared {
                resolvedCaree = resolveCareeFromCache()
            }
        }
        .onReceive(cacheService?.$sharedCarees.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if let current = resolvedCaree, current.isShared {
                resolvedCaree = resolveCareeFromCache()
            }
        }
        // REACTIVE: Listen for shared caree data updates (immediate notification)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SharedCareeDataUpdated"))) { notification in
            // Check if this notification is for our caree
            if let updatedCareeID = notification.object as? UUID, updatedCareeID == careeID {
                resolvedCaree = resolveCareeFromCache()
                // Force view refresh to see updated relationships
                refreshID = UUID()
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
