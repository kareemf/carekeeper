import Foundation
import CloudKit
import SwiftData

/// SwiftData model to track accepted CloudKit shares
/// This allows us to know which Caree records are available in the shared database
@Model
final class AcceptedShare {
    /// The CloudKit record ID of the CKShare (as string)
    var shareRecordID: String = ""
    
    /// The CloudKit record ID of the root record being shared (as string)
    var rootRecordID: String = ""
    
    /// When this share was accepted by the user
    var dateAccepted: Date = Date()
    
    /// Optional title from the share for display purposes
    var shareTitle: String?
    
    /// The CloudKit zone ID where this share exists
    var zoneID: String = ""
    
    init(shareRecordID: String, rootRecordID: String, shareTitle: String? = nil, zoneID: String = CloudKitConfig.zoneName) {
        self.shareRecordID = shareRecordID
        self.rootRecordID = rootRecordID
        self.shareTitle = shareTitle
        self.zoneID = zoneID
        self.dateAccepted = Date()
    }
}

// MARK: - Computed Properties
extension AcceptedShare {
    /// Convert stored string back to CKRecord.ID for the share
    var ckShareRecordID: CKRecord.ID {
        // Parse the record ID string back to CKRecord.ID
        let components = shareRecordID.split(separator: "/")
        if components.count >= 2 {
            let recordName = String(components[0])
            let zoneName = String(components[1])
            let zoneID = CKRecordZone.ID(zoneName: zoneName)
            return CKRecord.ID(recordName: recordName, zoneID: zoneID)
        } else {
            // Fallback to default zone
            return CKRecord.ID(recordName: shareRecordID, zoneID: CKRecordZone.ID(zoneName: zoneID))
        }
    }
    
    /// Convert stored string back to CKRecord.ID for the root record
    var ckRootRecordID: CKRecord.ID {
        // Parse the record ID string back to CKRecord.ID
        let components = rootRecordID.split(separator: "/")
        if components.count >= 2 {
            let recordName = String(components[0])
            let zoneName = String(components[1])
            let zoneID = CKRecordZone.ID(zoneName: zoneName)
            return CKRecord.ID(recordName: recordName, zoneID: zoneID)
        } else {
            // Fallback to default zone
            return CKRecord.ID(recordName: rootRecordID, zoneID: CKRecordZone.ID(zoneName: zoneID))
        }
    }
}

// MARK: - Helper Extensions
extension CKRecord.ID {
    /// Convert CKRecord.ID to string for storage
    var storageString: String {
        return "\(recordName)/\(zoneID.zoneName)"
    }
}
