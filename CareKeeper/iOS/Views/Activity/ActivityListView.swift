import Combine
import os
import SwiftUI

struct ActivityListView: View {
    let careeID: UUID
    private let logger = AppLogger.ui

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService
    @EnvironmentObject private var pendingActivityBuffer: PendingActivityBuffer

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Reactive state - updated when cache changes
    @State private var caree: Caree?
    @State private var activityIDs: [UUID] = []
    @State private var loadedActivityIDSet: Set<UUID> = []
    @State private var lastCursorDate: Date?
    @State private var hasMorePages = true
    @State private var isLoadingPage = false
    @State private var hasLoadedInitialPage = false

    @State private var selectedActivityType: ActivityType?
    @State private var showingFilterMenu = false
    @State private var error: Error?
    @State private var activityToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false

    private let pageSize = 50

    init(careeID: UUID) {
        self.careeID = careeID
    }

    // Resolve Activity objects from caree.activities (populated by LocalCacheService).
    // Order is preserved by using activityIDs as the source of truth.
    private var activities: [Activity] {
        guard !activityIDs.isEmpty, let caree else { return [] }
        let idSet = Set(activityIDs)
        let idToActivity = Dictionary(
            uniqueKeysWithValues: (caree.activities ?? []).compactMap { a -> (UUID, Activity)? in
                guard idSet.contains(a.id) else { return nil }
                return (a.id, a)
            }
        )
        return activityIDs.compactMap { idToActivity[$0] }
    }

    // Helper publishers to observe cache changes
    private var myCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService {
            cacheService.$myCarees.eraseToAnyPublisher()
        } else {
            Just([]).eraseToAnyPublisher()
        }
    }

    private var sharedCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService {
            cacheService.$sharedCarees.eraseToAnyPublisher()
        } else {
            Just([]).eraseToAnyPublisher()
        }
    }

    var body: some View {
        Group {
            if let caree {
                List {
                    if filteredActivities(for: caree).isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredActivities(for: caree)) { activity in
                            ActivityRowView(activity: activity)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            activityToDelete = offsets
                            showingDeleteConfirmation = true
                        }

                        if hasMorePages {
                            loadMoreRow
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle(NSLocalizedString("Activities", comment: "Activities list title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                selectedActivityType = nil
                            } label: {
                                Label(
                                    NSLocalizedString("All Types", comment: "All activity types filter"),
                                    systemImage: selectedActivityType == nil ? "checkmark" : ""
                                )
                            }

                            Divider()

                            ForEach(caree.sortedActivityTypes) { activityType in
                                Button {
                                    selectedActivityType = activityType
                                } label: {
                                    Label {
                                        Text("\(activityType.displayIcon) \(activityType.name)")
                                    } icon: {
                                        if selectedActivityType?.id == activityType.id {
                                            Image(systemName: "checkmark")
                                        } else {
                                            // Empty space to maintain alignment
                                            Image(systemName: "checkmark")
                                                .hidden()
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(
                                NSLocalizedString("Filter", comment: "Filter button"),
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        }
                    }
                }
                .refreshable {
                    await refreshData()
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .errorAlert($error)
        .confirmationDialog(
            NSLocalizedString("Delete Activity?", comment: "Delete activity confirmation title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                if let offsets = activityToDelete, let caree {
                    deleteActivities(at: offsets, from: caree)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                activityToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("This cannot be undone.", comment: "Delete confirmation message"))
        }
        .task {
            await refreshData()
        }
        .onReceive(cloudKitService.$cacheService.compactMap(\.self)) { _ in
            logger.info("📋 [LIST] onReceive cacheService published → refreshData()")
            Task {
                await refreshData()
            }
        }
        .onReceive(myCareesPublisher) { _ in
            logger.info("📋 [LIST] onReceive myCarees changed → updateActivities()")
            updateActivities()
        }
        .onReceive(sharedCareesPublisher) { _ in
            logger.info("📋 [LIST] onReceive sharedCarees changed → updateActivities()")
            updateActivities()
        }
        .onReceive(sharedRecordsService.$sharedCarees.eraseToAnyPublisher()) { _ in
            logger.info("📋 [LIST] onReceive sharedRecordsService.sharedCarees → updateActivities()")
            updateActivities()
        }
        .onReceive(cacheService?.$cacheRevision.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            logger.info("📋 [LIST] onReceive cacheRevision → refreshCareeReference()")
            Task {
                await refreshCareeReference()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SharedCareeDataUpdated"))) { notification in
            if let updatedCareeID = notification.object as? UUID, updatedCareeID == careeID {
                updateActivities()
            }
        }
        .onChange(of: selectedActivityType) { _, _ in
            Task {
                await loadInitialPage()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(selectedActivityType == nil
                ? NSLocalizedString("No activities yet", comment: "Empty activities message")
                : NSLocalizedString("No activities for this type", comment: "Empty filtered activities message"))
                .font(.headline)
                .foregroundColor(.secondary)

            if selectedActivityType != nil {
                Button(NSLocalizedString("Show All", comment: "Show all activities button")) {
                    selectedActivityType = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @MainActor
    private func updateActivities() {
        guard let cacheService else {
            logger.info("📋 [LIST] updateActivities: no cacheService — clearing state")
            caree = nil
            activityIDs = []
            loadedActivityIDSet = []
            hasLoadedInitialPage = false
            return
        }

        // Find the specific caree from cache (owned or shared)
        let foundCaree = cacheService.getCachedCaree(id: careeID)

        let careeChanged = caree?.id != foundCaree?.id
        caree = foundCaree

        if caree == nil {
            logger.info("📋 [LIST] updateActivities: caree \(careeID) not found in cache — clearing state")
            activityIDs = []
            loadedActivityIDSet = []
            hasLoadedInitialPage = false
            return
        }

        let cacheActivityCount = (foundCaree?.activities ?? []).count
        logger.info("📋 [LIST] updateActivities: caree has \(cacheActivityCount, privacy: .public) activities in cache, hasLoadedInitial=\(hasLoadedInitialPage, privacy: .public), careeChanged=\(careeChanged, privacy: .public)")

        // Only load initial page if we haven't loaded yet or caree changed
        if !hasLoadedInitialPage || careeChanged {
            logger.info("📋 [LIST] updateActivities: triggering loadInitialPage (hasLoaded=\(hasLoadedInitialPage, privacy: .public), changed=\(careeChanged, privacy: .public))")
            Task {
                await loadInitialPage()
            }
        }
    }

    private func filteredActivities(for caree: Caree) -> [Activity] {
        let merged = mergeActivities(base: activities, pending: pendingActivityBuffer.pendingActivities(for: caree.id))

        if let selectedType = selectedActivityType {
            return merged.filter { $0.activityType?.id == selectedType.id }
        }

        return merged
    }

    private func mergeActivities(base: [Activity], pending: [Activity]) -> [Activity] {
        guard !pending.isEmpty else { return base }

        var seen = Set(base.map(\.id))
        var merged = base
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

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if isLoadingPage {
                ProgressView()
            } else {
                Button(NSLocalizedString("Load more", comment: "Load more activities")) {
                    Task { await loadNextPage() }
                }
            }
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private func deleteActivities(at offsets: IndexSet, from caree: Caree) {
        let activities = filteredActivities(for: caree)

        Task {
            do {
                for index in offsets {
                    let activity = activities[index]
                    // Pure CloudKit: Delete via unified API (routes internally based on caree.isShared)
                    try await cloudKitService.deleteActivity(activity: activity, caree: caree)
                }

                // Cache is automatically updated by CloudKitDataService
                activityToDelete = nil
            } catch {
                await MainActor.run {
                    self.error = AppError.deleteFailed(error.localizedDescription)
                }
            }
        }
    }

    @Sendable
    private func refreshData() async {
        if let cacheService {
            try? await cacheService.refreshCache()
        }

        let needsSharedFetch = await MainActor.run { () -> Bool in
            guard let cacheService else { return true }
            guard let targetCaree = cacheService.getCachedCaree(id: careeID) else { return true }
            return targetCaree.isShared
        }

        if needsSharedFetch {
            await sharedRecordsService.fetchSharedCarees()
        }

        // Reset pagination to reload fresh data
        await MainActor.run {
            hasLoadedInitialPage = false
            updateActivities()
        }
    }

    @MainActor
    private func loadInitialPage() async {
        guard let cacheService else {
            logger.info("📋 [LIST] loadInitialPage: no cacheService — clearing")
            caree = nil
            activityIDs = []
            loadedActivityIDSet = []
            hasLoadedInitialPage = false
            return
        }

        caree = cacheService.getCachedCaree(id: careeID)
        let cacheCount = (caree?.activities ?? []).count
        logger.info("📋 [LIST] loadInitialPage: RESETTING pagination (cache has \(cacheCount, privacy: .public) activities)")
        activityIDs = []
        loadedActivityIDSet = []
        lastCursorDate = nil
        hasMorePages = true
        await loadNextPage()
        hasLoadedInitialPage = true
        logger.info("📋 [LIST] loadInitialPage: done — showing \(activityIDs.count, privacy: .public) activities")
    }

    /// Incrementally update the loaded activity set when the cache changes,
    /// without resetting pagination. New activities are prepended; removed
    /// activities are pruned from the loaded set.
    @MainActor
    private func refreshCareeReference() async {
        guard let cacheService else { return }
        caree = cacheService.getCachedCaree(id: careeID)
        guard let caree, hasLoadedInitialPage else {
            logger.info("📋 [LIST] refreshCareeReference: skipping (caree=\(self.caree != nil, privacy: .public), hasLoadedInitial=\(hasLoadedInitialPage, privacy: .public))")
            return
        }

        let allIDs = Set((caree.activities ?? []).map(\.id))
        logger.info("📋 [LIST] refreshCareeReference: cache has \(allIDs.count, privacy: .public) activities, loaded set has \(loadedActivityIDSet.count, privacy: .public), displayed \(activityIDs.count, privacy: .public)")

        // Prepend genuinely new activities (from sync/creation)
        let newIDs = allIDs.subtracting(loadedActivityIDSet)
        if !newIDs.isEmpty {
            let newActivities = (caree.activities ?? [])
                .filter { newIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    if lhs.dateTime != rhs.dateTime { return lhs.dateTime > rhs.dateTime }
                    return lhs.id.uuidString > rhs.id.uuidString
                }
            activityIDs = newActivities.map(\.id) + activityIDs
            loadedActivityIDSet.formUnion(newIDs)
            logger.info("📋 [LIST] refreshCareeReference: prepended \(newIDs.count, privacy: .public) new activities")
        }

        // Remove deleted activities
        let removedIDs = loadedActivityIDSet.subtracting(allIDs)
        if !removedIDs.isEmpty {
            activityIDs.removeAll { removedIDs.contains($0) }
            loadedActivityIDSet.subtract(removedIDs)
            logger.info("📋 [LIST] refreshCareeReference: removed \(removedIDs.count, privacy: .public) deleted activities")
        }

        hasMorePages = loadedActivityIDSet.count < allIDs.count

        if newIDs.isEmpty && removedIDs.isEmpty {
            logger.info("📋 [LIST] refreshCareeReference: no changes to activity set")
        }

        // Log pending buffer state for correlation
        let pendingCount = pendingActivityBuffer.pendingActivities(for: careeID).count
        if pendingCount > 0 {
            logger.info("📋 [LIST] refreshCareeReference: \(pendingCount, privacy: .public) activities still in pending buffer (shown via mergeActivities)")
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoadingPage, hasMorePages, let caree else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let selectedTypeID = selectedActivityType?.id
        let cursorDate = lastCursorDate

        // Filter first, then sort only the candidates — reduces sort input size
        let allActivities = caree.activities ?? []
        let typeFiltered: [Activity] = if let typeID = selectedTypeID {
            allActivities.filter { $0.activityType?.id == typeID }
        } else { allActivities }
        let cursorFiltered: [Activity] = if let cursorDate {
            typeFiltered.filter { $0.dateTime <= cursorDate }
        } else { typeFiltered }
        let sorted = cursorFiltered.sorted { lhs, rhs in
            if lhs.dateTime != rhs.dateTime { return lhs.dateTime > rhs.dateTime }
            return lhs.id.uuidString > rhs.id.uuidString
        }

        // Filter out already loaded activities and take pageSize new ones
        var newIDs: [UUID] = []
        for activity in sorted {
            if !loadedActivityIDSet.contains(activity.id) {
                newIDs.append(activity.id)
                loadedActivityIDSet.insert(activity.id)
                if newIDs.count >= pageSize {
                    break
                }
            }
        }

        activityIDs.append(contentsOf: newIDs)

        // Update cursor to last loaded activity
        if let lastID = newIDs.last,
           let lastActivity = sorted.first(where: { $0.id == lastID })
        {
            lastCursorDate = lastActivity.dateTime
        }

        if newIDs.count < pageSize {
            hasMorePages = false
        }
    }
}

#Preview {
    NavigationStack {
        ActivityListView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
