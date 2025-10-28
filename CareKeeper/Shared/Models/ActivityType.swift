import Foundation
import SwiftData

@Model
final class ActivityType {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String?
    var hasQuantity: Bool = false
    var quantityUnit: String?
    var hasLocation: Bool = false
    var listOrder: Int = 0
    var dateCreated: Date = Date()

    // Cache metadata (for Pure CloudKit migration)
    var lastSyncedAt: Date?      // Last time this record was synced from CloudKit
    var cloudKitRecordID: String? // CloudKit record ID for tracking

    // Relationships
    var caree: Caree?

    @Relationship(deleteRule: .cascade, inverse: \Activity.activityType)
    var activities: [Activity]? = []

    init(
        name: String = "",
        icon: String? = nil,
        hasQuantity: Bool = false,
        quantityUnit: String? = nil,
        hasLocation: Bool = false,
        listOrder: Int = 0,
        caree: Caree? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.hasQuantity = hasQuantity
        self.quantityUnit = quantityUnit
        self.hasLocation = hasLocation
        self.listOrder = listOrder
        self.dateCreated = Date()
        self.caree = caree
        self.lastSyncedAt = nil
        self.cloudKitRecordID = nil
    }
}

// MARK: - Computed Properties
extension ActivityType {
    var displayIcon: String {
        if let icon = icon, !icon.isEmpty {
            return icon
        }
        return "" // Empty string instead of showing "circle" SF Symbol name
    }
    
    var recentActivities: [Activity] {
        (activities ?? []).sorted { $0.dateTime > $1.dateTime }
    }

    var totalActivitiesCount: Int {
        activities?.count ?? 0
    }
}

// MARK: - CloudKit Configuration
extension ActivityType {
    static func configureCloudKitSchema() {
        // All fields use CloudKit's infrastructure-level encryption.
        // Activity types are shared with all caree participants.
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

extension ActivityType: PropertyUpdatable {
    // Only include scalar fields you want to copy during a sync/update.
    // Exclude identity, relationships, and cache metadata.
    static let scalarUpdaters: [(ActivityType, ActivityType) -> Void] = [
        makeUpdater(\.name),
        makeUpdater(\.icon),
        makeUpdater(\.hasQuantity),
        makeUpdater(\.quantityUnit),
        makeUpdater(\.hasLocation),
        makeUpdater(\.listOrder),
        makeUpdater(\.dateCreated)
    ]

    func applyScalarUpdates(from other: ActivityType) {
        for updater in Self.scalarUpdaters {
            updater(self, other)
        }
    }
}
