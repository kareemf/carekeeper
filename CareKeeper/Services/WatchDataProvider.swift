import Foundation
import SwiftUI
import os.log

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
    @Published var careesError: Error?

    // Activity types loaded on-demand per caree (not upfront!)
    @Published var activityTypesByCaree: [UUID: [ActivityTypeSnapshot]] = [:]

    // Activities loaded on-demand (recent only!)
    @Published var recentActivitiesByCaree: [UUID: [ActivitySnapshot]] = [:]

    // Pending activities (for optimistic UI)
    @Published var pendingActivities: [ActivitySnapshot] = []

    // MARK: - Private Properties

    private let selectiveService = SelectiveCloudKitService()
    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "watch-data")

    // Task management for cancellation
    private var loadCareesTask: Task<Void, Never>?
    private var loadActivityTypesTask: Task<Void, Never>?
    private var loadActivitiesTask: Task<Void, Never>?

    // MARK: - Caree Loading (Eager - Small Dataset)

    /// Load all carees (owned + shared)
    /// This is the only eager load - carees are small and needed upfront
    func loadCarees() async {
        // Cancel any existing task
        loadCareesTask?.cancel()

        loadCareesTask = Task {
            guard !Task.isCancelled else { return }
            guard !isLoadingCarees else { return }

            isLoadingCarees = true
            careesError = nil
            logger.info("📱 WatchDataProvider: Loading carees...")

            do {
                // Load carees (acceptable - small dataset)
                var loadedCarees = try await selectiveService.fetchAllCarees()

                guard !Task.isCancelled else {
                    isLoadingCarees = false
                    return
                }

                // Load activity type COUNTS (not full objects)
                for index in loadedCarees.indices {
                    guard !Task.isCancelled else {
                        isLoadingCarees = false
                        return
                    }

                    let caree = loadedCarees[index]
                    let count = try await selectiveService.fetchActivityTypeCount(
                        for: caree.id,
                        isShared: caree.isShared
                    )
                    loadedCarees[index].activityTypeCount = count
                }

                guard !Task.isCancelled else {
                    isLoadingCarees = false
                    return
                }

                carees = loadedCarees
                logger.info("✅ Loaded \(carees.count) carees")

            } catch {
                careesError = error
                logger.error("❌ Failed to load carees: \(error.localizedDescription)")
            }

            isLoadingCarees = false
        }

        await loadCareesTask?.value
    }

    // MARK: - Lazy Loading (On-Demand)

    /// Load activity types ONLY when user opens caree detail
    /// - Parameter careeID: ID of the caree
    func loadActivityTypes(for careeID: UUID) async {
        // Skip if already loaded
        guard activityTypesByCaree[careeID] == nil else {
            logger.info("Activity types already loaded for caree: \(careeID)")
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

            logger.info("📱 Lazy loading activity types for caree: \(caree.name)")

            do {
                let types = try await selectiveService.fetchActivityTypes(
                    for: careeID,
                    isShared: caree.isShared
                )

                guard !Task.isCancelled else { return }

                activityTypesByCaree[careeID] = types
                logger.info("✅ Loaded \(types.count) activity types")

            } catch {
                logger.error("❌ Failed to load activity types: \(error.localizedDescription)")
                // Set empty array so we don't retry constantly
                activityTypesByCaree[careeID] = []
            }
        }

        await loadActivityTypesTask?.value
    }

    /// Load recent activities ONLY when user opens activity list
    /// - Parameters:
    ///   - careeID: ID of the caree
    ///   - hoursBack: How many hours of history (default 48)
    func loadRecentActivities(for careeID: UUID, hoursBack: TimeInterval = 48 * 3600) async {
        guard let caree = carees.first(where: { $0.id == careeID }) else {
            logger.warning("Caree not found: \(careeID)")
            return
        }

        // Cancel any existing task
        loadActivitiesTask?.cancel()

        loadActivitiesTask = Task {
            guard !Task.isCancelled else { return }

            logger.info("📱 Lazy loading recent activities for caree: \(caree.name)")
            MemoryMonitor.logMemoryUsage(context: "Before loadRecentActivities")

            do {
                let activities = try await selectiveService.fetchRecentActivities(
                    for: careeID,
                    isShared: caree.isShared,
                    hoursBack: hoursBack
                )

                guard !Task.isCancelled else { return }

                // Merge with pending activities
                let allActivities = (pendingActivities.filter { $0.careeID == careeID } + activities)
                    .sorted { $0.dateTime > $1.dateTime }

                recentActivitiesByCaree[careeID] = allActivities
                logger.info("✅ Loaded \(activities.count) activities (+ \(pendingActivities.count) pending)")
                MemoryMonitor.logMemoryUsage(context: "After loadRecentActivities")

            } catch {
                logger.error("❌ Failed to load activities: \(error.localizedDescription)")
                // Keep existing data if available
            }
        }

        await loadActivitiesTask?.value
    }

    // MARK: - Activity Creation (Optimistic UI)

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
                let syncedActivity = try await self.selectiveService.createActivity(
                    activity,
                    isShared: caree.isShared
                )

                // Update state to synced
                await self.updateActivityState(activity.id, state: .synced)
                await self.removePendingActivity(activity.id)

                self.logger.info("✅ Activity synced successfully")

            } catch {
                // Update state to failed
                await self.updateActivityState(activity.id, state: .failed(error.localizedDescription))
                self.logger.error("❌ Failed to sync activity: \(error.localizedDescription)")
            }
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

    // MARK: - Memory Management

    /// Clear cached data for carees not currently in use
    /// Call this when navigating away from caree detail
    /// - Parameter currentCareeID: ID of the caree currently being viewed (keep its data)
    func clearUnusedCache(except currentCareeID: UUID?) {
        let keysToKeep = currentCareeID.map { Set([$0]) } ?? Set<UUID>()

        // Clear activity types for carees not in use
        let typesBeforeCount = activityTypesByCaree.count
        activityTypesByCaree = activityTypesByCaree.filter { keysToKeep.contains($0.key) }

        // Clear activities for carees not in use
        let activitiesBeforeCount = recentActivitiesByCaree.count
        recentActivitiesByCaree = recentActivitiesByCaree.filter { keysToKeep.contains($0.key) }

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

        // Keep carees loaded (small memory footprint)
        logger.info("✅ Cache cleared (kept \(carees.count) carees)")
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

    deinit {
        cancelAllTasks()
    }
}
