import CloudKit
import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Converts between domain models (Caree, ActivityType, Activity) and CloudKit CKRecords
/// Handles CKAsset creation for images, parent references, and field mapping
class CloudKitRecordConverter {
    private let logger = AppLogger.cloudkit
    private let fileManager = FileManager.default

    // MARK: - To CloudKit

    /// Convert Caree to CKRecord with optional image as CKAsset
    /// - Parameters:
    ///   - caree: The Caree domain model
    ///   - imageData: Optional image data to convert to CKAsset
    ///   - zoneID: Optional zoneID to place the record in (required for sharing)
    ///   - existingRecord: Optional existing record to update (preserves recordID)
    /// - Returns: CKRecord for CD_Caree
    func careeToRecord(
        _ caree: Caree,
        imageData: Data?,
        zoneID: CKRecordZone.ID? = nil,
        existingRecord: CKRecord? = nil
    ) async throws -> CKRecord {
        let recordID: CKRecord.ID = if let existing = existingRecord {
            existing.recordID
        } else {
            if let zoneID {
                CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)", zoneID: zoneID)
            } else {
                CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")
            }
        }

        let record = CKRecord(recordType: "CD_Caree", recordID: recordID)

        // Map fields
        record["CD_id"] = caree.id.uuidString as CKRecordValue
        record["CD_name"] = caree.name as CKRecordValue
        record["CD_listOrder"] = caree.listOrder as CKRecordValue
        record["CD_dateCreated"] = caree.dateCreated as CKRecordValue

        // Handle image as CKAsset (using CD_image_ckAsset field to avoid BYTES/Asset type conflict)
        if let imageData {
            do {
                let asset = try createImageAsset(from: imageData)
                record["CD_image_ckAsset"] = asset
                logger.info("Created CKAsset for caree image: \(caree.id)")
            } catch {
                logger.error("Failed to create image asset for caree \(caree.id): \(error.localizedDescription)")
                throw error
            }
        } else if existingRecord?["CD_image_ckAsset"] == nil {
            // Explicitly set to nil if no image and no existing image
            record["CD_image_ckAsset"] = nil
        }
        // If existingRecord has image and we don't provide new data, keep existing

        return record
    }

    /// Convert ActivityType to CKRecord with parent reference to Caree
    /// - Parameters:
    ///   - activityType: The ActivityType domain model
    ///   - parentCaree: The parent Caree record (for parent reference)
    ///   - zoneID: Optional zoneID to place the record in (required for sharing)
    ///   - existingRecord: Optional existing record to update
    /// - Returns: CKRecord for CD_ActivityType with parent set
    func activityTypeToRecord(
        _ activityType: ActivityType,
        parentCaree: CKRecord,
        zoneID: CKRecordZone.ID? = nil,
        existingRecord: CKRecord? = nil,
        creatorRecordName: String? = nil
    ) throws -> CKRecord {
        let recordID: CKRecord.ID = if let existing = existingRecord {
            existing.recordID
        } else {
            if let zoneID {
                CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)", zoneID: zoneID)
            } else {
                CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)")
            }
        }

        let record = CKRecord(recordType: "CD_ActivityType", recordID: recordID)

        // CRITICAL: Set parent reference for CloudKit sharing hierarchy
        // Parent references must use .none action (CloudKit requirement for sharing)
        record.parent = CKRecord.Reference(record: parentCaree, action: .none)

        // Map fields
        record["CD_id"] = activityType.id.uuidString as CKRecordValue
        record["CD_name"] = activityType.name as CKRecordValue
        record["CD_icon"] = activityType.icon as CKRecordValue?
        record["CD_hasQuantity"] = (activityType.hasQuantity ? 1 : 0) as CKRecordValue
        record["CD_quantityUnit"] = activityType.quantityUnit as CKRecordValue?
        record["CD_hasLocation"] = (activityType.hasLocation ? 1 : 0) as CKRecordValue
        record["CD_listOrder"] = activityType.listOrder as CKRecordValue
        record["CD_dateCreated"] = activityType.dateCreated as CKRecordValue

        // Relationship reference
        // Must use .none (not .deleteSelf) for records in a CloudKit sharing hierarchy.
        // Cascade deletion is handled manually by CloudKitDataService.deleteCaree().
        record["CD_caree"] = CKRecord.Reference(record: parentCaree, action: .none)

        logger.info("Created ActivityType record with parent: \(activityType.id)")
        return record
    }

    /// Convert Activity to CKRecord with parent reference to Caree
    /// - Parameters:
    ///   - activity: The Activity domain model
    ///   - parentCaree: The parent Caree record
    ///   - activityTypeRecord: The ActivityType record for reference
    ///   - zoneID: Optional zoneID to place the record in (required for sharing)
    ///   - existingRecord: Optional existing record to update
    /// - Returns: CKRecord for CD_Activity with parent set
    func activityToRecord(
        _ activity: Activity,
        parentCaree: CKRecord,
        activityTypeRecord: CKRecord,
        zoneID: CKRecordZone.ID? = nil,
        existingRecord: CKRecord? = nil,
        creatorRecordName: String? = nil
    ) throws -> CKRecord {
        let recordID: CKRecord.ID = if let existing = existingRecord {
            existing.recordID
        } else {
            if let zoneID {
                CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)", zoneID: zoneID)
            } else {
                CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)")
            }
        }

        let record = CKRecord(recordType: "CD_Activity", recordID: recordID)

        // CRITICAL: Set parent reference for CloudKit sharing hierarchy
        // Parent references must use .none action (CloudKit requirement for sharing)
        record.parent = CKRecord.Reference(record: parentCaree, action: .none)

        // Map required fields
        record["CD_id"] = activity.id.uuidString as CKRecordValue
        record["CD_dateTime"] = activity.dateTime as CKRecordValue
        record["CD_dateCreated"] = activity.dateCreated as CKRecordValue

        // Map optional fields
        record["CD_notes"] = activity.notes as CKRecordValue?
        record["CD_quantity"] = activity.quantity as CKRecordValue?
        record["CD_latitude"] = activity.latitude as CKRecordValue?
        record["CD_longitude"] = activity.longitude as CKRecordValue?

        // Creator tracking (for notifications)
        let resolvedCreatorRecordName = creatorRecordName ?? CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName
        record["CD_creatorUserRecordID"] = resolvedCreatorRecordName as CKRecordValue

        // Relationship references
        // Must use .none (not .deleteSelf) for records in a CloudKit sharing hierarchy.
        // Cascade deletion is handled manually by CloudKitDataService.deleteCaree().
        record["CD_caree"] = CKRecord.Reference(record: parentCaree, action: .none)
        record["CD_activityType"] = CKRecord.Reference(record: activityTypeRecord, action: .none)

        logger.info("Created Activity record with parent: \(activity.id)")
        return record
    }

    // MARK: - From CloudKit

    /// Convert CKRecord to Caree domain model
    /// - Parameter record: CKRecord with CD_Caree type
    /// - Returns: Caree domain model with image data loaded from CKAsset
    func recordToCaree(_ record: CKRecord) async throws -> Caree {
        guard record.recordType == "CD_Caree" else {
            throw ConversionError.invalidRecordType(expected: "CD_Caree", actual: record.recordType)
        }

        guard let cdId = record["CD_id"] as? String,
              let uuid = UUID(uuidString: cdId),
              let name = record["CD_name"] as? String
        else {
            logger.error("Caree record missing required fields: \(record.recordID.recordName)")
            throw ConversionError.missingRequiredField(recordType: "CD_Caree", field: "CD_id or CD_name")
        }

        let caree = Caree(
            name: name,
            listOrder: record["CD_listOrder"] as? Int ?? 0
        )
        caree.id = uuid

        // Load image from CKAsset if present
        if let imageAsset = record["CD_image_ckAsset"] as? CKAsset {
            do {
                let imageData = try await loadImageData(from: imageAsset)
                caree.image = imageData
                logger.info("Loaded image for caree: \(uuid)")
            } catch {
                logger.warning("Failed to load image for caree \(uuid): \(error.localizedDescription)")
                // Don't fail the entire conversion, just skip the image
            }
        }

        if let dateCreated = record["CD_dateCreated"] as? Date {
            caree.dateCreated = dateCreated
        }

        return caree
    }

    /// Convert CKRecord to ActivityType domain model
    /// - Parameter record: CKRecord with CD_ActivityType type
    /// - Returns: ActivityType domain model
    func recordToActivityType(_ record: CKRecord) throws -> ActivityType {
        guard record.recordType == "CD_ActivityType" else {
            throw ConversionError.invalidRecordType(expected: "CD_ActivityType", actual: record.recordType)
        }

        guard let cdId = record["CD_id"] as? String,
              let uuid = UUID(uuidString: cdId),
              let name = record["CD_name"] as? String
        else {
            logger.error("ActivityType record missing required fields: \(record.recordID.recordName)")
            throw ConversionError.missingRequiredField(recordType: "CD_ActivityType", field: "CD_id or CD_name")
        }

        let activityType = ActivityType(
            name: name,
            icon: record["CD_icon"] as? String,
            hasQuantity: (record["CD_hasQuantity"] as? Int ?? 0) != 0,
            quantityUnit: record["CD_quantityUnit"] as? String,
            hasLocation: (record["CD_hasLocation"] as? Int ?? 0) != 0,
            listOrder: record["CD_listOrder"] as? Int ?? 0
        )
        activityType.id = uuid

        if let dateCreated = record["CD_dateCreated"] as? Date {
            activityType.dateCreated = dateCreated
        }

        return activityType
    }

    /// Convert CKRecord to Activity domain model
    /// - Parameter record: CKRecord with CD_Activity type
    /// - Returns: Activity domain model
    func recordToActivity(_ record: CKRecord) throws -> Activity {
        guard record.recordType == "CD_Activity" else {
            throw ConversionError.invalidRecordType(expected: "CD_Activity", actual: record.recordType)
        }

        guard let cdId = record["CD_id"] as? String,
              let uuid = UUID(uuidString: cdId),
              let dateTime = record["CD_dateTime"] as? Date
        else {
            logger.error("Activity record missing required fields: \(record.recordID.recordName)")
            throw ConversionError.missingRequiredField(recordType: "CD_Activity", field: "CD_id or CD_dateTime")
        }

        let activity = Activity(
            dateTime: dateTime,
            notes: record["CD_notes"] as? String,
            quantity: record["CD_quantity"] as? Double,
            latitude: record["CD_latitude"] as? Double,
            longitude: record["CD_longitude"] as? Double
        )
        activity.id = uuid

        if let dateCreated = record["CD_dateCreated"] as? Date {
            activity.dateCreated = dateCreated
        }

        return activity
    }

    // MARK: - CKAsset Handling

    /// Create a CKAsset from image data
    /// - Parameter data: Image data (PNG, JPEG, etc.)
    /// - Returns: CKAsset pointing to temporary file
    func createImageAsset(from data: Data) throws -> CKAsset {
        // Create temporary file for CKAsset
        let tempDirectory = fileManager.temporaryDirectory
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            let asset = CKAsset(fileURL: fileURL)
            logger.info("Created CKAsset at: \(fileURL.path)")
            return asset
        } catch {
            logger.error("Failed to write image data to temp file: \(error.localizedDescription)")
            throw ConversionError.assetCreationFailed(reason: error.localizedDescription)
        }
    }

    /// Load image data from a CKAsset
    /// - Parameter asset: CKAsset from CloudKit record
    /// - Returns: Image data
    func loadImageData(from asset: CKAsset) async throws -> Data {
        guard let fileURL = asset.fileURL else {
            logger.error("CKAsset has no fileURL")
            throw ConversionError.assetLoadFailed(reason: "CKAsset fileURL is nil")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            logger.info("Loaded image data from CKAsset: \(fileURL.path)")
            return data
        } catch {
            logger.error("Failed to read data from CKAsset fileURL: \(error.localizedDescription)")
            throw ConversionError.assetLoadFailed(reason: error.localizedDescription)
        }
    }

    /// Clean up temporary files created for CKAssets
    /// Call this after successful CloudKit save operations
    func cleanupTempFiles() {
        let tempDirectory = fileManager.temporaryDirectory

        do {
            let tempFiles = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            )

            for fileURL in tempFiles where fileURL.pathExtension == "jpg" {
                try? fileManager.removeItem(at: fileURL)
            }

            logger.info("Cleaned up temporary CKAsset files")
        } catch {
            logger.warning("Failed to cleanup temp files: \(error.localizedDescription)")
        }
    }
}

// MARK: - Conversion Errors

enum ConversionError: LocalizedError {
    case invalidRecordType(expected: String, actual: String)
    case missingRequiredField(recordType: String, field: String)
    case assetCreationFailed(reason: String)
    case assetLoadFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidRecordType(expected, actual):
            "Invalid record type: expected \(expected), got \(actual)"
        case let .missingRequiredField(recordType, field):
            "Missing required field '\(field)' in \(recordType) record"
        case let .assetCreationFailed(reason):
            "Failed to create CKAsset: \(reason)"
        case let .assetLoadFailed(reason):
            "Failed to load data from CKAsset: \(reason)"
        }
    }
}
