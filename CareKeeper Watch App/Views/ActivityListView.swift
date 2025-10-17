import SwiftUI
import SwiftData

struct ActivityListView: View {
    let careeID: UUID

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedDataService: CloudKitSharedDataService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Get the specific caree from cache
    private var caree: Caree? {
        cacheService?.getCachedCaree(id: careeID)
    }

    @State private var selectedActivityType: ActivityType?
    @State private var error: Error?
    @State private var activityToDelete: Activity?
    @State private var showingDeleteConfirmation = false

    init(careeID: UUID) {
        self.careeID = careeID
    }

    var body: some View {
        Group {
            if let caree = caree {
                List {
                    if filteredActivities(for: caree).isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredActivities(for: caree)) { activity in
                            NavigationLink(destination: ActivityDetailView(activityID: activity.id)) {
                                activityRow(for: activity)
                            }
                        }
                        .onDelete { offsets in
                            if let index = offsets.first {
                                activityToDelete = filteredActivities(for: caree)[index]
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Activities", comment: "Activities list title"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            cycleFilter(for: caree)
                        } label: {
                            if let selectedType = selectedActivityType {
                                Text(selectedType.displayIcon)
                            } else {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
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
                if let activity = activityToDelete {
                    deleteActivity(activity)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                activityToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("This cannot be undone.", comment: "Delete confirmation message"))
        }
        .task {
            // Light-weight cache refresh (debounced/coalesced)
            try? await cacheService?.refreshCache()
        }
    }

    private func activityRow(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activity.activityType?.displayIcon ?? "⭐")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.activityType?.name ?? NSLocalizedString("Unknown", comment: "Unknown activity type"))
                        .font(.headline)

                    Text(activity.formattedDateTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if let formattedQuantity = activity.formattedQuantity {
                Text(formattedQuantity)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = activity.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(selectedActivityType == nil
                 ? NSLocalizedString("No activities yet", comment: "Empty activities message")
                 : NSLocalizedString("No activities for this type", comment: "Empty filtered activities message"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if selectedActivityType != nil {
                Button(NSLocalizedString("Show All", comment: "Show all activities button")) {
                    selectedActivityType = nil
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func filteredActivities(for caree: Caree) -> [Activity] {
        let activities = (caree.activities ?? []).sorted { $0.dateTime > $1.dateTime }

        if let selectedType = selectedActivityType {
            return activities.filter { $0.activityType?.id == selectedType.id }
        }

        return activities
    }

    private func deleteActivity(_ activity: Activity) {
        guard let caree = activity.caree else {
            self.error = AppError.invalidInput("Activity has no associated caree")
            return
        }

        let isShared = caree.isShared  // Use cache metadata

        Task {
            do {
                if isShared {
                    // Shared path via CloudKitSharedDataService
                    try await sharedDataService.deleteActivity(activity, caree: caree)
                } else {
                    // Owned path via CloudKitDataService
                    try await cloudKitService.deleteActivity(activity, isShared: false)
                }

                await MainActor.run {
                    activityToDelete = nil
                }
            } catch {
                await MainActor.run {
                    self.error = AppError.deleteFailed(error.localizedDescription)
                }
            }
        }
    }

    private func cycleFilter(for caree: Caree) {
        let types = caree.sortedActivityTypes

        if types.isEmpty {
            selectedActivityType = nil
            return
        }

        if let currentType = selectedActivityType,
           let currentIndex = types.firstIndex(where: { $0.id == currentType.id }) {
            // Move to next type or wrap to "All"
            let nextIndex = currentIndex + 1
            if nextIndex < types.count {
                selectedActivityType = types[nextIndex]
            } else {
                selectedActivityType = nil  // Back to "All"
            }
        } else {
            // No filter or not found, select first type
            selectedActivityType = types.first
        }
    }
}

#Preview {
    NavigationStack {
        ActivityListView(careeID: PreviewData.sampleCareeWithActivities.id)
    }
    .modelContainer(PreviewContainer.shared)
}
