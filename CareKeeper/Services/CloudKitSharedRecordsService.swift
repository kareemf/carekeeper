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

    /// Fetch shared Caree records using zone-based discovery:
    /// 1. Fetch all zones from the shared database
    /// 2. Query each zone for CD_Caree records
    /// 3. Convert CloudKit records to temporary Caree objects
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

            if zones.isEmpty {
                await MainActor.run {
                    self.sharedCarees = []
                    self.isLoading = false
                }
                return
            }

            // Step 2: Query each zone for CD_Caree records and their CKShare
            var allRecords: [CKRecord] = []
            var shares: [UUID: CKShare] = [:]

            for zone in zones {
                // Skip the default zone - only query custom zones (which are created for shares)
                if zone.zoneID.zoneName == CKRecordZone.ID.defaultZoneName {
                    continue
                }

                logger.info("🔍 Querying zone: \(zone.zoneID.zoneName, privacy: .public)")

                let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))

                do {
                    let (matchResults, _) = try await sharedDatabase.records(
                        matching: query,
                        inZoneWith: zone.zoneID
                    )

                    // Extract successful records and fetch their shares
                    for (_, result) in matchResults {
                        switch result {
                        case .success(let record):
                            allRecords.append(record)
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
                            logger.warning("  ⚠️ Failed to fetch record: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    logger.warning("  ⚠️ Failed to query zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                    // Continue with other zones instead of failing completely
                }
            }

            // Step 3: Convert to Caree objects
            let carees = try await convertRecordsToCarees(allRecords)

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

    /// Convert CloudKit records to temporary Caree objects for display
    /// These are not persisted in SwiftData - they're ephemeral representations of shared data
    private func convertRecordsToCarees(_ records: [CKRecord]) async throws -> [Caree] {
        var carees: [Caree] = []

        for record: CKRecord in records {
            // Extract data from CloudKit record
            // SwiftData adds "CD_" prefix to all stored properties in CloudKit
            guard let cdId = record["CD_id"] as? String,
                  let uuid = UUID(uuidString: cdId),
                  let name = record["CD_name"] as? String else {
                logger.warning("⚠️ Skipping record with missing required fields: \(record.recordID.recordName)")
                continue
            }

            // Create a temporary Caree object (not persisted in SwiftData)
            let caree = Caree(
                name: name,
                listOrder: record["CD_listOrder"] as? Int ?? 0
            )
            caree.id = uuid

            // Set other properties if they exist
            if let imageAsset = record["CD_image"] as? CKAsset,
               let imageURL = imageAsset.fileURL,
               let imageData = try? Data(contentsOf: imageURL) {
                caree.image = imageData
            }

            if let dateCreated = record["CD_dateCreated"] as? Date {
                caree.dateCreated = dateCreated
            }

            carees.append(caree)
        }

        return carees.sorted { $0.listOrder < $1.listOrder }
    }
}
