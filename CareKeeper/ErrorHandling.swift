/**
 https://www.ralfebert.com/swiftui/generic-error-handling/
 */
import SwiftUI

class ErrorHandling: ObservableObject {
    struct ErrorAlert: Identifiable {
        var id = UUID()
        var message: String
        var dismissAction: (() -> Void)?
    }

    @Published var currentAlert: ErrorAlert?

    func handle(error: Error, dismissAction: (() -> Void)? = nil, description: String = "") {
        if let localizedError = error as? LocalizedError {
            let localizedDescription = localizedError.localizedDescription
            let message = description.isEmpty ? localizedDescription : "\(description)\n\(localizedDescription)"

            currentAlert = ErrorAlert(message: message)
        } else {
            let message = description.isEmpty ? "\(error)" : "\(description)\n\(error)"
            currentAlert = ErrorAlert(message: message)
        }

        if dismissAction != nil {
            currentAlert?.dismissAction = dismissAction
        }
    }
}

struct HandleErrorsByShowingAlertViewModifier: ViewModifier {
    @StateObject var errorHandling = ErrorHandling()

    func body(content: Content) -> some View {
        content
            .environmentObject(errorHandling)
        // Applying the alert for error handling using a background element
        // is a workaround, if the alert would be applied directly,
        // other .alert modifiers inside of content would not work anymore
            .background(
                EmptyView()
                    .alert(item: $errorHandling.currentAlert) { currentAlert in
                        Alert(
                            title: Text("Error"),
                            message: Text(currentAlert.message),
                            dismissButton: .default(Text("Ok")) {
                                currentAlert.dismissAction?()
                            }
                        )
                    }
            )
    }
}

extension View {
    func withErrorHandling() -> some View {
        modifier(HandleErrorsByShowingAlertViewModifier())
    }
}
