import SwiftUI
import CoreLocation
import WidgetKit

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
    @State private var isSaving: Bool = false

    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    @StateObject private var sharedDataService = CloudKitSharedDataService()
    @StateObject private var sharingService = CloudKitSharingService()

    private var isSharedCaree: Bool {
        sharedRecordsService.sharedCarees.contains { $0.id == caree.id }
    }
    
    private var sortedActivityTypes: [ActivityType] {
        caree.sortedActivityTypes
    }
    
    var body: some View {
        NavigationView {
            Form {
                activityTypeSection

                if selectedActivityType != nil {
                    detailsSection
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    timingSection
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    locationSection
                        .transition(.move(edge: .leading).combined(with: .opacity))
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
                    Button(action: {
                        saveActivity()
                    }) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text(NSLocalizedString("Save", comment: "Save button"))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(selectedActivityType == nil || isSaving)
                }
            }
        }
        .onAppear {
            requestLocationIfNeeded()
        }
        .task {
            await sharedRecordsService.fetchSharedCarees()
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
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedActivityType = activityType
                        }
                    }) {
                        HStack {
                            Text(activityType.displayIcon)
                                .font(.title2)
                                .scaleEffect(selectedActivityType?.id == activityType.id ? 1.1 : 1.0)

                            Text(activityType.name)
                                .foregroundColor(.primary)
                                .fontWeight(selectedActivityType?.id == activityType.id ? .semibold : .regular)

                            Spacer()

                            if selectedActivityType?.id == activityType.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .transition(.scale.combined(with: .opacity))
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

        // Parse quantity if provided
        var quantityValue: Double? = nil
        if activityType.hasQuantity && !quantity.isEmpty {
            if let parsedQuantity = Double(quantity), parsedQuantity >= 0 {
                quantityValue = parsedQuantity
            }
        }

        isSaving = true

        let activityDateTime = useCustomTime ? customDateTime : Date()
        let location = includeLocation ? locationManager.location : nil
        let latitude = location?.coordinate.latitude
        let longitude = location?.coordinate.longitude

        if isSharedCaree {
            // Handle shared caree - use CloudKit service
            Task {
                do {
                    _ = try await sharedDataService.createActivity(
                        for: caree,
                        activityType: activityType,
                        dateTime: activityDateTime,
                        notes: notes.isEmpty ? nil : notes,
                        quantity: quantityValue,
                        latitude: latitude,
                        longitude: longitude
                    )

                    // Refresh shared carees to reflect changes
                    await sharedRecordsService.fetchSharedCarees()

                    await MainActor.run {
                        locationManager.stopUpdating()
                        WidgetCenter.shared.reloadAllTimelines()
                        isSaving = false
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed(error.localizedDescription)
                        locationManager.stopUpdating()
                        isSaving = false
                    }
                }
            }
        } else {
            // Handle owned caree - use SwiftData
            // Add slight delay for visual feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let newActivity = Activity(
                    dateTime: activityDateTime,
                    notes: notes.isEmpty ? nil : notes,
                    quantity: quantityValue,
                    latitude: latitude,
                    longitude: longitude,
                    activityType: activityType,
                    caree: caree
                )

                withAnimation(.easeOut(duration: 0.2)) {
                    modelContext.insert(newActivity)
                    do {
                        try modelContext.save()

                        // If caree is shared, ensure parent references are set for the new child record
                        Task {
                            await sharingService.ensureParentReferencesIfShared(for: caree, in: modelContext)
                        }

                        WidgetCenter.shared.reloadAllTimelines()
                    } catch {
                        self.error = AppError.saveFailed(error.localizedDescription)
                    }
                    locationManager.stopUpdating()
                    isSaving = false
                }

                // Dismiss with slight delay for smoother transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}
