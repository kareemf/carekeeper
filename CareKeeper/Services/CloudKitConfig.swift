import Foundation

/// CloudKit configuration constants
/// Pure CloudKit Architecture:
/// - Uses explicit CRUD operations instead of automatic SwiftData sync
/// - Records stored in default zone (CKRecordZone.default)
/// - Record IDs follow pattern: CD_{EntityName}/{UUID}
/// - Parent references use CKRecord.Reference for cascading deletes
enum CloudKitConfig {
    /// Legacy zone name used by SwiftData/CoreData CloudKit integration
    /// Pure CloudKit uses the default zone instead of this custom zone
    /// Kept for reference and legacy zone cleanup utilities
    static let zoneName = "com.apple.coredata.cloudkit.zone"

    /// The CloudKit container identifier for this app
    static let containerID = "iCloud.com.kareemf.CareKeeper2"

    /// The app group identifier for local data sharing between iOS and watchOS
    static let appGroupID = "group.com.kareemf.CareKeeper"
}
