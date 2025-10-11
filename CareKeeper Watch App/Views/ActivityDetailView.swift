import SwiftUI
import SwiftData
import MapKit

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let activityID: UUID
    @Query private var myActivities: [Activity]  // Only private database records

    // Services for shared records
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    @StateObject private var sharedDataService = CloudKitSharedDataService()

    // Combined list of all activities (private + shared)
    private var allActivities: [Activity] {
        var activities = myActivities
        // Add activities from shared carees
        for caree in sharedRecordsService.sharedCarees {
            if let careeActivities = caree.activities {
                activities.append(contentsOf: careeActivities)
            }
        }
        return activities
    }

    // Computed property to get the specific activity
    private var activity: Activity? {
        allActivities.first { $0.id == activityID }
    }

    // Check if this activity belongs to a shared caree
    private var isSharedActivity: Bool {
        guard let activity = activity, let caree = activity.caree else { return false }
        return sharedRecordsService.sharedCarees.contains { $0.id == caree.id }
    }

    @State private var isEditing = false
    @State private var editingNotes: String = ""
    @State private var editingQuantity: String = ""
    @State private var useCustomTime: Bool = false
    @State private var editingTime: Date = Date()
    @State private var showingDeleteConfirmation = false
    @State private var error: Error?
    @State private var isSaving = false

    init(activityID: UUID) {
        self.activityID = activityID
    }

    var body: some View {
        Group {
            if let activity = activity {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(for: activity)
                        detailsSection(for: activity)

                        if activity.hasLocation {
                            locationSection(for: activity)
                        }

                        if isEditing {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding()
                            } else {
                                Button {
                                    saveChanges(for: activity)
                                } label: {
                                    Text(NSLocalizedString("Save", comment: "Save button"))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)

                                Button {
                                    cancelEditing(for: activity)
                                } label: {
                                    Text(NSLocalizedString("Cancel", comment: "Cancel button"))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Text(NSLocalizedString("Delete Activity", comment: "Delete activity button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
                .navigationTitle(activity.activityType?.name ?? NSLocalizedString("Activity", comment: "Activity title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if !isEditing {
                            Button {
                                startEditing(for: activity)
                            } label: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                }
                .confirmationDialog(
                    NSLocalizedString("Delete Activity?", comment: "Delete confirmation title"),
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                        deleteActivity(activity)
                    }
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("This cannot be undone.", comment: "Delete confirmation message"))
                }
                .onAppear {
                    setupEditingValues(for: activity)
                }
                .task {
                    await sharedRecordsService.fetchSharedCarees()
                }
            } else {
                Text(NSLocalizedString("Activity not found", comment: "Activity not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .errorAlert($error)
    }

    private func headerSection(for activity: Activity) -> some View {
        VStack(spacing: 8) {
            Text(activity.activityType?.displayIcon ?? "⭐")
                .font(.system(size: 40))

            Text(activity.activityType?.name ?? NSLocalizedString("Unknown Activity", comment: "Unknown activity"))
                .font(.headline)

            Text(activity.formattedDateTime)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailsSection(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time section (watch-friendly, time-only)
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Time", comment: "Time section"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(NSLocalizedString("Custom time", comment: "Custom time toggle"), isOn: $useCustomTime)

                    if useCustomTime {
                        DatePicker(
                            NSLocalizedString("Time", comment: "Time picker label"),
                            selection: $editingTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
            }

            // Quantity section
            if activity.activityType?.hasQuantity == true {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Quantity", comment: "Quantity section title"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isEditing {
                        HStack {
                            TextField(NSLocalizedString("Amount", comment: "Quantity placeholder"),
                                     text: $editingQuantity)

                            if let unit = activity.activityType?.quantityUnit {
                                Text(unit)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        if let formattedQuantity = activity.formattedQuantity {
                            Text(formattedQuantity)
                                .font(.title3)
                        } else {
                            Text(NSLocalizedString("None", comment: "No quantity"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
            }

            // Notes section
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Notes", comment: "Notes section title"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isEditing {
                    TextField(NSLocalizedString("Add notes...", comment: "Notes placeholder"),
                             text: $editingNotes, axis: .vertical)
                        .lineLimit(2...4)
                } else {
                    if let notes = activity.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                    } else {
                        Text(NSLocalizedString("None", comment: "No notes"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func locationSection(for activity: Activity) -> some View {
        if let location = activity.location {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Location", comment: "Location section title"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Map(position: .constant(.region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))) {
                    Marker("", coordinate: location.coordinate)
                }
                .frame(height: 120)
                .cornerRadius(8)

                Text(String(format: "%.6f, %.6f",
                           location.coordinate.latitude,
                           location.coordinate.longitude))
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func setupEditingValues(for activity: Activity) {
        editingNotes = activity.notes ?? ""
        editingQuantity = activity.quantity?.description ?? ""
        useCustomTime = false
        editingTime = activity.dateTime
    }

    private func startEditing(for activity: Activity) {
        isEditing = true
        setupEditingValues(for: activity)
    }

    private func cancelEditing(for activity: Activity) {
        setupEditingValues(for: activity)
        isEditing = false
    }

    private func saveChanges(for activity: Activity) {
        guard let caree = activity.caree else {
            error = AppError.invalidInput("Activity has no associated caree")
            return
        }

        // Update local values
        activity.notes = editingNotes.isEmpty ? nil : editingNotes
        activity.quantity = Double(editingQuantity)

        if useCustomTime {
            // Preserve the original date, change only the time component.
            activity.dateTime = combine(date: activity.dateTime, timeOfDayFrom: editingTime)
        }

        if isSharedActivity {
            // Handle shared activity - use CloudKit service
            isSaving = true
            Task {
                do {
                    try await sharedDataService.updateActivity(activity, caree: caree)

                    // Refresh shared carees to reflect changes
                    await sharedRecordsService.fetchSharedCarees()

                    await MainActor.run {
                        isSaving = false
                        isEditing = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed(error.localizedDescription)
                        isSaving = false
                    }
                }
            }
        } else {
            // Handle owned activity - use SwiftData
            do {
                try modelContext.save()
                isEditing = false
            } catch {
                self.error = AppError.saveFailed(error.localizedDescription)
            }
        }
    }

    // Combine a base date with the hour/minute from a time-of-day Date
    private func combine(date baseDate: Date, timeOfDayFrom time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second ?? 0
        return calendar.date(from: dateComponents) ?? baseDate
    }

    private func deleteActivity(_ activity: Activity) {
        guard let caree = activity.caree else {
            error = AppError.invalidInput("Activity has no associated caree")
            return
        }

        if isSharedActivity {
            // Handle shared activity - use CloudKit service
            Task {
                do {
                    try await sharedDataService.deleteActivity(activity, caree: caree)

                    // Refresh shared carees to reflect changes
                    await sharedRecordsService.fetchSharedCarees()

                    await MainActor.run {
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.deleteFailed(error.localizedDescription)
                    }
                }
            }
        } else {
            // Handle owned activity - use SwiftData
            modelContext.delete(activity)

            do {
                try modelContext.save()
                dismiss()
            } catch {
                self.error = AppError.deleteFailed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ActivityDetailView(activityID: PreviewData.sampleActivity.id)
    }
    .modelContainer(PreviewContainer.shared)
}
