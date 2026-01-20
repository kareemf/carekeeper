import Foundation

enum CloudKitNotificationAuthorFilter {
    static func shouldNotify(
        creatorRecordID: String?,
        creatorIDField: String?,
        currentUserRecordName: String?
    ) -> Bool {
        guard let currentUserRecordName else { return true }
        if let creatorIDField, creatorIDField != currentUserRecordName { return true }
        if let creatorRecordID, creatorRecordID == currentUserRecordName { return false }
        if creatorRecordID == nil, let creatorIDField, creatorIDField == currentUserRecordName { return false }
        return true
    }
}
