import Foundation
import CloudKit
import os.log

/// Watch-optimized CloudKit queries with aggressive filtering
/// Key optimizations:
/// - Time-based filters (last 48h for activities)
/// - Hard result limits (100 activities max)
/// - On-demand loading (activity types loaded per caree, not upfront)
/// - Lightweight count queries (avoids loading full objects)
@MainActor
class SelectiveCloudKitService {

    // MARK: - Configuration

    /// Only load activities from last 48 hours (configurable)
    static let activityHistoryHours: TimeInterval = 48 * 3600

    /// Maximum activities to load per caree (hard limit to prevent memory issues)
    static let maxActivitiesPerCaree = 100

    /// Maximum activity types to load (should be small anyway)
    static let maxActivityTypes = 50

    // MARK: - Private Properties

    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "selective-queries")

    // MARK: - Caree Queries (Small Dataset - Load All)

    /// Load all carees (both owned and shared)
    /// This is acceptable because caree count should be small (<20 typically)
    func fetchAllCarees() async throws -> [CareeSnapshot] {
        logger.info("🔍 Fetching all carees (selective: owned + shared)")
        MemoryMonitor.logMemoryUsage(context: "Before fetchAllCarees")

        async let ownedCarees = fetchOwnedCarees()
        async let sharedCarees = fetchSharedCarees()

        let (owned, shared) = try await (ownedCarees, sharedCarees)
        let allCarees = owned + shared

        logger.info("✅ Loaded \(owned.count) owned + \(shared.count) shared = \(allCarees.count) total carees")
        MemoryMonitor.logMemoryUsage(
            context: "After fetchAllCarees",
            objectCount: allCarees.count,
            objectType: "carees"
        )

        return allCarees
    }

    private func fetchOwnedCarees() async throws -> [CareeSnapshot] {
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        let results = try await database.records(matching: query)

        return try results.matchResults.compactMap { _, result in
            let record = try result.get()
            return try CareeSnapshot(from: record, isShared: false)
        }
    }

    private func fetchSharedCarees() async throws -> [CareeSnapshot] {
        let database = container.sharedCloudDatabase
        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))

        let results = try await database.records(matching: query)

        return try results.matchResults.compactMap { _, result in
            let record = try result.get()
            return try CareeSnapshot(from: record, isShared: true)
        }
    }

    // MARK: - ActivityType Queries (On-Demand Per Caree)

    /// Load activity types ONLY for a specific caree
    /// Called when user taps on a caree, not upfront
    /// - Parameters:
    ///   - careeID: ID of the caree
    ///   - isShared: Whether this is a shared caree
    /// - Returns: Array of activity type snapshots
    func fetchActivityTypes(for careeID: UUID, isShared: Bool) async throws -> [ActivityTypeSnapshot] {
        logger.info("🔍 Fetching activity types for caree: \(careeID)")
        MemoryMonitor.logMemoryUsage(context: "Before fetchActivityTypes")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Query only for this specific caree
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)")
        let careeReference = CKRecord.Reference(recordID: careeRecordID, action: .none)
        let predicate = NSPredicate(format: "CD_caree == %@", careeReference)

        let query = CKQuery(recordType: "CD_ActivityType", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        let results = try await database.records(
            matching: query,
            desiredKeys: nil,
            resultsLimit: Self.maxActivityTypes
        )

        let activityTypes = try results.matchResults.compactMap { _, result in
            try ActivityTypeSnapshot(from: result.get())
        }

        logger.info("✅ Loaded \(activityTypes.count) activity types for caree")
        MemoryMonitor.logMemoryUsage(
            context: "After fetchActivityTypes",
            objectCount: activityTypes.count,
            objectType: "activity types"
        )

        return activityTypes
    }

    // MARK: - Activity Queries (Recent Only, Paginated)

    /// Load ONLY recent activities for a specific caree
    /// This is the key optimization - never load all history on watch!
    /// - Parameters:
    ///   - careeID: ID of the caree
    ///   - activityTypeID: Optional filter by activity type
    ///   - isShared: Whether this is a shared caree
    ///   - hoursBack: How many hours of history to load (default 48)
    /// - Returns: Array of activity snapshots (max 100)
    func fetchRecentActivities(
        for careeID: UUID,
        activityTypeID: UUID? = nil,
        isShared: Bool,
        hoursBack: TimeInterval = activityHistoryHours
    ) async throws -> [ActivitySnapshot] {
        logger.info("🔍 Fetching recent activities (last \(hoursBack/3600)h) for caree: \(careeID)")
        MemoryMonitor.logMemoryUsage(context: "Before fetchRecentActivities")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Build predicate with date filter (CRITICAL for performance)
        let cutoffDate = Date().addingTimeInterval(-hoursBack)
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)")
        let careeReference = CKRecord.Reference(recordID: careeRecordID, action: .none)

        var predicateFormat = "CD_caree == %@ AND CD_dateTime > %@"
        var predicateArgs: [Any] = [careeReference, cutoffDate]

        // Optionally filter by activity type
        if let activityTypeID = activityTypeID {
            let typeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityTypeID.uuidString)")
            let typeReference = CKRecord.Reference(recordID: typeRecordID, action: .none)
            predicateFormat += " AND CD_activityType == %@"
            predicateArgs.append(typeReference)
        }

        let predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        let query = CKQuery(recordType: "CD_Activity", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "CD_dateTime", ascending: false)]

        // Hard limit to prevent memory issues
        let results = try await database.records(
            matching: query,
            desiredKeys: nil,
            resultsLimit: Self.maxActivitiesPerCaree
        )

        let activities = try results.matchResults.compactMap { _, result in
            try ActivitySnapshot(from: result.get())
        }

        logger.info("✅ Loaded \(activities.count) recent activities (capped at \(Self.maxActivitiesPerCaree))")
        MemoryMonitor.logMemoryUsage(
            context: "After fetchRecentActivities",
            objectCount: activities.count,
            objectType: "activities"
        )

        return activities
    }

    // MARK: - Activity Type Count (Efficient Aggregation)

    /// Get count of activity types without loading full objects
    /// Uses lightweight count query instead of loading relationships
    /// - Parameters:
    ///   - careeID: ID of the caree
    ///   - isShared: Whether this is a shared caree
    /// - Returns: Count of activity types
    func fetchActivityTypeCount(for careeID: UUID, isShared: Bool) async throws -> Int {
        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)")
        let careeReference = CKRecord.Reference(recordID: careeRecordID, action: .none)
        let predicate = NSPredicate(format: "CD_caree == %@", careeReference)

        let query = CKQuery(recordType: "CD_ActivityType", predicate: predicate)

        // Only fetch count, not full records (use empty desiredKeys for minimal data)
        let results = try await database.records(
            matching: query,
            desiredKeys: [],
            resultsLimit: 1000  // High enough to get accurate count
        )

        let count = results.matchResults.count
        logger.info("📊 Activity type count for caree \(careeID): \(count)")

        return count
    }

    // MARK: - Activity Creation (For Watch)

    /// Create a new activity record in CloudKit
    /// - Parameters:
    ///   - activity: Activity snapshot to create
    ///   - isShared: Whether this belongs to a shared caree
    /// - Returns: Updated snapshot with synced state
    func createActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot {
        logger.info("📝 Creating activity in CloudKit")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Create CKRecord
        let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)")
        let record = CKRecord(recordType: "CD_Activity", recordID: recordID)

        // Set fields
        record["CD_dateTime"] = activity.dateTime
        record["CD_notes"] = activity.notes
        record["CD_quantity"] = activity.quantity
        record["CD_latitude"] = activity.latitude
        record["CD_longitude"] = activity.longitude
        record["CD_dateCreated"] = activity.dateCreated

        // Set references
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(activity.careeID.uuidString)")
        record["CD_caree"] = CKRecord.Reference(recordID: careeRecordID, action: .none)

        let typeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activity.activityTypeID.uuidString)")
        record["CD_activityType"] = CKRecord.Reference(recordID: typeRecordID, action: .none)

        // Set parent reference for sharing hierarchy
        record.parent = CKRecord.Reference(recordID: careeRecordID, action: .none)

        // Save to CloudKit
        _ = try await database.save(record)

        logger.info("✅ Activity created successfully")

        // Return updated snapshot with synced state
        var updatedActivity = activity
        updatedActivity.syncState = .synced
        return updatedActivity
    }
}
