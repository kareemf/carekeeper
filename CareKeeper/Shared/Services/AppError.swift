import Foundation

/// Application-specific errors with user-friendly messages
enum AppError: LocalizedError {
    case modelContainerFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case locationPermissionDenied
    case locationUnavailable
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .modelContainerFailed(let detail):
            return NSLocalizedString("Failed to initialize data storage", comment: "Model container error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case .saveFailed(let detail):
            return NSLocalizedString("Failed to save changes", comment: "Save error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case .deleteFailed(let detail):
            return NSLocalizedString("Failed to delete item", comment: "Delete error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case .locationPermissionDenied:
            return NSLocalizedString("Location access denied. Please enable location services in Settings.", comment: "Location permission error")
        case .locationUnavailable:
            return NSLocalizedString("Unable to determine location. Please try again.", comment: "Location unavailable error")
        case .invalidInput(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelContainerFailed:
            return NSLocalizedString("Please restart the app. If the problem persists, contact support.", comment: "Model container recovery")
        case .saveFailed, .deleteFailed:
            return NSLocalizedString("Please try again.", comment: "Generic recovery")
        case .locationPermissionDenied:
            return NSLocalizedString("Open Settings > Privacy & Security > Location Services", comment: "Location permission recovery")
        case .locationUnavailable:
            return NSLocalizedString("Make sure location services are enabled and you have a clear view of the sky.", comment: "Location unavailable recovery")
        case .invalidInput:
            return nil
        }
    }
}
