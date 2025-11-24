import Combine
import SwiftData
import SwiftUI

struct ActivityListView: View {
    @Environment(\.modelContext) private var modelContext

    let careeID: UUID

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Reactive state - updated when cache changes
    @State private var caree: Caree?
    @State private var activities: [Activity] = []
    @State private var lastCursorDate: Date?
    @State private var hasMorePages = true
    @State private var isLoadingPage = false

    @State private var selectedActivityType: ActivityType?
    @State private var showingFilterMenu = false
    @State private var error: Error?
    @State private var activityToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false

    private let pageSize = 50

    init(careeID: UUID) {
        self.careeID = careeID
    }

    // Helper publishers to observe cache changes
    private var myCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService {
            cacheService.$myCarees.eraseToAnyPublisher()
        } else {
            Just([]).eraseToAnyPublisher()
        }
    }

    private var sharedCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService {
            cacheService.$sharedCarees.eraseToAnyPublisher()
        } else {
            Just([]).eraseToAnyPublisher()
        }
    }

    var body: some View {
        Group {
            if let caree {
                List {
                    if filteredActivities(for: caree).isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredActivities(for: caree)) { activity in
                            ActivityRowView(activity: activity)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            activityToDelete = offsets
                            showingDeleteConfirmation = true
                        }

                        if hasMorePages {
                            loadMoreRow
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle(NSLocalizedString("Activities", comment: "Activities list title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                selectedActivityType = nil
                            } label: {
                                Label(
                                    NSLocalizedString("All Types", comment: "All activity types filter"),
                                    systemImage: selectedActivityType == nil ? "checkmark" : ""
                                )
                            }

                            Divider()

                            ForEach(caree.sortedActivityTypes) { activityType in
                                Button {
                                    selectedActivityType = activityType
                                } label: {
                                    Label {
                                        Text("\(activityType.displayIcon) \(activityType.name)")
                                    } icon: {
                                        if selectedActivityType?.id == activityType.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(
                                NSLocalizedString("Filter", comment: "Filter button"),
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        }
                    }
                }
                .refreshable {
                    await refreshData()
                }
            } else {
                Text(NSLocalizedString("Caree not found", comment: "Caree not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .errorAlert($error)
        .confirmationDialog(
            NSLocalizedString("Delete Activity?", comment: "Delete activity confirmation title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                if let offsets = activityToDelete, let caree {
                    deleteActivities(at: offsets, from: caree)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                activityToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("This cannot be undone.", comment: "Delete confirmation message"))
        }
        .task {
            await refreshData()
        }
        .onReceive(cloudKitService.$cacheService.compactMap(\.self)) { _ in
            Task {
                await refreshData()
            }
        }
        .onReceive(myCareesPublisher) { _ in
            updateActivities()
        }
        .onReceive(sharedCareesPublisher) { _ in
            updateActivities()
        }
        .onReceive(sharedRecordsService.$sharedCarees.eraseToAnyPublisher()) { _ in
            updateActivities()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SharedCareeDataUpdated"))) { notification in
            if let updatedCareeID = notification.object as? UUID, updatedCareeID == careeID {
                updateActivities()
            }
        }
        .onChange(of: selectedActivityType) { _, _ in
            Task {
                await loadInitialPage()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(selectedActivityType == nil
                ? NSLocalizedString("No activities yet", comment: "Empty activities message")
                : NSLocalizedString("No activities for this type", comment: "Empty filtered activities message"))
                .font(.headline)
                .foregroundColor(.secondary)

            if selectedActivityType != nil {
                Button(NSLocalizedString("Show All", comment: "Show all activities button")) {
                    selectedActivityType = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @MainActor
    private func updateActivities() {
        guard let cacheService else {
            caree = nil
            activities = []
            return
        }

        // Find the specific caree from cache (owned or shared)
        let foundCaree = cacheService.getCachedCaree(id: careeID)

        caree = foundCaree
        if caree == nil {
            activities = []
            return
        }
        Task {
            await loadInitialPage()
        }
    }

    private func filteredActivities(for caree: Caree) -> [Activity] {
        // Use state activities array instead of reading from caree
        if let selectedType = selectedActivityType {
            return activities.filter { $0.activityType?.id == selectedType.id }
        }

        return activities
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if isLoadingPage {
                ProgressView()
            } else {
                Button(NSLocalizedString("Load more", comment: "Load more activities")) {
                    Task { await loadNextPage() }
                }
            }
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private func deleteActivities(at offsets: IndexSet, from caree: Caree) {
        let activities = filteredActivities(for: caree)

        Task {
            do {
                for index in offsets {
                    let activity = activities[index]
                    // Pure CloudKit: Delete via unified API (routes internally based on caree.isShared)
                    try await cloudKitService.deleteActivity(activity: activity, caree: caree)
                }

                // Cache is automatically updated by CloudKitDataService
                activityToDelete = nil
            } catch {
                await MainActor.run {
                    self.error = AppError.deleteFailed(error.localizedDescription)
                }
            }
        }
    }

    @Sendable
    private func refreshData() async {
        if let cacheService {
            try? await cacheService.refreshCache()
        }

        let needsSharedFetch = await MainActor.run { () -> Bool in
            guard let cacheService else { return true }
            guard let targetCaree = cacheService.getCachedCaree(id: careeID) else { return true }
            return targetCaree.isShared
        }

        if needsSharedFetch {
            await sharedRecordsService.fetchSharedCarees()
        }

        await MainActor.run {
            updateActivities()
        }
    }

    @MainActor
    private func loadInitialPage() async {
        guard let cacheService else {
            caree = nil
            activities = []
            return
        }

        caree = cacheService.getCachedCaree(id: careeID)
        activities = []
        lastCursorDate = nil
        hasMorePages = true
        await loadNextPage()
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoadingPage, hasMorePages, let caree else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let careeID = caree.id
        let selectedTypeID = selectedActivityType?.id
        let cursor = lastCursorDate

        let predicate: Predicate<Activity>
        if let typeID = selectedTypeID, let cursorDate = cursor {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.activityType?.id == typeID
                    && activity.dateTime < cursorDate
            }
        } else if let typeID = selectedTypeID {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.activityType?.id == typeID
            }
        } else if let cursorDate = cursor {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.dateTime < cursorDate
            }
        } else {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
            }
        }

        var fetch = FetchDescriptor<Activity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dateTime, order: .reverse)]
        )
        fetch.fetchLimit = pageSize

        do {
            let page = try modelContext.fetch(fetch)
            activities.append(contentsOf: page)
            lastCursorDate = activities.last?.dateTime
            if page.count < pageSize {
                hasMorePages = false
            }
        } catch {
            self.error = error
            hasMorePages = false
        }
    }
}

#Preview {
    NavigationStack {
        ActivityListView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
