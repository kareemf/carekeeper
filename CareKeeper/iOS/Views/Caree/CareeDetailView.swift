import Combine
import SwiftUI

struct CareeDetailView: View {
    let careeID: UUID

    // Use services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService
    @EnvironmentObject private var pendingActivityBuffer: PendingActivityBuffer

    private let logger = AppLogger.cloudkit

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Keep a resilient, last-known reference to the Caree while refreshes occur
    @State private var resolvedCaree: Caree?

    // Fast accessor to try resolving from cache
    private func resolveCareeFromCache() -> Caree? {
        cacheService?.getCachedCaree(id: careeID)
    }

    // Check if this is one of my owned carees (vs shared)
    private var isMyCaree: Bool {
        (resolvedCaree?.isOwned) ?? true
    }

    @State private var showingEditCaree = false
    @State private var showingAddActivityType = false
    @State private var showingTrackActivity = false
    @State private var reorderTask: Task<Void, Never>?
    @State private var activityTypeToDelete: ActivityType?
    @State private var showingDeleteActivityTypeConfirmation = false
    @State private var activityToDelete: Activity?
    @State private var showingDeleteActivityConfirmation = false
    @State private var isSyncedToCloudKit: Bool? = nil
    @State private var isCheckingSync = false
    @State private var activityCount: Int?
    @State private var activityTypeCount: Int?
    @State private var exportItem: ExportItem?
    @State private var error: Error?
    @State private var isLoadingSharedCaree = false

    @StateObject private var syncService = CloudKitSyncService()
    @StateObject private var notificationPrefs = UserNotificationPreferences.shared
    @StateObject private var notificationService = UserNotificationService.shared

    private let exportService = CareeExportService()

    @State private var showingPermissionAlert = false

    init(careeID: UUID) {
        self.careeID = careeID
    }
    
    var body: some View {
        Group {
            if isLoadingSharedCaree {
                // Show loading state while fetching shared caree
                VStack(spacing: 16) {
                    ProgressView()
                    Text(NSLocalizedString("Loading...", comment: "Loading shared caree message"))
                        .foregroundColor(.secondary)
                }
            } else if let caree = resolvedCaree {
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
                            let recentActivities = mergedRecentActivities(for: caree)
                            if recentActivities.isEmpty {
                                emptyActivitiesView
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(Array(recentActivities.prefix(5))) { activity in
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
                        .listRowSeparator(.hidden)
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
                    .listRowSeparator(.hidden)

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
                .refreshable {
                    await refreshCareeData(for: caree)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            #if os(iOS)
                                // Notification toggle button
                                Button {
                                    toggleNotifications(for: caree)
                                } label: {
                                    Image(systemName: notificationPrefs.isEnabled(for: caree.id) ? "bell.fill" : "bell.slash")
                                }

                                CareeShareButton(
                                    caree: caree,
                                    isSynced: isSyncedToCloudKit ?? false,
                                    isMyCaree: isMyCaree
                                )

                                Button {
                                    exportCaree(caree)
                                } label: {
                                    Image(systemName: "square.and.arrow.up.on.square")
                                }
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
                    Text(NSLocalizedString(
                        "This will also delete all associated activities. This cannot be undone.",
                        comment: "Delete activity type confirmation message"
                    ))
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
                #if os(iOS)
                .sheet(item: $exportItem) { item in
                    ShareSheet(items: [item.url])
                }
                .alert(
                    NSLocalizedString("Notification Permission Required", comment: "Permission alert title"),
                    isPresented: $showingPermissionAlert
                ) {
                    Button(NSLocalizedString("Open Settings", comment: "Open settings button")) {
                        notificationService.openSettings()
                    }
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString(
                        "Please enable notifications in Settings to receive activity alerts.",
                        comment: "Permission alert message"
                    ))
                }
                #endif
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .task(id: careeID) {
            // Resolve caree from cache (runs on appear and when careeID changes)
            resolvedCaree = resolveCareeFromCache()
            if let caree = resolvedCaree {
                await loadCounts(for: caree)
            } else {
                activityCount = nil
                activityTypeCount = nil
            }

            // Light-weight cache refresh (debounced/coalesced)
            try? await cacheService?.refreshCache()

            // If this caree is missing or shared, fetch shared carees (service will update cache in batch)
            if resolvedCaree == nil || resolvedCaree?.isShared == true {
                isLoadingSharedCaree = true
                await sharedRecordsService.fetchSharedCarees()
                // Re-resolve after fetch completes
                resolvedCaree = resolveCareeFromCache()
                if let caree = resolvedCaree {
                    await loadCounts(for: caree)
                }
                isLoadingSharedCaree = false
            }

            if let caree = self.resolvedCaree {
                await checkSyncStatus(for: caree)
            }
        }
        .onReceive(cloudKitService.$cacheService.compactMap(\.self)) { _ in
            Task {
                await handleCacheServiceAttachment()
            }
        }
        // Re-resolve after any shared refresh completes (both services post this)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitBackgroundRefreshFinished"))) { _ in
            resolvedCaree = resolveCareeFromCache()
            if let caree = resolvedCaree {
                Task { await loadCounts(for: caree) }
            }
            isLoadingSharedCaree = false
        }
        // Also re-resolve when the in-memory shared list changes
        .onChange(of: sharedRecordsService.sharedCarees) { _, _ in
            resolvedCaree = resolveCareeFromCache()
            if let caree = resolvedCaree {
                Task { await loadCounts(for: caree) }
            }
            isLoadingSharedCaree = false
        }
        // REACTIVE: Re-resolve when cache publishers update (for inline CRUD reactivity)
        .onReceive(cacheService?.$myCarees.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if let current = resolvedCaree, !current.isShared {
                resolvedCaree = resolveCareeFromCache()
                if let caree = resolvedCaree {
                    Task { await loadCounts(for: caree) }
                }
            }
        }
        .onReceive(cacheService?.$sharedCarees.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if let current = resolvedCaree, current.isShared {
                resolvedCaree = resolveCareeFromCache()
                if let caree = resolvedCaree {
                    Task { await loadCounts(for: caree) }
                }
            }
        }
        .onReceive(cacheService?.$cacheRevision.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            resolvedCaree = resolveCareeFromCache()
            if let caree = resolvedCaree {
                Task { await loadCounts(for: caree) }
            }
        }
        // REACTIVE: Listen for shared caree data updates (immediate notification)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SharedCareeDataUpdated"))) { notification in
            // Check if this notification is for our caree
            if let updatedCareeID = notification.object as? UUID, updatedCareeID == careeID {
                resolvedCaree = resolveCareeFromCache()
            }
        }
        .errorAlert($error)
        .onDisappear {
            reorderTask?.cancel()
        }
    }
    
    private func handleCacheServiceAttachment() async {
        resolvedCaree = resolveCareeFromCache()
        if let caree = resolvedCaree {
            await loadCounts(for: caree)
        } else {
            activityCount = nil
            activityTypeCount = nil
        }
        try? await cacheService?.refreshCache()

        if resolvedCaree == nil || resolvedCaree?.isShared == true {
            isLoadingSharedCaree = true
            await sharedRecordsService.fetchSharedCarees()
            resolvedCaree = resolveCareeFromCache()
            if let caree = resolvedCaree {
                await loadCounts(for: caree)
            }
            isLoadingSharedCaree = false
        }

        if let caree = resolvedCaree {
            await checkSyncStatus(for: caree)
        }
    }

    private func deleteActivityType(_ activityType: ActivityType) {
        guard let caree = resolvedCaree else { return }

        Task {
            do {
                // Delete activity type (unified API routes internally)
                try await cloudKitService.deleteActivityType(activityType: activityType, caree: caree)
                // Cache is automatically updated by service with optimistic update

                activityTypeToDelete = nil
            } catch {
                logger.error("❌ Failed to delete activity type: \(error.localizedDescription)")
                self.error = AppError.saveFailed(error.localizedDescription)
            }
        }
    }

    private func deleteActivity(_ activity: Activity) {
        guard let caree = resolvedCaree else { return }

        Task {
            do {
                // Delete activity (unified API routes internally)
                try await cloudKitService.deleteActivity(activity: activity, caree: caree)
                // Cache is automatically updated by service with optimistic update

                activityToDelete = nil
            } catch {
                logger.error("❌ Failed to delete activity: \(error.localizedDescription)")
                self.error = AppError.deleteFailed(error.localizedDescription)
            }
        }
    }

    private func moveActivityTypes(from source: IndexSet, to destination: Int) {
        guard let caree = resolvedCaree else { return }

        var updatedActivityTypes = caree.sortedActivityTypes
        updatedActivityTypes.move(fromOffsets: source, toOffset: destination)

        for (index, activityType) in updatedActivityTypes.enumerated() {
            activityType.listOrder = index
        }

        reorderTask?.cancel()
        reorderTask = Task {
            await persistActivityTypeOrder(
                updates: updatedActivityTypes.map { ($0, $0.listOrder) },
                caree: caree
            )
        }
    }

    private func headerSection(for caree: Caree) -> some View {
        HStack {
            profileImageView(for: caree)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString(
                    "\(activityTypeCount ?? 0) Activity Types",
                    comment: "Activity types count"
                ))
                .font(.subheadline)
                .foregroundColor(.secondary)

                Text(NSLocalizedString(
                    "\(displayActivityCount(for: caree)) Activities",
                    comment: "Total activities count"
                ))
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            #if os(iOS)
                // Indicator on the right:
                if isMyCaree {
                    // Owned: show CloudKit sync status indicator
                    syncStatusIndicator
                } else {
                    // Shared: show shared icon (matches CareeListView behavior)
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(Text(NSLocalizedString("Shared Caree", comment: "Shared caree indicator")))
                }
            #endif
        }
    }

    private func persistActivityTypeOrder(
        updates: [(ActivityType, Int)],
        caree: Caree
    ) async {
        guard !updates.isEmpty else { return }

        do {
            for (activityType, order) in updates {
                if Task.isCancelled { return }
                activityType.listOrder = order
                try await cloudKitService.updateActivityType(
                    activityType,
                    caree: caree,
                    listOrder: order,
                    isShared: activityType.caree?.isShared ?? caree.isShared
                )
            }

            if Task.isCancelled { return }

            if let cache = cloudKitService.cacheService {
                await cache.refreshPublishedProperties()
            }
        } catch {
            await MainActor.run {
                let template = NSLocalizedString(
                    "Failed to update activity type order. %@",
                    comment: "Activity type reorder failure message"
                )
                let message = String(format: template, error.localizedDescription)
                self.error = AppError.saveFailed(message)
            }

            await refreshCareeData(for: caree)
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

                Text(NSLocalizedString(
                    "This list will be populated once you start tracking activities.",
                    comment: "Empty activities description"
                ))
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

            Text(NSLocalizedString(
                "Once you've configured your first activity type, you'll be able to track new activities and view recent ones here.",
                comment: "No activity types guidance"
            ))
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

    private var syncStatusIndicator: some View {
        CloudKitSyncStatusView(
            isChecking: isCheckingSync,
            isSynced: isSyncedToCloudKit,
            size: .medium
        )
    }

    private func checkSyncStatus(for caree: Caree) async {
        logger.info("🔄 Checking sync status for caree: \(caree.name)")
        isCheckingSync = true
        isSyncedToCloudKit = await syncService.isSynced(caree: caree)
        logger.info("🔄 Sync status check complete: \(isSyncedToCloudKit == true ? "✅ Synced" : "❌ Not synced")")
        isCheckingSync = false
    }

    private func refreshCareeData(for caree: Caree) async {
        logger.info("🔄 Pull-to-refresh: Refreshing data for caree: \(caree.name)")

        // If this is a shared caree, fetch shared data from CloudKit (service will update cache)
        if caree.isShared {
            isLoadingSharedCaree = true
            await sharedRecordsService.fetchSharedCarees()
            resolvedCaree = resolveCareeFromCache()
            isLoadingSharedCaree = false
        } else {
            do {
                try await cloudKitService.refreshOwnedCareesFromCloudKit()
                resolvedCaree = resolveCareeFromCache()
            } catch {
                logger.error("❌ Owned caree refresh failed: \(error.localizedDescription)")
                self.error = error
            }
        }

        // Check sync status (only relevant for owned carees; harmless for shared)
        await checkSyncStatus(for: caree)

        logger.info("🔄 Pull-to-refresh complete")
    }

    private func exportCaree(_ caree: Caree) {
        do {
            // Generate JSON data (v2.0 format with full fidelity)
            let jsonData = try exportService.exportCaree(caree)

            // Create temporary file
            let filename = exportService.generateFilename(careeCount: 1)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try jsonData.write(to: tempURL)

            // Set export item to trigger share sheet
            exportItem = ExportItem(url: tempURL, filename: filename)
        } catch {
            self.error = error
        }
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
                } else {
                    showingPermissionAlert = true
                }
            } else if notificationService.authorizationStatus == .authorized {
                // Toggle the preference
                notificationPrefs.toggle(for: caree.id)
            } else {
                // Permission denied - show alert to open settings
                showingPermissionAlert = true
            }
        }
    }

    private func mergedRecentActivities(for caree: Caree) -> [Activity] {
        let pending = pendingActivityBuffer.pendingActivities(for: caree.id)
        guard !pending.isEmpty else { return caree.recentActivities }

        var seen = Set(caree.recentActivities.map(\.id))
        var merged = caree.recentActivities
        for activity in pending where !seen.contains(activity.id) {
            merged.append(activity)
            seen.insert(activity.id)
        }
        merged.sort { lhs, rhs in
            if lhs.dateTime == rhs.dateTime {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.dateTime > rhs.dateTime
        }
        return merged
    }

    private func displayActivityCount(for caree: Caree) -> Int {
        let cachedIDs = Set((caree.activities ?? []).map(\.id))
        let uniquePendingCount = pendingActivityBuffer.pendingActivities(for: caree.id)
            .filter { !cachedIDs.contains($0.id) }
            .count
        return (activityCount ?? 0) + uniquePendingCount
    }

    @MainActor
    private func loadCounts(for caree: Caree) async {
        activityCount = caree.activities?.count ?? 0
        activityTypeCount = caree.activityTypes?.count ?? 0
    }
}

// MARK: - Helper Types

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
}

#Preview {
    NavigationView {
        CareeDetailView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
