import SwiftUI

/// View modifier for displaying error alerts
struct ErrorAlertModifier: ViewModifier {
    @Binding var error: Error?

    func body(content: Content) -> some View {
        content
            .alert(
                NSLocalizedString("Error", comment: "Error alert title"),
                isPresented: .constant(error != nil),
                presenting: error
            ) { error in
                if let settingsError = error as? SettingsRedirectableError, settingsError.canOpenSettings {
                    Button(settingsError.settingsButtonTitle) {
                        settingsError.openSettings()
                    }
                }
                Button(NSLocalizedString("OK", comment: "Error alert dismiss")) {
                    self.error = nil
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)

                    if let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion {
                        Text(recoverySuggestion)
                            .font(.caption)
                    }
                }
            }
    }
}

extension View {
    /// Presents an alert when an error occurs
    /// - Parameter error: Binding to an optional Error
    func errorAlert(_ error: Binding<Error?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
}
