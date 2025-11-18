import CoreLocation
import SwiftUI
import WidgetKit

struct TrackActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let caree: Caree

    @State private var selectedActivityType: ActivityType?
    @State private var notes: String = ""
    @State private var quantity: String = ""
    @State private var customDateTime: Date = .init()
    @State private var useCustomTime: Bool = false
    @State private var includeLocation: Bool = false
    @StateObject private var locationManager = LocationManager()
    @State private var error: Error?
    @State private var isSaving: Bool = false
    @State private var reminderEnabled: Bool = false
    @State private var reminderDate: Date = .init().addingTimeInterval(300)

    // Use unified API from CloudKitDataService
    @EnvironmentObject private var cloudKitService: CloudKitDataService

    private var sortedActivityTypes: [ActivityType] {
        caree.sortedActivityTypes
    }

    private let reminderWindow: TimeInterval = 7 * 24 * 60 * 60
    
    var body: some View {
        NavigationView {
            Form {
                activityTypeSection

                if selectedActivityType != nil {
                    detailsSection
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    timingSection
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    reminderSection
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
                Text(NSLocalizedString(
                    "No activity types available. Add activity types first.",
                    comment: "No activity types message"
                ))
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
            TextField(
                NSLocalizedString("Notes (optional)", comment: "Notes field placeholder"),
                text: $notes,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            
            if selectedActivityType?.hasQuantity == true {
                HStack {
                    TextField(
                        NSLocalizedString("Quantity", comment: "Quantity field placeholder"),
                        text: $quantity
                    )
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
                DatePicker(
                    NSLocalizedString("When", comment: "Date picker label"),
                    selection: $customDateTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    private var reminderSection: some View {
        Section(NSLocalizedString("Reminder", comment: "Reminder section title")) {
            Toggle(NSLocalizedString("Set Reminder", comment: "Reminder toggle label"), isOn: $reminderEnabled.animation())
                .onChange(of: reminderEnabled) { _, isOn in
                    if isOn {
                        reminderDate = defaultReminderDate()
                    }
                }

            if reminderEnabled {
                DatePicker(
                    NSLocalizedString("Remind me on", comment: "Reminder date picker label"),
                    selection: $reminderDate,
                    in: reminderPickerRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
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
        if activityType.hasQuantity, !quantity.isEmpty {
            if let parsedQuantity = Double(quantity), parsedQuantity >= 0 {
                quantityValue = parsedQuantity
            }
        }

        isSaving = true

        let activityDateTime = useCustomTime ? customDateTime : Date()
        let location = includeLocation ? locationManager.location : nil
        let latitude = location?.coordinate.latitude
        let longitude = location?.coordinate.longitude

        Task {
            do {
                // Create activity (unified API routes internally)
                let newActivity = try await cloudKitService.createActivity(
                    caree: caree,
                    activityType: activityType,
                    dateTime: activityDateTime,
                    notes: notes.isEmpty ? nil : notes,
                    quantity: quantityValue,
                    latitude: latitude,
                    longitude: longitude
                )

                if reminderEnabled {
                    await scheduleReminderIfNeeded(
                        for: newActivity,
                        caree: caree,
                        activityType: activityType
                    )
                }

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
    }

    private func scheduleReminderIfNeeded(for activity: Activity, caree: Caree, activityType: ActivityType) async {
        let scheduler = ReminderScheduler.shared
        let authorized = await scheduler.ensureAuthorization()
        guard authorized else {
            await MainActor.run {
                self.error = ReminderPermissionError(platform: .iOS)
                self.reminderEnabled = false
            }
            return
        }

        let dueDate = clampedReminderDate()
        do {
            let result = try await scheduler.scheduleReminder(
                careeName: caree.name,
                activityTypeName: activityType.name,
                dueDate: dueDate,
                note: activity.notes
            )

            if let cacheService = cloudKitService.cacheService {
                try await cacheService.updateReminderMetadata(
                    activityID: activity.id,
                    identifier: result.identifier,
                    dueDate: result.dueDate,
                    source: ReminderSource.current
                )
            }
        } catch {
            await MainActor.run {
                self.error = AppError.saveFailed(error.localizedDescription)
            }
        }
    }

    private var reminderPickerRange: ClosedRange<Date> {
        let now = Date()
        let minDate = now.addingTimeInterval(60)
        let maxDate = now.addingTimeInterval(reminderWindow)
        return minDate ... maxDate
    }

    private func clampedReminderDate() -> Date {
        let range = reminderPickerRange
        let bounded = min(max(reminderDate, range.lowerBound), range.upperBound)
        return bounded.roundedDownToMinute()
    }

    private func defaultReminderDate() -> Date {
        let now = Date()
        let defaultDate = now.addingTimeInterval(300) // 5 minutes from now
        let range = reminderPickerRange
        return min(max(defaultDate, range.lowerBound), range.upperBound).roundedDownToMinute()
    }
}

#Preview {
    TrackActivityView(caree: PreviewData.sampleCareeWithActivities)
        .modelContainer(PreviewContainer.shared)
}
