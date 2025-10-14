import Foundation
import SwiftData

@Model
final class Caree {
    var id: UUID = UUID()
    var name: String = ""
    var image: Data?
    var listOrder: Int = 0
    var dateCreated: Date = Date()

    // Cache metadata (for Pure CloudKit migration)
    var isShared: Bool = false  // True if this is a shared caree (not owned by user)
    var isOwned: Bool = true     // True if this caree is owned by user
    var lastSyncedAt: Date?      // Last time this record was synced from CloudKit
    var cloudKitRecordID: String? // CloudKit record ID for tracking

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \ActivityType.caree)
    var activityTypes: [ActivityType]? = []

    @Relationship(deleteRule: .cascade, inverse: \Activity.caree)
    var activities: [Activity]? = []

    init(name: String = "", image: Data? = nil, listOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.image = image
        self.listOrder = listOrder
        self.dateCreated = Date()
        self.isShared = false
        self.isOwned = true
        self.lastSyncedAt = nil
        self.cloudKitRecordID = nil
    }
}

// MARK: - Computed Properties
extension Caree {
    var sortedActivityTypes: [ActivityType] {
        (activityTypes ?? []).sorted { $0.listOrder < $1.listOrder }
    }

    var recentActivities: [Activity] {
        (activities ?? []).sorted { $0.dateTime > $1.dateTime }
    }
}

// MARK: - CloudKit Configuration
extension Caree {
    // Configure CloudKit field encryption for sensitive data
    static func configureCloudKitSchema() {
        // This would be configured in CloudKit Dashboard
        // - name: encrypted field
        // - image: encrypted field  
        // - other fields: standard encryption
    }
}

// MARK: - Property Update Helpers
private protocol PropertyUpdatable: AnyObject {
    associatedtype ModelType = Self
    static func makeUpdater<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>) -> (Self, Self) -> Void
}

private extension PropertyUpdatable {
    static func makeUpdater<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>) -> (Self, Self) -> Void {
        { dest, src in
            dest[keyPath: keyPath] = src[keyPath: keyPath]
        }
    }
}

extension Caree: PropertyUpdatable {
    // Only include scalar fields you want to copy during a sync/update.
    // Exclude identity, relationships, and cache metadata (isShared/isOwned set by caller).
    static let scalarUpdaters: [(Caree, Caree) -> Void] = [
        makeUpdater(\.name),
        makeUpdater(\.image),
        makeUpdater(\.listOrder),
        makeUpdater(\.dateCreated)
    ]

    func applyScalarUpdates(from other: Caree) {
        for updater in Self.scalarUpdaters {
            updater(self, other)
        }
    }
}
