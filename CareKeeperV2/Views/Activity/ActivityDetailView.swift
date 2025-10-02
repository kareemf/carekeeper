import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let activityID: UUID
    @Query private var allActivities: [Activity]

    // Computed property to get the specific activity
    private var activity: Activity? {
        allActivities.first { $0.id == activityID }
    }

    @State private var isEditing = false
    @State private var editingNotes: String = ""
    @State private var editingQuantity: String = ""
    @State private var editingDateTime: Date = Date()
    @State private var showingDeleteConfirmation = false

    init(activityID: UUID) {
        self.activityID = activityID
    }
    
    var body: some View {
        Group {
            if let activity = activity {
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
                                    Button(NSLocalizedString("Save", comment: "Save button")) {
                                        saveChanges(for: activity)
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
                                            Label(NSLocalizedString("Delete Activity", comment: "Delete activity button"),
                                                  systemImage: "trash")
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
            } else {
                Text(NSLocalizedString("Activity not found", comment: "Activity not found message"))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func headerSection(for activity: Activity) -> some View {
        HStack {
            Text(activity.activityType?.displayIcon ?? "⭐")
                .font(.system(size: 50))

            VStack(alignment: .leading, spacing: 8) {
                Text(activity.activityType?.name ?? NSLocalizedString("Unknown Activity", comment: "Unknown activity"))
                    .font(.title2)
                    .fontWeight(.medium)

                if isEditing {
                    DatePicker(NSLocalizedString("When", comment: "Date picker label"),
                              selection: $editingDateTime,
                              displayedComponents: [.date, .hourAndMinute])
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
                    TextField(NSLocalizedString("Add notes...", comment: "Notes placeholder"),
                             text: $editingNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
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
                            TextField(NSLocalizedString("Amount", comment: "Quantity placeholder"),
                                     text: $editingQuantity)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.6f, %.6f",
                               location.coordinate.latitude,
                               location.coordinate.longitude))
                        .font(.body)
                        .fontDesign(.monospaced)

                    Text(NSLocalizedString("Tap to view in Maps", comment: "Maps CTA"))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
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
        activity.notes = editingNotes.isEmpty ? nil : editingNotes
        activity.quantity = Double(editingQuantity)
        activity.dateTime = editingDateTime

        isEditing = false
    }

    private func openInMaps(for activity: Activity) {
        guard let location = activity.location else { return }

        let url = URL(string: "http://maps.apple.com/?ll=\(location.coordinate.latitude),\(location.coordinate.longitude)")
        if let url = url {
            UIApplication.shared.open(url)
        }
    }

    private func deleteActivity(_ activity: Activity) {
        modelContext.delete(activity)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("⚠️ Failed to delete activity: \(error)")
        }
    }
}

#Preview {
    ActivityDetailView(activityID: PreviewData.sampleActivity.id)
        .modelContainer(PreviewContainer.shared)
}