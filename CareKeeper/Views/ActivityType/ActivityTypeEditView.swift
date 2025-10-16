import SwiftUI

struct ActivityTypeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let caree: Caree
    let activityType: ActivityType?

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var hasQuantity: Bool = false
    @State private var quantityUnit: String = ""
    @State private var hasLocation: Bool = false
    @State private var error: Error?
    @State private var isSaving: Bool = false
    @FocusState private var isNameFieldFocused: Bool

    // Use unified API from CloudKitDataService
    @EnvironmentObject private var cloudKitService: CloudKitDataService

    private var isEditing: Bool { activityType != nil }

    init(caree: Caree, activityType: ActivityType? = nil) {
        self.caree = caree
        self.activityType = activityType

        if let activityType = activityType {
            _name = State(initialValue: activityType.name)
            _icon = State(initialValue: activityType.icon ?? "")
            _hasQuantity = State(initialValue: activityType.hasQuantity)
            _quantityUnit = State(initialValue: activityType.quantityUnit ?? "")
            _hasLocation = State(initialValue: activityType.hasLocation)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(NSLocalizedString("Name", comment: "Activity type name field"), text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFieldFocused)

                    TextField(NSLocalizedString("Icon (emoji)", comment: "Activity type icon field"), text: $icon)
                        .textInputAutocapitalization(.never)
                }
                
                Section {
                    Toggle(NSLocalizedString("Has quantity", comment: "Has quantity toggle"), isOn: $hasQuantity)
                    
                    if hasQuantity {
                        TextField(NSLocalizedString("Unit (e.g., oz, minutes)", comment: "Quantity unit field"), 
                                text: $quantityUnit)
                            .textInputAutocapitalization(.never)
                    }
                    
                    Toggle(NSLocalizedString("Track location", comment: "Track location toggle"), isOn: $hasLocation)
                }
            }
            .navigationTitle(isEditing ? 
                           NSLocalizedString("Edit Activity Type", comment: "Edit activity type title") :
                           NSLocalizedString("Add Activity Type", comment: "Add activity type title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveActivityType()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text(NSLocalizedString("Save", comment: "Save button"))
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            // Auto-focus on name field for new activity types
            if !isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNameFieldFocused = true
                }
            }
        }
        .errorAlert($error)
    }
    
    private func saveActivityType() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = AppError.invalidInput(
                NSLocalizedString("Please enter a name for the activity type", comment: "Empty activity type name error")
            )
            return
        }

        isSaving = true

        Task {
            do {
                if let existingActivityType = activityType {
                    // Update existing activity type (unified API routes internally)
                    existingActivityType.name = trimmedName
                    existingActivityType.icon = icon.isEmpty ? nil : icon
                    existingActivityType.hasQuantity = hasQuantity
                    existingActivityType.quantityUnit = hasQuantity && !quantityUnit.isEmpty ? quantityUnit : nil
                    existingActivityType.hasLocation = hasLocation

                    try await cloudKitService.updateActivityType(activityType: existingActivityType, caree: caree)
                } else {
                    // Create new activity type (unified API routes internally)
                    _ = try await cloudKitService.createActivityType(
                        caree: caree,
                        name: trimmedName,
                        icon: icon.isEmpty ? nil : icon,
                        hasQuantity: hasQuantity,
                        quantityUnit: hasQuantity && !quantityUnit.isEmpty ? quantityUnit : nil,
                        hasLocation: hasLocation,
                        listOrder: caree.activityTypes?.count ?? 0
                    )
                }

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = AppError.saveFailed(error.localizedDescription)
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    ActivityTypeEditView(caree: PreviewData.sampleCaree)
        .modelContainer(PreviewContainer.shared)
}

#Preview("Editing") {
    ActivityTypeEditView(caree: PreviewData.sampleCaree, activityType: PreviewData.sampleActivityType)
        .modelContainer(PreviewContainer.shared)
}
