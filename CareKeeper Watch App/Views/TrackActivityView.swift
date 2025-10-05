import SwiftUI
import SwiftData
import CoreLocation

struct TrackActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let caree: Caree

    @State private var selectedActivityType: ActivityType?
    @State private var notes: String = ""
    @State private var quantity: Double = 0
    @State private var showingStep2 = false
    @State private var includeLocation: Bool = false
    @StateObject private var locationManager = LocationManager()
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            if !showingStep2 {
                activityTypeSelection
            } else if let activityType = selectedActivityType {
                activityDetailsForm(for: activityType)
            }
        }
        .onChange(of: locationManager.error != nil) { _, hasError in
            if hasError {
                error = locationManager.error
            }
        }
        .errorAlert($error)
    }

    private var activityTypeSelection: some View {
        List {
            ForEach(caree.sortedActivityTypes) { activityType in
                Button(action: {
                    selectedActivityType = activityType
                    showingStep2 = true
                }) {
                    HStack {
                        Text(activityType.displayIcon)
                            .font(.title2)

                        Text(activityType.name)
                            .font(.headline)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Select Type", comment: "Select activity type title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                    dismiss()
                }
            }
        }
    }

    private func activityDetailsForm(for activityType: ActivityType) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Large Save button at top
                Button(action: { saveActivity(for: activityType) }) {
                    Text(NSLocalizedString("Save", comment: "Save button"))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundColor(.white)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // Form fields
                VStack(spacing: 12) {
                    // Quantity section
                    if activityType.hasQuantity {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activityType.quantityUnit ?? NSLocalizedString("Quantity", comment: "Quantity section"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text(String(format: "%.1f", quantity))
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                if let unit = activityType.quantityUnit {
                                    Text(unit)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .focusable()
                            .digitalCrownRotation($quantity, from: 0, through: 999, by: 0.5, sensitivity: .medium)
                        }
                    }

                    // Location section
                    if activityType.hasLocation {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(NSLocalizedString("Include Location", comment: "Location toggle"), isOn: $includeLocation)
                                .onChange(of: includeLocation) { _, newValue in
                                    if newValue {
                                        locationManager.requestLocation()
                                    } else {
                                        locationManager.stopUpdating()
                                    }
                                }

                            if includeLocation, let location = locationManager.location {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("Location", comment: "Location label"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.6f, %.6f",
                                               location.coordinate.latitude,
                                               location.coordinate.longitude))
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                }
                            }
                        }
                    }

                    // Notes section (last to prevent accidental crown scrolling on quantity)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Notes", comment: "Notes section"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("Optional", comment: "Notes placeholder"), text: $notes)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(activityType.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("Back", comment: "Back button")) {
                    showingStep2 = false
                    selectedActivityType = nil
                    includeLocation = false
                    locationManager.stopUpdating()
                }
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
    }

    private func saveActivity(for activityType: ActivityType) {
        // Validate quantity if required
        if activityType.hasQuantity && quantity < 0 {
            error = AppError.invalidInput(
                NSLocalizedString("Please enter a valid quantity (0 or greater)", comment: "Invalid quantity error")
            )
            return
        }

        let location = includeLocation ? locationManager.location : nil

        let activity = Activity(
            notes: notes.isEmpty ? nil : notes,
            quantity: activityType.hasQuantity && quantity > 0 ? quantity : nil,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            activityType: activityType,
            caree: caree
        )

        modelContext.insert(activity)

        do {
            try modelContext.save()
            locationManager.stopUpdating()
            dismiss()
        } catch {
            self.error = AppError.saveFailed(error.localizedDescription)
        }
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}
