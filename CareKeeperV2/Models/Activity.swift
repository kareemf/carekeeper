import Foundation
import SwiftData
import CoreLocation

@Model
final class Activity {
    var id: UUID
    var dateTime: Date
    var notes: String?
    var quantity: Double?
    var latitude: Double?
    var longitude: Double?
    var dateCreated: Date
    
    // Relationships
    var activityType: ActivityType?
    var caree: Caree?
    
    init(
        dateTime: Date = Date(),
        notes: String? = nil,
        quantity: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activityType: ActivityType,
        caree: Caree
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
    }
}

// MARK: - Computed Properties
extension Activity {
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }
    
    var location: CLLocation? {
        guard let latitude = latitude, let longitude = longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateTime)
    }
    
    var formattedQuantity: String? {
        guard let quantity = quantity else { return nil }
        let unit = activityType?.quantityUnit ?? ""
        return "\(quantity) \(unit)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - CloudKit Configuration
extension Activity {
    static func configureCloudKitSchema() {
        // Configure in CloudKit Dashboard:
        // - notes: encrypted field (sensitive user data)
        // - location data: encrypted fields (privacy sensitive)
        // - other fields: standard encryption
    }
}