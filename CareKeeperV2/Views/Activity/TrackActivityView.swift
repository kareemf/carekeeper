import SwiftUI
import CoreLocation

struct TrackActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let caree: Caree

    @State private var selectedActivityType: ActivityType?
    @State private var notes: String = ""
    @State private var quantity: String = ""
    @State private var customDateTime: Date = Date()
    @State private var useCustomTime: Bool = false
    @State private var includeLocation: Bool = false
    @StateObject private var locationManager = LocationManager()
    @State private var error: Error?
    
    private var sortedActivityTypes: [ActivityType] {
        caree.sortedActivityTypes
    }
    
    var body: some View {
        NavigationView {
            Form {
                activityTypeSection
                
                if selectedActivityType != nil {
                    detailsSection
                    timingSection
                    locationSection
                }
            }
            .navigationTitle(NSLocalizedString("Track Activity", comment: "Track activity navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Save", comment: "Save button")) {
                        saveActivity()
                    }
                    .disabled(selectedActivityType == nil)
                }
            }
        }
        .onAppear {
            requestLocationIfNeeded()
        }
        .onChange(of: locationManager.error != nil) { _, hasError in
            if hasError {
                error = locationManager.error
            }
        }
        .errorAlert($error)
    }
    
    private var activityTypeSection: some View {
        Section(NSLocalizedString("Activity Type", comment: "Activity type section title")) {
            if sortedActivityTypes.isEmpty {
                Text(NSLocalizedString("No activity types available. Add activity types first.", 
                                     comment: "No activity types message"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedActivityTypes) { activityType in
                    Button(action: { selectedActivityType = activityType }) {
                        HStack {
                            Text(activityType.displayIcon)
                                .font(.title2)
                            
                            Text(activityType.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedActivityType?.id == activityType.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var detailsSection: some View {
        Section(NSLocalizedString("Details", comment: "Details section title")) {
            TextField(NSLocalizedString("Notes (optional)", comment: "Notes field placeholder"), 
                     text: $notes, axis: .vertical)
                .lineLimit(3...6)
            
            if selectedActivityType?.hasQuantity == true {
                HStack {
                    TextField(NSLocalizedString("Quantity", comment: "Quantity field placeholder"), 
                             text: $quantity)
                        .keyboardType(.decimalPad)
                    
                    if let unit = selectedActivityType?.quantityUnit {
                        Text(unit)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var timingSection: some View {
        Section {
            Toggle(NSLocalizedString("Custom time", comment: "Custom time toggle"), isOn: $useCustomTime)
            
            if useCustomTime {
                DatePicker(NSLocalizedString("When", comment: "Date picker label"), 
                          selection: $customDateTime, 
                          displayedComponents: [.date, .hourAndMinute])
            }
        }
    }
    
    @ViewBuilder
    private var locationSection: some View {
        if selectedActivityType?.hasLocation == true {
            Section(NSLocalizedString("Location", comment: "Location section title")) {
                Toggle(NSLocalizedString("Include Location", comment: "Location toggle"), isOn: $includeLocation)
                    .onChange(of: includeLocation) { _, newValue in
                        if newValue {
                            locationManager.requestLocation()
                        } else {
                            locationManager.stopUpdating()
                        }
                    }

                if includeLocation {
                    if let location = locationManager.location {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Current location", comment: "Current location label"))
                                .font(.subheadline)

                            Text(String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(NSLocalizedString("Getting location...", comment: "Getting location message"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func requestLocationIfNeeded() {
        // Location is now requested on-demand via toggle
    }
    
    private func saveActivity() {
        guard let activityType = selectedActivityType else { return }

        let activityDateTime = useCustomTime ? customDateTime : Date()
        let quantityValue = activityType.hasQuantity ? Double(quantity) : nil
        let location = includeLocation ? locationManager.location : nil
        let latitude = location?.coordinate.latitude
        let longitude = location?.coordinate.longitude

        let newActivity = Activity(
            dateTime: activityDateTime,
            notes: notes.isEmpty ? nil : notes,
            quantity: quantityValue,
            latitude: latitude,
            longitude: longitude,
            activityType: activityType,
            caree: caree
        )

        modelContext.insert(newActivity)
        locationManager.stopUpdating()
        dismiss()
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}