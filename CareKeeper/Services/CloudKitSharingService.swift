import SwiftUI
import os
import SwiftData
import CloudKit
import CoreData

// @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
// @see https://developer.apple.com/documentation/uikit/uicloudsharingcontroller
@MainActor
class CloudKitSharingService: ObservableObject {
    private let container: CKContainer

    init(containerIdentifier: String = CloudKitConfig.containerID) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: - Share Status

    // Returns the CKShare associated with this SwiftData model if one exists.
    // Implementation detail: SwiftData currently doesn't expose first-class share APIs.
    // We bridge to the underlying Core Data stack to use the NSPersistentStoreCoordinator sharing APIs.
    // This uses a KVC-based accessor to reach NSManagedObjectContext from ModelContext and to get the
    // underlying NSManagedObject for a SwiftData model instance.
    //
    // @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
    func getShare(for caree: Caree, in modelContext: ModelContext) -> CKShare? {
        guard
            let nsContext = modelContext._nsManagedObjectContext,
            let psc = nsContext.persistentStoreCoordinator,
            let managedObject = nsContext._managedObject(forSwiftDataModel: caree)
        else {
            return nil
        }

        do {
            // Ask PSC for the share associated with this object.
            return try psc.getShare(for: managedObject.objectID, in: nsContext)
        } catch {
            Logger.logError("Failed to fetch CKShare for Caree", error: error)
            return nil
        }
    }

    func isShared(_ caree: Caree, in modelContext: ModelContext) -> Bool {
        return getShare(for: caree, in: modelContext) != nil
    }

    // MARK: - Create or Get Share

    // Fetch existing share or create a new one for the Caree.
    // Centralizes "fetch-or-create" to avoid UI-level race conditions.
    //
    // @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
    func createOrGetShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare {
        if let existing = getShare(for: caree, in: modelContext) {
            return existing
        }

        guard
            let nsContext = modelContext._nsManagedObjectContext,
            let psc = nsContext.persistentStoreCoordinator,
            let managedObject = nsContext._managedObject(forSwiftDataModel: caree)
        else {
            throw AppError.invalidInput("Unable to access Core Data bridge for sharing.")
        }

        do {
            // Create a new share for this object using PSC sharing APIs.
            // The returned tuple is (CKShare, CKRecord for the root object).
            let (share, _) = try psc.createShare(for: managedObject.objectID, to: container, in: nsContext)
            share[CKShare.SystemFieldKey.title] = caree.name
            share.publicPermission = .none

            // Persist share metadata to the store so SwiftData/Core Data knows about it.
            if nsContext.hasChanges {
                try nsContext.save()
            }

            return share
        } catch {
            Logger.logError("Failed to create share", error: error)
            throw error
        }
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
            Logger.logError("Failed to delete share", error: error)
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
            Logger.logError("Failed to save share", error: error)
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

// MARK: - SwiftData/Core Data bridge helpers

/*
 Design decision: Use the SwiftData → Core Data bridge (PSC sharing APIs) instead of raw CKQuery

 Why this approach:
 - Official sharing path for Core Data/SwiftData mirroring:
   Apple documents sharing via the Core Data stack (NSPersistentCloudKitContainer / PSC) rather than
   hand-rolling CloudKit queries when your data is mirrored.
   @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
   @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app
   @see https://developer.apple.com/documentation/uikit/uicloudsharingcontroller

 - Correctness and metadata consistency:
   The store maintains the association between your model object and its CKShare/CKRecord. Using PSC
   getShare/createShare keeps that association correct and persisted so future calls “just work”.

 - Avoids brittle schema coupling:
   Raw CKQuery requires hardcoding recordType/field names (e.g., "CD_Caree", "CD_id") that are an
   implementation detail of SwiftData’s CloudKit mapping, not a public contract. The mapping could
   evolve; PSC APIs abstract this.

 - Cleaner integration with UICloudSharingController:
   The controller expects to manage shares that the store knows about. PSC APIs ensure both the store
   and controller are in sync.

 Trade-offs:
 - Private bridging:
   SwiftData doesn’t currently expose public share APIs, so we access the underlying Core Data stack
   via KVC/selectors to obtain NSManagedObjectContext and the backing NSManagedObject. This is
   pragmatic but private; we keep it isolated here for easy replacement if Apple provides public APIs.

 - Alternative (raw CKQuery) pros/cons:
   Direct CloudKit queries give full manual control, but you take on zone/record management and risk
   creating shares the store doesn’t know about unless you also write back share metadata correctly.
   That’s more code and easier to get wrong in a mirrored setup.

 Summary:
 - For a SwiftData + CloudKit mirrored app, PSC sharing APIs are the recommended, least brittle path.
   We use a small, isolated bridge here to reach them until SwiftData exposes first-class sharing APIs.
*/

private extension ModelContext {
    // Access the underlying NSManagedObjectContext when using SwiftData.
    // Note: This uses a private bridge via KVC to reach Core Data until SwiftData exposes public sharing APIs.
    // Keep this isolated so it can be swapped out in the future if needed.
    //
    // @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
    var _nsManagedObjectContext: NSManagedObjectContext? {
        (self as AnyObject).value(forKey: "nsContext") as? NSManagedObjectContext
    }
}

private extension NSManagedObjectContext {
    // Obtain the underlying NSManagedObject that backs a SwiftData model instance.
    // This uses KVC to access SwiftData's internal bridging layer.
    //
    // Implementation notes:
    // - SwiftData models are backed by Core Data entities at runtime.
    // - We ask the context to resolve the "backing" NSManagedObject for the given SwiftData model object.
    // - This avoids relying on PersistentIdentifier.uriRepresentation, which isn't publicly available.
    //
    // If this ever changes, keep this helper as the single place to update.
    func _managedObject(forSwiftDataModel model: AnyObject) -> NSManagedObject? {
        // Known internal key used by SwiftData to get the underlying managed object for a model instance.
        // We purposefully keep this KVC usage isolated.
        (self as AnyObject).perform(Selector(("_managedObjectFor:")), with: model)?.takeUnretainedValue() as? NSManagedObject
    }
}

private extension NSPersistentStoreCoordinator {
    // Wrapper helpers for clarity at call sites.
    func getShare(for objectID: NSManagedObjectID, in context: NSManagedObjectContext) throws -> CKShare? {
        try self.getShare(for: objectID, in: context)
    }

    func createShare(for objectID: NSManagedObjectID, to container: CKContainer, in context: NSManagedObjectContext) throws -> (CKShare, CKRecord) {
        try self.createShare(for: objectID, to: container, in: context)
    }
}
