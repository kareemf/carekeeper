import SwiftUI

/// CareeListView rebuilt with defensive patterns
/// Key changes from original:
/// - Uses WatchDataProvider instead of multiple services
/// - Consumes immutable snapshots (no SwiftData models in UI)
/// - Task cancellation on view disappear
/// - No Combine subscriptions (explicit async/await)
/// - Safe rendering (no relationship access like caree.activityTypes)
struct CareeListView: View {

    @StateObject private var dataProvider = WatchDataProvider()
    @State private var loadTask: Task<Void, Never>?
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Carees")
                .task {
                    // Cancel previous task if view reappears
                    loadTask?.cancel()

                    loadTask = Task {
                        await loadWithCancellation()
                    }
                }
                .onDisappear {
                    // Clean up when view disappears
                    loadTask?.cancel()
                    loadTask = nil
                }
                .errorAlert($error)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if dataProvider.isLoadingCarees && dataProvider.carees.isEmpty {
            // Loading state (only if no cached data)
            loadingView
        } else if let error = dataProvider.careesError, dataProvider.carees.isEmpty {
            // Error state (only if no cached data to show)
            errorView(error)
        } else if dataProvider.carees.isEmpty {
            // Empty state
            emptyStateView
        } else {
            // Data loaded - show list
            careeList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading Carees...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Load Failed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await dataProvider.loadCarees(force: true) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Carees")
                .font(.headline)

            Text("Add carees on iPhone or accept shared ones")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var careeList: some View {
        List(dataProvider.carees) { caree in
            NavigationLink {
                CareeDetailView(careeSnapshot: caree)
                    .environmentObject(dataProvider)
            } label: {
                CareeRowView(snapshot: caree)
            }
        }
        .refreshable {
            guard !Task.isCancelled else { return }
            await dataProvider.loadCarees(force: true) // Force refresh to remove deleted carees
        }
    }

    // MARK: - Data Loading

    private func loadWithCancellation() async {
        // Check cancellation before starting
        guard !Task.isCancelled else { return }

        MemoryMonitor.logMemoryUsage(context: "CareeListView - Before Load")

        await dataProvider.loadCarees()

        // Check again after async work
        guard !Task.isCancelled else { return }

        MemoryMonitor.logMemoryUsage(context: "CareeListView - After Load")

        // Handle errors
        if let error = dataProvider.careesError {
            self.error = error
        }
    }
}

// MARK: - Row Views

/// Row view using snapshot instead of SwiftData model
/// Safe - all properties are pre-loaded, no relationship access
struct CareeRowView: View {
    let snapshot: CareeSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ProfileImageView(imageData: snapshot.imageData)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.name)
                        .font(.headline)

                    if snapshot.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Spacer()
                }

                // Safe - count pre-loaded, NOT accessing relationship!
                Text("\(snapshot.activityTypeCount) Activity Types")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Profile image view using optional Data instead of SwiftData model
struct ProfileImageView: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
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
}
