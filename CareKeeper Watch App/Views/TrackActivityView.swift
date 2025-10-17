import SwiftUI
import SwiftData
import CoreLocation
import WidgetKit

struct TrackActivityView: View {
    @Environment(\.dismiss) private var dismiss

    let caree: Caree

    @State private var selectedActivityType: ActivityType?
    @State private var notes: String = ""
    @State private var quantity: Double = 0
    @State private var showingStep2 = false
    @State private var includeLocation: Bool = false
    @StateObject private var locationManager = LocationManager()
    @State private var error: Error?
    @State private var useCustomTime: Bool = false
    @State private var customTime: Date = Date()

    // Use shared services from environment
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedDataService: CloudKitSharedDataService

    private var isSharedCaree: Bool {
        caree.isShared  // Use cache metadata
    }

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

                    // Time section (watch-friendly, time-only)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Time", comment: "Time section"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle(NSLocalizedString("Custom time", comment: "Custom time toggle"), isOn: $useCustomTime)

                        if useCustomTime {
                            // Time-only picker; watchOS will use crown-friendly interaction
                            DatePicker(
                                NSLocalizedString("Time", comment: "Time picker label"),
                                selection: $customTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
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
                Button {
                    showingStep2 = false
                    selectedActivityType = nil
                    includeLocation = false
                    locationManager.stopUpdating()
                } label: {
                    Image(systemName: "chevron.left")
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

        // Build the final dateTime using today's date + selected time (if custom)
        let now = Date()
        let finalDateTime: Date = useCustomTime ? combine(date: now, timeOfDayFrom: customTime) : now

        if isSharedCaree {
            // Handle shared caree - use CloudKit service
            Task {
                do {
                    _ = try await sharedDataService.createActivity(
                        for: caree,
                        activityType: activityType,
                        dateTime: finalDateTime,
                        notes: notes.isEmpty ? nil : notes,
                        quantity: activityType.hasQuantity && quantity > 0 ? quantity : nil,
                        latitude: location?.coordinate.latitude,
                        longitude: location?.coordinate.longitude
                    )

                    await MainActor.run {
                        locationManager.stopUpdating()
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed(error.localizedDescription)
                        locationManager.stopUpdating()
                    }
                }
            }
        } else {
            // Handle owned caree - use Pure CloudKit
            Task {
                do {
                    _ = try await cloudKitService.createActivity(
                        for: caree,
                        activityType: activityType,
                        dateTime: finalDateTime,
                        notes: notes.isEmpty ? nil : notes,
                        quantity: activityType.hasQuantity && quantity > 0 ? quantity : nil,
                        latitude: location?.coordinate.latitude,
                        longitude: location?.coordinate.longitude,
                        isShared: false
                    )

                    await MainActor.run {
                        locationManager.stopUpdating()
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed(error.localizedDescription)
                        locationManager.stopUpdating()
                    }
                }
            }
        }
    }

    // Combine a base date (today) with the hour/minute from a time-of-day Date
    private func combine(date baseDate: Date, timeOfDayFrom time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second ?? 0
        return calendar.date(from: dateComponents) ?? baseDate
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}
