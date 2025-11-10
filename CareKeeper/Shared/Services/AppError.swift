import Foundation

/// Application-specific errors with user-friendly messages
enum AppError: LocalizedError {
    case modelContainerFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case locationPermissionDenied
    case locationUnavailable
    case invalidInput(String)
    case missingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .modelContainerFailed(detail):
            NSLocalizedString("Failed to initialize data storage", comment: "Model container error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case let .saveFailed(detail):
            NSLocalizedString("Failed to save changes", comment: "Save error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case let .deleteFailed(detail):
            NSLocalizedString("Failed to delete item", comment: "Delete error")
                + (detail.isEmpty ? "" : ": \(detail)")
        case .locationPermissionDenied:
            NSLocalizedString(
                "Location access denied. Please enable location services in Settings.",
                comment: "Location permission error"
            )
        case .locationUnavailable:
            NSLocalizedString("Unable to determine location. Please try again.", comment: "Location unavailable error")
        case let .invalidInput(message):
            message
        case let .missingConfiguration(message):
            message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelContainerFailed:
            NSLocalizedString(
                "Please restart the app. If the problem persists, contact support.",
                comment: "Model container recovery"
            )
        case .saveFailed, .deleteFailed:
            NSLocalizedString("Please try again.", comment: "Generic recovery")
        case .locationPermissionDenied:
            NSLocalizedString("Open Settings > Privacy & Security > Location Services", comment: "Location permission recovery")
        case .locationUnavailable:
            NSLocalizedString(
                "Make sure location services are enabled and you have a clear view of the sky.",
                comment: "Location unavailable recovery"
            )
        case .invalidInput:
            nil
        case .missingConfiguration:
            NSLocalizedString(
                "Set CLOUDKIT_CONTAINER_ID, APP_GROUP_IDENTIFIER, and ZONE_NAME (via Config.plist or environment) then relaunch.",
                comment: "Missing configuration recovery"
            )
        }
    }
}
