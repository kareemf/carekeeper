import SwiftUI

struct CareeListRowView: View {
    let caree: Caree
    var isShared: Bool = false

    @State private var isCheckingSync = false
    @State private var isSyncedToCloudKit: Bool? = nil
    @StateObject private var syncService = CloudKitSyncService()

    var body: some View {
        HStack {
            profileImageView

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(caree.name)
                        .font(.headline)

                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Text(NSLocalizedString("\(caree.activityTypes?.count ?? 0) Activity Types",
                                         comment: "Activity types count in caree row"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(NSLocalizedString("\(caree.activities?.count ?? 0) Activities",
                                         comment: "Activities count in caree row"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    #if os(iOS)
                    // Show share icon for shared carees, sync status for owned carees
                    if isShared {
                        // This caree is shared with me - show share icon
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if isCheckingSync || isSyncedToCloudKit != nil {
                        // This is my caree - show CloudKit sync status
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        CloudKitSyncStatusView(
                            isChecking: isCheckingSync,
                            isSynced: isSyncedToCloudKit,
                            size: .small
                        )
                    }
                    #endif
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            // Only check sync status for owned carees
            if !isShared {
                isCheckingSync = true
                isSyncedToCloudKit = await syncService.isSynced(caree: caree)
                isCheckingSync = false
            }
        }
    }
    
    private var profileImageView: some View {
        Group {
            if let imageData = caree.image, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
    }
}

#Preview {
    List {
        CareeListRowView(caree: PreviewData.sampleCaree)
        CareeListRowView(caree: PreviewData.sampleCareeWithImage)
    }
    .modelContainer(PreviewContainer.shared)
}
