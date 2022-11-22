import SwiftUI

extension Caree {
    func fetchActivities(fetchLimit: Int = 5) throws -> [Activity] {
        let predicate = NSPredicate(format: "caree == %@", self)

        let fetchRequest = Activity.fetchRequest()

        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Activity.when, ascending: false)]
        fetchRequest.fetchLimit = fetchLimit

        do {
            return try self.managedObjectContext!.fetch(fetchRequest) as [Activity]
        } catch {
            throw error
        }
    }

    func fetchBehaviors() throws -> [Behavior] {
        let predicate = NSPredicate(format: "caree == %@", self)

        let fetchRequest = Behavior.fetchRequest()

        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Behavior.listOrder, ascending: true),
            NSSortDescriptor(keyPath: \Behavior.dateCreated, ascending: false)
        ]

        do {
            return try self.managedObjectContext!.fetch(fetchRequest) as [Behavior]
        } catch {
            throw error
        }
    }
}
