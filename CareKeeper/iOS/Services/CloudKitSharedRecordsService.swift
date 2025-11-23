import CloudKit
import SwiftData
import SwiftUI

/// Service for fetching shared CloudKit records using zone-based queries
/// Queries all zones in the shared database to discover carees shared with the user
@MainActor
class CloudKitSharedRecordsService: ObservableObject {
    private let container: CKContainer
    private let logger = AppLogger.cloudkit
    private let reminderMetadataStore: any ReminderMetadataStoreProtocol
    private let changeTokenStore = SharedZoneChangeTokenStore()
    private let fetchDebounceInterval: TimeInterval = 0.25

    private var sharedFetchTask: Task<Void, Never>?
    private var pendingSharedFetch = false
    private var pendingSharedFetchForce = false
    private var lastSharedFetchRequestedAt: Date?

    var cacheService: LocalCacheService?

    @Published var sharedCarees: [Caree] = []
    @Published var sharesByCareeID: [UUID: CKShare] = [:]
    @Published var isLoading = false
    @Published var error: Error?

    init(
        container: CKContainer = CKContainer(identifier: CloudKitConfig.containerID),
        reminderMetadataStore: (any ReminderMetadataStoreProtocol)? = nil
    ) {
        self.container = container
        self.reminderMetadataStore = reminderMetadataStore ?? ActivityReminderMetadataStore.shared
        setupNotificationObservers()
    }

    func setCacheService(_ cacheService: LocalCacheService) {
        self.cacheService = cacheService
    }

    /// Remove the current user from a shared caree.
    func leaveShare(for caree: Caree) async throws {
        guard let share = sharesByCareeID[caree.id] else {
            throw AppError.invalidInput("Share metadata not found for this caree. Please refresh and try again.")
        }

        do {
            try await container.sharedCloudDatabase.deleteRecord(withID: share.recordID)
            logger.info("✅ Left share for caree: \(caree.id)")

            if let cacheService,
               let cached = cacheService.sharedCarees.first(where: { $0.id == caree.id })
            {
                do {
                    try await cacheService.removeCachedCaree(cached)
                } catch {
                    logger.warning("⚠️ Failed to remove cached caree after leaving share: \(error.localizedDescription)")
                }
            }

            sharesByCareeID[caree.id] = nil
            sharedCarees.removeAll { $0.id == caree.id }

            NotificationCenter.default.post(name: NSNotification.Name("SharedCareeDataUpdated"), object: caree.id)

            Task {
                await self.fetchSharedCarees()
            }
        } catch {
            logger.error("❌ Failed to leave share: \(error.localizedDescription)")
            throw AppError.deleteFailed("Could not leave this shared caree. \(error.localizedDescription)")
        }
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

        if let zoneNotification = notification as? CKRecordZoneNotification,
           zoneNotification.databaseScope == .shared
        {
            await handleSharedZoneNotification(zoneNotification)
        }

        // Handle query notifications for new activities (user-facing alerts)
        if let queryNotification = notification as? CKQueryNotification,
           queryNotification.queryNotificationReason == .recordCreated
        {
            await handleNewActivityNotification(queryNotification)
        }

        // For any CloudKit change, refresh the shared carees
        await fetchSharedCarees(force: true, reason: "cloudkit-notification")
    }

    /// Handle query notifications for new activities
    private func handleNewActivityNotification(_ queryNotification: CKQueryNotification) async {
        logger.info("🔔 New activity query notification received")

        guard let recordID = queryNotification.recordID,
              recordID.recordName.hasPrefix("CD_Activity/")
        else {
            logger.warning("⚠️ Query notification is not for a CD_Activity record")
            return
        }

        do {
            let database: CKDatabase
            switch queryNotification.databaseScope {
            case .shared:
                database = container.sharedCloudDatabase
            case .private:
                database = container.privateCloudDatabase
            default:
                logger
                    .warning(
                        "⚠️ Unsupported database scope for activity notification: \(queryNotification.databaseScope.rawValue)"
                    )
                return
            }

            let record = try await database.record(for: recordID)

            let creatorIDField = record["CD_creatorUserRecordID"] as? String
            let creatorRecordID = record.creatorUserRecordID?.recordName
            let creatorID = creatorIDField ?? creatorRecordID
            let currentUserID = CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName
            if creatorID == currentUserID { return }

            guard let cdId = record["CD_id"] as? String,
                  let activityID = UUID(uuidString: cdId),
                  let dateTime = record["CD_dateTime"] as? Date
            else {
                logger.warning("⚠️ Activity record missing required fields")
                return
            }

            guard let careeReference = record["CD_caree"] as? CKRecord.Reference,
                  let careeIDFromRef = careeReference.recordID.recordName.components(separatedBy: "/").last,
                  let careeID = UUID(uuidString: careeIDFromRef)
            else {
                logger.warning("⚠️ Could not extract caree ID from activity")
                return
            }

            let prefs = UserNotificationPreferences.shared
            guard prefs.isEnabled(for: careeID) else { return }

            let careeRecord = try await database.record(for: careeReference.recordID)
            let careeName = careeRecord["CD_name"] as? String ?? "Unknown"

            var activityTypeName = "Activity"
            if let activityTypeRef = record["CD_activityType"] as? CKRecord.Reference {
                if let activityTypeRecord = try? await database.record(for: activityTypeRef.recordID) {
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

    func handleSharedZoneNotification(_ notification: CKRecordZoneNotification) async {
        guard let zoneID = notification.recordZoneID else {
            logger.warning("⚠️ Zone notification missing zone ID")
            return
        }

        let existingActivityIDs: Set<UUID> = Set(
            sharedCarees
                .flatMap { $0.activities ?? [] }
                .map(\.id)
        )

        await fetchSharedChanges(for: zoneID, existingActivityIDs: existingActivityIDs)
        await fetchSharedCarees(force: true, reason: "zone-notification")
    }

    func fetchSharedChanges(for zoneID: CKRecordZone.ID, existingActivityIDs: Set<UUID>) async {
        logger.info("🔁 Fetching shared zone changes for \(zoneID.zoneName, privacy: .public)")

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = changeTokenStore.token(for: zoneID)
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config]
        )

        var newActivityRecords: [CKRecord] = []
        var fetchError: Error?
        var mutableExistingIDs = existingActivityIDs

        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case let .success(record):
                if record.recordType == "CD_Activity" {
                    newActivityRecords.append(record)
                }
            case let .failure(error):
                self.logger.warning("⚠️ Failed record change for \(recordID.recordName, privacy: .public): \(error.localizedDescription)")
            }
        }

        operation.recordZoneChangeTokensUpdatedBlock = { [self] zoneID, token, _ in
            if let token {
                logger.debug("🔁 Token updated during shared change fetch for \(zoneID.zoneName, privacy: .public)")
            }
        }

        operation.recordZoneFetchResultBlock = { [self] zoneID, result in
            switch result {
            case let .success(fetchResult):
                if let token = fetchResult.serverChangeToken {
                    logger.debug("🔁 Token received during shared change fetch for \(zoneID.zoneName, privacy: .public)")
                }
            case let .failure(error):
                fetchError = error
            }
        }

        await withCheckedContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { _ in
                continuation.resume()
            }
            container.sharedCloudDatabase.add(operation)
        }

        if let error = fetchError {
            if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                logger.warning("⚠️ Change token expired for zone \(zoneID.zoneName, privacy: .public); clearing token")
                changeTokenStore.clear(for: zoneID)
            } else {
                logger.error("❌ Failed fetching shared zone changes: \(error.localizedDescription)")
            }
            return
        }

        for record in newActivityRecords {
            guard
                let cdId = record["CD_id"] as? String,
                let activityID = UUID(uuidString: cdId)
            else {
                logger.warning("⚠️ Activity record missing CD_id")
                continue
            }

            if mutableExistingIDs.contains(activityID) {
                continue
            }

            if await notifyForActivityRecord(record) {
                mutableExistingIDs.insert(activityID)
            }
        }
    }

    @discardableResult
    func notifyForActivityRecord(_ record: CKRecord) async -> Bool {
        let creatorIDField = record["CD_creatorUserRecordID"] as? String
        let creatorRecordID = record.creatorUserRecordID?.recordName
        let creatorID = creatorIDField ?? creatorRecordID
        let currentUserID = CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName
        if creatorID == currentUserID { return false }

        guard
            let cdId = record["CD_id"] as? String,
            let activityID = UUID(uuidString: cdId),
            let dateTime = record["CD_dateTime"] as? Date
        else {
            logger.warning("⚠️ Activity record missing required fields")
            return false
        }

        guard
            let careeReference = record["CD_caree"] as? CKRecord.Reference,
            let careeIDFromRef = careeReference.recordID.recordName.components(separatedBy: "/").last,
            let careeID = UUID(uuidString: careeIDFromRef)
        else {
            logger.warning("⚠️ Could not extract caree ID from activity")
            return false
        }

        let prefs = UserNotificationPreferences.shared
        guard prefs.isEnabled(for: careeID) else { return false }

        do {
            let database = container.sharedCloudDatabase
            let careeRecord = try await database.record(for: careeReference.recordID)
            let careeName = careeRecord["CD_name"] as? String ?? "Unknown"

            var activityTypeName = "Activity"
            if let activityTypeRef = record["CD_activityType"] as? CKRecord.Reference {
                if let activityTypeRecord = try? await database.record(for: activityTypeRef.recordID) {
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
            return true
        } catch {
            logger.error("❌ Failed to present activity notification: \(error.localizedDescription)")
            return false
        }
    }

    func fetchSharedCarees() async {
        await fetchSharedCarees(force: false, reason: "manual")
    }

    /// Debounced/concurrency-guarded entry point for shared refreshes (mirrors LocalCacheService.scheduleRefresh pattern).
    func fetchSharedCarees(force: Bool, reason: String) async {
        // Short debounce to coalesce bursty triggers (push + manual refresh).
        if let last = lastSharedFetchRequestedAt {
            let delta = Date().timeIntervalSince(last)
            if delta < fetchDebounceInterval {
                let remaining = fetchDebounceInterval - delta
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastSharedFetchRequestedAt = Date()

        if let task = sharedFetchTask {
            // Another fetch is running; queue one follow-up and optionally upgrade to force.
            pendingSharedFetch = true
            pendingSharedFetchForce = pendingSharedFetchForce || force
            await task.value

            if pendingSharedFetch {
                let nextForce = pendingSharedFetchForce
                pendingSharedFetch = false
                pendingSharedFetchForce = false
                await fetchSharedCarees(force: nextForce, reason: "coalesced-\(reason)")
            }
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSharedFetch(force: force, reason: reason)
        }
        sharedFetchTask = task
        await task.value
        sharedFetchTask = nil
    }

    /// Fetch shared Caree records with their ActivityTypes and Activities using zone-based discovery
    private func performSharedFetch(force: Bool, reason: String) async {
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
                logger
                    .info(
                        "   Zone: \(zone.zoneID.zoneName, privacy: .public) (owner: \(zone.zoneID.ownerName, privacy: .public))"
                    )
            }

            if zones.isEmpty {
                await MainActor.run {
                    self.sharedCarees = []
                    self.sharesByCareeID = [:]
                    self.isLoading = false
                }
                await applySharedResultsToCache(
                    [],
                    activityTypesByCaree: [:],
                    activitiesByCaree: [:],
                    activityTypeIDByActivity: [:]
                )
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
                return
            }

            await ensureSharedZoneSubscriptions(zones)

            // Step 1.5: Use change tokens to skip work when nothing changed unless forced.
            var zonesWithChanges: [CKRecordZone.ID] = []
            var pendingTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]
            for zone in zones where zone.zoneID.zoneName != CKRecordZone.ID.defaultZoneName {
                let result = await inspectSharedZoneChanges(zone.zoneID)
                if result.needsFetch {
                    zonesWithChanges.append(zone.zoneID)
                    if let token = result.token {
                        pendingTokens[zone.zoneID] = token
                    }
                } else if let token = result.token {
                    // No changes; token is safe to persist immediately.
                    changeTokenStore.save(token, for: zone.zoneID)
                }
            }

            if zonesWithChanges.isEmpty && !force {
                await MainActor.run {
                    self.isLoading = false
                }
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
                logger.info("⏩ Skipping shared fetch; no changes detected (\(reason, privacy: .public))")
                return
            }

            // Step 2: Query each zone
            var allCareeRecords: [CKRecord] = []
            var allActivityTypeRecords: [CKRecord] = []
            var allActivityRecords: [CKRecord] = []
            var shares: [UUID: CKShare] = [:]
            var zonesWithQueryErrors: Set<CKRecordZone.ID> = []

            for zone in zones {
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName { continue }

                logger.info("🔍 Querying zone: \(zone.zoneID.zoneName, privacy: .public)")

                // Carees
                do {
                    let careeQuery = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
                    let careeRecords = try await fetchAllSharedRecords(
                        query: careeQuery,
                        database: sharedDatabase,
                        zoneID: zone.zoneID,
                        recordType: "shared caree"
                    )

                    for record in careeRecords {
                        allCareeRecords.append(record)
                        logger.info("  ✅ Found caree: \(record["CD_name"] as? String ?? "unknown")")
                        if let shareReference = record.share {
                            do {
                                let shareRecord = try await sharedDatabase.record(for: shareReference.recordID)
                                if let share = shareRecord as? CKShare,
                                   let cdId = record["CD_id"] as? String,
                                   let uuid = UUID(uuidString: cdId)
                                {
                                    shares[uuid] = share
                                    logger.info("    📎 Fetched share for caree: \(uuid)")
                                }
                            } catch {
                                logger.warning("    ⚠️ Failed to fetch share: \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    logger.warning("  ⚠️ Failed to query carees in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                    zonesWithQueryErrors.insert(zone.zoneID)
                }

                // ActivityTypes
                do {
                    let activityTypeQuery = CKQuery(recordType: "CD_ActivityType", predicate: NSPredicate(value: true))
                    let activityTypeRecords = try await fetchAllSharedRecords(
                        query: activityTypeQuery,
                        database: sharedDatabase,
                        zoneID: zone.zoneID,
                        recordType: "shared activity type"
                    )
                    for record in activityTypeRecords {
                        allActivityTypeRecords.append(record)
                        logger.info("  ✅ Found activity type: \(record["CD_name"] as? String ?? "unknown")")
                    }
                } catch {
                    logger
                        .warning(
                            "  ⚠️ Failed to query activity types in zone \(zone.zoneID.zoneName): \(error.localizedDescription)"
                        )
                    zonesWithQueryErrors.insert(zone.zoneID)
                }

                // Activities
                do {
                    let activityQuery = CKQuery(recordType: "CD_Activity", predicate: NSPredicate(value: true))
                    let activityRecords = try await fetchAllSharedRecords(
                        query: activityQuery,
                        database: sharedDatabase,
                        zoneID: zone.zoneID,
                        recordType: "shared activity"
                    )
                    for record in activityRecords {
                        allActivityRecords.append(record)
                        logger.info("  ✅ Found activity at: \(record["CD_dateTime"] as? Date ?? Date())")
                    }
                } catch {
                    logger
                        .warning("  ⚠️ Failed to query activities in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                    zonesWithQueryErrors.insert(zone.zoneID)
                }
            }

            // Step 3: Convert to objects with relationships
            let (carees, activityTypesByCaree, activitiesByCaree, activityTypeIDByActivity) = try await convertRecordsToCarees(
                allCareeRecords,
                activityTypeRecords: allActivityTypeRecords,
                activityRecords: allActivityRecords
            )

            await MainActor.run {
                self.sharedCarees = carees
                self.sharesByCareeID = shares
                self.isLoading = false
                logger
                    .info(
                        "✅ Successfully fetched \(carees.count, privacy: .public) shared carees with \(shares.count, privacy: .public) shares"
                    )
            }

            // Step 4: Push results into LocalCacheService so UI updates automatically
            await applySharedResultsToCache(
                carees,
                activityTypesByCaree: activityTypesByCaree,
                activitiesByCaree: activitiesByCaree,
                activityTypeIDByActivity: activityTypeIDByActivity
            )
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitBackgroundRefreshFinished"), object: nil)
            for (zoneID, token) in pendingTokens where !zonesWithQueryErrors.contains(zoneID) {
                changeTokenStore.save(token, for: zoneID)
            }

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
    ) async throws -> ([Caree], [UUID: [ActivityType]], [UUID: [Activity]], [UUID: UUID]) {
        var careesByID: [UUID: Caree] = [:]
        var activityTypesByCaree: [UUID: [ActivityType]] = [:]
        var activitiesByCaree: [UUID: [Activity]] = [:]
        var activityTypesByID: [UUID: ActivityType] = [:]
        var activityTypeIDByActivity: [UUID: UUID] = [:]

        for record in careeRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String
            else {
                logger.warning("⚠️ Skipping caree record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let caree = Caree(name: name, listOrder: record["CD_listOrder"] as? Int ?? 0)
            caree.id = uuid
            caree.isShared = true
            caree.isOwned = false

            if let imageAsset = record["CD_image_ckAsset"] as? CKAsset,
               let imageURL = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageURL)
            {
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
                  let name = record["CD_name"] as? String
            else {
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
               careesByID[careeUUID] != nil
            {
                activityTypesByCaree[careeUUID, default: []].append(activityType)
            }

            activityTypesByID[uuid] = activityType
        }

        for record in activityRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let dateTime = record["CD_dateTime"] as? Date
            else {
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
               activityTypesByID[activityTypeUUID] != nil
            {
                activityTypeIDByActivity[activity.id] = activityTypeUUID
            }

            if let careeReference = record["CD_caree"] as? CKRecord.Reference,
               let careeIDString = careeReference.recordID.recordName.components(separatedBy: "/").last,
               let careeUUID = UUID(uuidString: careeIDString),
               careesByID[careeUUID] != nil
            {
                activitiesByCaree[careeUUID, default: []].append(activity)
            }
        }

        for (careeID, caree) in careesByID {
            let types = activityTypesByCaree[careeID] ?? []
            caree.activityTypes = types
            let activities = activitiesByCaree[careeID] ?? []
            caree.activities = activities

            for activityType in types {
                activityType.caree = caree
            }

            for activity in activities {
                if let activityTypeID = activityTypeIDByActivity[activity.id],
                   let activityType = activityTypesByID[activityTypeID]
                {
                    activity.activityType = activityType
                    var activitiesForType = activityType.activities ?? []
                    activitiesForType.append(activity)
                    activityType.activities = activitiesForType
                }
                activity.caree = caree
            }
        }

        do {
            let metadata = try await reminderMetadataStore.fetchMetadata(for: Array(activityTypeIDByActivity.keys))
            logger.info("🔔 Overlaying reminder metadata (shared) for \(metadata.count, privacy: .public) activities.")
            applyReminderMetadata(metadata, to: &activitiesByCaree)
        } catch {
            logger.warning("⚠️ Failed to fetch reminder metadata for shared carees: \(error.localizedDescription)")
        }

        let carees = Array(careesByID.values).sorted { $0.listOrder < $1.listOrder }
        return (carees, activityTypesByCaree, activitiesByCaree, activityTypeIDByActivity)
    }

    private func applySharedResultsToCache(
        _ carees: [Caree],
        activityTypesByCaree: [UUID: [ActivityType]],
        activitiesByCaree: [UUID: [Activity]],
        activityTypeIDByActivity: [UUID: UUID]
    ) async {
        guard let cacheService else {
            logger.info("ℹ️ No cacheService injected; skipping cache update.")
            return
        }

        await cacheService.withBatch {
            // Remove any previously cached shared carees that are no longer present.
            let fetchedIDs = Set(carees.map(\.id))
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
                    let cacheCaree = cloneCareeForCaching(caree, isShared: true)
                    let types = activityTypesByCaree[caree.id] ?? []
                    let activities = activitiesByCaree[caree.id] ?? []
                    let mapping = Dictionary(uniqueKeysWithValues: activities.compactMap { activity in
                        activityTypeIDByActivity[activity.id].map { (activity.id, $0) }
                    })

                    try await cacheService.replaceCaree(
                        cacheCaree,
                        activityTypes: types,
                        activities: activities,
                        activityTypeIDsByActivity: mapping
                    )
                } catch {
                    logger.warning("⚠️ Failed caching shared records: \(error.localizedDescription)")
                }
            }
        }

        // No direct refreshPublishedProperties() here; the batch will coalesce refresh.
    }

    private func applyReminderMetadata(
        _ metadata: [UUID: ActivityReminderMetadata],
        to activitiesByCaree: inout [UUID: [Activity]]
    ) {
        guard !metadata.isEmpty else { return }
        logger.info("🔔 Overlaying reminder metadata (shared) for \(metadata.count, privacy: .public) activities")
        for (careeID, activities) in activitiesByCaree {
            let updated = activities.map { activity -> Activity in
                if let entry = metadata[activity.id] {
                    activity.reminderIdentifier = entry.identifier(for: .phone)
                    activity.reminderDueDate = entry.reminderDueDate
                    activity.reminderSource = entry.reminderSource
                }
                return activity
            }
            activitiesByCaree[careeID] = updated
        }
    }

    private func ensureSharedZoneSubscriptions(_ zones: [CKRecordZone]) async {
        let sharedDatabase = container.sharedCloudDatabase
        let existing: [CKSubscription]
        do {
            existing = try await sharedDatabase.allSubscriptions()
        } catch {
            logger.warning("⚠️ Unable to list shared subscriptions: \(error.localizedDescription)")
            return
        }

        for zone in zones where zone.zoneID.zoneName != CKRecordZone.ID.defaultZoneName {
            let subID = "shared-zone-\(zone.zoneID.zoneName)-\(zone.zoneID.ownerName)"
            if existing.contains(where: { $0.subscriptionID == subID }) {
                continue
            }

            let subscription = CKRecordZoneSubscription(zoneID: zone.zoneID, subscriptionID: subID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            info.shouldBadge = false
            subscription.notificationInfo = info

            do {
                _ = try await sharedDatabase.save(subscription)
                logger.info("✅ Created shared zone subscription: \(subID)")
            } catch {
                logger.warning("⚠️ Failed to save shared zone subscription \(subID): \(error.localizedDescription)")
            }
        }
    }

    private struct SharedZoneChangeCheckResult {
        let needsFetch: Bool
        let token: CKServerChangeToken?
    }

    /// Lightweight change check to decide whether to run a full shared fetch and to capture the next token.
    private func inspectSharedZoneChanges(_ zoneID: CKRecordZone.ID) async -> SharedZoneChangeCheckResult {
        var hasChanges = false
        var fetchError: Error?
        var latestToken: CKServerChangeToken?

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = changeTokenStore.token(for: zoneID)
        config.desiredKeys = ["CD_id"]
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config]
        )

        operation.recordWasChangedBlock = { _, result in
            switch result {
            case .success:
                hasChanges = true
            case .failure:
                hasChanges = true // treat error as potential change to force fetch
            }
        }
        operation.recordWasDeletedBlock = { _, _ in
            hasChanges = true
        }
        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            if let token {
                latestToken = token
            }
        }
        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case let .success(fetchResult):
                if let token = fetchResult.serverChangeToken {
                    latestToken = token
                }
            case let .failure(error):
                fetchError = error
            }
        }

        await withCheckedContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { _ in
                continuation.resume()
            }
            container.sharedCloudDatabase.add(operation)
        }

        if let error = fetchError {
            if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                logger.warning("⚠️ Change token expired for zone \(zoneID.zoneName, privacy: .public); clearing token")
                changeTokenStore.clear(for: zoneID)
            } else {
                logger.warning("⚠️ Change check failed for zone \(zoneID.zoneName, privacy: .public); forcing full fetch: \(error.localizedDescription)")
            }
            return SharedZoneChangeCheckResult(needsFetch: true, token: nil)
        }

        // If we have no prior token or no token returned, run a full fetch to establish a baseline.
        let needsBaseline = config.previousServerChangeToken == nil || latestToken == nil
        return SharedZoneChangeCheckResult(needsFetch: hasChanges || needsBaseline, token: latestToken)
    }


    private func cloneCareeForCaching(_ caree: Caree, isShared: Bool) -> Caree {
        let clone = Caree(name: caree.name, image: caree.image, listOrder: caree.listOrder)
        clone.id = caree.id
        clone.dateCreated = caree.dateCreated
        clone.isShared = isShared
        clone.isOwned = !isShared
        clone.lastSyncedAt = caree.lastSyncedAt
        clone.cloudKitRecordID = caree.cloudKitRecordID
        return clone
    }

    private func fetchAllSharedRecords(
        query: CKQuery,
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        recordType: String,
        desiredKeys: [String]? = nil,
        resultsLimit: Int = CKQueryOperation.maximumResults
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var batchIndex = 0

        repeat {
            let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
            let nextCursor: CKQueryOperation.Cursor?

            if let cursor {
                (matchResults, nextCursor) = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: desiredKeys,
                    resultsLimit: resultsLimit
                )
            } else {
                (matchResults, nextCursor) = try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: desiredKeys,
                    resultsLimit: resultsLimit
                )
            }

            for (_, result) in matchResults {
                switch result {
                case let .success(record):
                    records.append(record)
                case let .failure(error):
                    logger.warning("  ⚠️ Failed \(recordType) record fetch: \(error.localizedDescription)")
                }
            }

            batchIndex += 1
            cursor = nextCursor
        } while cursor != nil

        logger
            .info(
                "  📥 Fetched \(records.count) \(recordType) records in zone \(zoneID.zoneName) (\(batchIndex) batch\(batchIndex == 1 ? "" : "es"))"
            )
        return records
    }
}

private struct SharedZoneChangeTokenStore {
    private let defaults = UserDefaults.standard

    func token(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: key(for: zoneID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func save(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return
        }
        defaults.set(data, forKey: key(for: zoneID))
    }

    func clear(for zoneID: CKRecordZone.ID) {
        defaults.removeObject(forKey: key(for: zoneID))
    }

    private func key(for zoneID: CKRecordZone.ID) -> String {
        "sharedZoneToken-\(zoneID.zoneName)-\(zoneID.ownerName)"
    }
}
