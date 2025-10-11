import SwiftUI

struct CareeListRowView: View {
    let caree: Caree
    var isShared: Bool = false

    @State private var hasShare = false
    @StateObject private var sharingService = CloudKitSharingService()
    @Environment(\.modelContext) private var modelContext

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
                    // Share indicator - show if caree is shared with others
                    if hasShare {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    #endif
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            // Check if this caree has a share (is shared with others)
            if !isShared {
                hasShare = await sharingService.isShared(caree, in: modelContext)
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
