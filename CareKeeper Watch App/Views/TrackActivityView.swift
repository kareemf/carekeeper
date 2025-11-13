import CoreLocation
import SwiftUI

/// TrackActivityView rebuilt with optimistic UI and snapshots
/// Key changes:
/// - Uses snapshots instead of SwiftData models
/// - Optimistic UI: shows activity immediately, syncs in background
/// - WatchDataProvider handles CloudKit operations
/// - No SwiftData access
struct TrackActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataProvider: WatchDataProvider

    let careeSnapshot: CareeSnapshot
    let activityTypeSnapshot: ActivityTypeSnapshot

    @State private var notes: String = ""
    @State private var quantity: Double = 0
    @State private var includeLocation: Bool = false
    @State private var useCustomTime: Bool = false
    @State private var minutesAgo: Double = 0
    @State private var reminderEnabled: Bool = false
    @State private var reminderMinutesAhead: Double = 5
    @State private var isSaving = false
    @State private var showSuccessToast = false
    @State private var error: Error?
    @FocusState private var timeInputFocused: Bool

    @StateObject private var locationManager = LocationManager()
    private let reminderWindowMinutes: Double = Double(60 * 24 * 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                saveButton
                formFields
            }
        }
        .navigationTitle(activityTypeSnapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSaving)
            }
        }
        .overlay(alignment: .center) {
            if showSuccessToast {
                successToast
            }
        }
        .errorAlert($error)
    }

    // MARK: - Computed Properties

    private var timeText: String {
        let targetTime = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: targetTime)
    }

    private var reminderTimeText: String {
        let dueDate = clampedReminderDueDate()
        if Calendar.current.isDateInToday(dueDate) {
            return dueDate.formatted(date: .omitted, time: .shortened)
        } else {
            return dueDate.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private var reminderMinutesRange: ClosedRange<Double> {
        1 ... reminderWindowMinutes
    }

    // MARK: - View Components

    private var successToast: some View {
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

    private var saveButton: some View {
        Button(action: saveActivity) {
            if isSaving {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Text("Save")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .foregroundColor(.white)
        .background(Color.green.opacity(0.8))
        .cornerRadius(12)
        .disabled(isSaving)
        .padding(.horizontal)
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            // Quantity section
            if activityTypeSnapshot.hasQuantity {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activityTypeSnapshot.quantityUnit ?? "Quantity")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(String(format: "%.1f", quantity))
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let unit = activityTypeSnapshot.quantityUnit {
                            Text(unit)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .focusable(true)
                    .digitalCrownRotation(
                        $quantity,
                        from: 0,
                        through: 100,
                        by: 0.5,
                        sensitivity: .medium
                    )
                }
            }

            // Time section
            VStack(alignment: .leading, spacing: 4) {
                Text("Time")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(isOn: $useCustomTime) {
                    Text(useCustomTime ? "Custom" : "Now")
                        .font(.body)
                }
                .onChange(of: useCustomTime) { _, newValue in
                    if newValue {
                        // Focus time input when custom time is enabled
                        timeInputFocused = true
                    }
                }

                if useCustomTime {
                    VStack(spacing: 8) {
                        HStack {
                            Text(timeText)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }

                        HStack {
                            Text("\(Int(minutesAgo)) min ago")
                                .font(.caption)
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
                        through: 1440, // 24 hours
                        by: 1,
                        sensitivity: .low,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                }
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)

            // Location section
            if activityTypeSnapshot.hasLocation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $includeLocation) {
                        Text("Include Location")
                            .font(.body)
                    }

                    if includeLocation {
                        if locationManager.location != nil {
                            Text("📍 Location captured")
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
                            Text("Tap to request location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .onChange(of: includeLocation) { _, enabled in
                    if enabled {
                        locationManager.requestLocation()
                    }
                }
            }

            reminderSection

            // Notes section
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reminder")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(isOn: $reminderEnabled) {
                Text("Set Reminder")
            }
            .onChange(of: reminderEnabled) { _, newValue in
                if newValue {
                    reminderMinutesAhead = defaultReminderMinutes()
                }
            }

            if reminderEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text(reminderTimeText)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    HStack {
                        Text("in \(Int(reminderMinutesAhead)) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
                .digitalCrownRotation(
                    $reminderMinutesAhead,
                    from: reminderMinutesRange.lowerBound,
                    through: reminderMinutesRange.upperBound,
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }

    private func clampedReminderDueDate() -> Date {
        let minutes = clampReminderMinutes(reminderMinutesAhead)
        return Date().addingTimeInterval(minutes * 60)
    }

    private func clampReminderMinutes(_ value: Double) -> Double {
        min(max(value, reminderMinutesRange.lowerBound), reminderMinutesRange.upperBound)
    }

    private func defaultReminderMinutes() -> Double {
        clampReminderMinutes(5)
    }

    @MainActor
    private func attachReminderMetadata(to activity: inout ActivitySnapshot) async throws {
        let scheduler = ReminderScheduler.shared
        let authorized = await scheduler.ensureAuthorization()
        guard authorized else {
            throw ReminderPermissionError(platform: .watch)
        }

        let dueDate = clampedReminderDueDate()
        let result = try await scheduler.scheduleReminder(
            careeName: careeSnapshot.name,
            activityTypeName: activityTypeSnapshot.name,
            dueDate: dueDate
        )

        activity.reminderIdentifier = result.identifier
        activity.reminderDueDate = result.dueDate
        activity.reminderSourceRawValue = ReminderSource.current.rawValue
    }

    // MARK: - Actions

    private func saveActivity() {
        guard !isSaving else { return }

        isSaving = true

        Task {
            let dateTime = useCustomTime ? Date().addingTimeInterval(-Double(minutesAgo) * 60) : Date()
            let activityQuantity = activityTypeSnapshot.hasQuantity ? quantity : nil
            let latitude = (includeLocation && activityTypeSnapshot.hasLocation) ? locationManager.location?.coordinate
                .latitude : nil
            let longitude = (includeLocation && activityTypeSnapshot.hasLocation) ? locationManager.location?.coordinate
                .longitude : nil

            var activity = ActivitySnapshot(
                dateTime: dateTime,
                notes: notes.isEmpty ? nil : notes,
                quantity: activityQuantity,
                latitude: latitude,
                longitude: longitude,
                activityTypeID: activityTypeSnapshot.id,
                careeID: careeSnapshot.id
            )

            if reminderEnabled {
                do {
                    try await attachReminderMetadata(to: &activity)
                } catch let permissionError as ReminderPermissionError {
                    await MainActor.run {
                        isSaving = false
                        self.error = permissionError
                    }
                    return
                } catch let appError as AppError {
                    await MainActor.run {
                        isSaving = false
                        self.error = appError
                    }
                    return
                } catch {
                    await MainActor.run {
                        isSaving = false
                        self.error = AppError.saveFailed(error.localizedDescription)
                    }
                    return
                }
            }

            // Track with optimistic UI
            await dataProvider.trackActivity(activity)

            // Show success toast briefly before dismissing
            await MainActor.run {
                isSaving = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSuccessToast = true
                }
            }

            // Wait for toast to be visible
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

            // Navigate back to caree detail
            await MainActor.run {
                dismiss()
            }
        }
    }
}

#Preview {
    let careeSnapshot = CareeSnapshot(
        from: PreviewData.sampleCareeWithActivities
    )

    let activityTypeSnapshot = ActivityTypeSnapshot(
        from: PreviewData.sampleCareeWithActivities.sortedActivityTypes.first!,
        careeID: careeSnapshot.id
    )

    return NavigationStack {
        TrackActivityView(
            careeSnapshot: careeSnapshot,
            activityTypeSnapshot: activityTypeSnapshot
        )
        .environmentObject(WatchDataProvider())
    }
}
