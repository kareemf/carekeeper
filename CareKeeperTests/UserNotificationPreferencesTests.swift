@testable import CareKeeper
import XCTest

@MainActor
final class UserNotificationPreferencesTests: XCTestCase {
    /// Test that enableForSharedCareeIfNeeded auto-enables notifications for new shared carees
    func testEnableForSharedCareeIfNeededEnablesNewCarees() {
        let prefs = UserNotificationPreferences.shared
        let careeID = UUID()

        // Verify initial state is disabled (no preference set)
        XCTAssertFalse(prefs.isEnabled(for: careeID))

        // Enable global notifications
        prefs.notificationsEnabled = true

        // Enable for shared caree
        prefs.enableForSharedCareeIfNeeded(careeID)

        // Should now be enabled
        XCTAssertTrue(prefs.isEnabled(for: careeID))

        // Clean up
        prefs.removePreferences(for: careeID)
    }

    /// Test that enableForSharedCareeIfNeeded doesn't override explicit user preferences
    func testEnableForSharedCareeIfNeededPreservesExplicitPreferences() {
        let prefs = UserNotificationPreferences.shared
        let careeID = UUID()

        // Enable global notifications
        prefs.notificationsEnabled = true

        // User explicitly disables notifications for this caree
        prefs.setEnabled(false, for: careeID)

        // Try to auto-enable
        prefs.enableForSharedCareeIfNeeded(careeID)

        // Should still be disabled because user explicitly set it
        XCTAssertFalse(prefs.isEnabled(for: careeID))

        // Clean up
        prefs.removePreferences(for: careeID)
    }

    /// Test that enableForSharedCareeIfNeeded enables global toggle if needed
    func testEnableForSharedCareeIfNeededEnablesGlobalToggle() {
        let prefs = UserNotificationPreferences.shared
        let careeID = UUID()

        // Start with global notifications disabled
        prefs.notificationsEnabled = false

        // Enable for shared caree
        prefs.enableForSharedCareeIfNeeded(careeID)

        // Global toggle should now be enabled
        XCTAssertTrue(prefs.notificationsEnabled)

        // And caree should be enabled
        XCTAssertTrue(prefs.isEnabled(for: careeID))

        // Clean up
        prefs.removePreferences(for: careeID)
        prefs.notificationsEnabled = false
    }

    /// Test that isEnabled returns false when global toggle is off
    func testIsEnabledReturnsFalseWhenGlobalDisabled() {
        let prefs = UserNotificationPreferences.shared
        let careeID = UUID()

        // Enable for this caree
        prefs.notificationsEnabled = true
        prefs.setEnabled(true, for: careeID)

        // Verify enabled
        XCTAssertTrue(prefs.isEnabled(for: careeID))

        // Disable global toggle
        prefs.notificationsEnabled = false

        // Should now return false despite per-caree being enabled
        XCTAssertFalse(prefs.isEnabled(for: careeID))

        // Clean up
        prefs.removePreferences(for: careeID)
    }

    /// Test removePreferences clears the preference
    func testRemovePreferencesClears() {
        let prefs = UserNotificationPreferences.shared
        let careeID = UUID()

        prefs.notificationsEnabled = true
        prefs.setEnabled(true, for: careeID)
        XCTAssertTrue(prefs.isEnabled(for: careeID))

        prefs.removePreferences(for: careeID)

        // After removal, should return default (false)
        XCTAssertFalse(prefs.isEnabled(for: careeID))

        // Clean up
        prefs.notificationsEnabled = false
    }
}
