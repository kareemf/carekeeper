import SwiftUI
import SwiftData
import CloudKit

@MainActor
class CloudKitSharingService: ObservableObject {
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let logger = AppLogger.sharing

    init(containerIdentifier: String = CloudKitConfig.containerID) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
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
    func createOrGetShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare {
        // Check if share already exists
        if let existingShare = try await getShare(for: caree, in: modelContext) {
            return existingShare
        }
        
        // Find the CloudKit record for this Caree
        guard let careeCKRecord = try await findCKRecord(for: caree) else {
            throw AppError.invalidInput("Caree not found in CloudKit. Make sure it's synced first.")
        }
        
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
                return finalShare
            } else {
                throw AppError.invalidInput("Failed to save share to CloudKit")
            }
        } catch {
            logger.error("Failed to create share: \(error.localizedDescription)")
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
