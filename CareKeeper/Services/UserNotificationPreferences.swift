import Foundation
import SwiftUI

/// Service for managing user notification preferences
/// Stores preferences in app group UserDefaults for iOS/watchOS sync
@MainActor
class UserNotificationPreferences: ObservableObject {

    // MARK: - Shared Instance

    static let shared = UserNotificationPreferences()

    // MARK: - App Group UserDefaults

    private let appGroupDefaults: UserDefaults
    private let logger = AppLogger.app
    private let isUsingFallbackDefaults: Bool
    private var hasLoggedFallbackWarning = false

    // MARK: - Keys

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationsPerCaree = "notificationsPerCaree"
    }

    // MARK: - Published Properties

    /// Global notification toggle - controls all notifications
    @Published var notificationsEnabled: Bool {
        didSet {
            appGroupDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    /// Per-caree notification preferences
    private var careePreferences: [String: Bool] {
        get {
            appGroupDefaults.dictionary(forKey: Keys.notificationsPerCaree) as? [String: Bool] ?? [:]
        }
        set {
            appGroupDefaults.set(newValue, forKey: Keys.notificationsPerCaree)
        }
    }

    // MARK: - Initialization

    private init() {
        // Initialize app group UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: CloudKitConfig.appGroupID) {
            self.appGroupDefaults = appGroupDefaults
            self.isUsingFallbackDefaults = false
        } else {
            self.logger.error("⚠️ Failed to resolve app-group UserDefaults (\(CloudKitConfig.appGroupID, privacy: .public)); falling back to standard defaults.")
            self.appGroupDefaults = .standard
            self.isUsingFallbackDefaults = true
        }

        // Load initial value
        self.notificationsEnabled = self.appGroupDefaults.bool(forKey: Keys.notificationsEnabled)
    }

    // MARK: - Per-Caree Preferences

    /// Check if notifications are enabled for a specific caree
    /// - Parameter careeID: The caree's UUID
    /// - Returns: true if notifications are enabled for this caree and globally enabled
    func isEnabled(for careeID: UUID) -> Bool {
        guard notificationsEnabled else { return false }
        return careePreferences[careeID.uuidString] ?? false
    }

    /// Set notification preference for a specific caree
    /// - Parameters:
    ///   - enabled: Whether to enable notifications for this caree
    ///   - careeID: The caree's UUID
    func setEnabled(_ enabled: Bool, for careeID: UUID) {
        var preferences = careePreferences
        preferences[careeID.uuidString] = enabled
        careePreferences = preferences

        // If enabling a caree, ensure global notifications are enabled
        if enabled && !notificationsEnabled {
            notificationsEnabled = true
        }

        if isUsingFallbackDefaults && !hasLoggedFallbackWarning {
            logger.warning("⚠️ Notification preferences are using fallback defaults; settings will not sync via app group.")
            hasLoggedFallbackWarning = true
        }

        objectWillChange.send()
    }

    /// Toggle notification preference for a specific caree
    /// - Parameter careeID: The caree's UUID
    /// - Returns: The new enabled state
    @discardableResult
    func toggle(for careeID: UUID) -> Bool {
        let newValue = !isEnabled(for: careeID)
        setEnabled(newValue, for: careeID)
        return newValue
    }

    /// Get all caree IDs that have notifications enabled
    /// - Returns: Array of UUID strings for carees with notifications enabled
    func enabledCareeIDs() -> [String] {
        guard notificationsEnabled else { return [] }
        return careePreferences.filter { $0.value }.map { $0.key }
    }

    /// Remove preferences for a deleted caree
    /// - Parameter careeID: The caree's UUID
    func removePreferences(for careeID: UUID) {
        var preferences = careePreferences
        preferences.removeValue(forKey: careeID.uuidString)
        careePreferences = preferences
        objectWillChange.send()
    }
}
