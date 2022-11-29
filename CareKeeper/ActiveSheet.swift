import CloudKit

enum ActiveSheet: Identifiable, Equatable {
    case activityTracking1
    case activityTracking2(Behavior)
    case activityDetail(Activity)
    case behaviorDetail(Behavior)
    case participantView(CKShare)
    case cloudSharingSheet(CKShare)
//    TODO: remove
    case managingSharesView
    case sharePicker(Caree)
    case careeContextMenu(Caree)
#if os(iOS)
    case fullImage
#endif

    /**
     Use the enumeration member name string as the identifier for Identifiable.
     In the case where an enumeration has an associated value, use the label, which is equal to the member name string.
     */
    var id: String {
        let mirror = Mirror(reflecting: self)
        if let label = mirror.children.first?.label {
            return label
        } else {
            return "\(self)"
        }
    }
}

