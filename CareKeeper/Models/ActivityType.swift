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
        // Configure in CloudKit Dashboard:
        // - name: encrypted field (contains user-defined taxonomy)
        // - other fields: standard encryption
    }
}