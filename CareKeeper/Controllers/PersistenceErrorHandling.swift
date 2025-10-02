import SwiftUI

struct PersistenceErrorHandlingAlertViewModifier: ViewModifier {
    let persistenceController = PersistenceController.shared

    func body(content: Content) -> some View {
        content
            // Applying the alert for error handling using a background element
            // is a workaround, if the alert would be applied directly,
            // other .alert modifiers inside of content would not work anymore
            .background(
                EmptyView()
                    .alert(item: .constant(persistenceController.errorHandling.currentAlert)) { (currentAlert: ErrorAlert) in
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
    func withPersistenceErrorHandling() -> some View {
        modifier(PersistenceErrorHandlingAlertViewModifier())
    }
}
