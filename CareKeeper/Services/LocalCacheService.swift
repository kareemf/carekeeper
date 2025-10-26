import Foundation
import SwiftData
import SwiftUI

/// Manages SwiftData as a local cache for CloudKit data
/// Provides fast offline access and @Published properties for SwiftUI
@MainActor
class LocalCacheService: ObservableObject {

    // MARK: - Published Properties

    @Published var myCarees: [Caree] = []
    @Published var sharedCarees: [Caree] = []
    @Published var isLoading = false
    @Published var syncError: Error?

    // MARK: - Private Properties

    private let modelContext: ModelContext
    private let logger = AppLogger.cloudkit
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // Debounce/coalescing state
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var pendingRefresh = false
    private let refreshDebounceInterval: TimeInterval = 0.25

    // Batching state
    private var batchDepth: Int = 0

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Cache Write Operations

    /// Cache a Caree in SwiftData
    /// - Parameters:
    ///   - caree: Caree to cache (may be a transient object)
    ///   - isShared: Whether this is a shared caree
    func cacheCaree(_ caree: Caree, isShared: Bool) async throws {
        logger.info("Caching caree: \(caree.name) (isShared: \(isShared))")

        // Upsert by id
        let careeId = caree.id
        let fetchDescriptor = FetchDescriptor<Caree>(
            predicate: #Predicate { $0.id == careeId }
        )
        let existingCarees = try modelContext.fetch(fetchDescriptor)

        if let existingCaree = existingCarees.first {
            // Update existing managed instance
            existingCaree.applyScalarUpdates(from: caree)
            existingCaree.isShared = isShared
            existingCaree.isOwned = !isShared
            existingCaree.lastSyncedAt = Date()
            existingCaree.cloudKitRecordID = "CD_Caree/\(caree.id.uuidString)"

            logger.info("Updated existing caree in cache: \(caree.name)")
        } else {
            // Insert new managed instance (use the incoming object is fine)
            caree.isShared = isShared
            caree.isOwned = !isShared
            caree.lastSyncedAt = Date()
            caree.cloudKitRecordID = "CD_Caree/\(caree.id.uuidString)"

            modelContext.insert(caree)
            logger.info("Inserted new caree into cache: \(caree.name)")
        }

        try modelContext.save()
        scheduleRefresh(reason: "cacheCaree")
    }

    /// Update a cached Caree
    func updateCachedCaree(_ caree: Caree) async throws {
        logger.info("Updating cached caree: \(caree.name)")

        caree.lastSyncedAt = Date()
        try modelContext.save()

        scheduleRefresh(reason: "updateCachedCaree")
    }

    /// Remove a Caree from cache
    func removeCachedCaree(_ caree: Caree) async throws {
        logger.info("Removing caree from cache: \(caree.name)")

        modelContext.delete(caree)
        try modelContext.save()

        scheduleRefresh(reason: "removeCachedCaree")
    }

    /// Remove an ActivityType from cache
    func removeCachedActivityType(_ activityType: ActivityType) async throws {
        logger.info("Removing activity type from cache: \(activityType.name)")

        modelContext.delete(activityType)
        try modelContext.save()

        scheduleRefresh(reason: "removeCachedActivityType")
    }

    /// Remove an Activity from cache
    func removeCachedActivity(_ activity: Activity) async throws {
        logger.info("Removing activity from cache: \(activity.id)")

        modelContext.delete(activity)
        try modelContext.save()

        scheduleRefresh(reason: "removeCachedActivity")
    }

    /// Cache an ActivityType in SwiftData
    /// - Parameters:
    ///   - activityType: ActivityType to cache (may be transient)
    ///   - caree: Parent Caree (may be transient) — will be resolved to the managed instance
    func cacheActivityType(_ activityType: ActivityType, for caree: Caree) async throws {
        logger.info("Caching activity type: \(activityType.name)")

        // Resolve managed parent Caree
        guard let managedCaree = getCachedCaree(id: caree.id) else {
            logger.warning("Parent caree not found in cache; caching it first to avoid implicit insert")
            try await cacheCaree(caree, isShared: caree.isShared)
            guard let managedCaree2 = getCachedCaree(id: caree.id) else {
                logger.error("Failed to resolve parent caree after caching; aborting ActivityType cache")
                return
            }
            try await cacheActivityType(activityType, for: managedCaree2)
            return
        }

        // Upsert ActivityType by id
        let activityTypeId = activityType.id
        let fetchDescriptor = FetchDescriptor<ActivityType>(
            predicate: #Predicate { $0.id == activityTypeId }
        )
        let existing = try modelContext.fetch(fetchDescriptor)

        if let existingActivityType = existing.first {
            existingActivityType.applyScalarUpdates(from: activityType)
            existingActivityType.lastSyncedAt = Date()
            existingActivityType.cloudKitRecordID = "CD_ActivityType/\(activityType.id.uuidString)"
            attachActivityType(existingActivityType, to: managedCaree)
            logger.info("Updated existing activity type in cache: \(activityType.name)")
        } else {
            let newActivityType = ActivityType(
                name: activityType.name,
                icon: activityType.icon,
                hasQuantity: activityType.hasQuantity,
                quantityUnit: activityType.quantityUnit,
                hasLocation: activityType.hasLocation,
                listOrder: activityType.listOrder
            )
            newActivityType.id = activityType.id
            newActivityType.dateCreated = activityType.dateCreated
            newActivityType.lastSyncedAt = Date()
            newActivityType.cloudKitRecordID = "CD_ActivityType/\(activityType.id.uuidString)"

            modelContext.insert(newActivityType)
            attachActivityType(newActivityType, to: managedCaree)
            logger.info("Inserted new activity type into cache: \(activityType.name)")
        }

        try modelContext.save()
        scheduleRefresh(reason: "cacheActivityType")
    }

    /// Cache an Activity in SwiftData
    /// - Parameters:
    ///   - activity: Activity to cache (may be transient)
    ///   - caree: Parent Caree (may be transient) — will be resolved to the managed instance
    ///   - activityTypeID: Identifier of the parent ActivityType
    func cacheActivity(_ activity: Activity, for caree: Caree, activityTypeID: UUID) async throws {
        logger.info("Caching activity at: \(activity.dateTime)")

        // Resolve managed parent Caree and ActivityType
        guard let managedCaree = getCachedCaree(id: caree.id) else {
            logger.warning("Parent caree not found in cache; caching it first to avoid implicit insert")
            try await cacheCaree(caree, isShared: caree.isShared)
            try await cacheActivity(activity, for: caree, activityTypeID: activityTypeID)
            return
        }

        let managedActivityType: ActivityType
        do {
            if let at = try fetchActivityType(id: activityTypeID) {
                managedActivityType = at
            } else {
                logger.warning("Parent activity type not found; caching it first to avoid implicit insert")
                logger.error("Cannot resolve parent activity type \(activityTypeID)")
                return
            }
        } catch {
            logger.error("Failed to fetch activity type: \(error.localizedDescription)")
            return
        }

        // Upsert Activity by id
        let activityId = activity.id
        let fetchDescriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.id == activityId }
        )
        let existing = try modelContext.fetch(fetchDescriptor)

        if let existingActivity = existing.first {
            existingActivity.applyScalarUpdates(from: activity)
            existingActivity.lastSyncedAt = Date()
            existingActivity.cloudKitRecordID = "CD_Activity/\(activity.id.uuidString)"
            attachActivity(existingActivity, to: managedCaree)
            attachActivity(existingActivity, toActivityType: managedActivityType)

            logger.info("Updated existing activity in cache")
        } else {
            let newActivity = Activity(
                dateTime: activity.dateTime,
                notes: activity.notes,
                quantity: activity.quantity,
                latitude: activity.latitude,
                longitude: activity.longitude
            )
            newActivity.id = activity.id
            newActivity.dateCreated = activity.dateCreated
            newActivity.lastSyncedAt = Date()
            newActivity.cloudKitRecordID = "CD_Activity/\(activity.id.uuidString)"

            modelContext.insert(newActivity)
            attachActivity(newActivity, to: managedCaree)
            attachActivity(newActivity, toActivityType: managedActivityType)

            logger.info("Inserted new activity into cache")
        }

        try modelContext.save()
        scheduleRefresh(reason: "cacheActivity")
    }
    // MARK: - Cache Read Operations

    func getCachedCaree(id: UUID) -> Caree? {
        let careeId = id
        let fetchDescriptor = FetchDescriptor<Caree>(
            predicate: #Predicate { $0.id == careeId }
        )

        do {
            let results = try modelContext.fetch(fetchDescriptor)
            return results.first
        } catch {
            logger.error("Failed to fetch cached caree: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchActivityType(id: UUID) throws -> ActivityType? {
        let fetchDescriptor = FetchDescriptor<ActivityType>(
            predicate: #Predicate { $0.id == id }
        )
        let results = try modelContext.fetch(fetchDescriptor)
        return results.first
    }

    func getCachedActivityTypes(for caree: Caree) -> [ActivityType] {
        return caree.sortedActivityTypes
    }

    func getCachedActivities(for caree: Caree) -> [Activity] {
        return caree.recentActivities
    }

    func isCacheStale(lastSyncedAt: Date?) -> Bool {
        guard let lastSyncedAt = lastSyncedAt else {
            return true
        }
        let age = Date().timeIntervalSince(lastSyncedAt)
        return age > cacheTTL
    }

    // MARK: - Debounced refresh

    /// Coalesce refresh requests and avoid overlapping refresh runs.
    func scheduleRefresh(reason: String? = nil) {
        // If we're in a batch, just mark pending and return.
        if batchDepth > 0 {
            pendingRefresh = true
            return
        }

        // Cancel any scheduled-but-not-started refresh task.
        refreshTask?.cancel()

        let label = reason ?? "unknown"
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.refreshDebounceInterval * 1_000_000_000))
            } catch {
                return // task was cancelled
            }
            await self.runRefreshIfNeeded(reason: label)
        }
    }

    private func runRefreshIfNeeded(reason: String) async {
        if isRefreshing {
            // Another refresh is running; mark pending and return.
            pendingRefresh = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshPublishedProperties()
        logger.info("🔁 Coalesced refresh executed (\(reason, privacy: .public))")

        // If another refresh was requested during the run, perform one more pass.
        if pendingRefresh {
            pendingRefresh = false
            await refreshPublishedProperties()
            logger.info("🔁 Follow-up coalesced refresh executed")
        }
    }

    // MARK: - Cache Refresh

    /// Refresh the @Published properties from SwiftData
    func refreshPublishedProperties() async {
        MemoryMonitor.logMemoryUsage(context: "Before Cache Refresh")

        do {
            // Fetch owned and shared separately to avoid in-memory filtering.
            let ownedFetch = FetchDescriptor<Caree>(
                predicate: #Predicate { $0.isOwned == true },
                sortBy: [SortDescriptor(\.listOrder)]
            )
            let sharedFetch = FetchDescriptor<Caree>(
                predicate: #Predicate { $0.isShared == true },
                sortBy: [SortDescriptor(\.listOrder)]
            )

            let newOwned = try modelContext.fetch(ownedFetch)
            let newShared = try modelContext.fetch(sharedFetch)

            // Only assign when changed (by identity + order) to avoid redundant SwiftUI updates.
            if !arraysEqualByID(lhs: myCarees, rhs: newOwned) {
                myCarees = newOwned
            }
            if !arraysEqualByID(lhs: sharedCarees, rhs: newShared) {
                sharedCarees = newShared
            }

            logger.info("Refreshed cache: \(self.myCarees.count) owned, \(self.sharedCarees.count) shared")
            MemoryMonitor.logMemoryUsage(
                context: "After Cache Refresh",
                objectCount: myCarees.count + sharedCarees.count,
                objectType: "carees"
            )
        } catch {
            logger.error("Failed to refresh published properties: \(error.localizedDescription)")
            syncError = error
        }
    }

    func refreshCache() async throws {
        isLoading = true
        defer { isLoading = false }
        scheduleRefresh(reason: "refreshCache")
    }

    /// This forces a complete refresh of all published properties
    func invalidateAndRefresh() async throws {
        logger.info("Invalidating and refreshing cache")
        isLoading = true
        defer { isLoading = false }

        scheduleRefresh(reason: "invalidateAndRefresh")

        logger.info("Cache invalidated and refresh scheduled")
    }

    // MARK: - Cache Invalidation

    func clearCache() async throws {
        logger.warning("Clearing all cached data")

        // Delete all carees (cascade will delete children)
        let fetchDescriptor = FetchDescriptor<Caree>()
        let allCarees = try modelContext.fetch(fetchDescriptor)

        for caree in allCarees {
            modelContext.delete(caree)
        }

        try modelContext.save()

        // Clear published properties
        myCarees = []
        sharedCarees = []

        logger.info("Cache cleared")
    }

    /// Remove stale cached records older than TTL
    func removeStaleRecords() async throws {
        logger.info("Removing stale cached records")

        let staleThreshold = Date().addingTimeInterval(-cacheTTL)

        // Find stale carees
        let staleFetchDescriptor = FetchDescriptor<Caree>(
            predicate: #Predicate { caree in
                caree.lastSyncedAt != nil && caree.lastSyncedAt! < staleThreshold
            }
        )

        let staleCarees = try modelContext.fetch(staleFetchDescriptor)

        for caree in staleCarees {
            logger.info("Removing stale caree: \(caree.name)")
            modelContext.delete(caree)
        }

        try modelContext.save()
        scheduleRefresh(reason: "removeStaleRecords")

        logger.info("Removed \(staleCarees.count) stale records")
    }

    // MARK: - Cache Statistics

    /// Get cache statistics for diagnostics
    func getCacheStats() throws -> CacheStats {
        let careeCount = try modelContext.fetchCount(FetchDescriptor<Caree>())
        let activityTypeCount = try modelContext.fetchCount(FetchDescriptor<ActivityType>())
        let activityCount = try modelContext.fetchCount(FetchDescriptor<Activity>())

        let ownedCount = myCarees.count
        let sharedCount = sharedCarees.count

        return CacheStats(
            totalCarees: careeCount,
            ownedCarees: ownedCount,
            sharedCarees: sharedCount,
            totalActivityTypes: activityTypeCount,
            totalActivities: activityCount
        )
    }

    // MARK: - Helpers

    private func arraysEqualByID<T: AnyObject>(lhs: [T], rhs: [T]) -> Bool {
        // All three models have a stable UUID id; cast dynamically
        func id(of obj: AnyObject) -> UUID? {
            if let c = obj as? Caree { return c.id }
            if let a = obj as? Activity { return a.id }
            if let t = obj as? ActivityType { return t.id }
            return nil
        }
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if id(of: l) != id(of: r) { return false }
        }
        return true
    }

    // MARK: - Batching

    /// Begin a batch of cache mutations. Suppresses refresh until the batch ends.
    func beginBatch() {
        batchDepth += 1
    }

    /// End a batch of cache mutations. Triggers a single coalesced refresh if needed.
    func endBatch() {
        guard batchDepth > 0 else { return }
        batchDepth -= 1
        if batchDepth == 0, pendingRefresh {
            pendingRefresh = false
            scheduleRefresh(reason: "endBatch")
        }
    }

    /// Perform a set of operations as a batch, ensuring a single refresh at the end.
    func withBatch<R>(_ operation: () async throws -> R) async rethrows -> R {
        beginBatch()
        defer { endBatch() }
        return try await operation()
    }

    private func attachActivityType(_ activityType: ActivityType, to caree: Caree) {
        var types = caree.activityTypes ?? []
        if !types.contains(where: { $0.id == activityType.id }) {
            types.append(activityType)
            caree.activityTypes = types
        }
    }

    private func attachActivity(_ activity: Activity, to caree: Caree) {
        var activities = caree.activities ?? []
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        caree.activities = activities
    }

    private func attachActivity(_ activity: Activity, toActivityType activityType: ActivityType) {
        var activities = activityType.activities ?? []
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        activityType.activities = activities
    }
}

// MARK: - Cache Statistics

struct CacheStats {
    let totalCarees: Int
    let ownedCarees: Int
    let sharedCarees: Int
    let totalActivityTypes: Int
    let totalActivities: Int

    var description: String {
        """
        Cache Statistics:
        - Total Carees: \(totalCarees) (Owned: \(ownedCarees), Shared: \(sharedCarees))
        - Activity Types: \(totalActivityTypes)
        - Activities: \(totalActivities)
        """
    }
}
