import SwiftUI
import os
import SwiftData
import CloudKit

@MainActor
class CloudKitSharingService: ObservableObject {
    private let container: CKContainer

    init(containerIdentifier: String = "iCloud.com.kareemf.CareKeeperCloudKit") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: - Share Status

    func getShare(for caree: Caree, in modelContext: ModelContext) -> CKShare? {
        // Check if this model is already shared
        // SwiftData stores share information in the persistent store
        // Note: In SwiftData + CloudKit, we need to query the share using the persistent identifier
        // This is a simplified version - actual implementation may need coordinator access
        return nil // Placeholder - will be implemented when testing sharing
    }

    func isShared(_ caree: Caree, in modelContext: ModelContext) -> Bool {
        return getShare(for: caree, in: modelContext) != nil
    }

    // MARK: - Permission Checks

    func isOwner(of share: CKShare) -> Bool {
        return share.owner == share.currentUserParticipant
    }

    func canDelete(caree: Caree, in modelContext: ModelContext) -> Bool {
        guard let share = getShare(for: caree, in: modelContext) else {
            // No share means user owns it locally
            return true
        }

        return isOwner(of: share)
    }

    // MARK: - Share Management

    func stopSharing(caree: Caree, in modelContext: ModelContext) async throws {
        // To stop sharing, we delete the share from CloudKit
        // SwiftData will handle updating the local store
        guard let share = getShare(for: caree, in: modelContext) else {
            return // Not shared
        }

        let database = container.sharedCloudDatabase
        do {
            try await database.deleteRecord(withID: share.recordID)
        } catch {
            os_log("❌ Failed to delete share: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
            throw error
        }
    }

    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) async throws {
        guard participant != share.owner else {
            throw AppError.invalidInput("Cannot remove the owner from a share")
        }

        let database = container.sharedCloudDatabase

        // Remove the participant from the share
        share.removeParticipant(participant)

        // Save the updated share
        do {
            try await database.save(share)
        } catch {
            os_log("❌ Failed to save share: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
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
}

