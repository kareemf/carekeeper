import Foundation
import SwiftUI

// Simple ErrorHandling class for v1 compatibility
// This will be replaced when we fully migrate to v2
class ErrorHandling: ObservableObject {
    @Published var currentAlert: ErrorAlert?
    
    func handle(error: Error, description: String) {
        DispatchQueue.main.async {
            self.currentAlert = ErrorAlert(
                title: "Error",
                message: "\(description): \(error.localizedDescription)"
            )
        }
    }
}

struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var dismissAction: (() -> Void)? = nil
}