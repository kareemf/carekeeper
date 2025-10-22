import SwiftUI
import SwiftData
import Combine

struct ActivityListView: View {
    @Environment(\.modelContext) private var modelContext

    let careeID: UUID

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Reactive state - updated when cache changes
    @State private var caree: Caree?
    @State private var activities: [Activity] = []

    @State private var selectedActivityType: ActivityType?
    @State private var showingFilterMenu = false
    @State private var error: Error?
    @State private var activityToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false

    init(careeID: UUID) {
        self.careeID = careeID
    }

    // Helper publishers to observe cache changes
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
        Group {
            if let caree = caree {
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
                                Label(NSLocalizedString("All Types", comment: "All activity types filter"),
                                      systemImage: selectedActivityType == nil ? "checkmark" : "")
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
                            Label(NSLocalizedString("Filter", comment: "Filter button"),
                                  systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .refreshable {
                    // Refresh cache on pull-to-refresh
                    try? await cacheService?.refreshCache()
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
                if let offsets = activityToDelete, let caree = caree {
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
            // Initial load: refresh cache and update activities
            try? await cacheService?.refreshCache()
            updateActivities()
        }
        .onReceive(myCareesPublisher) { _ in
            updateActivities()
        }
        .onReceive(sharedCareesPublisher) { _ in
            updateActivities()
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

    private func updateActivities() {
        guard let cacheService = cacheService else {
            caree = nil
            activities = []
            return
        }

        // Find the specific caree from cache (owned or shared)
        let foundCaree = cacheService.getCachedCaree(id: careeID)

        // Update caree and activities state
        caree = foundCaree

        if let foundCaree = foundCaree {
            // Extract and sort activities
            activities = (foundCaree.activities ?? []).sorted { $0.dateTime > $1.dateTime }
        } else {
            activities = []
        }
    }

    private func filteredActivities(for caree: Caree) -> [Activity] {
        // Use state activities array instead of reading from caree
        if let selectedType = selectedActivityType {
            return activities.filter { $0.activityType?.id == selectedType.id }
        }

        return activities
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
}

#Preview {
    NavigationStack {
        ActivityListView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
