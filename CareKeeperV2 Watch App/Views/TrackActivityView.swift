import SwiftUI
import SwiftData
import CoreLocation

struct TrackActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let caree: Caree

    @State private var selectedActivityType: ActivityType?
    @State private var notes: String = ""
    @State private var quantity: String = ""
    @State private var showingStep2 = false
    @State private var includeLocation: Bool = false
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            if !showingStep2 {
                activityTypeSelection
            } else if let activityType = selectedActivityType {
                activityDetailsForm(for: activityType)
            }
        }
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
        Form {
            Section(header: Text(NSLocalizedString("Notes", comment: "Notes section"))) {
                TextField(NSLocalizedString("Optional", comment: "Notes placeholder"), text: $notes)
            }

            if activityType.hasQuantity {
                Section(header: Text(activityType.quantityUnit ?? NSLocalizedString("Quantity", comment: "Quantity section"))) {
                    TextField(NSLocalizedString("Amount", comment: "Quantity placeholder"), text: $quantity)
                }
            }

            if activityType.hasLocation {
                Section {
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

            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("Save", comment: "Save button")) {
                    saveActivity(for: activityType)
                }
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
    }

    private func saveActivity(for activityType: ActivityType) {
        let location = includeLocation ? locationManager.location : nil

        let activity = Activity(
            notes: notes.isEmpty ? nil : notes,
            quantity: Double(quantity),
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
            print("⚠️ Failed to save activity: \(error)")
        }
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}
