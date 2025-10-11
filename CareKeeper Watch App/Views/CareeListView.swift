import SwiftUI
import SwiftData

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Caree.listOrder) private var myCarees: [Caree]  // Only private database records
    
    // Service for fetching shared records
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    
    @State private var error: Error?
    
    // Combined list of all carees (private + shared)
    private var allCarees: [Caree] {
        return myCarees + sharedRecordsService.sharedCarees
    }

    var body: some View {
        NavigationStack {
            Group {
                if allCarees.isEmpty {
                    emptyStateView
                } else {
                    careeListView
                }
            }
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .task {
                sharedRecordsService.setModelContext(modelContext)
                await sharedRecordsService.fetchSharedCarees()
            }
            .onReceive(sharedRecordsService.$error) { newError in
                if let newError = newError {
                    error = newError
                }
            }
            .errorAlert($error)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("No Carees", comment: "Empty state title"))
                .font(.headline)

            if sharedRecordsService.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text(NSLocalizedString("Loading shared carees...", comment: "Loading shared carees message"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("Add carees on iPhone or accept shared ones", comment: "Empty state description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var careeListView: some View {
        List(allCarees) { caree in
            NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                CareeRowView(
                    caree: caree, 
                    isShared: sharedRecordsService.sharedCarees.contains { $0.id == caree.id }
                )
            }
        }
        .refreshable {
            sharedRecordsService.setModelContext(modelContext)
            await sharedRecordsService.fetchSharedCarees()
        }
    }
}

struct CareeRowView: View {
    let caree: Caree
    let isShared: Bool

    var body: some View {
        HStack {
            ProfileImageView(caree: caree)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(caree.name)
                        .font(.headline)
                    
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }

                Text(NSLocalizedString("\(caree.activityTypes?.count ?? 0) Activity Types", comment: "Activity Types count"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ProfileImageView: View {
    let caree: Caree
    
    var body: some View {
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
    CareeListView()
        .modelContainer(PreviewContainer.shared)
}
