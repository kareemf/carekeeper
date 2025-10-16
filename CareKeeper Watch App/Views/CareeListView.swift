import SwiftUI
import Combine
import SwiftData

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext

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

    // Combined list of all carees - updated when cache changes
    @State private var allCarees: [Caree] = []

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

    private func updateAllCarees() {
        guard let cacheService = cacheService else {
            allCarees = []
            return
        }
        let newCombined = cacheService.myCarees + cacheService.sharedCarees
        // Only assign when the identity + order actually changed to keep navigation stable
        if !arraysEqualByID(lhs: allCarees, rhs: newCombined) {
            allCarees = newCombined
        }
    }

    private var careeListView: some View {
        List(allCarees) { caree in
            NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
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

    // MARK: - Helpers

    private func arraysEqualByID<T: AnyObject>(lhs: [T], rhs: [T]) -> Bool {
        func id(of obj: AnyObject) -> UUID? {
            if let c = obj as? Caree { return c.id }
            if let a = obj as? Activity { return a.id }
            if let t = obj as? ActivityType { return t.id }
            return nil
        }
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if id(of: l) != id(of: r) { return false }
        }
        return true
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
