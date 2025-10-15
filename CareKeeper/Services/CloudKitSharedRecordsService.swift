import SwiftUI
import SwiftData
import CloudKit

/// Service for fetching shared CloudKit records using zone-based queries
/// Queries all zones in the shared database to discover carees shared with the user
@MainActor
class CloudKitSharedRecordsService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let logger = AppLogger.cloudkit

    var cacheService: LocalCacheService?

    @Published var sharedCarees: [Caree] = []
    @Published var sharesByCareeID: [UUID: CKShare] = [:]
    @Published var isLoading = false
    @Published var error: Error?

    init() {
        setupNotificationObservers()
    }

    func setCacheService(_ cacheService: LocalCacheService) {
        self.cacheService = cacheService
    }

    /// Setup notification observers for automatic refresh on CloudKit changes
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitNotificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let ckNotification = notification.object as? CKNotification {
                self?.logger.info("🔔 CloudKit notification received - refreshing shared carees")
                Task {
                    await self?.handleCloudKitNotification(ckNotification)
                }
            }
        }
    }

    /// Handle CloudKit notifications by refreshing the shared carees list
    /// Also presents user-facing notifications for new activities from other users
    private func handleCloudKitNotification(_ notification: CKNotification) async {
        logger.info("📨 Processing CloudKit notification: \(notification.notificationType.rawValue)")

        // Handle query notifications for new activities (user-facing alerts)
        if let queryNotification = notification as? CKQueryNotification,
           queryNotification.queryNotificationReason == .recordCreated {
            await handleNewActivityNotification(queryNotification)
        }

        // For any CloudKit change, refresh the shared carees
        await fetchSharedCarees()
    }

    /// Handle query notifications for new activities
    private func handleNewActivityNotification(_ queryNotification: CKQueryNotification) async {
        logger.info("🔔 New activity query notification received")

        guard let recordID = queryNotification.recordID,
              recordID.recordName.hasPrefix("CD_Activity/") else {
            logger.warning("⚠️ Query notification is not for a CD_Activity record")
            return
        }

        do {
            let sharedDatabase = container.sharedCloudDatabase
            let record = try await sharedDatabase.record(for: recordID)

            let creatorID = record["CD_creatorUserRecordID"] as? String
            let currentUserID = CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName
            if creatorID == currentUserID { return }

            guard let cdId = record["CD_id"] as? String,
                  let activityID = UUID(uuidString: cdId),
                  let dateTime = record["CD_dateTime"] as? Date else {
                logger.warning("⚠️ Activity record missing required fields")
                return
            }

            guard let careeReference = record["CD_caree"] as? CKRecord.Reference,
                  let careeIDFromRef = careeReference.recordID.recordName.components(separatedBy: "/").last,
                  let careeID = UUID(uuidString: careeIDFromRef) else {
                logger.warning("⚠️ Could not extract caree ID from activity")
                return
            }

            let prefs = UserNotificationPreferences.shared
            guard prefs.isEnabled(for: careeID) else { return }

            let careeRecord = try await sharedDatabase.record(for: careeReference.recordID)
            let careeName = careeRecord["CD_name"] as? String ?? "Unknown"

            var activityTypeName = "Activity"
            if let activityTypeRef = record["CD_activityType"] as? CKRecord.Reference {
                if let activityTypeRecord = try? await sharedDatabase.record(for: activityTypeRef.recordID) {
                    activityTypeName = activityTypeRecord["CD_name"] as? String ?? "Activity"
                }
            }

            let notificationService = UserNotificationService.shared
            await notificationService.presentNewActivityNotification(
                activityID: activityID,
                careeID: careeID,
                careeName: careeName,
                activityTypeName: activityTypeName,
                creatorName: "Another caregiver",
                timestamp: dateTime
            )

        } catch {
            logger.error("❌ Failed to handle activity notification: \(error.localizedDescription)")
        }
    }

    /// Fetch shared Caree records with their ActivityTypes and Activities using zone-based discovery
    func fetchSharedCarees() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let sharedDatabase = container.sharedCloudDatabase

            // Step 1: Fetch all zones in the shared database
            let zones = try await sharedDatabase.allRecordZones()
            logger.info("📱 Found \(zones.count, privacy: .public) shared zones")

            for zone in zones {
                logger.info("   Zone: \(zone.zoneID.zoneName, privacy: .public) (owner: \(zone.zoneID.ownerName, privacy: .public))")
            }

            if zones.isEmpty {
                await MainActor.run {
                    self.sharedCarees = []
                    self.sharesByCareeID = [:]
                    self.isLoading = false
                }
                await applySharedResultsToCache([])
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
                return
            }

            // Step 2: Query each zone
            var allCareeRecords: [CKRecord] = []
            var allActivityTypeRecords: [CKRecord] = []
            var allActivityRecords: [CKRecord] = []
            var shares: [UUID: CKShare] = [:]

            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                logger.info("🔍 Querying zone: \(zone.zoneID.zoneName, privacy: .public)")

                // Carees
                do {
                    let careeQuery = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
                    let (matchResults, _) = try await sharedDatabase.records(matching: careeQuery, inZoneWith: zone.zoneID)
                    for (_, result) in matchResults {
                        switch result {
                        case .success(let record):
                            allCareeRecords.append(record)
                            logger.info("  ✅ Found caree: \(record["CD_name"] as? String ?? "unknown")")
                            if let shareReference = record.share {
                                do {
                                    let shareRecord = try await sharedDatabase.record(for: shareReference.recordID)
                                    if let share = shareRecord as? CKShare,
                                       let cdId = record["CD_id"] as? String,
                                       let uuid = UUID(uuidString: cdId) {
                                        shares[uuid] = share
                                        logger.info("    📎 Fetched share for caree: \(uuid)")
                                    }
                                } catch {
                                    logger.warning("    ⚠️ Failed to fetch share: \(error.localizedDescription)")
                                }
                            }
                        case .failure(let error):
                            logger.warning("  ⚠️ Failed to fetch caree record: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    logger.warning("  ⚠️ Failed to query carees in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                }

                // ActivityTypes
                do {
                    let activityTypeQuery = CKQuery(recordType: "CD_ActivityType", predicate: NSPredicate(value: true))
                    let (matchResults, _) = try await sharedDatabase.records(matching: activityTypeQuery, inZoneWith: zone.zoneID)
                    for (_, result) in matchResults {
                        switch result {
                        case .success(let record):
                            allActivityTypeRecords.append(record)
                            logger.info("  ✅ Found activity type: \(record["CD_name"] as? String ?? "unknown")")
                        case .failure(let error):
                            logger.warning("  ⚠️ Failed to fetch activity type record: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    logger.warning("  ⚠️ Failed to query activity types in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                }

                // Activities
                do {
                    let activityQuery = CKQuery(recordType: "CD_Activity", predicate: NSPredicate(value: true))
                    let (matchResults, _) = try await sharedDatabase.records(matching: activityQuery, inZoneWith: zone.zoneID)
                    for (_, result) in matchResults {
                        switch result {
                        case .success(let record):
                            allActivityRecords.append(record)
                            logger.info("  ✅ Found activity at: \(record["CD_dateTime"] as? Date ?? Date())")
                        case .failure(let error):
                            logger.warning("  ⚠️ Failed to fetch activity record: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    logger.warning("  ⚠️ Failed to query activities in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                }
            }

            // Step 3: Convert to objects with relationships
            let carees = try await convertRecordsToCarees(
                allCareeRecords,
                activityTypeRecords: allActivityTypeRecords,
                activityRecords: allActivityRecords
            )

            await MainActor.run {
                self.sharedCarees = carees
                self.sharesByCareeID = shares
                self.isLoading = false
                logger.info("✅ Successfully fetched \(carees.count, privacy: .public) shared carees with \(shares.count, privacy: .public) shares")
            }

            // Step 4: Push results into LocalCacheService so UI updates automatically
            await applySharedResultsToCache(carees)
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)

        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
                logger.error("❌ Failed to fetch shared carees: \(error.localizedDescription)")
            }
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
        }
    }

    private func convertRecordsToCarees(
        _ careeRecords: [CKRecord],
        activityTypeRecords: [CKRecord],
        activityRecords: [CKRecord]
    ) async throws -> [Caree] {
        var careesByID: [UUID: Caree] = [:]
        var activityTypesByID: [UUID: ActivityType] = [:]

        for record in careeRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String else {
                logger.warning("⚠️ Skipping caree record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let caree = Caree(name: name, listOrder: record["CD_listOrder"] as? Int ?? 0)
            caree.id = uuid

            if let imageAsset = record["CD_image_ckAsset"] as? CKAsset,
               let imageURL = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageURL) {
                caree.image = imageData
            }

            if let dateCreated = record["CD_dateCreated"] as? Date {
                caree.dateCreated = dateCreated
            }

            careesByID[uuid] = caree
        }

        for record in activityTypeRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String else {
                logger.warning("⚠️ Skipping activity type record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let hasQuantityInt = record["CD_hasQuantity"] as? Int ?? 0
            let hasLocationInt = record["CD_hasLocation"] as? Int ?? 0

            let activityType = ActivityType(
                name: name,
                icon: record["CD_icon"] as? String,
                hasQuantity: hasQuantityInt != 0,
                quantityUnit: record["CD_quantityUnit"] as? String,
                hasLocation: hasLocationInt != 0,
                listOrder: record["CD_listOrder"] as? Int ?? 0
            )
            activityType.id = uuid

            if let dateCreated = record["CD_dateCreated"] as? Date {
                activityType.dateCreated = dateCreated
            }

            if let careeReference = record["CD_caree"] as? CKRecord.Reference,
               let careeIDString = careeReference.recordID.recordName.components(separatedBy: "/").last,
               let careeUUID = UUID(uuidString: careeIDString),
               let caree = careesByID[careeUUID] {
                activityType.caree = caree
                if caree.activityTypes == nil { caree.activityTypes = [] }
                caree.activityTypes?.append(activityType)
            }

            activityTypesByID[uuid] = activityType
        }

        for record in activityRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let dateTime = record["CD_dateTime"] as? Date else {
                logger.warning("⚠️ Skipping activity record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let activity = Activity(
                dateTime: dateTime,
                notes: record["CD_notes"] as? String,
                quantity: record["CD_quantity"] as? Double,
                latitude: record["CD_latitude"] as? Double,
                longitude: record["CD_longitude"] as? Double
            )
            activity.id = uuid

            if let dateCreated = record["CD_dateCreated"] as? Date {
                activity.dateCreated = dateCreated
            }

            if let activityTypeReference = record["CD_activityType"] as? CKRecord.Reference,
               let activityTypeIDString = activityTypeReference.recordID.recordName.components(separatedBy: "/").last,
               let activityTypeUUID = UUID(uuidString: activityTypeIDString),
               let activityType = activityTypesByID[activityTypeUUID] {
                activity.activityType = activityType
                if activityType.activities == nil { activityType.activities = [] }
                activityType.activities?.append(activity)
            }

            if let careeReference = record["CD_caree"] as? CKRecord.Reference,
               let careeIDString = careeReference.recordID.recordName.components(separatedBy: "/").last,
               let careeUUID = UUID(uuidString: careeIDString),
               let caree = careesByID[careeUUID] {
                activity.caree = caree
                if caree.activities == nil { caree.activities = [] }
                caree.activities?.append(activity)
            }
        }

        return Array(careesByID.values).sorted { $0.listOrder < $1.listOrder }
    }

    private func applySharedResultsToCache(_ carees: [Caree]) async {
        guard let cacheService = cacheService else {
            logger.info("ℹ️ No cacheService injected; skipping cache update.")
            return
        }

        await cacheService.withBatch {
            // Remove any previously cached shared carees that are no longer present.
            let fetchedIDs = Set(carees.map { $0.id })
            let existingShared = cacheService.sharedCarees
            for cached in existingShared where !fetchedIDs.contains(cached.id) {
                do {
                    logger.info("🧹 Removing unshared/deleted caree from cache: \(cached.name)")
                    try await cacheService.removeCachedCaree(cached)
                } catch {
                    logger.warning("⚠️ Failed removing cached caree: \(error.localizedDescription)")
                }
            }

            // Upsert fetched carees and their children.
            for caree in carees {
                do {
                    try await cacheService.cacheCaree(caree, isShared: true)
                    for activityType in (caree.activityTypes ?? []) {
                        try await cacheService.cacheActivityType(activityType, for: caree)
                    }
                    for activity in (caree.activities ?? []) {
                        if let activityType = activity.activityType {
                            try await cacheService.cacheActivity(activity, for: caree, activityType: activityType)
                        }
                    }
                } catch {
                    logger.warning("⚠️ Failed caching shared records: \(error.localizedDescription)")
                }
            }
        }

        // No direct refreshPublishedProperties() here; the batch will coalesce refresh.
    }
}
