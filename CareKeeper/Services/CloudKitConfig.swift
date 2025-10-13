import Foundation

/// CloudKit configuration constants
/// These values are determined by Apple's SwiftData/CoreData CloudKit integration
enum CloudKitConfig {
    /// The CloudKit zone name used by SwiftData for syncing
    /// This is a framework constant and cannot be customized
    static let zoneName = "com.apple.coredata.cloudkit.zone"

    /// The CloudKit container identifier for this app
    static let containerID = "iCloud.com.kareemf.CareKeeper2"

    /// The app group identifier for local data sharing between iOS and watchOS
    static let appGroupID = "group.com.kareemf.CareKeeper"
}
