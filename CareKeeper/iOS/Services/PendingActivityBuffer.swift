import Foundation

@MainActor
final class PendingActivityBuffer: ObservableObject {
    struct PendingActivityMutation: Identifiable {
        let id: UUID
        let careeID: UUID
        let activityTypeID: UUID
        let activity: Activity
        let createdAt: Date
    }

    @Published private(set) var pendingByCaree: [UUID: [PendingActivityMutation]] = [:]

    func enqueue(_ mutation: PendingActivityMutation) {
        pendingByCaree[mutation.careeID, default: []].append(mutation)
    }

    func remove(activityID: UUID, careeID: UUID) {
        guard var list = pendingByCaree[careeID] else { return }
        list.removeAll { $0.id == activityID }
        if list.isEmpty {
            pendingByCaree.removeValue(forKey: careeID)
        } else {
            pendingByCaree[careeID] = list
        }
    }

    func drain(for careeID: UUID) -> [PendingActivityMutation] {
        let drained = pendingByCaree[careeID] ?? []
        pendingByCaree.removeValue(forKey: careeID)
        return drained
    }

    func pendingMutations(for careeID: UUID) -> [PendingActivityMutation] {
        pendingByCaree[careeID] ?? []
    }

    func pendingActivities(for careeID: UUID) -> [Activity] {
        (pendingByCaree[careeID] ?? []).map(\.activity)
    }

    var pendingCareeIDs: [UUID] {
        Array(pendingByCaree.keys)
    }
}
