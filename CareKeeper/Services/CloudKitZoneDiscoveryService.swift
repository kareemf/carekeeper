import Foundation
import CloudKit
import os.log

/// Shared zone discovery logic for CloudKit shared database operations
/// Finds zones containing specific records (carees, activity types, activities)
@MainActor
class CloudKitZoneDiscoveryService {

    // MARK: - Properties

    private let container: CKContainer
    private let logger: Logger
    private let retryService: CloudKitRetryService

    // Simple cache to avoid repeated zone queries within a short timeframe
    private var zoneCache: [String: CKRecordZone.ID] = [:]
    private var zoneCacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    init(
        containerIdentifier: String = CloudKitConfig.containerID,
        retryService: CloudKitRetryService = CloudKitRetryService()
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "zone-discovery")
        self.retryService = retryService
    }

    // MARK: - Zone Discovery

    /// Find the zone containing a specific caree record
    /// - Parameter careeID: UUID of the caree to find
    /// - Returns: Zone ID if found, nil otherwise
    func findZone(for careeID: UUID) async throws -> CKRecordZone.ID? {
        // Check cache first
        if let cachedZone = getCachedZone(for: careeID) {
            logger.info("✅ Using cached zone for caree: \(careeID)")
            return cachedZone
        }

        let sharedDatabase = container.sharedCloudDatabase

        // Fetch all zones
        let zones = try await retryService.retryableRequest(operation: "fetchSharedZones") {
            try await sharedDatabase.allRecordZones()
        }

        logger.info("🔍 Searching \(zones.count) zones for caree: \(careeID)")

        // Search each zone for the caree
        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                continue
            }

            let query = CKQuery(
                recordType: "CD_Caree",
                predicate: NSPredicate(format: "CD_id == %@", careeID.uuidString)
            )

            do {
                let (results, _) = try await sharedDatabase.records(matching: query, inZoneWith: zone.zoneID)
                if !results.isEmpty {
                    logger.info("✅ Found caree in zone: \(zone.zoneID.zoneName)")
                    cacheZone(zone.zoneID, for: careeID)
                    return zone.zoneID
                }
            } catch {
                logger.warning("⚠️ Failed to query zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
            }
        }

        logger.warning("⚠️ Caree \(careeID) not found in any zone")
        return nil
    }

    /// Find the zone containing a specific activity record
    /// - Parameter activityID: UUID of the activity to find
    /// - Returns: Zone ID if found, nil otherwise
    func findZone(for activityID: UUID) async throws -> CKRecordZone.ID? {
        // Check cache first
        if let cachedZone = getCachedZone(for: activityID) {
            logger.info("✅ Using cached zone for activity: \(activityID)")
            return cachedZone
        }

        let sharedDatabase = container.sharedCloudDatabase

        // Fetch all zones
        let zones = try await retryService.retryableRequest(operation: "fetchSharedZones") {
            try await sharedDatabase.allRecordZones()
        }

        logger.info("🔍 Searching \(zones.count) zones for activity: \(activityID)")

        // Search each zone for the activity
        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                continue
            }

            // Try to fetch the activity record directly
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activityID.uuidString)", zoneID: zone.zoneID)

            do {
                _ = try await sharedDatabase.record(for: recordID)
                logger.info("✅ Found activity in zone: \(zone.zoneID.zoneName)")
                cacheZone(zone.zoneID, for: activityID)
                return zone.zoneID
            } catch {
                // Activity not in this zone, continue searching
            }
        }

        logger.warning("⚠️ Activity \(activityID) not found in any zone")
        return nil
    }

    /// Find the zone containing a specific activity type record
    /// - Parameter activityTypeID: UUID of the activity type to find
    /// - Returns: Zone ID if found, nil otherwise
    func findZone(forActivityType activityTypeID: UUID) async throws -> CKRecordZone.ID? {
        // Check cache first
        if let cachedZone = getCachedZone(for: activityTypeID) {
            logger.info("✅ Using cached zone for activity type: \(activityTypeID)")
            return cachedZone
        }

        let sharedDatabase = container.sharedCloudDatabase

        // Fetch all zones
        let zones = try await retryService.retryableRequest(operation: "fetchSharedZones") {
            try await sharedDatabase.allRecordZones()
        }

        logger.info("🔍 Searching \(zones.count) zones for activity type: \(activityTypeID)")

        // Search each zone for the activity type
        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                continue
            }

            // Try to fetch the activity type record directly
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityTypeID.uuidString)", zoneID: zone.zoneID)

            do {
                _ = try await sharedDatabase.record(for: recordID)
                logger.info("✅ Found activity type in zone: \(zone.zoneID.zoneName)")
                cacheZone(zone.zoneID, for: activityTypeID)
                return zone.zoneID
            } catch {
                // Activity type not in this zone, continue searching
            }
        }

        logger.warning("⚠️ Activity type \(activityTypeID) not found in any zone")
        return nil
    }

    // MARK: - Cache Management

    private func cacheZone(_ zoneID: CKRecordZone.ID, for id: UUID) {
        // Invalidate cache if too old
        if let timestamp = zoneCacheTimestamp, Date().timeIntervalSince(timestamp) > cacheTTL {
            logger.info("🧹 Zone cache expired, clearing")
            zoneCache.removeAll()
        }

        zoneCache[id.uuidString] = zoneID
        zoneCacheTimestamp = Date()
    }

    private func getCachedZone(for id: UUID) -> CKRecordZone.ID? {
        // Check if cache is valid
        if let timestamp = zoneCacheTimestamp, Date().timeIntervalSince(timestamp) > cacheTTL {
            logger.info("🧹 Zone cache expired, clearing")
            zoneCache.removeAll()
            zoneCacheTimestamp = nil
            return nil
        }

        return zoneCache[id.uuidString]
    }

    /// Clear the zone cache (useful when zones may have changed)
    func clearCache() {
        logger.info("🧹 Manually clearing zone cache")
        zoneCache.removeAll()
        zoneCacheTimestamp = nil
    }
}
