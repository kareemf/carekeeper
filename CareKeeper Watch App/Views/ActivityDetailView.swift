import SwiftUI
import MapKit

/// ActivityDetailView rebuilt with snapshots
/// Supports editing notes, quantity, and time
struct ActivityDetailView: View {

    let activitySnapshot: ActivitySnapshot

    @EnvironmentObject private var dataProvider: WatchDataProvider
    @Environment(\.dismiss) private var dismiss

    @State private var isRetrying = false
    @State private var isEditing = false
    @State private var editedNotes: String = ""
    @State private var editedQuantity: Double = 0
    @State private var minutesAgo: Double = 0
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showingDeleteSuccess = false

    private var activityType: ActivityTypeSnapshot? {
        // Find activity type across all loaded carees
        for (_, types) in dataProvider.activityTypesByCaree {
            if let type = types.first(where: { $0.id == activitySnapshot.activityTypeID }) {
                return type
            }
        }
        return nil
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
                    if activitySnapshot.syncState != .synced {
                        syncStateBadge
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()

                // Details sections
                detailsSection
                    .padding(.horizontal)

                if activitySnapshot.notes != nil || activitySnapshot.quantity != nil {
                    Divider()
                    additionalInfoSection
                        .padding(.horizontal)
                }

                if activitySnapshot.latitude != nil && activitySnapshot.longitude != nil {
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
        .navigationTitle(Text(activitySnapshot.dateTime, style: .date))
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
        .alert("Activity Deleted", isPresented: $showingDeleteSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("The activity has been deleted successfully")
        }
        .onAppear {
            initializeEditingValues()
        }
    }

    // MARK: - Sections

    private var syncStateBadge: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                switch activitySnapshot.syncState {
                case .pending:
                    Image(systemName: "clock")
                    Text("Pending")
                case .syncing:
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                case .failed(let errorMessage):
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
            if case .failed(let errorMessage) = activitySnapshot.syncState {
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
            await dataProvider.trackActivity(activitySnapshot)

            await MainActor.run {
                isRetrying = false
            }
        }
    }

    private func initializeEditingValues() {
        editedNotes = activitySnapshot.notes ?? ""
        editedQuantity = activitySnapshot.quantity ?? 0

        // Calculate minutes ago from current time
        let timeDiff = Date().timeIntervalSince(activitySnapshot.dateTime)
        minutesAgo = max(0, timeDiff / 60)
    }

    private func startEditing() {
        initializeEditingValues()
        withAnimation {
            isEditing = true
        }
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
            // Create new activity snapshot with updated values
            let updatedActivity = ActivitySnapshot(
                id: activitySnapshot.id,
                dateTime: editedDateTime,
                notes: editedNotes.isEmpty ? nil : editedNotes,
                quantity: activityType?.hasQuantity == true ? editedQuantity : activitySnapshot.quantity,
                latitude: activitySnapshot.latitude,
                longitude: activitySnapshot.longitude,
                activityTypeID: activitySnapshot.activityTypeID,
                careeID: activitySnapshot.careeID
            )

            // Update the activity (optimistic UI with background sync)
            await dataProvider.updateActivity(updatedActivity)

            await MainActor.run {
                isSaving = false
                isEditing = false
            }
        }
    }

    private func deleteActivity() {
        guard !isDeleting else { return }
        isDeleting = true

        Task {
            // Delete the activity using WatchDataProvider
            await dataProvider.deleteActivity(activitySnapshot)

            await MainActor.run {
                isDeleting = false
                // Show success message
                showingDeleteSuccess = true
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                // Editable time with crown control
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                    .digitalCrownRotation(
                        $minutesAgo,
                        from: 0,
                        through: 1440,
                        by: 1,
                        sensitivity: .low,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                }
            } else {
                // Time
                HStack {
                    Label("Time", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(activitySnapshot.dateTime, style: .time)
                        .font(.body)
                }

                // Date
                HStack {
                    Label("Date", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(activitySnapshot.dateTime, style: .date)
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
                } else if let quantity = activitySnapshot.quantity {
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
                } else if let notes = activitySnapshot.notes, !notes.isEmpty {
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
        if let latitude = activitySnapshot.latitude,
           let longitude = activitySnapshot.longitude {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location", systemImage: "location")
                    .font(.caption)
                    .foregroundColor(.secondary)

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
