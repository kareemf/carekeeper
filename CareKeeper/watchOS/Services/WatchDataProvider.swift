import Foundation
import SwiftUI
import CloudKit
import os.log
import os.signpost

/// Watch-optimized data provider using selective CloudKit queries
/// Key features:
/// - Lazy loading (activity types/activities loaded on-demand)
/// - Memory management (cache clearing for unused data)
/// - Immutable snapshots (no SwiftData relationships)
/// - Error resilience (show stale data on failure)
@MainActor
class WatchDataProvider: ObservableObject {

    // MARK: - Published State

    @Published var carees: [CareeSnapshot] = []
    @Published var isLoadingCarees = false
    @Published var isRefreshingCarees = false
    @Published var careesError: Error?

    // Activity types loaded on-demand per caree (not upfront!)
    @Published var activityTypesByCaree: [UUID: [ActivityTypeSnapshot]] = [:]
    @Published private(set) var refreshingActivityTypeCareeIDs: Set<UUID> = []

    // Activities loaded on-demand (recent only!)
    @Published var recentActivitiesByCaree: [UUID: [ActivitySnapshot]] = [:]
    @Published private(set) var refreshingRecentActivityCareeIDs: Set<UUID> = []

    // Pending activities (for optimistic UI)
    @Published var pendingActivities: [ActivitySnapshot] = []

    // MARK: - Private Properties

    private let selectiveService = SelectiveCloudKitService()
    private let cacheService: WatchCacheService
    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "watch-data")
    private let signposter = OSSignposter(logger: Logger(subsystem: "com.kareemf.CareKeeper", category: "watch-data-signpost"))
    private let activitiesChunkSize = 20
    private let careeRefreshThrottleInterval: TimeInterval = 60

    // Task management for cancellation
    private var loadCareesTask: Task<Void, Never>?
    private var loadActivityTypesTask: Task<Void, Never>?
    private var loadActivitiesTask: Task<Void, Never>?

    private var refreshedActivityTypesCareeIDs: Set<UUID> = []
    private var refreshedRecentActivitiesCareeIDs: Set<UUID> = []
    private var lastCareesRefreshDate: Date?

    // MARK: - Init

    init(cacheService: WatchCacheService? = nil) {
        let resolvedCache = cacheService ?? WatchCacheService()
        self.cacheService = resolvedCache

        guard resolvedCache.isAppGroupAvailable else {
            logger.warning("⚠️ Watch cache disabled: app group container unavailable.")
            return
        }

        let cachedCarees = resolvedCache.loadCarees()
        self.carees = cachedCarees

        // Preload cached per-caree data when available
        for caree in cachedCarees {
            let cachedActivityTypes = resolvedCache.loadActivityTypes(for: caree.id)
            if !cachedActivityTypes.isEmpty {
                activityTypesByCaree[caree.id] = cachedActivityTypes
            }

            let cachedActivities = resolvedCache.loadRecentActivities(for: caree.id)
            if !cachedActivities.isEmpty {
                recentActivitiesByCaree[caree.id] = cachedActivities
            }
        }
    }

    // MARK: - Refresh State Queries

    func isRefreshingActivityTypes(for careeID: UUID) -> Bool {
        refreshingActivityTypeCareeIDs.contains(careeID)
    }

    func isRefreshingRecentActivities(for careeID: UUID) -> Bool {
        refreshingRecentActivityCareeIDs.contains(careeID)
    }

    // MARK: - Caree Loading (Eager - Small Dataset)

    /// Load all carees (owned + shared)
    /// This is the only eager load - carees are small and needed upfront
    /// Always refreshes to ensure deleted carees are removed
    func loadCarees(force: Bool = false) async {
        // Cancel any existing task
        loadCareesTask?.cancel()

        if !force,
           !carees.isEmpty,
           let lastRefresh = lastCareesRefreshDate,
           Date().timeIntervalSince(lastRefresh) < careeRefreshThrottleInterval {
            logger.info("⏭️ Throttling loadCarees - refreshed recently")
            return
        }

        loadCareesTask = Task {
            guard !Task.isCancelled else { return }
            let signpostID = signposter.makeSignpostID()
            let interval = signposter.beginInterval("loadCarees", id: signpostID)

            // Skip if already loading, unless force refresh
            if isRefreshingCarees && !force {
                logger.info("⏭️ Skipping loadCarees - already loading")
                signposter.endInterval("loadCarees", interval)
                return
            }

            isRefreshingCarees = true
            if carees.isEmpty {
                isLoadingCarees = true
            }
            careesError = nil
            logger.info("📱 WatchDataProvider: Loading carees...")
            defer {
                isLoadingCarees = false
                isRefreshingCarees = false
                signposter.endInterval("loadCarees", interval)
            }

            do {
                signposter.emitEvent("loadCarees.fetch-start", id: signpostID)
                let loadedCarees = try await Task.detached(priority: .utility) { [selectiveService, force] () -> [CareeSnapshot] in
                    var results = try await selectiveService.fetchAllCarees(includeImages: force)
                    for index in results.indices {
                        try Task.checkCancellation()
                        let caree = results[index]
                        let count = try await selectiveService.fetchActivityTypeCount(
                            for: caree.id,
                            isShared: caree.isShared
                        )
                        results[index].activityTypeCount = count
                    }
                    return results
                }.value
                signposter.emitEvent("loadCarees.fetch-end", id: signpostID)

                guard !Task.isCancelled else { return }

                var mergedCarees = mergeCareesWithCachedImages(loadedCarees, allowCacheFallback: !force)

                if force || mergedCarees.contains(where: { $0.imageData == nil }) {
                    await fetchMissingCareeImages(into: &mergedCarees, forceRefresh: force)
                }

                carees = mergedCarees
                if cacheService.isAppGroupAvailable {
                    cacheService.saveCarees(mergedCarees)
                } else {
                    logger.warning("⚠️ Skipping caree cache save: app group unavailable.")
                }
                lastCareesRefreshDate = Date()
                logger.info("✅ Loaded \(self.carees.count) carees")

            } catch is CancellationError {
                logger.info("⏹️ loadCarees cancelled")
                signposter.emitEvent("loadCarees.cancelled", id: signpostID)
            } catch {
                careesError = error
                logger.error("❌ Failed to load carees: \(error.localizedDescription)")
                FileLogger.shared.exception(error, context: "WatchDataProvider.loadCarees() - Failed to load carees from CloudKit")
                signposter.emitEvent("loadCarees.error", id: signpostID)
            }
        }
    }

    // MARK: - Lazy Loading (On-Demand)

    /// Load activity types ONLY when user opens caree detail
    /// - Parameter careeID: ID of the caree
    func loadActivityTypes(for careeID: UUID, force: Bool = false) async {
        if cacheService.isAppGroupAvailable, activityTypesByCaree[careeID] == nil {
            let cachedTypes = cacheService.loadActivityTypes(for: careeID)
            if !cachedTypes.isEmpty {
                activityTypesByCaree[careeID] = cachedTypes
            }
        }

        if refreshedActivityTypesCareeIDs.contains(careeID) && !force {
            logger.info("⏭️ Skipping activity type refresh for caree \(careeID) - already refreshed")
            return
        }

        guard let caree = carees.first(where: { $0.id == careeID }) else {
            logger.warning("Caree not found: \(careeID)")
            return
        }

        // Cancel any existing task
        loadActivityTypesTask?.cancel()

        loadActivityTypesTask = Task {
            guard !Task.isCancelled else { return }
            let signpostID = signposter.makeSignpostID()
            let interval = signposter.beginInterval("loadActivityTypes", id: signpostID)

            logger.info("📱 Lazy loading activity types for caree: \(caree.name)")
            refreshingActivityTypeCareeIDs.insert(careeID)
            defer {
                refreshingActivityTypeCareeIDs.remove(careeID)
                signposter.endInterval("loadActivityTypes", interval)
            }

            do {
                signposter.emitEvent("loadActivityTypes.fetch-start", id: signpostID)
                let types = try await selectiveService.fetchActivityTypes(
                    for: careeID,
                    isShared: caree.isShared
                )
                signposter.emitEvent("loadActivityTypes.fetch-end", id: signpostID)

                guard !Task.isCancelled else { return }

                activityTypesByCaree[careeID] = types
                if cacheService.isAppGroupAvailable {
                    cacheService.saveActivityTypes(types, for: careeID)
                } else {
                    logger.warning("⚠️ Skipping activity type cache save for \(careeID): app group unavailable.")
                }
                refreshedActivityTypesCareeIDs.insert(careeID)
                logger.info("✅ Loaded \(types.count) activity types")

            } catch {
                logger.error("❌ Failed to load activity types: \(error.localizedDescription)")
                FileLogger.shared.exception(error, context: "WatchDataProvider.loadActivityTypes() - Failed to load activity types for caree \(careeID)")
                // Preserve cached values when available
                if activityTypesByCaree[careeID] == nil {
                    activityTypesByCaree[careeID] = []
                }
                signposter.emitEvent("loadActivityTypes.error", id: signpostID)
            }
        }

        await loadActivityTypesTask?.value
    }

    /// Load recent activities ONLY when user opens activity list
    /// - Parameters:
    ///   - careeID: ID of the caree
    ///   - hoursBack: How many hours of history (default 24)
    func loadRecentActivities(for careeID: UUID, hoursBack: TimeInterval = 24 * 3600, force: Bool = false) async {
        if cacheService.isAppGroupAvailable, recentActivitiesByCaree[careeID] == nil {
            let cachedActivities = cacheService.loadRecentActivities(for: careeID)
            if !cachedActivities.isEmpty {
                recentActivitiesByCaree[careeID] = mergedActivities(for: careeID, with: cachedActivities)
            }
        }

        if refreshedRecentActivitiesCareeIDs.contains(careeID) && !force {
            logger.info("⏭️ Skipping recent activities refresh for caree \(careeID) - already refreshed")
            return
        }

        guard let caree = carees.first(where: { $0.id == careeID }) else {
            logger.warning("Caree not found: \(careeID)")
            return
        }

        // Cancel any existing task
        loadActivitiesTask?.cancel()

        loadActivitiesTask = Task {
            guard !Task.isCancelled else { return }
            let signpostID = signposter.makeSignpostID()
            let interval = signposter.beginInterval("loadRecentActivities", id: signpostID)

            logger.info("📱 Lazy loading recent activities for caree: \(caree.name)")
            MemoryMonitor.logMemoryUsage(context: "Before loadRecentActivities")
            refreshingRecentActivityCareeIDs.insert(careeID)
            defer {
                refreshingRecentActivityCareeIDs.remove(careeID)
                signposter.endInterval("loadRecentActivities", interval)
            }

            do {
                signposter.emitEvent("loadRecent.fetch-start", id: signpostID)
                let activities = try await Task.detached(priority: .utility) { [selectiveService] () -> [ActivitySnapshot] in
                    try await selectiveService.fetchRecentActivities(
                        for: careeID,
                        isShared: caree.isShared,
                        hoursBack: hoursBack
                    )
                }.value
                signposter.emitEvent("loadRecent.fetch-end", id: signpostID)

                guard !Task.isCancelled else { return }

                let pendingForCaree = pendingActivities.filter { $0.careeID == careeID }
                let mergedActivities = await Task.detached(priority: .utility) {
                    mergeActivitiesForCaching(pending: pendingForCaree, fetched: activities)
                }.value
                signposter.emitEvent("loadRecent.merge", id: signpostID)

                try Task.checkCancellation()

                await applyRecentActivities(mergedActivities, to: careeID)
                signposter.emitEvent("loadRecent.apply", id: signpostID)

                if cacheService.isAppGroupAvailable {
                    cacheService.saveRecentActivities(mergedActivities, for: careeID)
                } else {
                    logger.warning("⚠️ Skipping recent activity cache save for \(careeID): app group unavailable.")
                }
                refreshedRecentActivitiesCareeIDs.insert(careeID)
                logger.info("✅ Loaded \(activities.count) activities (+ \(self.pendingActivities.count) pending)")
                MemoryMonitor.logMemoryUsage(context: "After loadRecentActivities")

            } catch is CancellationError {
                logger.info("⏹️ loadRecentActivities cancelled for caree \(careeID)")
                signposter.emitEvent("loadRecent.cancelled", id: signpostID)
            } catch {
                logger.error("❌ Failed to load activities: \(error.localizedDescription)")
                FileLogger.shared.exception(error, context: "WatchDataProvider.loadRecentActivities() - Failed to load activities for caree \(careeID)")
                // Keep existing data if available
                signposter.emitEvent("loadRecent.error", id: signpostID)
            }
        }

        await loadActivitiesTask?.value
    }

    // MARK: - Activity Management (Optimistic UI)

    /// Track a new activity with optimistic UI
    /// Shows immediately, syncs in background
    /// - Parameter activity: Activity snapshot to create
    func trackActivity(_ activity: ActivitySnapshot) async {
        guard let caree = carees.first(where: { $0.id == activity.careeID }) else {
            logger.error("Cannot track activity: caree not found")
            return
        }

        logger.info("📱 Tracking activity (optimistic)")

        // 1. Show immediately in UI with pending state
        var pendingActivity = activity
        pendingActivity.syncState = .pending
        pendingActivities.append(pendingActivity)

        // Update recent activities if loaded
        if var existing = recentActivitiesByCaree[activity.careeID] {
            existing.insert(pendingActivity, at: 0)
            recentActivitiesByCaree[activity.careeID] = existing
        }

        // 2. Upload to CloudKit (async)
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                // Update state to syncing
                await self.updateActivityState(activity.id, state: .syncing)

                // Create in CloudKit
                _ = try await self.selectiveService.createActivity(
                    activity,
                    isShared: caree.isShared
                )

                // Update state to synced
                await self.updateActivityState(activity.id, state: .synced)
                await self.removePendingActivity(activity.id)
                await MainActor.run {
                    if self.cacheService.isAppGroupAvailable, let updated = self.recentActivitiesByCaree[activity.careeID] {
                        self.cacheService.saveRecentActivities(updated, for: activity.careeID)
                    } else if !self.cacheService.isAppGroupAvailable {
                        self.logger.warning("⚠️ Skipping recent activity cache save after create for \(activity.careeID): app group unavailable.")
                    }
                }

                self.logger.info("✅ Activity synced successfully")

            } catch {
                // Update state to failed
                await self.updateActivityState(activity.id, state: .failed(error.localizedDescription))
                self.logger.error("❌ Failed to sync activity: \(error.localizedDescription)")
                await MainActor.run {
                    FileLogger.shared.exception(error, context: "WatchDataProvider.trackActivity() - Failed to sync activity to CloudKit")
                }
            }
        }
    }

    /// Update an existing activity with optimistic UI
    /// Updates locally immediately, syncs in background
    /// - Parameter activity: Activity snapshot with updated values
    func updateActivity(_ activity: ActivitySnapshot) async {
        guard let caree = carees.first(where: { $0.id == activity.careeID }) else {
            logger.error("Cannot update activity: caree not found")
            return
        }

        logger.info("📱 Updating activity (optimistic)")

        // 1. Update immediately in UI
        updateActivityState(activity.id, state: .syncing)
        updateActivityData(activity)

        // 2. Upload to CloudKit (async)
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                // Update state to syncing
                await self.updateActivityState(activity.id, state: .syncing)

                // Update in CloudKit
                _ = try await self.selectiveService.updateActivity(
                    activity,
                    isShared: caree.isShared
                )

                // Update state to synced
                await self.updateActivityState(activity.id, state: .synced)
                await MainActor.run {
                    if self.cacheService.isAppGroupAvailable, let updated = self.recentActivitiesByCaree[activity.careeID] {
                        self.cacheService.saveRecentActivities(updated, for: activity.careeID)
                    } else if !self.cacheService.isAppGroupAvailable {
                        self.logger.warning("⚠️ Skipping recent activity cache save after update for \(activity.careeID): app group unavailable.")
                    }
                }

                self.logger.info("✅ Activity updated successfully")

            } catch {
                // Update state to failed
                await self.updateActivityState(activity.id, state: .failed(error.localizedDescription))
                self.logger.error("❌ Failed to update activity: \(error.localizedDescription)")
                await MainActor.run {
                    FileLogger.shared.exception(error, context: "WatchDataProvider.updateActivity() - Failed to update activity in CloudKit")
                }
            }
        }
    }

    /// Delete an existing activity with optimistic UI
    /// Removes from UI immediately, deletes from CloudKit in background
    /// - Parameter activity: Activity snapshot to delete
    func deleteActivity(_ activity: ActivitySnapshot) async {
        guard let caree = carees.first(where: { $0.id == activity.careeID }) else {
            logger.error("Cannot delete activity: caree not found")
            return
        }

        logger.info("📱 Deleting activity (optimistic)")

        // 1. Remove immediately from UI
        removeActivityFromUI(activity.id)

        // 2. Delete from CloudKit (async)
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                // Delete from CloudKit
                try await self.selectiveService.deleteActivity(
                    activity,
                    isShared: caree.isShared
                )

                await MainActor.run {
                    if self.cacheService.isAppGroupAvailable {
                        if let updated = self.recentActivitiesByCaree[activity.careeID] {
                            self.cacheService.saveRecentActivities(updated, for: activity.careeID)
                        } else {
                            self.cacheService.saveRecentActivities([], for: activity.careeID)
                        }
                    } else {
                        self.logger.warning("⚠️ Skipping recent activity cache save after delete for \(activity.careeID): app group unavailable.")
                    }
                }

                self.logger.info("✅ Activity deleted successfully")

            } catch {
                // Restore activity on failure
                await self.restoreActivityToUI(activity)
                self.logger.error("❌ Failed to delete activity: \(error.localizedDescription)")
                await MainActor.run {
                    FileLogger.shared.exception(error, context: "WatchDataProvider.deleteActivity() - Failed to delete activity from CloudKit")
                }
            }
        }
    }

    private func updateActivityData(_ activity: ActivitySnapshot) {
        // Update in recent activities
        if var existing = recentActivitiesByCaree[activity.careeID],
           let index = existing.firstIndex(where: { $0.id == activity.id }) {
            existing[index] = activity
            recentActivitiesByCaree[activity.careeID] = existing
        }
    }

    private func removeActivityFromUI(_ activityID: UUID) {
        // Remove from pending list
        pendingActivities.removeAll { $0.id == activityID }

        // Remove from recent activities
        for (careeID, activities) in recentActivitiesByCaree {
            if let index = activities.firstIndex(where: { $0.id == activityID }) {
                var updated = activities
                updated.remove(at: index)
                recentActivitiesByCaree[careeID] = updated
            }
        }
    }

    private func restoreActivityToUI(_ activity: ActivitySnapshot) {
        // Add back to recent activities
        if var existing = recentActivitiesByCaree[activity.careeID] {
            existing.append(activity)
            existing.sort { $0.dateTime > $1.dateTime }
            recentActivitiesByCaree[activity.careeID] = existing
        }
    }

    private func updateActivityState(_ activityID: UUID, state: ActivitySnapshot.SyncState) {
        // Update in pending list
        if let index = pendingActivities.firstIndex(where: { $0.id == activityID }) {
            pendingActivities[index].syncState = state
        }

        // Update in recent activities
        for (careeID, activities) in recentActivitiesByCaree {
            if let index = activities.firstIndex(where: { $0.id == activityID }) {
                var updated = activities
                updated[index].syncState = state
                recentActivitiesByCaree[careeID] = updated
            }
        }
    }

    private func removePendingActivity(_ activityID: UUID) {
        pendingActivities.removeAll { $0.id == activityID }
    }

    private func applyRecentActivities(_ activities: [ActivitySnapshot], to careeID: UUID) async {
        guard activitiesChunkSize > 0 else {
            recentActivitiesByCaree[careeID] = activities
            return
        }

        var rolling: [ActivitySnapshot] = []
        rolling.reserveCapacity(activities.count)

        for activity in activities {
            rolling.append(activity)
            if rolling.count % activitiesChunkSize == 0 {
                recentActivitiesByCaree[careeID] = rolling
                signposter.emitEvent("loadRecent.chunk")
                await Task.yield()
            }
        }

        if rolling.count % activitiesChunkSize != 0 {
            recentActivitiesByCaree[careeID] = rolling
            signposter.emitEvent("loadRecent.chunk-final")
        }
    }

    private func mergedActivities(for careeID: UUID, with activities: [ActivitySnapshot]) -> [ActivitySnapshot] {
        let pendingForCaree = pendingActivities.filter { $0.careeID == careeID }
        return mergeActivitiesForCaching(pending: pendingForCaree, fetched: activities)
    }

    private func mergeCareesWithCachedImages(_ carees: [CareeSnapshot], allowCacheFallback: Bool) -> [CareeSnapshot] {
        guard allowCacheFallback, cacheService.isAppGroupAvailable else { return carees }

        let cachedCarees = cacheService.loadCarees()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedCarees.map { ($0.id, $0) })

        return carees.map { caree in
            guard caree.imageData == nil,
                  let cached = cachedByID[caree.id],
                  let cachedImage = cached.imageData else {
                return caree
            }
            return caree.updating(imageData: cachedImage)
        }
    }

    private func fetchMissingCareeImages(into carees: inout [CareeSnapshot], forceRefresh: Bool) async {
        for index in carees.indices {
            let snapshot = carees[index]
            let needsFetch = forceRefresh || snapshot.imageData == nil
            guard needsFetch else { continue }

            do {
                if let data = try await selectiveService.fetchCareeImage(
                    for: snapshot.id,
                    zoneName: snapshot.zoneName,
                    zoneOwnerName: snapshot.zoneOwnerName,
                    isShared: snapshot.isShared
                ) {
                    carees[index] = snapshot.updating(imageData: data)
                } else if forceRefresh {
                    carees[index] = snapshot.updating(imageData: nil)
                }
            } catch {
                logger.error("❌ Failed to fetch caree image for \(snapshot.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Memory Management

    /// Clear cached data for carees not currently in use
    /// Call this when navigating away from caree detail
    /// - Parameter currentCareeID: ID of the caree currently being viewed (keep its data)
    func clearUnusedCache(except currentCareeID: UUID?) {
        let keysToKeep = currentCareeID.map { Set([$0]) } ?? Set<UUID>()

        let removedActivityTypeIDs = Set(activityTypesByCaree.keys).subtracting(keysToKeep)
        let removedRecentActivityIDs = Set(recentActivitiesByCaree.keys).subtracting(keysToKeep)

        // Clear activity types for carees not in use
        let typesBeforeCount = activityTypesByCaree.count
        activityTypesByCaree = activityTypesByCaree.filter { keysToKeep.contains($0.key) }

        // Clear activities for carees not in use
        let activitiesBeforeCount = recentActivitiesByCaree.count
        recentActivitiesByCaree = recentActivitiesByCaree.filter { keysToKeep.contains($0.key) }

        refreshedActivityTypesCareeIDs.subtract(removedActivityTypeIDs)
        refreshedRecentActivitiesCareeIDs.subtract(removedRecentActivityIDs)
        refreshingActivityTypeCareeIDs.subtract(removedActivityTypeIDs)
        refreshingRecentActivityCareeIDs.subtract(removedRecentActivityIDs)

        let cleared = (typesBeforeCount - activityTypesByCaree.count) + (activitiesBeforeCount - recentActivitiesByCaree.count)

        if cleared > 0 {
            logger.info("🧹 Cleared cache for \(cleared) unused carees (keeping \(keysToKeep.count))")
            MemoryMonitor.logMemoryUsage(context: "After cache clear")
        }
    }

    /// Clear all cached data (called when app goes to background or memory warning)
    func clearAllCache() {
        logger.info("🧹 Clearing all cached data")

        activityTypesByCaree.removeAll()
        recentActivitiesByCaree.removeAll()
        refreshedActivityTypesCareeIDs.removeAll()
        refreshedRecentActivitiesCareeIDs.removeAll()
        refreshingActivityTypeCareeIDs.removeAll()
        refreshingRecentActivityCareeIDs.removeAll()

        // Keep carees loaded (small memory footprint)
        logger.info("✅ Cache cleared (kept \(self.carees.count) carees)")
        MemoryMonitor.logMemoryUsage(context: "After full cache clear")
    }

    // MARK: - Task Cancellation

    /// Cancel all running tasks (call on view disappear)
    func cancelAllTasks() {
        loadCareesTask?.cancel()
        loadActivityTypesTask?.cancel()
        loadActivitiesTask?.cancel()

        logger.info("🛑 Cancelled all running tasks")
    }
}

private func mergeActivitiesForCaching(pending: [ActivitySnapshot], fetched: [ActivitySnapshot]) -> [ActivitySnapshot] {
    var combined = pending
    var seen = Set(combined.map { $0.id })

    for activity in fetched where !seen.contains(activity.id) {
        combined.append(activity)
        seen.insert(activity.id)
    }

    combined.sort { $0.dateTime > $1.dateTime }
    return combined
}
