import SwiftUI

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let activity: Activity
    
    @State private var isEditing = false
    @State private var editingNotes: String = ""
    @State private var editingQuantity: String = ""
    @State private var editingDateTime: Date = Date()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    detailsSection
                    
                    if activity.hasLocation {
                        locationSection
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
                    if isEditing {
                        Button(NSLocalizedString("Save", comment: "Save button")) {
                            saveChanges()
                        }
                    } else {
                        Button(NSLocalizedString("Edit", comment: "Edit button")) {
                            startEditing()
                        }
                    }
                }
            }
        }
        .onAppear {
            setupEditingValues()
        }
    }
    
    private var headerSection: some View {
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
    
    private var detailsSection: some View {
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
    private var locationSection: some View {
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
                    openInMaps()
                }
            }
        }
    }
    
    private func setupEditingValues() {
        editingNotes = activity.notes ?? ""
        editingQuantity = activity.quantity?.description ?? ""
        editingDateTime = activity.dateTime
    }
    
    private func startEditing() {
        isEditing = true
        setupEditingValues()
    }
    
    private func saveChanges() {
        activity.notes = editingNotes.isEmpty ? nil : editingNotes
        activity.quantity = Double(editingQuantity)
        activity.dateTime = editingDateTime
        
        isEditing = false
    }
    
    private func openInMaps() {
        guard let location = activity.location else { return }
        
        let url = URL(string: "http://maps.apple.com/?ll=\(location.coordinate.latitude),\(location.coordinate.longitude)")
        if let url = url {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ActivityDetailView(activity: PreviewData.sampleActivity)
        .modelContainer(PreviewContainer.shared)
}