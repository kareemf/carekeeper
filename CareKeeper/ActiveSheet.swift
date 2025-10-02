// Temporary ActiveSheet enum for v1 sharing compatibility
// This will be updated when we implement v2 sharing in Phase 2

import Foundation
import CloudKit

enum ActiveSheet: Identifiable {
    case cloudSharingSheet(CKShare)
    case participantView(CKShare)
    
    var id: String {
        switch self {
        case .cloudSharingSheet(let share):
            return "cloudSharing-\(share.recordID.recordName)"
        case .participantView(let share):
            return "participant-\(share.recordID.recordName)"
        }
    }
}