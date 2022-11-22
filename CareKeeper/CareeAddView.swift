import SwiftUI

struct CareeAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var errorHandling: ErrorHandling

    @StateObject var profileImageModel = ProfileImageModel()
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    @Binding var isPresenting: Bool

    private func addCaree() {
        withAnimation {
            let newCaree = Caree(context: viewContext)
            newCaree.dateCreated = Date()
            newCaree.name = name.trimmingCharacters(in: .whitespacesAndNewlines)

#if os(iOS)
            if profileImageModel.imageSelection != nil {
                do {
                    let photo = try profileImageModel.createPhotoFromSelection(context: viewContext)
                    newCaree.photo = photo
                } catch {
                    errorHandling.handle(error: error)
                }
            }
#endif
            do {
                try viewContext.save()
                name = ""
            } catch {
                self.errorHandling.handle(error: error)
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                EditableCircularProfileImage(model: profileImageModel)
                TextField("Name", text: $name)
                    .focused($isNameFocused)
            }
            .onAppear {
                isNameFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresenting = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        isPresenting = false
                        addCaree()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

struct CareeAddView_Previews: PreviewProvider {
    static var previews: some View {
        CareeAddView(isPresenting: .constant(true))
    }
}
