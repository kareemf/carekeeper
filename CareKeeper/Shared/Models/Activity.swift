import CoreLocation
import Foundation
import SwiftData

@Model
final class Activity {
    var id: UUID = UUID()
    var dateTime: Date = Date()
    var notes: String?
    var quantity: Double?
    var latitude: Double?
    var longitude: Double?
    var dateCreated: Date = Date()

    // Cache metadata (for Pure CloudKit migration)
    var lastSyncedAt: Date? // Last time this record was synced from CloudKit
    var cloudKitRecordID: String? // CloudKit record ID for tracking

    // Relationships
    var activityType: ActivityType?
    var caree: Caree?

    init(
        dateTime: Date = Date(),
        notes: String? = nil,
        quantity: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activityType: ActivityType? = nil,
        caree: Caree? = nil
    ) {
        self.id = UUID()
        self.dateTime = dateTime
        self.notes = notes
        self.quantity = quantity
        self.latitude = latitude
        self.longitude = longitude
        self.dateCreated = Date()
        self.activityType = activityType
        self.caree = caree
        self.lastSyncedAt = nil
        self.cloudKitRecordID = nil
    }
}

// MARK: - Computed Properties

extension Activity {
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }
    
    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateTime)
    }
    
    var formattedQuantity: String? {
        guard let quantity else { return nil }
        let unit = activityType?.quantityUnit ?? ""
        return "\(quantity) \(unit)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - CloudKit Configuration

extension Activity {
    static func configureCloudKitSchema() {
        // All fields use CloudKit's infrastructure-level encryption (in transit and at rest).
        // Field-level encryption via encryptedValues is not used to maintain CloudKit
        // sharing compatibility - participants need access to all activity data.
        //
        // Privacy is maintained through:
        // - Apple ID authentication
        // - Explicit share acceptance
        // - Device-level encryption when locked
    }
}

// MARK: - Property Update Helpers

private protocol PropertyUpdatable: AnyObject {
    associatedtype ModelType = Self
    static func makeUpdater(_ keyPath: ReferenceWritableKeyPath<Self, some Any>) -> (Self, Self) -> Void
}

private extension PropertyUpdatable {
    static func makeUpdater(_ keyPath: ReferenceWritableKeyPath<Self, some Any>) -> (Self, Self) -> Void {
        { dest, src in
            dest[keyPath: keyPath] = src[keyPath: keyPath]
        }
    }
}

extension Activity: PropertyUpdatable {
    // Only include scalar fields you want to copy during a sync/update.
    // Exclude identity, relationships, and cache metadata.
    static let scalarUpdaters: [(Activity, Activity) -> Void] = [
        makeUpdater(\.dateTime),
        makeUpdater(\.notes),
        makeUpdater(\.quantity),
        makeUpdater(\.latitude),
        makeUpdater(\.longitude),
        makeUpdater(\.dateCreated),
    ]

    func applyScalarUpdates(from other: Activity) {
        for updater in Self.scalarUpdaters {
            updater(self, other)
        }
    }
}
