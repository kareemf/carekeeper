import CloudKit
import Foundation

enum CloudKitNotificationAuthorFilter {
    static func shouldNotify(
        creatorRecordID: String?,
        creatorIDField: String?,
        currentUserRecordName: String?
    ) -> Bool {
        guard let currentUserRecordName else { return true }

        // If explicit field matches current user, suppress notification
        if let creatorIDField, creatorIDField == currentUserRecordName { return false }

        // If explicit field is a real (non-fallback) ID that differs, trust it and notify
        if let creatorIDField, creatorIDField != CKCurrentUserDefaultName { return true }

        // Field is missing or is __defaultOwner__ (unreliable fallback from watchOS);
        // fall through to CloudKit record metadata
        if let creatorRecordID, creatorRecordID == currentUserRecordName { return false }

        return true
    }
}
