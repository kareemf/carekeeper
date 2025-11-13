import Foundation
#if os(iOS) || os(macOS)
    import UIKit
#endif
#if os(watchOS)
    import WatchKit
#endif

protocol SettingsRedirectableError {
    var canOpenSettings: Bool { get }
    var settingsButtonTitle: String { get }
    func openSettings()
}

enum ReminderPermissionPlatform {
    case iOS
    case watch
}

struct ReminderPermissionError: LocalizedError, SettingsRedirectableError {
    let platform: ReminderPermissionPlatform

    var errorDescription: String? {
        NSLocalizedString("Reminders permission not granted.", comment: "Reminder permission error title")
    }

    var recoverySuggestion: String? {
        switch platform {
        case .iOS:
            return NSLocalizedString("Enable Reminders access for CareKeeper in Settings to schedule reminders.", comment: "Reminder permission recovery iOS")
        case .watch:
            return NSLocalizedString("Enable notifications for CareKeeper in the Watch app on your iPhone to schedule reminders from the watch.", comment: "Reminder permission recovery watch")
        }
    }

    var canOpenSettings: Bool {
        #if os(iOS)
            return platform == .iOS
        #else
            return false
        #endif
    }

    var settingsButtonTitle: String {
        NSLocalizedString("Open Settings", comment: "Settings button title")
    }

    func openSettings() {
        guard canOpenSettings else { return }
        #if os(iOS)
            let url = URL(string: UIApplication.openSettingsURLString)
            if let url, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        #endif
    }
}
