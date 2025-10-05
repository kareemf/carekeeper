import SwiftUI

/// Reusable CloudKit sync status indicator
struct CloudKitSyncStatusView: View {
    let isChecking: Bool
    let isSynced: Bool?
    let size: Size

    enum Size {
        case small  // For list rows (caption)
        case medium // For headers (body)

        var font: Font {
            switch self {
            case .small: return .caption
            case .medium: return .body
            }
        }

        var scale: CGFloat {
            switch self {
            case .small: return 0.7
            case .medium: return 0.7
            }
        }
    }

    var body: some View {
        Group {
            if isChecking {
                ProgressView()
                    .scaleEffect(size.scale)
            } else if let isSynced = isSynced {
                Image(systemName: isSynced ? "icloud.and.arrow.up.fill" : "icloud.slash")
                    .foregroundColor(isSynced ? .green : .gray.opacity(0.3))
                    .font(size.font)
                    .help(isSynced ? "Synced to iCloud" : "Not synced to iCloud")
            }
        }
    }
}

#Preview("Small - Synced") {
    CloudKitSyncStatusView(isChecking: false, isSynced: true, size: .small)
}

#Preview("Small - Not Synced") {
    CloudKitSyncStatusView(isChecking: false, isSynced: false, size: .small)
}

#Preview("Small - Loading") {
    CloudKitSyncStatusView(isChecking: true, isSynced: nil, size: .small)
}

#Preview("Medium - Synced") {
    CloudKitSyncStatusView(isChecking: false, isSynced: true, size: .medium)
}
