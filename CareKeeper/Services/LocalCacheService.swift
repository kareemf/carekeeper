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
        await refreshPublishedProperties()
    }

    /// Update a cached Caree
    func updateCachedCaree(_ caree: Caree) async throws {
        logger.info("Updating cached caree: \(caree.name)")

        caree.lastSyncedAt = Date()
        try modelContext.save()

        await refreshPublishedProperties()
    }

    /// Remove a Caree from cache
    func removeCachedCaree(_ caree: Caree) async throws {
        logger.info("Removing caree from cache: \(caree.name)")

        modelContext.delete(caree)
        try modelContext.save()

        await refreshPublishedProperties()
    }

    /// Remove an ActivityType from cache
    func removeCachedActivityType(_ activityType: ActivityType) async throws {
        logger.info("Removing activity type from cache: \(activityType.name)")

        modelContext.delete(activityType)
        try modelContext.save()

        await refreshPublishedProperties()
    }

    /// Remove an Activity from cache
    func removeCachedActivity(_ activity: Activity) async throws {
        logger.info("Removing activity from cache: \(activity.id)")

        modelContext.delete(activity)
        try modelContext.save()

        await refreshPublishedProperties()
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
            existingActivityType.caree = managedCaree

            logger.info("Updated existing activity type in cache: \(activityType.name)")
        } else {
            // Insert new managed instance, attach to managedCaree
            activityType.lastSyncedAt = Date()
            activityType.cloudKitRecordID = "CD_ActivityType/\(activityType.id.uuidString)"
            activityType.caree = managedCaree

            modelContext.insert(activityType)
            logger.info("Inserted new activity type into cache: \(activityType.name)")
        }

        try modelContext.save()
        await refreshPublishedProperties()
    }

    /// Cache an Activity in SwiftData
    /// - Parameters:
    ///   - activity: Activity to cache (may be transient)
    ///   - caree: Parent Caree (may be transient) — will be resolved to the managed instance
    ///   - activityType: ActivityType (may be transient) — will be resolved to the managed instance
    func cacheActivity(_ activity: Activity, for caree: Caree, activityType: ActivityType) async throws {
        logger.info("Caching activity at: \(activity.dateTime)")

        // Resolve managed parent Caree and ActivityType
        guard let managedCaree = getCachedCaree(id: caree.id) else {
            logger.warning("Parent caree not found in cache; caching it first to avoid implicit insert")
            try await cacheCaree(caree, isShared: caree.isShared)
            try await cacheActivity(activity, for: caree, activityType: activityType)
            return
        }

        let managedActivityType: ActivityType
        do {
            if let at = try fetchActivityType(id: activityType.id) {
                managedActivityType = at
            } else {
                logger.warning("Parent activity type not found; caching it first to avoid implicit insert")
                try await cacheActivityType(activityType, for: managedCaree)
                guard let at2 = try fetchActivityType(id: activityType.id) else {
                    logger.error("Failed to resolve activity type after caching; aborting Activity cache")
                    return
                }
                managedActivityType = at2
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
            existingActivity.caree = managedCaree
            existingActivity.activityType = managedActivityType

            logger.info("Updated existing activity in cache")
        } else {
            activity.lastSyncedAt = Date()
            activity.cloudKitRecordID = "CD_Activity/\(activity.id.uuidString)"
            activity.caree = managedCaree
            activity.activityType = managedActivityType

            modelContext.insert(activity)
            logger.info("Inserted new activity into cache")
        }

        try modelContext.save()
        await refreshPublishedProperties()
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

    // MARK: - Cache Refresh

    /// Refresh the @Published properties from SwiftData
    func refreshPublishedProperties() async {
        do {
            // Fetch all carees
            let allCareesFetchDescriptor = FetchDescriptor<Caree>(
                sortBy: [SortDescriptor(\.listOrder)]
            )
            let allCarees = try modelContext.fetch(allCareesFetchDescriptor)

            // Separate into owned and shared
            myCarees = allCarees.filter { $0.isOwned }
            sharedCarees = allCarees.filter { $0.isShared }

            logger.info("Refreshed cache: \(self.myCarees.count) owned, \(self.sharedCarees.count) shared")
        } catch {
            logger.error("Failed to refresh published properties: \(error.localizedDescription)")
            syncError = error
        }
    }

    func refreshCache() async throws {
        isLoading = true
        defer { isLoading = false }
        await refreshPublishedProperties()
    }

    /// This forces a complete refresh of all published properties
    func invalidateAndRefresh() async throws {
        logger.info("Invalidating and refreshing cache")
        isLoading = true
        defer { isLoading = false }

        await refreshPublishedProperties()

        logger.info("Cache invalidated and refreshed")
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
        await refreshPublishedProperties()

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
