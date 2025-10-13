import SwiftUI
import PhotosUI

struct CareeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let caree: Caree?

    @State private var name: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var error: Error?
    @State private var shakeField: Bool = false
    @State private var isSaving = false
    @FocusState private var isNameFieldFocused: Bool

    // Pure CloudKit architecture services
    @StateObject private var cloudKitService = CloudKitDataService()

    private var isEditing: Bool { caree != nil }
    
    init(caree: Caree? = nil) {
        self.caree = caree
        if let caree = caree {
            _name = State(initialValue: caree.name)
            _imageData = State(initialValue: caree.image)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    profileImageSection

                    TextField(NSLocalizedString("Name", comment: "Name field label"), text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFieldFocused)
                        .modifier(ShakeEffect(shakes: shakeField ? 2 : 0))
                        .onChange(of: shakeField) { _, _ in
                            if shakeField {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    shakeField = false
                                }
                            }
                        }
                }
            }
            .navigationTitle(isEditing ?
                           NSLocalizedString("Edit Caree", comment: "Edit caree navigation title") :
                           NSLocalizedString("Add Caree", comment: "Add caree navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(NSLocalizedString("Save", comment: "Save button")) {
                            Task {
                                await saveCaree()
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear {
            // Auto-focus on name field for new carees
            if !isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNameFieldFocused = true
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadSelectedPhoto(from: newItem)
        }
        .errorAlert($error)
    }
    
    private var profileImageSection: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 12) {
                profileImageView
                
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Text(imageData == nil ? 
                         NSLocalizedString("Add Photo", comment: "Add photo button") :
                         NSLocalizedString("Change Photo", comment: "Change photo button"))
                        .font(.caption)
                }
            }
            
            Spacer()
        }
        .padding(.vertical)
    }
    
    private var profileImageView: some View {
        Group {
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
    }
    
    private func loadSelectedPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    self.imageData = data
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.error = error
                }
            }
        }
    }
    
    private func saveCaree() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            withAnimation(.default) {
                shakeField = true
            }
            error = AppError.invalidInput(
                NSLocalizedString("Please enter a name for the caree", comment: "Empty caree name error")
            )
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let existingCaree = caree {
                // Pure CloudKit: Update existing caree via CloudKitDataService
                print("📝 Updating caree via CloudKit: \(trimmedName) (ID: \(existingCaree.id.uuidString))")

                // Determine if this is a shared caree
                let isShared = existingCaree.isShared

                try await cloudKitService.updateCaree(
                    existingCaree,
                    name: trimmedName,
                    imageData: imageData,
                    isShared: isShared
                )

                print("✅ Caree updated successfully in CloudKit")
            } else {
                // Pure CloudKit: Create new caree via CloudKitDataService
                print("➕ Creating new caree via CloudKit: \(trimmedName)")

                _ = try await cloudKitService.createCaree(
                    name: trimmedName,
                    imageData: imageData,
                    listOrder: 0
                )

                print("✅ Caree created successfully in CloudKit and cached locally")
            }

            dismiss()
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
            self.error = AppError.saveFailed(error.localizedDescription)
        }
    }
}

#Preview {
    CareeEditView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("Editing") {
    CareeEditView(caree: PreviewData.sampleCaree)
        .modelContainer(PreviewContainer.shared)
}