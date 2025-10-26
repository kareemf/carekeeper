import Foundation
import CloudKit

// MARK: - Snapshot Errors

enum SnapshotError: LocalizedError {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }
}

// MARK: - Snapshot Models for Watch App

/// Immutable value types for watch UI - NO SwiftData relationships
/// These prevent crashes from accessing invalidated model objects
/// and avoid triggering cascade fetches on relationships

/// Immutable snapshot of a Caree for watch UI
struct CareeSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let imageData: Data?
    let isShared: Bool
    let listOrder: Int
    let dateCreated: Date

    // Pre-loaded count, NOT a relationship!
    // This prevents accessing caree.activityTypes which can trigger crashes
    var activityTypeCount: Int = 0

    /// Create snapshot from CloudKit record
    init(from record: CKRecord, isShared: Bool) throws {
        // Extract ID from record name (format: "CD_Caree/UUID")
        guard let idString = record.recordID.recordName.components(separatedBy: "/").last,
              let id = UUID(uuidString: idString) else {
            throw SnapshotError.invalidInput("Invalid caree record ID: \(record.recordID.recordName)")
        }

        guard let name = record["CD_name"] as? String else {
            throw SnapshotError.invalidInput("Missing caree name in record")
        }

        self.id = id
        self.name = name
        self.imageData = record["CD_image"] as? Data
        self.isShared = isShared
        self.listOrder = (record["CD_listOrder"] as? Int) ?? 0
        self.dateCreated = (record["CD_dateCreated"] as? Date) ?? Date()
    }

    /// Create snapshot from SwiftData Caree model
    init(from caree: Caree) {
        self.id = caree.id
        self.name = caree.name
        self.imageData = caree.image
        self.isShared = caree.isShared
        self.listOrder = caree.listOrder
        self.dateCreated = caree.dateCreated
        // Count must be set separately to avoid relationship access
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CareeSnapshot, rhs: CareeSnapshot) -> Bool {
        lhs.id == rhs.id
    }
}

/// Immutable snapshot of an ActivityType for watch UI
struct ActivityTypeSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let hasQuantity: Bool
    let quantityUnit: String?
    let hasLocation: Bool
    let listOrder: Int
    let careeID: UUID
    let dateCreated: Date

    /// Create snapshot from CloudKit record
    init(from record: CKRecord) throws {
        // Extract ID from record name (format: "CD_ActivityType/UUID")
        guard let idString = record.recordID.recordName.components(separatedBy: "/").last,
              let id = UUID(uuidString: idString) else {
            throw SnapshotError.invalidInput("Invalid activity type record ID: \(record.recordID.recordName)")
        }

        guard let name = record["CD_name"] as? String else {
            throw SnapshotError.invalidInput("Missing activity type name in record")
        }

        // Extract caree ID from reference
        guard let careeRef = record["CD_caree"] as? CKRecord.Reference,
              let careeIDString = careeRef.recordID.recordName.components(separatedBy: "/").last,
              let careeID = UUID(uuidString: careeIDString) else {
            throw SnapshotError.invalidInput("Invalid caree reference in activity type")
        }

        self.id = id
        self.name = name
        self.icon = (record["CD_icon"] as? String) ?? "circle.fill"
        self.hasQuantity = (record["CD_hasQuantity"] as? Int == 1)
        self.quantityUnit = record["CD_quantityUnit"] as? String
        self.hasLocation = (record["CD_hasLocation"] as? Int == 1)
        self.listOrder = (record["CD_listOrder"] as? Int) ?? 0
        self.careeID = careeID
        self.dateCreated = (record["CD_dateCreated"] as? Date) ?? Date()
    }

    /// Create snapshot from SwiftData ActivityType model
    init(from activityType: ActivityType, careeID: UUID) {
        self.id = activityType.id
        self.name = activityType.name
        self.icon = activityType.icon ?? "circle.fill"
        self.hasQuantity = activityType.hasQuantity
        self.quantityUnit = activityType.quantityUnit
        self.hasLocation = activityType.hasLocation
        self.listOrder = activityType.listOrder
        self.careeID = careeID
        self.dateCreated = activityType.dateCreated
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ActivityTypeSnapshot, rhs: ActivityTypeSnapshot) -> Bool {
        lhs.id == rhs.id
    }
}

/// Immutable snapshot of an Activity for watch UI
struct ActivitySnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let dateTime: Date
    let notes: String?
    let quantity: Double?
    let latitude: Double?
    let longitude: Double?
    let activityTypeID: UUID
    let careeID: UUID
    let dateCreated: Date

    // For optimistic UI
    var syncState: SyncState = .synced

    enum SyncState: Hashable, Sendable {
        case pending
        case syncing
        case synced
        case failed(String)
    }

    /// Create snapshot from CloudKit record
    init(from record: CKRecord) throws {
        // Extract ID from record name (format: "CD_Activity/UUID")
        guard let idString = record.recordID.recordName.components(separatedBy: "/").last,
              let id = UUID(uuidString: idString) else {
            throw SnapshotError.invalidInput("Invalid activity record ID: \(record.recordID.recordName)")
        }

        guard let dateTime = record["CD_dateTime"] as? Date else {
            throw SnapshotError.invalidInput("Missing dateTime in activity record")
        }

        // Extract activity type ID from reference
        guard let typeRef = record["CD_activityType"] as? CKRecord.Reference,
              let typeIDString = typeRef.recordID.recordName.components(separatedBy: "/").last,
              let typeID = UUID(uuidString: typeIDString) else {
            throw SnapshotError.invalidInput("Invalid activity type reference")
        }

        // Extract caree ID from reference
        guard let careeRef = record["CD_caree"] as? CKRecord.Reference,
              let careeIDString = careeRef.recordID.recordName.components(separatedBy: "/").last,
              let careeID = UUID(uuidString: careeIDString) else {
            throw SnapshotError.invalidInput("Invalid caree reference in activity")
        }

        self.id = id
        self.dateTime = dateTime
        self.notes = record["CD_notes"] as? String
        self.quantity = record["CD_quantity"] as? Double
        self.latitude = record["CD_latitude"] as? Double
        self.longitude = record["CD_longitude"] as? Double
        self.activityTypeID = typeID
        self.careeID = careeID
        self.dateCreated = (record["CD_dateCreated"] as? Date) ?? Date()
        self.syncState = .synced
    }

    /// Create snapshot from SwiftData Activity model
    init(from activity: Activity, activityTypeID: UUID, careeID: UUID) {
        self.id = activity.id
        self.dateTime = activity.dateTime
        self.notes = activity.notes
        self.quantity = activity.quantity
        self.latitude = activity.latitude
        self.longitude = activity.longitude
        self.activityTypeID = activityTypeID
        self.careeID = careeID
        self.dateCreated = activity.dateCreated
        self.syncState = .synced
    }

    /// Create new activity (for tracking on watch)
    init(
        id: UUID = UUID(),
        dateTime: Date,
        notes: String? = nil,
        quantity: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activityTypeID: UUID,
        careeID: UUID
    ) {
        self.id = id
        self.dateTime = dateTime
        self.notes = notes
        self.quantity = quantity
        self.latitude = latitude
        self.longitude = longitude
        self.activityTypeID = activityTypeID
        self.careeID = careeID
        self.dateCreated = Date()
        self.syncState = .pending
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ActivitySnapshot, rhs: ActivitySnapshot) -> Bool {
        lhs.id == rhs.id
    }
}
