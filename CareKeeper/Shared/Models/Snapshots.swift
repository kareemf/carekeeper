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
struct CareeSnapshot: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let imageData: Data?
    let changeTag: String?
    let isShared: Bool
    let listOrder: Int
    let dateCreated: Date
    let zoneName: String
    let zoneOwnerName: String?

    // Pre-loaded count, NOT a relationship!
    // This prevents accessing caree.activityTypes which can trigger crashes
    var activityTypeCount: Int = 0

    init(
        id: UUID,
        name: String,
        imageData: Data?,
        isShared: Bool,
        changeTag: String? = nil,
        listOrder: Int,
        dateCreated: Date,
        zoneName: String = CloudKitConfig.zoneName,
        zoneOwnerName: String? = nil,
        activityTypeCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.changeTag = changeTag
        self.isShared = isShared
        self.listOrder = listOrder
        self.dateCreated = dateCreated
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.activityTypeCount = activityTypeCount
    }

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

        // Load image from CKAsset (using CD_image_ckAsset field)
        if let imageAsset = record["CD_image_ckAsset"] as? CKAsset,
           let imageURL = imageAsset.fileURL,
           let imageData = try? Data(contentsOf: imageURL) {
            self.imageData = imageData
        } else {
            self.imageData = nil
        }

        self.isShared = isShared
        self.listOrder = (record["CD_listOrder"] as? Int) ?? 0
        self.dateCreated = (record["CD_dateCreated"] as? Date) ?? Date()
        self.changeTag = record.recordChangeTag
        self.zoneName = record.recordID.zoneID.zoneName
        self.zoneOwnerName = record.recordID.zoneID.ownerName
    }

    /// Create snapshot from SwiftData Caree model
    init(from caree: Caree) {
        self.init(
            id: caree.id,
            name: caree.name,
            imageData: caree.image,
            isShared: caree.isShared,
            changeTag: nil,
            listOrder: caree.listOrder,
            dateCreated: caree.dateCreated
        )
        // Count must be set separately to avoid relationship access
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case imageData
        case changeTag
        case isShared
        case listOrder
        case dateCreated
        case activityTypeCount
        case zoneName
        case zoneOwnerName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        changeTag = try container.decodeIfPresent(String.self, forKey: .changeTag)
        isShared = try container.decode(Bool.self, forKey: .isShared)
        listOrder = try container.decode(Int.self, forKey: .listOrder)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        activityTypeCount = try container.decodeIfPresent(Int.self, forKey: .activityTypeCount) ?? 0
        zoneName = try container.decodeIfPresent(String.self, forKey: .zoneName) ?? CloudKitConfig.zoneName
        zoneOwnerName = try container.decodeIfPresent(String.self, forKey: .zoneOwnerName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(changeTag, forKey: .changeTag)
        try container.encode(isShared, forKey: .isShared)
        try container.encode(listOrder, forKey: .listOrder)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(activityTypeCount, forKey: .activityTypeCount)
        try container.encode(zoneName, forKey: .zoneName)
        try container.encodeIfPresent(zoneOwnerName, forKey: .zoneOwnerName)
    }

    func updating(imageData: Data?) -> CareeSnapshot {
        CareeSnapshot(
            id: id,
            name: name,
            imageData: imageData,
            isShared: isShared,
            changeTag: changeTag,
            listOrder: listOrder,
            dateCreated: dateCreated,
            zoneName: zoneName,
            zoneOwnerName: zoneOwnerName,
            activityTypeCount: activityTypeCount
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CareeSnapshot, rhs: CareeSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.imageData == rhs.imageData &&
        lhs.changeTag == rhs.changeTag &&
        lhs.isShared == rhs.isShared &&
        lhs.listOrder == rhs.listOrder &&
        lhs.dateCreated == rhs.dateCreated &&
        lhs.activityTypeCount == rhs.activityTypeCount &&
        lhs.zoneName == rhs.zoneName &&
        lhs.zoneOwnerName == rhs.zoneOwnerName
    }
}

/// Immutable snapshot of an ActivityType for watch UI
struct ActivityTypeSnapshot: Identifiable, Hashable, Codable, Sendable {
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
struct ActivitySnapshot: Identifiable, Hashable, Codable, Sendable {
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

    enum SyncState: Hashable, Codable, Sendable {
        case pending
        case syncing
        case synced
        case failed(String)

        private enum CodingKeys: String, CodingKey {
            case state
            case errorMessage
        }

        private enum State: String, Codable {
            case pending
            case syncing
            case synced
            case failed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let state = try container.decode(State.self, forKey: .state)

            switch state {
            case .pending:
                self = .pending
            case .syncing:
                self = .syncing
            case .synced:
                self = .synced
            case .failed:
                let message = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "Unknown error"
                self = .failed(message)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .pending:
                try container.encode(State.pending, forKey: .state)
            case .syncing:
                try container.encode(State.syncing, forKey: .state)
            case .synced:
                try container.encode(State.synced, forKey: .state)
            case .failed(let message):
                try container.encode(State.failed, forKey: .state)
                try container.encode(message, forKey: .errorMessage)
            }
        }
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

    /// Create new activity (for tracking on watch or updating existing)
    init(
        id: UUID = UUID(),
        dateTime: Date,
        notes: String? = nil,
        quantity: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activityTypeID: UUID,
        careeID: UUID,
        dateCreated: Date = Date(),
        syncState: SyncState = .pending
    ) {
        self.id = id
        self.dateTime = dateTime
        self.notes = notes
        self.quantity = quantity
        self.latitude = latitude
        self.longitude = longitude
        self.activityTypeID = activityTypeID
        self.careeID = careeID
        self.dateCreated = dateCreated
        self.syncState = syncState
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ActivitySnapshot, rhs: ActivitySnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.dateTime == rhs.dateTime &&
        lhs.notes == rhs.notes &&
        lhs.quantity == rhs.quantity &&
        lhs.latitude == rhs.latitude &&
        lhs.longitude == rhs.longitude &&
        lhs.activityTypeID == rhs.activityTypeID &&
        lhs.careeID == rhs.careeID &&
        lhs.dateCreated == rhs.dateCreated &&
        lhs.syncState == rhs.syncState
    }
}
