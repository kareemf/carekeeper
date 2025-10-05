import Foundation
import SwiftData

@Model
final class Caree {
    var id: UUID = UUID()
    var name: String = ""
    var image: Data?
    var listOrder: Int = 0
    var dateCreated: Date = Date()

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