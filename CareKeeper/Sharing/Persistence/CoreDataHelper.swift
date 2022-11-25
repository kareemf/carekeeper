/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Extensions that add convenience methods to Core Data.
*/

import CoreData
import CloudKit

extension NSPersistentStore {
    func contains(manageObject: NSManagedObject) -> Bool {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: manageObject.entity.name!)
        fetchRequest.predicate = NSPredicate(format: "self == %@", manageObject)
        fetchRequest.affectedStores = [self]

        if let context = manageObject.managedObjectContext,
           let result = try? context.count(for: fetchRequest), result > 0 {
            return true
        }
        return false
    }
}

/**
 A convenience method for creating background contexts that specify the app as their transaction author.
 */
extension NSPersistentCloudKitContainer {
    func newTaskContext() -> NSManagedObjectContext {
        let context = newBackgroundContext()
        context.transactionAuthor = PersistenceController.authorName
        return context
    }

    /**
     Fetch and return shares in the persistent stores.
     */
    func fetchShares(in persistentStores: [NSPersistentStore]) throws -> [CKShare] {
        var results = [CKShare]()
        for persistentStore in persistentStores {
            do {
                let shares = try fetchShares(in: persistentStore)
                results += shares
            } catch let error {
                print("Failed to fetch shares in \(persistentStore).")
                throw error
            }
        }
        return results
    }
}

