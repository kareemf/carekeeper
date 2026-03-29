import SwiftUI

/// ViewModifier that presents a one-time alert prompting the user to set their caregiver display name.
/// Attach via `.displayNamePrompt(isPresented:onComplete:)`.
struct DisplayNamePromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onComplete: () -> Void

    @State private var draftName: String = ""

    func body(content: Content) -> some View {
        content
            .alert(
                NSLocalizedString("Set Your Display Name", comment: "Display name prompt title"),
                isPresented: $isPresented
            ) {
                TextField(
                    NSLocalizedString("Your name", comment: "Display name prompt placeholder"),
                    text: $draftName
                )
                .textContentType(.name)

                Button(NSLocalizedString("Save", comment: "Save button")) {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        CaregiverDisplayNameService.shared.displayName = trimmed
                        CaregiverDisplayNameService.shared.syncToCloudKitImmediately()
                    }
                    CaregiverDisplayNameService.shared.markPrompted()
                    onComplete()
                }

                Button(NSLocalizedString("Skip", comment: "Skip button"), role: .cancel) {
                    CaregiverDisplayNameService.shared.markPrompted()
                    onComplete()
                }
            } message: {
                Text(NSLocalizedString(
                    "Other caregivers will see this name in notifications when you track activities.",
                    comment: "Display name prompt message"
                ))
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    draftName = CaregiverDisplayNameService.shared.displayName ?? ""
                }
            }
    }
}

extension View {
    func displayNamePrompt(isPresented: Binding<Bool>, onComplete: @escaping () -> Void = {}) -> some View {
        modifier(DisplayNamePromptModifier(isPresented: isPresented, onComplete: onComplete))
    }
}
