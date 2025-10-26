import SwiftUI
import CoreLocation

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
    @State private var customTime: Date = Date()
    @State private var isSaving = false
    @State private var error: Error?

    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Large Save button at top
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

                // Form fields
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
                            .background(Color(.systemGray6))
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

                        if useCustomTime {
                            DatePicker(
                                "",
                                selection: $customTime,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.wheel)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
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
                                if let location = locationManager.location {
                                    Text("📍 Location captured")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else if locationManager.isLoading {
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
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: includeLocation) { _, enabled in
                            if enabled {
                                Task {
                                    await locationManager.requestLocation()
                                }
                            }
                        }
                    }

                    // Notes section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
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
        .onChange(of: locationManager.error) { _, error in
            if let error = error {
                self.error = error
            }
        }
        .errorAlert($error)
    }

    // MARK: - Actions

    private func saveActivity() {
        guard !isSaving else { return }

        isSaving = true

        Task {
            let dateTime = useCustomTime ? customTime : Date()
            let activityQuantity = activityTypeSnapshot.hasQuantity ? quantity : nil
            let latitude = (includeLocation && activityTypeSnapshot.hasLocation) ? locationManager.location?.coordinate.latitude : nil
            let longitude = (includeLocation && activityTypeSnapshot.hasLocation) ? locationManager.location?.coordinate.longitude : nil

            // Create activity snapshot
            let activity = ActivitySnapshot(
                dateTime: dateTime,
                notes: notes.isEmpty ? nil : notes,
                quantity: activityQuantity,
                latitude: latitude,
                longitude: longitude,
                activityTypeID: activityTypeSnapshot.id,
                careeID: careeSnapshot.id
            )

            // Track with optimistic UI
            await dataProvider.trackActivity(activity)

            // Dismiss (activity is saved in background)
            await MainActor.run {
                isSaving = false
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
