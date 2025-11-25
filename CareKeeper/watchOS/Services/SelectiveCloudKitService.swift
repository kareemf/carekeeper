import CloudKit
import Foundation
import os.log

@MainActor
protocol SelectiveCloudKitServiceProtocol: AnyObject {
    func fetchAllCarees(includeImages: Bool) async throws -> [CareeSnapshot]
    func fetchCareeImage(for careeID: UUID, zoneName: String, zoneOwnerName: String?, isShared: Bool) async throws -> Data?
    func fetchActivityTypes(for careeID: UUID, isShared: Bool) async throws -> [ActivityTypeSnapshot]
    func fetchRecentActivities(
        for careeID: UUID,
        activityTypeID: UUID?,
        isShared: Bool,
        hoursBack: TimeInterval?,
        before: Date?,
        resultsLimit: Int
    ) async throws -> [ActivitySnapshot]
    func fetchActivityTypeCount(for careeID: UUID, isShared: Bool) async throws -> Int
    func createActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot
    func updateActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot
    func deleteActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws
}

/// Watch-optimized CloudKit queries with aggressive filtering
/// Key optimizations:
/// - Time-based filters (last 24h for activities)
/// - Hard result limits (100 activities max)
/// - On-demand loading (activity types loaded per caree, not upfront)
/// - Lightweight count queries (avoids loading full objects)
@MainActor
class SelectiveCloudKitService: SelectiveCloudKitServiceProtocol {
    // MARK: - Configuration

    /// Only load activities from last 24 hours (configurable)
    static let activityHistoryHours: TimeInterval = 24 * 3600

    /// Maximum activities to load per caree (hard limit to prevent memory issues)
    static let maxActivitiesPerCaree = 100

    /// Maximum activity types to load (should be small anyway)
    static let maxActivityTypes = 50

    // MARK: - Private Properties

    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "selective-queries")
    private let retryService = CloudKitRetryService()

    // MARK: - Retry Logic (Delegated to CloudKitRetryService)

    /// Execute a CloudKit request with automatic retry for transient errors
    /// Delegates to CloudKitRetryService for consistent retry behavior
    private func retryableRequest<T>(
        operation: String,
        _ block: @escaping () async throws -> T
    ) async throws -> T {
        try await retryService.retryableRequest(operation: operation, block)
    }

    // MARK: - Caree Queries (Small Dataset - Load All)

    private let careeNonImageKeys = ["CD_name", "CD_listOrder", "CD_dateCreated"]

    /// Load all carees (both owned and shared)
    /// This is acceptable because caree count should be small (<20 typically)
    func fetchAllCarees(includeImages: Bool = false) async throws -> [CareeSnapshot] {
        logger.info("🔍 Fetching all carees (selective: owned + shared)")
        MemoryMonitor.logMemoryUsage(context: "Before fetchAllCarees")

        async let ownedCarees = fetchOwnedCarees(includeImages: includeImages)
        async let sharedCarees = fetchSharedCarees(includeImages: includeImages)

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

    private func fetchOwnedCarees(includeImages: Bool) async throws -> [CareeSnapshot] {
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        // Query from the custom app zone (matches iOS app)
        let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)

        let nonImageKeys = careeNonImageKeys
        let (results, _) = try await retryableRequest(operation: "fetchOwnedCarees") {
            try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: includeImages ? nil : nonImageKeys
            )
        }

        return try results.compactMap { _, result in
            let record = try result.get()
            return try CareeSnapshot(from: record, isShared: false)
        }
    }

    private func fetchSharedCarees(includeImages: Bool) async throws -> [CareeSnapshot] {
        let database = container.sharedCloudDatabase

        // Shared database requires zone-specific queries (no zone-wide queries!)
        let zones = try await retryableRequest(operation: "fetchSharedZones") {
            try await database.allRecordZones()
        }
        logger.info("📱 Found \(zones.count) shared zones")

        var allCarees: [CareeSnapshot] = []

        for zone in zones {
            // Skip default zone
            if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

            logger.info("🔍 Querying shared carees in zone: \(zone.zoneID.zoneName)")

            let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
            let nonImageKeys = careeNonImageKeys
            let (matchResults, _) = try await retryableRequest(operation: "fetchSharedCarees(zone: \(zone.zoneID.zoneName))") {
                try await database.records(
                    matching: query,
                    inZoneWith: zone.zoneID,
                    desiredKeys: includeImages ? nil : nonImageKeys
                )
            }

            for (_, result) in matchResults {
                if let record = try? result.get() {
                    if let caree = try? CareeSnapshot(from: record, isShared: true) {
                        allCarees.append(caree)
                    }
                }
            }
        }

        logger.info("✅ Loaded \(allCarees.count) shared carees from \(zones.count) zones")
        return allCarees
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

        var activityTypes: [ActivityTypeSnapshot] = []

        if isShared {
            // Shared database requires zone-specific queries
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                let (
                    matchResults,
                    _
                ) = try await retryableRequest(operation: "fetchActivityTypes(zone: \(zone.zoneID.zoneName))") {
                    try await database.records(
                        matching: query,
                        inZoneWith: zone.zoneID,
                        desiredKeys: nil,
                        resultsLimit: Self.maxActivityTypes
                    )
                }

                for (_, result) in matchResults {
                    if let record = try? result.get(),
                       let activityType = try? ActivityTypeSnapshot(from: record)
                    {
                        activityTypes.append(activityType)
                    }
                }
            }
        } else {
            // Private database - query from custom app zone (matches iOS app)
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)

            let (matchResults, _) = try await retryableRequest(operation: "fetchActivityTypes(private)") {
                try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: nil,
                    resultsLimit: Self.maxActivityTypes
                )
            }

            activityTypes = matchResults.compactMap { _, result in
                try? ActivityTypeSnapshot(from: result.get())
            }
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
    ///   - hoursBack: How many hours of history to load (default 24)
    /// - Returns: Array of activity snapshots (max 100)
    func fetchRecentActivities(
        for careeID: UUID,
        activityTypeID: UUID? = nil,
        isShared: Bool,
        hoursBack: TimeInterval? = nil,
        before: Date? = nil,
        resultsLimit: Int
    ) async throws -> [ActivitySnapshot] {
        let hours = hoursBack ?? Self.activityHistoryHours
        logger.info("🔍 Fetching recent activities (last \(hours / 3600)h) for caree: \(careeID)")
        MemoryMonitor.logMemoryUsage(context: "Before fetchRecentActivities")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Build predicate with date filter (CRITICAL for performance)
        let cutoffDate = Date().addingTimeInterval(-hours)
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)")
        let careeReference = CKRecord.Reference(recordID: careeRecordID, action: .none)

        var predicateFormat = "CD_caree == %@ AND CD_dateTime > %@"
        var predicateArgs: [Any] = [careeReference, cutoffDate]

        // Optionally filter by activity type
        if let activityTypeID {
            let typeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityTypeID.uuidString)")
            let typeReference = CKRecord.Reference(recordID: typeRecordID, action: .none)
            predicateFormat += " AND CD_activityType == %@"
            predicateArgs.append(typeReference)
        }

        if let before {
            predicateFormat += " AND CD_dateTime < %@"
            predicateArgs.append(before)
        }

        let predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        let query = CKQuery(recordType: "CD_Activity", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "CD_dateTime", ascending: false)]

        var activities: [ActivitySnapshot] = []

        if isShared {
            // Shared database requires zone-specific queries
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                let (
                    matchResults,
                    _
                ) = try await retryableRequest(operation: "fetchRecentActivities(zone: \(zone.zoneID.zoneName))") {
                    try await database.records(
                        matching: query,
                        inZoneWith: zone.zoneID,
                        desiredKeys: nil,
                        resultsLimit: resultsLimit
                    )
                }

                for (_, result) in matchResults {
                    if let record = try? result.get(),
                       let activity = try? ActivitySnapshot(from: record)
                    {
                        activities.append(activity)
                    }
                }
            }

            // Sort combined results by date (newest first)
            activities.sort { $0.dateTime > $1.dateTime }

            // Apply overall limit
            if activities.count > resultsLimit {
                activities = Array(activities.prefix(resultsLimit))
            }
        } else {
            // Private database - query from custom app zone (matches iOS app)
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)

            let (matchResults, _) = try await retryableRequest(operation: "fetchRecentActivities(private)") {
                try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: nil,
                    resultsLimit: resultsLimit
                )
            }

            activities = matchResults.compactMap { _, result in
                try? ActivitySnapshot(from: result.get())
            }
        }

        logger.info("✅ Loaded \(activities.count) recent activities (capped at \(Self.maxActivitiesPerCaree))")
        MemoryMonitor.logMemoryUsage(
            context: "After fetchRecentActivities",
            objectCount: activities.count,
            objectType: "activities"
        )

        return activities
    }

    func fetchCareeImage(for careeID: UUID, zoneName: String, zoneOwnerName: String?, isShared: Bool) async throws -> Data? {
        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        let zoneID: CKRecordZone.ID
        if isShared {
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }
            guard let matchedZone = zones.first(where: { zone in
                zone.zoneID.zoneName == zoneName &&
                    (zoneOwnerName == nil || zone.zoneID.ownerName == zoneOwnerName)
            }) else {
                logger.warning("⚠️ Shared zone \(zoneName) not found when fetching caree image")
                return nil
            }
            zoneID = matchedZone.zoneID
        } else {
            zoneID = CKRecordZone.ID(zoneName: zoneName)
        }

        let recordID = CKRecord.ID(recordName: "CD_Caree/\(careeID.uuidString)", zoneID: zoneID)

        return try await retryableRequest(operation: "fetchCareeImage") {
            let record = try await database.record(for: recordID)
            if let asset = record["CD_image_ckAsset"] as? CKAsset,
               let url = asset.fileURL
            {
                return try Data(contentsOf: url)
            }
            return nil
        }
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

        var count = 0

        if isShared {
            // Shared database requires zone-specific queries
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                let (
                    matchResults,
                    _
                ) = try await retryableRequest(operation: "fetchActivityTypeCount(zone: \(zone.zoneID.zoneName))") {
                    try await database.records(
                        matching: query,
                        inZoneWith: zone.zoneID,
                        desiredKeys: [],
                        resultsLimit: 1000
                    )
                }

                count += matchResults.count
            }
        } else {
            // Private database - query from custom app zone (matches iOS app)
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)

            let (matchResults, _) = try await retryableRequest(operation: "fetchActivityTypeCount(private)") {
                try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: [],
                    resultsLimit: 1000
                )
            }

            count = matchResults.count
        }

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
        logger.info("📝 Creating activity in CloudKit (isShared: \(isShared))")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Determine the correct zone for this activity
        // - Owned carees: Custom app zone (matches iOS app)
        // - Shared carees: Custom zone (requires discovery)
        let zoneID: CKRecordZone.ID
        if isShared {
            // Find the zone containing this shared caree
            logger.info("🔍 Finding zone for shared caree: \(activity.careeID)")
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }

            var foundZone: CKRecordZone.ID?
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                // Query for the caree in this zone
                let careeRecordName = "CD_Caree/\(activity.careeID.uuidString)"
                let careeRecordID = CKRecord.ID(recordName: careeRecordName, zoneID: zone.zoneID)

                do {
                    _ = try await database.record(for: careeRecordID)
                    foundZone = zone.zoneID
                    logger.info("✅ Found caree in zone: \(zone.zoneID.zoneName)")
                    break
                } catch {
                    // Caree not in this zone, continue searching
                }
            }

            guard let zone = foundZone else {
                throw SnapshotError.invalidInput("Shared caree \(activity.careeID) not found in any zone")
            }
            zoneID = zone
        } else {
            // Owned carees are in the custom app zone (matches iOS app)
            zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
        }

        // Create CKRecord in the correct zone
        let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "CD_Activity", recordID: recordID)

        // Set fields (CD_id required by SwiftData CloudKit schema)
        record["CD_id"] = activity.id.uuidString
        record["CD_dateTime"] = activity.dateTime
        record["CD_notes"] = activity.notes
        record["CD_quantity"] = activity.quantity
        record["CD_latitude"] = activity.latitude
        record["CD_longitude"] = activity.longitude
        record["CD_dateCreated"] = activity.dateCreated

        // Creator tracking (for notification filtering and shared activity attribution)
        record["CD_creatorUserRecordID"] = CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName

        // Set references (in the same zone)
        let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(activity.careeID.uuidString)", zoneID: zoneID)
        record["CD_caree"] = CKRecord.Reference(recordID: careeRecordID, action: .none)

        let typeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activity.activityTypeID.uuidString)", zoneID: zoneID)
        record["CD_activityType"] = CKRecord.Reference(recordID: typeRecordID, action: .none)

        // Set parent reference for sharing hierarchy (in the same zone)
        record.parent = CKRecord.Reference(recordID: careeRecordID, action: .none)

        // Save to CloudKit with retry
        _ = try await retryableRequest(operation: "createActivity") {
            try await database.save(record)
        }

        logger.info("✅ Activity created successfully")

        // Return updated snapshot with synced state
        var updatedActivity = activity
        updatedActivity.syncState = .synced
        return updatedActivity
    }

    /// Update an existing activity record in CloudKit
    /// - Parameters:
    ///   - activity: Activity snapshot with updated values
    ///   - isShared: Whether this belongs to a shared caree
    /// - Returns: Updated snapshot with synced state
    func updateActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot {
        logger.info("📝 Updating activity in CloudKit: \(activity.id) (isShared: \(isShared))")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Determine the correct zone for this activity
        // - Owned activities: Custom app zone (matches iOS app)
        // - Shared activities: Custom zone (requires discovery)
        let recordID: CKRecord.ID
        if isShared {
            // Find the zone containing this shared activity
            logger.info("🔍 Finding zone for shared activity: \(activity.id)")
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }

            var foundRecordID: CKRecord.ID?
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                let testRecordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zone.zoneID)
                do {
                    _ = try await database.record(for: testRecordID)
                    foundRecordID = testRecordID
                    logger.info("✅ Found activity in zone: \(zone.zoneID.zoneName)")
                    break
                } catch {
                    // Activity not in this zone, continue searching
                }
            }

            guard let found = foundRecordID else {
                throw SnapshotError.invalidInput("Shared activity \(activity.id) not found in any zone")
            }
            recordID = found
        } else {
            // Owned activities are in the custom app zone (matches iOS app)
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
            recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
        }

        // Fetch existing record with retry
        let record = try await retryableRequest(operation: "fetchActivity") {
            try await database.record(for: recordID)
        }

        // Update editable fields
        record["CD_dateTime"] = activity.dateTime
        record["CD_notes"] = activity.notes
        record["CD_quantity"] = activity.quantity
        // Note: latitude/longitude are not editable

        // Save to CloudKit with retry
        _ = try await retryableRequest(operation: "updateActivity") {
            try await database.save(record)
        }

        logger.info("✅ Activity updated successfully")

        // Return updated snapshot with synced state
        var updatedActivity = activity
        updatedActivity.syncState = .synced
        return updatedActivity
    }

    /// Delete an existing activity record from CloudKit
    /// - Parameters:
    ///   - activity: Activity snapshot to delete
    ///   - isShared: Whether this belongs to a shared caree
    func deleteActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws {
        logger.info("🗑️ Deleting activity from CloudKit: \(activity.id) (isShared: \(isShared))")

        let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

        // Determine the correct zone for this activity
        // - Owned activities: Custom app zone (matches iOS app)
        // - Shared activities: Custom zone (requires discovery)
        let recordID: CKRecord.ID
        if isShared {
            // Find the zone containing this shared activity
            logger.info("🔍 Finding zone for shared activity: \(activity.id)")
            let zones = try await retryableRequest(operation: "fetchSharedZones") {
                try await database.allRecordZones()
            }

            var foundRecordID: CKRecord.ID?
            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                let testRecordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zone.zoneID)
                do {
                    _ = try await database.record(for: testRecordID)
                    foundRecordID = testRecordID
                    logger.info("✅ Found activity in zone: \(zone.zoneID.zoneName)")
                    break
                } catch {
                    // Activity not in this zone, continue searching
                }
            }

            guard let found = foundRecordID else {
                throw SnapshotError.invalidInput("Shared activity \(activity.id) not found in any zone")
            }
            recordID = found
        } else {
            // Owned activities are in the custom app zone (matches iOS app)
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
            recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
        }

        // Delete from CloudKit with retry
        _ = try await retryableRequest(operation: "deleteActivity") {
            try await database.deleteRecord(withID: recordID)
        }

        logger.info("✅ Activity deleted successfully")
    }
}
