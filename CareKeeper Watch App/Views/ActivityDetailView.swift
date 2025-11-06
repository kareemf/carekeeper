import SwiftUI
import MapKit
import CoreLocation

/// ActivityDetailView rebuilt with snapshots
/// Supports editing notes, quantity, time, and location
struct ActivityDetailView: View {

    let activitySnapshot: ActivitySnapshot

    @EnvironmentObject private var dataProvider: WatchDataProvider
    @Environment(\.dismiss) private var dismiss

    @State private var isRetrying = false
    @State private var isEditing = false
    @State private var editedNotes: String = ""
    @State private var editedQuantity: Double = 0
    @State private var minutesAgo: Double = 0
    @State private var useCustomTime = false
    @State private var captureNewLocation: Bool = false
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showingDeleteSuccess = false
    @State private var showingSaveSuccess = false
    @FocusState private var timeInputFocused: Bool

    @StateObject private var locationManager = LocationManager()

    private var activityType: ActivityTypeSnapshot? {
        // Find activity type across all loaded carees
        for (_, types) in dataProvider.activityTypesByCaree {
            if let type = types.first(where: { $0.id == activitySnapshot.activityTypeID }) {
                return type
            }
        }
        return nil
    }

    private var currentActivity: ActivitySnapshot {
        if let refreshed = dataProvider.recentActivitiesByCaree[activitySnapshot.careeID]?.first(where: { $0.id == activitySnapshot.id }) {
            return refreshed
        }
        return activitySnapshot
    }

    private var editedDateTime: Date {
        Date().addingTimeInterval(-minutesAgo * 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with icon and name
                VStack(spacing: 8) {
                    if let icon = activityType?.icon, !icon.isEmpty {
                        Text(icon)
                            .font(.system(size: 50))
                    }

                    Text(activityType?.name ?? "Activity")
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Sync state if not synced
                    if currentActivity.syncState != .synced {
                        syncStateBadge
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()

                // Details sections
                detailsSection
                    .padding(.horizontal)

                if isEditing || currentActivity.notes != nil || currentActivity.quantity != nil {
                    Divider()
                    additionalInfoSection
                        .padding(.horizontal)
                }

                if currentActivity.latitude != nil && currentActivity.longitude != nil {
                    Divider()
                    locationSection
                        .padding(.horizontal)
                }

                // Delete button (only shown when not editing)
                if !isEditing {
                    Divider()
                        .padding(.top, 8)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Deleting...")
                            } else {
                                Image(systemName: "trash")
                                Text("Delete Activity")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isDeleting)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(Text(currentActivity.dateTime, style: .date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isEditing {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .disabled(isSaving)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if isEditing {
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                } else {
                    Button {
                        startEditing()
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarLeading) {
                if dataProvider.isRefreshingCarees || dataProvider.isRefreshingRecentActivities(for: currentActivity.careeID) {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }
        .confirmationDialog(
            "Delete this activity?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteActivity()
            }
        }
        .overlay(alignment: .center) {
            if showingDeleteSuccess {
                deleteSuccessToast
            } else if showingSaveSuccess {
                saveSuccessToast
            }
        }
        .onAppear {
            initializeEditingValues()
        }
        .onChange(of: dataProvider.recentActivitiesByCaree[currentActivity.careeID]) { _, _ in
            guard !isEditing else { return }
            initializeEditingValues()
        }
    }

    // MARK: - Sections

    private var deleteSuccessToast: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Deleted!")
                .font(.headline)
        }
        .padding(24)
        .background(
            Color.black.opacity(0.85)
                .cornerRadius(16)
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var saveSuccessToast: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Saved!")
                .font(.headline)
        }
        .padding(24)
        .background(
            Color.black.opacity(0.85)
                .cornerRadius(16)
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var syncStateBadge: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                switch currentActivity.syncState {
                case .pending:
                    Image(systemName: "clock")
                    Text("Pending")
                case .syncing:
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                    Text("Failed")
                case .synced:
                    EmptyView()
                }
            }
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(12)

            // Show error details for failed state
            if case .failed(let errorMessage) = currentActivity.syncState {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        retrySync()
                    } label: {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .disabled(isRetrying)
                }
            }
        }
    }

    // MARK: - Actions

    private func retrySync() {
        guard !isRetrying else { return }
        isRetrying = true

        Task {
            // Re-trigger the sync by calling trackActivity again
            await dataProvider.trackActivity(currentActivity)

            await MainActor.run {
                isRetrying = false
            }
        }
    }

    private func initializeEditingValues() {
        editedNotes = currentActivity.notes ?? ""
        editedQuantity = currentActivity.quantity ?? 0
        useCustomTime = false

        // Calculate minutes ago from current time
        let timeDiff = Date().timeIntervalSince(currentActivity.dateTime)
        minutesAgo = max(0, timeDiff / 60)
    }

    private func startEditing() {
        initializeEditingValues()
        withAnimation {
            isEditing = true
        }
        timeInputFocused = false
    }

    private func cancelEditing() {
        withAnimation {
            isEditing = false
        }
    }

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            let baseActivity = currentActivity
            let shouldAdjustTime = useCustomTime

            // Use new location if captured, otherwise keep existing location
            let latitude = captureNewLocation ? locationManager.location?.coordinate.latitude : baseActivity.latitude
            let longitude = captureNewLocation ? locationManager.location?.coordinate.longitude : baseActivity.longitude

            // Create new activity snapshot with updated values
            let updatedActivity = ActivitySnapshot(
                id: baseActivity.id,
                dateTime: shouldAdjustTime ? editedDateTime : baseActivity.dateTime,
                notes: editedNotes.isEmpty ? nil : editedNotes,
                quantity: activityType?.hasQuantity == true ? editedQuantity : baseActivity.quantity,
                latitude: latitude,
                longitude: longitude,
                activityTypeID: baseActivity.activityTypeID,
                careeID: baseActivity.careeID,
                dateCreated: baseActivity.dateCreated,
                syncState: baseActivity.syncState
            )

            // Update the activity (optimistic UI with background sync)
            await dataProvider.updateActivity(updatedActivity)

            // Show success toast briefly before exiting edit mode
            await MainActor.run {
                isSaving = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingSaveSuccess = true
                }
            }

            // Wait for toast to be visible
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

            // Exit edit mode
            await MainActor.run {
                showingSaveSuccess = false
                isEditing = false
            }
        }
    }

    private func deleteActivity() {
        guard !isDeleting else { return }
        isDeleting = true

        Task {
            // Delete the activity using WatchDataProvider
            await dataProvider.deleteActivity(currentActivity)

            // Show success toast briefly before dismissing
            await MainActor.run {
                isDeleting = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingDeleteSuccess = true
                }
            }

            // Wait for toast to be visible
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

            // Navigate back to activity list
            await MainActor.run {
                dismiss()
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                // Editable time guarded by toggle to avoid accidental crown changes
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $useCustomTime) {
                        Text(useCustomTime ? "Custom" : "Recorded")
                            .font(.body)
                    }
                    .onChange(of: useCustomTime) { _, newValue in
                        timeInputFocused = newValue
                    }

                    if useCustomTime {
                        VStack(spacing: 4) {
                            HStack {
                                Text(editedDateTime, style: .time)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            HStack {
                                Text("\(Int(minutesAgo)) min ago")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .focusable(true)
                        .focused($timeInputFocused)
                        .digitalCrownRotation(
                            $minutesAgo,
                            from: 0,
                            through: 1440,
                            by: 1,
                            sensitivity: .low,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                    } else {
                        VStack(spacing: 4) {
                            HStack {
                                Text(currentActivity.dateTime, style: .time)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            HStack {
                                Text(currentActivity.dateTime, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
            } else {
                // Time
                HStack {
                    Label("Time", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currentActivity.dateTime, style: .time)
                        .font(.body)
                }

                // Date
                HStack {
                    Label("Date", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currentActivity.dateTime, style: .date)
                        .font(.body)
                }
            }
        }
    }

    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quantity
            if activityType?.hasQuantity == true {
                if isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(activityType?.quantityUnit ?? "Quantity", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(String(format: "%.1f", editedQuantity))
                                .font(.title3)
                                .fontWeight(.semibold)

                            if let unit = activityType?.quantityUnit {
                                Text(unit)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .focusable(true)
                        .digitalCrownRotation(
                            $editedQuantity,
                            from: 0,
                            through: 100,
                            by: 0.5,
                            sensitivity: .medium
                        )
                    }
                } else if let quantity = currentActivity.quantity {
                    HStack {
                        Label("Quantity", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    if let unit = activityType?.quantityUnit {
                        Text("\(String(format: "%.1f", quantity)) \(unit)")
                            .font(.body)
                    } else {
                        Text(String(format: "%.1f", quantity))
                                .font(.body)
                        }
                    }
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isEditing {
                    TextField("Optional notes", text: $editedNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                } else if let notes = currentActivity.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.primary)
                } else if !isEditing {
                    Text("No notes")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        // Only show if activity type supports location OR if there's already a location
        if activityType?.hasLocation == true || (currentActivity.latitude != nil && currentActivity.longitude != nil) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location", systemImage: "location")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // In edit mode, allow capturing new location
                if isEditing && (activityType?.hasLocation == true || (currentActivity.latitude != nil && currentActivity.longitude != nil)) {
                    Toggle(isOn: $captureNewLocation) {
                        Text("Update Location")
                            .font(.body)
                    }
                    .onChange(of: captureNewLocation) { _, enabled in
                        if enabled {
                            locationManager.requestLocation()
                        }
                    }

                    if captureNewLocation {
                        if locationManager.location != nil {
                            Text("📍 New location captured")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if locationManager.isUpdating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Getting location...")
                                    .font(.caption)
                            }
                        } else if locationManager.authorizationStatus == .denied {
                            Text("Location access denied")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Waiting for location...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Display current or existing location
                if let latitude = (captureNewLocation ? locationManager.location?.coordinate.latitude : currentActivity.latitude),
                   let longitude = (captureNewLocation ? locationManager.location?.coordinate.longitude : currentActivity.longitude) {
                    Map(initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )) {
                        Marker("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    }
                    .frame(height: 120)
                    .cornerRadius(8)

                    Text("Lat: \(String(format: "%.6f", latitude)), Lon: \(String(format: "%.6f", longitude))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if !isEditing && currentActivity.latitude == nil {
                    Text("No location recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    let activity = ActivitySnapshot(
        dateTime: Date(),
        notes: "Sample notes",
        quantity: 8.0,
        latitude: 37.7749,
        longitude: -122.4194,
        activityTypeID: UUID(),
        careeID: UUID()
    )

    return NavigationStack {
        ActivityDetailView(activitySnapshot: activity)
            .environmentObject(WatchDataProvider())
    }
}
