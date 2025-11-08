import Foundation

/// CloudKit configuration constants
/// Pure CloudKit Architecture:
/// - Uses explicit CRUD operations instead of automatic SwiftData sync
/// - Records stored in default zone (CKRecordZone.default)
/// - Record IDs follow pattern: CD_{EntityName}/{UUID}
/// - Parent references use CKRecord.Reference for cascading deletes
enum CloudKitConfig {
    private static func loadPlist(named name: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    private static let config: [String: Any] = {
        if let custom = loadPlist(named: "Config") {
            return custom
        }
        if let fallback = loadPlist(named: "Config.default") {
            return fallback
        }
        return [:]
    }()

    static let zoneName = config["ZONE_NAME"] as? String ?? "com.example.carekeeper.zone"
    static let containerID = config["CLOUDKIT_CONTAINER_ID"] as? String ?? "iCloud.com.example.CareKeeper"
    static let appGroupID = config["APP_GROUP_IDENTIFIER"] as? String ?? "group.com.example.CareKeeper"
}
