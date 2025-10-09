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
    // We bridge to the underlying Core Data stack (NSPersistentCloudKitContainer) to use its sharing APIs.
    //
    // @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
    func getShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare? {
        guard
            let nsContext = modelContext._nsManagedObjectContext,
            let managedObject = nsContext._managedObject(forSwiftDataModel: caree),
            let pckContainer = nsContext._persistentCloudKitContainer
        else {
            return nil
        }

        // Fetch existing share for this objectID
        let mapping = try pckContainer._fetchShares(matching: [managedObject.objectID])
        return mapping[managedObject.objectID]
    }

    func isShared(_ caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            return try await getShare(for: caree, in: modelContext) != nil
        } catch {
            Logger.logError("Failed to check share status", error: error)
            return false
        }
    }

    // MARK: - Create or Get Share

    // Fetch existing share or create a new one for the Caree.
    // Centralizes "fetch-or-create" to avoid UI-level race conditions.
    //
    // @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
    func createOrGetShare(for caree: Caree, in modelContext: ModelContext) async throws -> CKShare {
        if let existing = try await getShare(for: caree, in: modelContext) {
            return existing
        }

        guard
            let nsContext = modelContext._nsManagedObjectContext,
            let managedObject = nsContext._managedObject(forSwiftDataModel: caree),
            let pckContainer = nsContext._persistentCloudKitContainer
        else {
            throw AppError.invalidInput("Unable to access Core Data bridge for sharing.")
        }

        do {
            // Create a new share for this object using NSPersistentCloudKitContainer sharing APIs.
            let share = try await pckContainer._share([managedObject])

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

    func canDelete(caree: Caree, in modelContext: ModelContext) async -> Bool {
        do {
            guard let share = try await getShare(for: caree, in: modelContext) else {
                // No share means user owns it locally
                return true
            }
            return isOwner(of: share)
        } catch {
            Logger.logError("Failed to determine delete permission", error: error)
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
            Logger.logError("Failed to delete share", error: error)
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
 Design decision: Use the SwiftData → Core Data bridge (NSPersistentCloudKitContainer sharing APIs).

 Why this approach:
 - Official sharing path for Core Data/SwiftData mirroring:
   Apple documents sharing via NSPersistentCloudKitContainer rather than hand-rolled CloudKit queries.
   @see https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
   @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app
   @see https://developer.apple.com/documentation/uikit/uicloudsharingcontroller

 - Correctness and metadata consistency:
   The store maintains the association between your model object and its CKShare/CKRecord. Using the
   container’s share/fetchShares keeps that association correct and persisted.

 - Avoids brittle schema coupling:
   Raw CKQuery requires hardcoding recordType/field names that are an implementation detail of SwiftData’s mapping.

 Trade-offs:
 - Private bridging:
   We access the underlying NSManagedObjectContext and locate the NSPersistentCloudKitContainer via a small
   private/KVC lookup from the context’s persistentStoreCoordinator. Kept isolated here for easy replacement
   if public APIs appear.
*/

private extension ModelContext {
    // Access the underlying NSManagedObjectContext when using SwiftData.
    var _nsManagedObjectContext: NSManagedObjectContext? {
        let anyObject = self as AnyObject

        // Prefer selector-based getters (safe).
        let getterSelectors = [
            "nsContext",                // exposed on many SDKs
            "managedObjectContext",     // observed on some builds
            "_managedObjectContext"     // internal name on some builds
        ]
        for name in getterSelectors {
            let sel = NSSelectorFromString(name)
            if anyObject.responds(to: sel),
               let unmanaged = anyObject.perform(sel) {
                return unmanaged.takeUnretainedValue() as? NSManagedObjectContext
            }
        }

        // Fallback: KVC only if a matching getter selector exists (avoids NSUndefinedKeyException).
        for name in getterSelectors {
            let sel = NSSelectorFromString(name)
            if anyObject.responds(to: sel),
               let ctx = anyObject.value(forKey: name) as? NSManagedObjectContext {
                return ctx
            }
        }

        return nil
    }
}

private extension NSManagedObjectContext {
    // Obtain the underlying NSManagedObject that backs a SwiftData model instance.
    func _managedObject(forSwiftDataModel model: AnyObject) -> NSManagedObject? {
        let candidates = [
            "_managedObjectFor:",       // observed in current toolchains
            "_managedObjectForModel:"   // alternate internal name on some builds
        ]
        for name in candidates {
            let sel = NSSelectorFromString(name)
            if (self as AnyObject).responds(to: sel),
               let unmanaged = (self as AnyObject).perform(sel, with: model) {
                return unmanaged.takeUnretainedValue() as? NSManagedObject
            }
        }
        return nil
    }

    // Locate the NSPersistentCloudKitContainer associated with this context’s coordinator.
    // Minimal private/KVC lookup; kept isolated.
    var _persistentCloudKitContainer: NSPersistentCloudKitContainer? {
        guard let psc = self.persistentStoreCoordinator else { return nil }

        // Try a few plausible getters on the coordinator.
        let keys = ["container", "_container", "persistentContainer"]
        let coordinatorObj = psc as NSObject
        for key in keys {
            let sel = NSSelectorFromString(key)
            if coordinatorObj.responds(to: sel),
               let unmanaged = coordinatorObj.perform(sel),
               let value = unmanaged.takeUnretainedValue() as? NSPersistentCloudKitContainer {
                return value
            }
        }

        // Some toolchains may keep a weak back-reference on one of the persistent stores.
        for store in psc.persistentStores {
            let storeObj = store as NSObject
            for key in keys {
                let sel = NSSelectorFromString(key)
                if storeObj.responds(to: sel),
                   let unmanaged = storeObj.perform(sel),
                   let value = unmanaged.takeUnretainedValue() as? NSPersistentCloudKitContainer {
                    return value
                }
            }
        }

        return nil
    }
}

// MARK: - Async wrappers for NSPersistentCloudKitContainer sharing APIs

private extension NSPersistentCloudKitContainer {
    // On this toolchain, fetchShares(matching:) is synchronous throwing. Call it directly (no await).
    func _fetchShares(matching objectIDs: [NSManagedObjectID]) throws -> [NSManagedObjectID: CKShare] {
        return try self.fetchShares(matching: objectIDs)
    }

    // Creating a new share uses the completion-handler overload that takes an optional CKShare.
    // Completion signature on this SDK: (Set<NSManagedObjectID>?, CKShare?, CKContainer?, Error?) -> Void
    func _share(_ objects: [NSManagedObject]) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            self.share(objects, to: nil, completion: { objectIDs, share, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let share = share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "CloudKitSharingService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown share creation state"]
                    ))
                }
            })
        }
    }
}
