import MapKit
import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let activityID: UUID

    // Use unified API from CloudKitDataService
    @EnvironmentObject private var cloudKitService: CloudKitDataService

    // Get cache service from shared CloudKitDataService
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    // Get the specific activity from cache
    private var activity: Activity? {
        guard let cacheService else { return nil }
        // Search through all cached carees (owned + shared) for the activity
        for caree in cacheService.myCarees + cacheService.sharedCarees {
            if let activities = caree.activities,
               let activity = activities.first(where: { $0.id == activityID })
            {
                return activity
            }
        }
        return nil
    }

    @State private var isEditing = false
    @State private var editingNotes: String = ""
    @State private var editingQuantity: String = ""
    @State private var editingDateTime: Date = .init()
    @State private var showingDeleteConfirmation = false
    @State private var error: Error?
    @State private var isSaving = false

    init(activityID: UUID) {
        self.activityID = activityID
    }
    
    var body: some View {
        Group {
            if let activity {
                NavigationView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerSection(for: activity)
                            detailsSection(for: activity)

                            if activity.hasLocation {
                                locationSection(for: activity)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle(activity.activityType?.name ?? NSLocalizedString("Activity", comment: "Activity title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(NSLocalizedString("Done", comment: "Done button")) {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
                                if isEditing {
                                    if isSaving {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.8)
                                    } else {
                                        Button(NSLocalizedString("Save", comment: "Save button")) {
                                            saveChanges(for: activity)
                                        }
                                    }
                                } else {
                                    Menu {
                                        Button(NSLocalizedString("Edit", comment: "Edit button")) {
                                            startEditing(for: activity)
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label(
                                                NSLocalizedString("Delete Activity", comment: "Delete activity button"),
                                                systemImage: "trash"
                                            )
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                }
                            }
                        }
                    }
                    .confirmationDialog(
                        NSLocalizedString("Delete this activity?", comment: "Delete confirmation title"),
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(NSLocalizedString("Delete Activity", comment: "Delete confirmation button"), role: .destructive) {
                            deleteActivity(activity)
                        }
                        Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                    } message: {
                        Text(NSLocalizedString("This action cannot be undone.", comment: "Delete confirmation message"))
                    }
                }
                .onAppear {
                    setupEditingValues(for: activity)
                }
                .task {
                    // Refresh cache to load activities
                    try? await cacheService?.refreshCache()
                }
                .onReceive(cloudKitService.$cacheService.compactMap(\.self)) { cache in
                    Task {
                        try? await cache.refreshCache()
                        await MainActor.run {
                            if let activity = self.activity {
                                self.setupEditingValues(for: activity)
                            }
                        }
                    }
                }
            } else {
                Text(NSLocalizedString("Activity not found", comment: "Activity not found message"))
                    .foregroundColor(.secondary)
            }
        }
        .errorAlert($error)
    }
    
    private func headerSection(for activity: Activity) -> some View {
        HStack {
            if let icon = activity.activityType?.displayIcon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 50))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(activity.activityType?.name ?? NSLocalizedString("Unknown Activity", comment: "Unknown activity"))
                    .font(.title2)
                    .fontWeight(.medium)

                if isEditing {
                    DatePicker(
                        NSLocalizedString("When", comment: "Date picker label"),
                        selection: $editingDateTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } else {
                    Text(activity.formattedDateTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }
    
    private func detailsSection(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Notes section
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Notes", comment: "Notes section title"))
                    .font(.headline)

                if isEditing {
                    TextField(
                        NSLocalizedString("Add notes...", comment: "Notes placeholder"),
                        text: $editingNotes,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
                } else {
                    if let notes = activity.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                    } else {
                        Text(NSLocalizedString("No notes", comment: "No notes placeholder"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }

            // Quantity section
            if activity.activityType?.hasQuantity == true {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Quantity", comment: "Quantity section title"))
                        .font(.headline)

                    if isEditing {
                        HStack {
                            TextField(
                                NSLocalizedString("Amount", comment: "Quantity placeholder"),
                                text: $editingQuantity
                            )
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                            if let unit = activity.activityType?.quantityUnit {
                                Text(unit)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        if let formattedQuantity = activity.formattedQuantity {
                            Text(formattedQuantity)
                                .font(.body)
                        } else {
                            Text(NSLocalizedString("No quantity recorded", comment: "No quantity placeholder"))
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func locationSection(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Location", comment: "Location section title"))
                .font(.headline)

            if let location = activity.location {
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))) {
                    Marker("", coordinate: location.coordinate)
                }
                .frame(height: 180)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle()) // Make the map tappable area clear
                .onTapGesture {
                    openInMaps(for: activity)
                }

                Text(String(
                    format: "%.6f, %.6f",
                    location.coordinate.latitude,
                    location.coordinate.longitude
                ))
                .font(.body)
                .fontDesign(.monospaced)

                Text(NSLocalizedString("Tap to view in Maps", comment: "Maps CTA"))
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)
                    .onTapGesture {
                        openInMaps(for: activity)
                    }
            }
        }
    }
    
    private func setupEditingValues(for activity: Activity) {
        editingNotes = activity.notes ?? ""
        editingQuantity = activity.quantity?.description ?? ""
        editingDateTime = activity.dateTime
    }

    private func startEditing(for activity: Activity) {
        isEditing = true
        setupEditingValues(for: activity)
    }

    private func saveChanges(for activity: Activity) {
        guard let caree = activity.caree else {
            error = AppError.invalidInput("Activity has no associated caree")
            return
        }

        guard let activityType = activity.activityType else {
            error = AppError.invalidInput("Activity has no associated activity type")
            return
        }

        // Update local values
        activity.notes = editingNotes.isEmpty ? nil : editingNotes
        activity.quantity = Double(editingQuantity)
        activity.dateTime = editingDateTime

        isSaving = true

        Task {
            do {
                // Update activity (unified API routes internally)
                try await cloudKitService.updateActivity(activity: activity, caree: caree, activityType: activityType)

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
    }

    private func openInMaps(for activity: Activity) {
        guard let location = activity.location else { return }

        let url = URL(string: "http://maps.apple.com/?ll=\(location.coordinate.latitude),\(location.coordinate.longitude)")
        if let url {
            UIApplication.shared.open(url)
        }
    }

    private func deleteActivity(_ activity: Activity) {
        guard let caree = activity.caree else {
            error = AppError.invalidInput("Activity has no associated caree")
            return
        }

        Task {
            do {
                // Delete activity (unified API routes internally)
                try await cloudKitService.deleteActivity(activity: activity, caree: caree)

                // Cache is automatically updated by service
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = AppError.deleteFailed(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    ActivityDetailView(activityID: PreviewData.sampleActivity.id)
        .modelContainer(PreviewContainer.shared)
}
