import SwiftUI

/// CareeDetailView rebuilt with lazy loading and defensive patterns
/// Key changes:
/// - Lazy loads activity types when view appears (not loaded in CareeListView)
/// - Uses snapshots instead of SwiftData models
/// - Task cancellation on view disappear
/// - Memory cleanup when leaving view
/// - No relationship access (caree.activityTypes, etc.)
struct CareeDetailView: View {

    let careeSnapshot: CareeSnapshot

    @EnvironmentObject private var dataProvider: WatchDataProvider
    @State private var loadTask: Task<Void, Never>?
    @State private var showingTrackActivity = false

    @StateObject private var notificationPrefs = UserNotificationPreferences.shared
    @StateObject private var notificationService = UserNotificationService.shared

    private var activityTypes: [ActivityTypeSnapshot] {
        dataProvider.activityTypesByCaree[careeSnapshot.id] ?? []
    }

    private var isLoadingActivityTypes: Bool {
        dataProvider.activityTypesByCaree[careeSnapshot.id] == nil
    }

    private var isRefreshingActivityTypes: Bool {
        dataProvider.isRefreshingActivityTypes(for: careeSnapshot.id)
    }

    var body: some View {
        Group {
            if isLoadingActivityTypes {
                loadingView
            } else if activityTypes.isEmpty {
                gettingStartedView
            } else {
                TabView {
                    // Track tab
                    VStack {
                        Spacer()
                        trackActivityButton
                        Spacer()
                    }
                    .containerBackground(.background, for: .tabView)

                    // Activities tab
                    activitiesTab
                        .containerBackground(.background, for: .tabView)
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .navigationTitle(careeSnapshot.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if dataProvider.isRefreshingCarees || (isRefreshingActivityTypes && !isLoadingActivityTypes) {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Button {
                    toggleNotifications()
                } label: {
                    Image(systemName: notificationPrefs.isEnabled(for: careeSnapshot.id) ? "bell.fill" : "bell.slash")
                        .foregroundColor(notificationPrefs.isEnabled(for: careeSnapshot.id) ? .blue : .gray)
                }
            }
        }
        .sheet(isPresented: $showingTrackActivity) {
            // Show activity types to select from
            if !activityTypes.isEmpty {
                TrackActivitySelectionView(
                    careeSnapshot: careeSnapshot,
                    activityTypes: activityTypes
                )
                .environmentObject(dataProvider)
            }
        }
        .task {
            // Lazy load activity types when view appears
            loadTask?.cancel()

            loadTask = Task {
                guard !Task.isCancelled else { return }

                MemoryMonitor.logMemoryUsage(context: "CareeDetailView - Before Load ActivityTypes")

                // Load activity types for this caree (on-demand)
                await dataProvider.loadActivityTypes(for: careeSnapshot.id)

                guard !Task.isCancelled else { return }

                MemoryMonitor.logMemoryUsage(context: "CareeDetailView - After Load ActivityTypes")
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

            Text("Loading Activity Types...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var gettingStartedView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "lightbulb.circle")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)

                Text("Getting Started")
                    .font(.headline)

                Text("Activity types must be created on iPhone before you can track activities on Apple Watch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private var trackActivityButton: some View {
        Button(action: { showingTrackActivity = true }) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                Text("Track")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .foregroundColor(.white)
            .background(Color.green.opacity(0.8))
            .cornerRadius(12)
        }
        .padding(.horizontal, 12)
    }

    private var activitiesTab: some View {
        NavigationLink {
            ActivityListView(careeSnapshot: careeSnapshot, activityTypes: activityTypes)
                .environmentObject(dataProvider)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 40))
                Text("Activities")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .foregroundColor(.white)
            .background(Color.blue.opacity(0.8))
            .cornerRadius(12)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func toggleNotifications() {
        Task {
            // Check current authorization status
            await notificationService.checkAuthorizationStatus()

            if notificationService.authorizationStatus == .notDetermined {
                // Request permission if not yet determined
                let granted = await notificationService.requestPermission()
                if granted {
                    // Enable notifications for this caree
                    notificationPrefs.setEnabled(true, for: careeSnapshot.id)
                }
            } else if notificationService.authorizationStatus == .authorized {
                // Toggle the preference
                notificationPrefs.toggle(for: careeSnapshot.id)
            }
            // Note: watchOS doesn't have Settings deep linking like iOS,
            // so we silently fail if permission is denied
        }
    }
}

/// Activity type selection view for tracking
struct TrackActivitySelectionView: View {
    let careeSnapshot: CareeSnapshot
    let activityTypes: [ActivityTypeSnapshot]

    @EnvironmentObject private var dataProvider: WatchDataProvider
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(activityTypes) { activityType in
                NavigationLink {
                    TrackActivityView(
                        careeSnapshot: careeSnapshot,
                        activityTypeSnapshot: activityType
                    )
                    .environmentObject(dataProvider)
                } label: {
                    HStack {
                        ActivityTypeIconView(icon: activityType.icon)
                            .font(.title3)
                        Text(activityType.name)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Track Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let snapshot = CareeSnapshot(
        from: PreviewData.sampleCareeWithActivities
    )

    return NavigationStack {
        CareeDetailView(careeSnapshot: snapshot)
            .environmentObject(WatchDataProvider())
    }
}
