import SwiftUI
import Combine
import SwiftData

struct CareeListView: View {
    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    @State private var error: Error?
    @State private var deletionProgress: Double = 0.0
    @State private var isDeleting = false

    // Track combined carees by stable identifier to avoid holding onto invalidated models
    @State private var careeIDs: [UUID] = []

    // Helper publishers to unify types and provide safe fallbacks
    private var myCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService = cacheService {
            return cacheService.$myCarees.eraseToAnyPublisher()
        } else {
            return Just([]).eraseToAnyPublisher()
        }
    }

    private var sharedCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService = cacheService {
            return cacheService.$sharedCarees.eraseToAnyPublisher()
        } else {
            return Just([]).eraseToAnyPublisher()
        }
    }

    @State private var navigationPath = NavigationPath()

    var body: some View {
        let carees = resolvedCarees()

        return NavigationStack(path: $navigationPath) {
            Group {
                if carees.isEmpty {
                    emptyStateView
                } else {
                    careeListView(carees)
                }
            }
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .task {
                updateAllCarees()
                // Fetch shared carees; service will push into cache (batched)
                await sharedRecordsService.fetchSharedCarees()
            }
            .onReceive(sharedRecordsService.$error) { newError in
                if let newError = newError {
                    error = newError
                }
            }
            .onReceive(myCareesPublisher) { _ in
                updateAllCarees()
            }
            .onReceive(sharedCareesPublisher) { _ in
                updateAllCarees()
            }
            .onReceive(cloudKitService.$deletionProgress) { progress in
                isDeleting = progress.isDeleting
                deletionProgress = progress.progress
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 8) {
                            ProgressView(value: deletionProgress) {
                                Text(NSLocalizedString("Deleting...", comment: "Deletion progress title"))
                                    .font(.caption)
                            }
                            .progressViewStyle(.linear)
                            .tint(.white)

                            Text("\(Int(deletionProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                }
            }
            .errorAlert($error)
        }
        .navigationDestination(for: UUID.self) { careeID in
            CareeDetailView(careeID: careeID)
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

    private func resolvedCarees() -> [Caree] {
        guard let cacheService = cacheService else {
            return []
        }

        return careeIDs.compactMap { cacheService.getCachedCaree(id: $0) }
    }

    private func updateAllCarees() {
        guard let cacheService = cacheService else {
            careeIDs = []
            return
        }

        let newIDs = (cacheService.myCarees + cacheService.sharedCarees).map { $0.id }
        if careeIDs != newIDs {
            careeIDs = newIDs
        }
    }

    private func careeListView(_ carees: [Caree]) -> some View {
        List(carees) { caree in
            NavigationLink(value: caree.id) {
                CareeRowView(
                    caree: caree,
                    isShared: caree.isShared  // Use cache metadata
                )
            }
        }
        .refreshable {
            // Refresh shared carees; LocalCacheService will update via batched apply
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
