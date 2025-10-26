import SwiftUI

/// ActivityListView rebuilt with lazy loading and pagination
/// Key features:
/// - Lazy loads activities when view appears (not upfront)
/// - Only loads last 48h by default
/// - Pagination: "Load Older" button for more history
/// - Uses snapshots instead of SwiftData models
/// - Task cancellation and memory cleanup
struct ActivityListView: View {

    let careeSnapshot: CareeSnapshot
    let activityTypes: [ActivityTypeSnapshot]

    @EnvironmentObject private var dataProvider: WatchDataProvider
    @State private var loadTask: Task<Void, Never>?
    @State private var hoursToLoad: TimeInterval = 48 * 3600  // Start with 48h
    @State private var filterActivityTypeID: UUID? = nil

    private var activities: [ActivitySnapshot] {
        dataProvider.recentActivitiesByCaree[careeSnapshot.id] ?? []
    }

    private var filteredActivities: [ActivitySnapshot] {
        guard let filterID = filterActivityTypeID else {
            return activities
        }
        return activities.filter { $0.activityTypeID == filterID }
    }

    private var isLoading: Bool {
        dataProvider.recentActivitiesByCaree[careeSnapshot.id] == nil
    }

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if filteredActivities.isEmpty {
                emptyStateView
            } else {
                activityList
            }
        }
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterButton
            }
        }
        .task {
            // Lazy load activities when view appears
            loadTask?.cancel()

            loadTask = Task {
                guard !Task.isCancelled else { return }

                MemoryMonitor.logMemoryUsage(context: "ActivityListView - Before Load")

                await dataProvider.loadRecentActivities(for: careeSnapshot.id, hoursBack: hoursToLoad)

                guard !Task.isCancelled else { return }

                MemoryMonitor.logMemoryUsage(context: "ActivityListView - After Load")
            }

            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading Activities...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            if filterActivityTypeID != nil {
                Text("No Matching Activities")
                    .font(.headline)

                Text("No activities found for this type in the selected time range")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    filterActivityTypeID = nil
                } label: {
                    Text("Clear Filter")
                }
                .buttonStyle(.bordered)
            } else {
                Text("No Activities")
                    .font(.headline)

                Text("Track an activity to see it appear here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var activityList: some View {
        List {
            ForEach(filteredActivities) { activity in
                NavigationLink {
                    ActivityDetailView(activitySnapshot: activity)
                        .environmentObject(dataProvider)
                } label: {
                    ActivityRowView(
                        activity: activity,
                        activityType: activityTypes.first { $0.id == activity.activityTypeID }
                    )
                }
            }

            // Pagination: load more if we hit the limit
            if activities.count >= SelectiveCloudKitService.maxActivitiesPerCaree {
                loadMoreButton
            }
        }
        .refreshable {
            guard !Task.isCancelled else { return }
            await dataProvider.loadRecentActivities(for: careeSnapshot.id, hoursBack: hoursToLoad)
        }
    }

    private var filterButton: some View {
        Button {
            cycleFilter()
        } label: {
            if let filterID = filterActivityTypeID,
               let activityType = activityTypes.first(where: { $0.id == filterID }) {
                // Filtering by specific type
                HStack(spacing: 4) {
                    Text(activityType.icon)
                    Text(activityType.name)
                        .font(.caption)
                }
            } else {
                // Show all
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func cycleFilter() {
        if let currentFilterID = filterActivityTypeID,
           let currentIndex = activityTypes.firstIndex(where: { $0.id == currentFilterID }) {
            // Move to next type, or back to "All" if at end
            let nextIndex = currentIndex + 1
            if nextIndex < activityTypes.count {
                filterActivityTypeID = activityTypes[nextIndex].id
            } else {
                filterActivityTypeID = nil  // Back to "All"
            }
        } else {
            // Currently showing all, move to first type
            filterActivityTypeID = activityTypes.first?.id
        }
    }

    private var loadMoreButton: some View {
        Button {
            hoursToLoad += 48 * 3600  // Add another 48h
            Task {
                await dataProvider.loadRecentActivities(for: careeSnapshot.id, hoursBack: hoursToLoad)
            }
        } label: {
            HStack {
                Spacer()
                Text("Load Older Activities")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
            }
        }
    }
}

// MARK: - Row View

/// Activity row using snapshots
struct ActivityRowView: View {
    let activity: ActivitySnapshot
    let activityType: ActivityTypeSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activityType?.icon ?? "⭐")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activityType?.name ?? "Unknown")
                        .font(.headline)

                    Text(activity.dateTime, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Sync state indicator
                if activity.syncState != .synced {
                    syncStateIndicator(for: activity.syncState)
                }
            }

            if let quantity = activity.quantity,
               let unit = activityType?.quantityUnit {
                Text("\(String(format: "%.1f", quantity)) \(unit)")
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

    @ViewBuilder
    private func syncStateIndicator(for state: ActivitySnapshot.SyncState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(.orange)
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.red)
        case .synced:
            EmptyView()
        }
    }
}

#Preview {
    let careeSnapshot = CareeSnapshot(
        from: PreviewData.sampleCareeWithActivities
    )

    let activityTypes = PreviewData.sampleCareeWithActivities.sortedActivityTypes.map {
        ActivityTypeSnapshot(from: $0, careeID: careeSnapshot.id)
    }

    return NavigationStack {
        ActivityListView(
            careeSnapshot: careeSnapshot,
            activityTypes: activityTypes
        )
        .environmentObject(WatchDataProvider())
    }
}
