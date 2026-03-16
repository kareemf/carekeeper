import Foundation

/// Service for managing the caregiver's display name shown in push notifications
/// Stores the name in app group UserDefaults for iOS/watchOS sync
@MainActor
class CaregiverDisplayNameService: ObservableObject {
    // MARK: - Shared Instance

    static let shared = CaregiverDisplayNameService()

    // MARK: - App Group UserDefaults

    private let appGroupDefaults: UserDefaults

    // MARK: - Keys

    private enum Keys {
        static let displayName = "caregiverDisplayName"
        static let hasBeenPrompted = "caregiverDisplayNamePrompted"
    }

    // MARK: - Published Properties

    /// The caregiver's display name, persisted to app group UserDefaults
    @Published var displayName: String? {
        didSet {
            appGroupDefaults.set(displayName, forKey: Keys.displayName)
        }
    }

    /// Whether a display name has been set
    var hasDisplayName: Bool {
        guard let name = displayName else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns displayName if set, otherwise a fallback string
    var resolvedDisplayName: String {
        if let name = displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "A caregiver"
    }

    /// Whether the user should be prompted to set their display name
    var shouldPromptForDisplayName: Bool {
        !hasDisplayName && !appGroupDefaults.bool(forKey: Keys.hasBeenPrompted)
    }

    /// Mark that the user has been prompted (call on both Save and Skip)
    func markPrompted() {
        appGroupDefaults.set(true, forKey: Keys.hasBeenPrompted)
    }

    // MARK: - Initialization

    private init() {
        if let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID) {
            self.appGroupDefaults = defaults
        } else {
            self.appGroupDefaults = .standard
        }
        self.displayName = self.appGroupDefaults.string(forKey: Keys.displayName)
    }
}
