import SwiftUI
import SwiftData
import CloudKit

/// Service for fetching shared CloudKit records using zone-based queries
/// Queries all zones in the shared database to discover carees shared with the user
@MainActor
class CloudKitSharedRecordsService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let logger = AppLogger.cloudkit

    @Published var sharedCarees: [Caree] = []
    @Published var sharesByCareeID: [UUID: CKShare] = [:]
    @Published var isLoading = false
    @Published var error: Error?

    init() {
        setupNotificationObservers()
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
    private func handleCloudKitNotification(_ notification: CKNotification) async {
        logger.info("📨 Processing CloudKit notification: \(notification.notificationType.rawValue)")

        // For any CloudKit change, refresh the shared carees
        // The zone-based query will automatically reflect the current state
        await fetchSharedCarees()
    }

    /// Fetch shared Caree records with their ActivityTypes and Activities using zone-based discovery:
    /// 1. Fetch all zones from the shared database
    /// 2. Query each zone for CD_Caree records
    /// 3. Query each zone for CD_ActivityType records
    /// 4. Query each zone for CD_Activity records
    /// 5. Convert CloudKit records to temporary objects with relationships populated
    func fetchSharedCarees() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let sharedDatabase = container.sharedCloudDatabase

            // Step 1: Fetch all zones in the shared database
            // Each accepted share creates a zone with the owner's records
            let zones = try await sharedDatabase.allRecordZones()
            logger.info("📱 Found \(zones.count, privacy: .public) shared zones")

            // Log all zone names for diagnostics
            for zone in zones {
                logger.info("   Zone: \(zone.zoneID.zoneName, privacy: .public) (owner: \(zone.zoneID.ownerName, privacy: .public))")
            }

            if zones.isEmpty {
                await MainActor.run {
                    self.sharedCarees = []
                    self.isLoading = false
                }
                return
            }

            // Step 2: Query each zone for CD_Caree, CD_ActivityType, and CD_Activity records
            var allCareeRecords: [CKRecord] = []
            var allActivityTypeRecords: [CKRecord] = []
            var allActivityRecords: [CKRecord] = []
            var shares: [UUID: CKShare] = [:]

            for zone in zones {
                // Skip the default zone - only query custom zones (which are created for shares)
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                    continue
                }

                logger.info("🔍 Querying zone: \(zone.zoneID.zoneName, privacy: .public)")

                // Query for Carees
                let careeQuery = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
                do {
                    let (matchResults, _) = try await sharedDatabase.records(
                        matching: careeQuery,
                        inZoneWith: zone.zoneID
                    )

                    // Extract successful records and fetch their shares
                    for (_, result) in matchResults {
                        switch result {
                        case .success(let record):
                            allCareeRecords.append(record)
                            logger.info("  ✅ Found caree: \(record["CD_name"] as? String ?? "unknown")")

                            // Fetch the CKShare for this record
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

                // Query for ActivityTypes
                let activityTypeQuery = CKQuery(recordType: "CD_ActivityType", predicate: NSPredicate(value: true))
                do {
                    let (matchResults, _) = try await sharedDatabase.records(
                        matching: activityTypeQuery,
                        inZoneWith: zone.zoneID
                    )

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

                // Query for Activities
                let activityQuery = CKQuery(recordType: "CD_Activity", predicate: NSPredicate(value: true))
                do {
                    let (matchResults, _) = try await sharedDatabase.records(
                        matching: activityQuery,
                        inZoneWith: zone.zoneID
                    )

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
                logger.info("✅ Successfully fetched \(carees.count, privacy: .public) shared carees with \(shares.count, privacy: .public) shares from \(zones.count - 1, privacy: .public) zones")
            }

        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
                logger.error("❌ Failed to fetch shared carees: \(error.localizedDescription)")
            }
        }
    }

    /// Convert CloudKit records to temporary objects for display with relationships populated
    /// These are not persisted in SwiftData - they're ephemeral representations of shared data
    private func convertRecordsToCarees(
        _ careeRecords: [CKRecord],
        activityTypeRecords: [CKRecord],
        activityRecords: [CKRecord]
    ) async throws -> [Caree] {
        var careesByID: [UUID: Caree] = [:]
        var activityTypesByID: [UUID: ActivityType] = [:]

        // Step 1: Create Caree objects
        for record in careeRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String else {
                logger.warning("⚠️ Skipping caree record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let caree = Caree(
                name: name,
                listOrder: record["CD_listOrder"] as? Int ?? 0
            )
            caree.id = uuid

            if let imageAsset = record["CD_image"] as? CKAsset,
               let imageURL = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageURL) {
                caree.image = imageData
            }

            if let dateCreated = record["CD_dateCreated"] as? Date {
                caree.dateCreated = dateCreated
            }

            careesByID[uuid] = caree
        }

        // Step 2: Create ActivityType objects and link to Carees
        for record in activityTypeRecords {
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String else {
                logger.warning("⚠️ Skipping activity type record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            let activityType = ActivityType(
                name: name,
                icon: record["CD_icon"] as? String,
                hasQuantity: record["CD_hasQuantity"] as? Bool ?? false,
                quantityUnit: record["CD_quantityUnit"] as? String,
                hasLocation: record["CD_hasLocation"] as? Bool ?? false,
                listOrder: record["CD_listOrder"] as? Int ?? 0
            )
            activityType.id = uuid

            if let dateCreated = record["CD_dateCreated"] as? Date {
                activityType.dateCreated = dateCreated
            }

            // Link to caree via CD_caree reference
            if let careeReference = record["CD_caree"] as? CKRecord.Reference,
               let careeIDString = careeReference.recordID.recordName.components(separatedBy: "/").last,
               let careeUUID = UUID(uuidString: careeIDString),
               let caree = careesByID[careeUUID] {
                activityType.caree = caree
                if caree.activityTypes == nil {
                    caree.activityTypes = []
                }
                caree.activityTypes?.append(activityType)
            }

            activityTypesByID[uuid] = activityType
        }

        // Step 3: Create Activity objects and link to ActivityTypes and Carees
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

            // Link to activity type via CD_activityType reference
            if let activityTypeReference = record["CD_activityType"] as? CKRecord.Reference,
               let activityTypeIDString = activityTypeReference.recordID.recordName.components(separatedBy: "/").last,
               let activityTypeUUID = UUID(uuidString: activityTypeIDString),
               let activityType = activityTypesByID[activityTypeUUID] {
                activity.activityType = activityType
                if activityType.activities == nil {
                    activityType.activities = []
                }
                activityType.activities?.append(activity)
            }

            // Link to caree via CD_caree reference
            if let careeReference = record["CD_caree"] as? CKRecord.Reference,
               let careeIDString = careeReference.recordID.recordName.components(separatedBy: "/").last,
               let careeUUID = UUID(uuidString: careeIDString),
               let caree = careesByID[careeUUID] {
                activity.caree = caree
                if caree.activities == nil {
                    caree.activities = []
                }
                caree.activities?.append(activity)
            }
        }

        return Array(careesByID.values).sorted { $0.listOrder < $1.listOrder }
    }
}
