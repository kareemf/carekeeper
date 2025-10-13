import SwiftUI
import SwiftData
import CloudKit

@MainActor
class CloudKitSharingService: ObservableObject {
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let logger = AppLogger.sharing
    private let dataService: CloudKitDataService

    init(containerIdentifier: String = CloudKitConfig.containerID, dataService: CloudKitDataService = CloudKitDataService()) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
        self.dataService = dataService
    }

    // MARK: - Share Status

    /// Get the CKShare for a Caree by checking if the record has a share reference
    func getShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare? {
        // First, find the actual CloudKit record for this Caree
        guard let careeCKRecord = try await findCKRecord(for: caree) else {
            return nil // Record not found, not an error - just means not synced yet
        }
        
        // Check if the record has a share reference
        guard let shareReference = careeCKRecord.share else {
            // Record is not shared
            return nil
        }
        
        do {
            // Fetch the actual share record
            let shareRecord = try await container.privateCloudDatabase.record(for: shareReference.recordID)
            return shareRecord as? CKShare
        } catch {
            logger.error("Failed to fetch share record: \(error.localizedDescription)")
            throw error
        }
    }

    func isShared(_ caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            return try await getShare(for: caree, in: modelContext) != nil
        } catch {
            logger.error("Failed to check share status: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Create Share

    /// Create a new CKShare for the Caree's CloudKit record
    /// Verifies all child records exist with proper parent references before creating share
    func createOrGetShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare {
        // Check if share already exists
        if let existingShare = try await getShare(for: caree, in: modelContext) {
            return existingShare
        }

        logger.info("🔍 Preparing to create share for Caree: \(caree.name)")

        // Step 1: Verify Caree exists in CloudKit
        guard let careeCKRecord = try await findCKRecord(for: caree) else {
            logger.error("❌ Caree not found in CloudKit")
            throw AppError.invalidInput("Caree not found in CloudKit. Please wait for sync to complete and try again.")
        }

        logger.info("✅ Caree record verified in CloudKit")
        logger.info("   RecordID: \(careeCKRecord.recordID.recordName)")

        // Step 2: Verify all ActivityTypes exist with parent references
        let activityTypeCount = caree.activityTypes?.count ?? 0
        if activityTypeCount > 0 {
            logger.info("🔍 Verifying \(activityTypeCount) ActivityTypes...")
            let (verifiedCount, missingParents) = try await verifyActivityTypes(for: caree)

            if verifiedCount < activityTypeCount {
                logger.error("❌ Only \(verifiedCount)/\(activityTypeCount) ActivityTypes found in CloudKit")
                throw AppError.invalidInput("Some activity types haven't synced to CloudKit yet. Please wait and try again.")
            }

            if missingParents > 0 {
                logger.warning("⚠️ Warning: \(missingParents) ActivityTypes missing parent references")
                // This shouldn't happen with CloudKitDataService, but log it for diagnostics
            }

            logger.info("✅ All \(verifiedCount) ActivityTypes verified")
        }

        // Step 3: Verify all Activities exist with parent references
        let activityCount = caree.activities?.count ?? 0
        if activityCount > 0 {
            logger.info("🔍 Verifying \(activityCount) Activities...")
            let (verifiedCount, missingParents) = try await verifyActivities(for: caree)

            if verifiedCount < activityCount {
                logger.error("❌ Only \(verifiedCount)/\(activityCount) Activities found in CloudKit")
                throw AppError.invalidInput("Some activities haven't synced to CloudKit yet. Please wait and try again.")
            }

            if missingParents > 0 {
                logger.warning("⚠️ Warning: \(missingParents) Activities missing parent references")
                // This shouldn't happen with CloudKitDataService, but log it for diagnostics
            }

            logger.info("✅ All \(verifiedCount) Activities verified")
        }

        // Step 4: All records verified - safe to create share
        logger.info("✅ All records verified, creating share...")

        // Create a new share
        let share = CKShare(rootRecord: careeCKRecord)
        share[CKShare.SystemFieldKey.title] = caree.name
        share.publicPermission = .none

        do {
            // Save both the updated root record and the share
            let recordsToSave = [careeCKRecord, share]
            let saveResults = try await container.privateCloudDatabase.modifyRecords(
                saving: recordsToSave,
                deleting: []
            )

            // Check if save was successful
            if let shareResult = saveResults.saveResults[share.recordID],
               case .success(let savedShare) = shareResult,
               let finalShare = savedShare as? CKShare {
                logger.info("✅ Share created successfully")
                return finalShare
            } else {
                throw AppError.invalidInput("Failed to save share to CloudKit")
            }
        } catch {
            logger.error("❌ Failed to create share: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Permission Checks

    func isOwner(of share: CKShare) -> Bool {
        return share.owner == share.currentUserParticipant
    }

    func canDelete(caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            guard let share = try await getShare(for: caree, in: modelContext) else {
                // No share means user owns it locally
                return true
            }
            return isOwner(of: share)
        } catch {
            logger.error("Failed to determine delete permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Share Management

    func stopSharing(caree: Caree, in modelContext: ModelContext) async throws {
        // To stop sharing, delete the share from the owner's private database.
        guard let share = try await getShare(for: caree, in: modelContext) else {
            return // Not shared
        }

        // Only the owner can stop sharing; callers should check, but we enforce as well.
        guard isOwner(of: share) else {
            throw AppError.invalidInput("Only the owner can stop sharing this item.")
        }

        do {
            try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        } catch {
            logger.error("Failed to delete share: \(error.localizedDescription)")
            throw error
        }
    }

    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) async throws {
        guard participant != share.owner else {
            throw AppError.invalidInput("Cannot remove the owner from a share")
        }

        // Remove the participant from the share
        share.removeParticipant(participant)

        // Save the updated share to the owner's private database
        do {
            _ = try await container.privateCloudDatabase.save(share)
        } catch {
            logger.error("Failed to save share: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchParticipants(for share: CKShare) -> [CKShare.Participant] {
        return share.participants.filter { $0 != share.owner }
    }

    // MARK: - Share URL

    func getShareURL(for share: CKShare) -> URL? {
        return share.url
    }

    // MARK: - Verification Helpers

    /// Verify all ActivityTypes for a Caree exist in CloudKit with parent references
    /// - Returns: (verifiedCount, missingParentCount)
    private func verifyActivityTypes(for caree: Caree) async throws -> (Int, Int) {
        let predicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_ActivityType", predicate: predicate)

        let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var verifiedCount = 0
        var missingParentCount = 0

        for (_, result) in results {
            if case .success(let record) = result {
                verifiedCount += 1

                // Check parent reference
                if record.parent == nil {
                    missingParentCount += 1
                    logger.warning("⚠️ ActivityType missing parent: \(record["CD_name"] as? String ?? "Unknown")")
                }
            }
        }

        return (verifiedCount, missingParentCount)
    }

    /// Verify all Activities for a Caree exist in CloudKit with parent references
    /// - Returns: (verifiedCount, missingParentCount)
    private func verifyActivities(for caree: Caree) async throws -> (Int, Int) {
        let predicate = NSPredicate(format: "CD_caree == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_Activity", predicate: predicate)

        let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)

        var verifiedCount = 0
        var missingParentCount = 0

        for (_, result) in results {
            if case .success(let record) = result {
                verifiedCount += 1

                // Check parent reference
                if record.parent == nil {
                    missingParentCount += 1
                    let dateTime = record["CD_dateTime"] as? Date ?? Date()
                    logger.warning("⚠️ Activity missing parent: \(dateTime)")
                }
            }
        }

        return (verifiedCount, missingParentCount)
    }

    // MARK: - Private Helpers

    /// Find the CloudKit record for a SwiftData Caree
    /// This uses the same approach as your CloudKitSyncService
    private func findCKRecord(for caree: Caree) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
        let query = CKQuery(recordType: "CD_Caree", predicate: predicate)
        
        do {
            let (results, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: zoneID)
            
            if let firstMatch = results.first {
                let (_, result) = firstMatch
                switch result {
                case .success(let record):
                    return record
                case .failure(let error):
                    throw error
                }
            }

            return nil
        } catch {
            logger.error("Failed to find CloudKit record for caree: \(error.localizedDescription)")
            throw error
        }
    }
}
