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
    ///   - caree: Caree to cache
    ///   - isShared: Whether this is a shared caree
    func cacheCaree(_ caree: Caree, isShared: Bool) async throws {
        logger.info("Caching caree: \(caree.name) (isShared: \(isShared))")

        // Check if caree already exists in cache
        let fetchDescriptor = FetchDescriptor<Caree>(
            predicate: #Predicate { $0.id == caree.id }
        )

        let existingCarees = try modelContext.fetch(fetchDescriptor)

        if let existingCaree = existingCarees.first {
            // Update existing caree
            existingCaree.name = caree.name
            existingCaree.image = caree.image
            existingCaree.listOrder = caree.listOrder
            existingCaree.dateCreated = caree.dateCreated
            existingCaree.isShared = isShared
            existingCaree.isOwned = !isShared
            existingCaree.lastSyncedAt = Date()
            existingCaree.cloudKitRecordID = "CD_Caree/\(caree.id.uuidString)"

            logger.info("Updated existing caree in cache: \(caree.name)")
        } else {
            // Insert new caree
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
    /// - Parameter caree: Caree to update (must already exist in cache)
    func updateCachedCaree(_ caree: Caree) async throws {
        logger.info("Updating cached caree: \(caree.name)")

        caree.lastSyncedAt = Date()
        try modelContext.save()

        await refreshPublishedProperties()
    }

    /// Remove a Caree from cache
    /// - Parameter caree: Caree to remove
    func removeCachedCaree(_ caree: Caree) async throws {
        logger.info("Removing caree from cache: \(caree.name)")

        modelContext.delete(caree)
        try modelContext.save()

        await refreshPublishedProperties()
    }

    /// Cache an ActivityType in SwiftData
    /// - Parameters:
    ///   - activityType: ActivityType to cache
    ///   - caree: Parent Caree (must already be cached)
    func cacheActivityType(_ activityType: ActivityType, for caree: Caree) async throws {
        logger.info("Caching activity type: \(activityType.name)")

        // Check if already exists
        let fetchDescriptor = FetchDescriptor<ActivityType>(
            predicate: #Predicate { $0.id == activityType.id }
        )

        let existing = try modelContext.fetch(fetchDescriptor)

        if let existingActivityType = existing.first {
            // Update existing
            existingActivityType.name = activityType.name
            existingActivityType.icon = activityType.icon
            existingActivityType.hasQuantity = activityType.hasQuantity
            existingActivityType.quantityUnit = activityType.quantityUnit
            existingActivityType.hasLocation = activityType.hasLocation
            existingActivityType.listOrder = activityType.listOrder
            existingActivityType.dateCreated = activityType.dateCreated
            existingActivityType.lastSyncedAt = Date()
            existingActivityType.cloudKitRecordID = "CD_ActivityType/\(activityType.id.uuidString)"
            existingActivityType.caree = caree

            logger.info("Updated existing activity type in cache: \(activityType.name)")
        } else {
            // Insert new
            activityType.lastSyncedAt = Date()
            activityType.cloudKitRecordID = "CD_ActivityType/\(activityType.id.uuidString)"
            activityType.caree = caree

            modelContext.insert(activityType)
            logger.info("Inserted new activity type into cache: \(activityType.name)")
        }

        try modelContext.save()
    }

    /// Cache an Activity in SwiftData
    /// - Parameters:
    ///   - activity: Activity to cache
    ///   - caree: Parent Caree (must already be cached)
    ///   - activityType: ActivityType (must already be cached)
    func cacheActivity(_ activity: Activity, for caree: Caree, activityType: ActivityType) async throws {
        logger.info("Caching activity at: \(activity.dateTime)")

        // Check if already exists
        let fetchDescriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.id == activity.id }
        )

        let existing = try modelContext.fetch(fetchDescriptor)

        if let existingActivity = existing.first {
            // Update existing
            existingActivity.dateTime = activity.dateTime
            existingActivity.notes = activity.notes
            existingActivity.quantity = activity.quantity
            existingActivity.latitude = activity.latitude
            existingActivity.longitude = activity.longitude
            existingActivity.dateCreated = activity.dateCreated
            existingActivity.lastSyncedAt = Date()
            existingActivity.cloudKitRecordID = "CD_Activity/\(activity.id.uuidString)"
            existingActivity.caree = caree
            existingActivity.activityType = activityType

            logger.info("Updated existing activity in cache")
        } else {
            // Insert new
            activity.lastSyncedAt = Date()
            activity.cloudKitRecordID = "CD_Activity/\(activity.id.uuidString)"
            activity.caree = caree
            activity.activityType = activityType

            modelContext.insert(activity)
            logger.info("Inserted new activity into cache")
        }

        try modelContext.save()
    }

    // MARK: - Cache Read Operations

    /// Get a cached Caree by ID
    /// - Parameter id: Caree UUID
    /// - Returns: Cached Caree if found
    func getCachedCaree(id: UUID) -> Caree? {
        let fetchDescriptor = FetchDescriptor<Caree>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let results = try modelContext.fetch(fetchDescriptor)
            return results.first
        } catch {
            logger.error("Failed to fetch cached caree: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get all cached ActivityTypes for a Caree
    /// - Parameter caree: Parent Caree
    /// - Returns: Array of ActivityTypes
    func getCachedActivityTypes(for caree: Caree) -> [ActivityType] {
        return caree.sortedActivityTypes
    }

    /// Get all cached Activities for a Caree
    /// - Parameter caree: Parent Caree
    /// - Returns: Array of Activities
    func getCachedActivities(for caree: Caree) -> [Activity] {
        return caree.recentActivities
    }

    /// Check if cache is stale for a given record
    /// - Parameter lastSyncedAt: Last sync timestamp
    /// - Returns: true if cache is stale
    func isCacheStale(lastSyncedAt: Date?) -> Bool {
        guard let lastSyncedAt = lastSyncedAt else {
            return true // No sync timestamp means stale
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

            logger.info("Refreshed cache: \(myCarees.count) owned, \(sharedCarees.count) shared")
        } catch {
            logger.error("Failed to refresh published properties: \(error.localizedDescription)")
            syncError = error
        }
    }

    /// Refresh cache from CloudKit (delegates to CloudKitDataService)
    /// This should be called by CloudKitDataService after sync operations
    func refreshCache() async throws {
        isLoading = true
        defer { isLoading = false }

        await refreshPublishedProperties()
    }

    // MARK: - Cache Invalidation

    /// Clear all cached data (use with caution)
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
                if let lastSyncedAt = caree.lastSyncedAt {
                    return lastSyncedAt < staleThreshold
                }
                return false
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
