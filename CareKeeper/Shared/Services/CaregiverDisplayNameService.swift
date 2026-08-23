import CloudKit
import Foundation

/// Service for managing the caregiver's display name shown in push notifications
/// Stores the name locally in app group UserDefaults and syncs to CloudKit
/// for cross-device availability (iOS → watchOS).
@MainActor
class CaregiverDisplayNameService: ObservableObject {
    // MARK: - Shared Instance

    static let shared = CaregiverDisplayNameService()

    // MARK: - Constants

    static let recordType = "CD_UserSettings"
    static let recordName = "CD_UserSettings/displayName"
    static let valueField = "CD_value"

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
            if !isSuppressingSync {
                syncToCloudKit()
            }
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

    // MARK: - CloudKit Sync

    /// Whether this instance may write display name changes to CloudKit.
    private let isCloudKitSyncEnabled: Bool
    /// When true, suppresses `didSet` sync-back to CloudKit (used during fetchFromCloudKit)
    private var isSuppressingSync = false
    private var syncTask: Task<Void, Never>?

    /// Debounced sync — called from `didSet` on `displayName`.
    /// Coalesces rapid keystrokes (e.g. SharingView TextField) into a single CloudKit write.
    private func syncToCloudKit() {
        guard isCloudKitSyncEnabled else { return }
        syncTask?.cancel()
        let value = displayName
        syncTask = Task { @MainActor [value] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            performCloudKitSync(value: value)
        }
    }

    /// Immediate sync — call from explicit Save actions (e.g. DisplayNamePromptModifier).
    /// Cancels any pending debounced sync and writes immediately.
    func syncToCloudKitImmediately() {
        guard isCloudKitSyncEnabled else { return }
        syncTask?.cancel()
        let value = displayName
        performCloudKitSync(value: value)
    }

    /// Fetch display name from CloudKit private zone and update local cache if different.
    /// Call on launch when no local cache exists (e.g. fresh install or reinstall).
    /// Suppresses sync-back to CloudKit since we just read from there.
    /// Returns the fetched name, or nil if not found.
    @discardableResult
    func fetchFromCloudKit() async -> String? {
        do {
            let container = CKContainer(identifier: CloudKitConfig.containerID)
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
            let recordID = CKRecord.ID(
                recordName: CaregiverDisplayNameService.recordName,
                zoneID: zoneID
            )
            let record = try await database.record(for: recordID)
            let value = record[CaregiverDisplayNameService.valueField] as? String
            if value != displayName {
                isSuppressingSync = true
                displayName = value
                isSuppressingSync = false
            }
            return value
        } catch {
            return nil
        }
    }

    /// Fire-and-forget write of display name to CloudKit private zone.
    /// Makes the name available cross-device via fetchFromCloudKit().
    private func performCloudKitSync(value: String?) {
        Task.detached { [value] in
            do {
                let container = CKContainer(identifier: CloudKitConfig.containerID)
                let database = container.privateCloudDatabase
                let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
                let recordID = CKRecord.ID(
                    recordName: CaregiverDisplayNameService.recordName,
                    zoneID: zoneID
                )

                // Try to fetch existing record to update, or create new
                let record: CKRecord
                do {
                    record = try await database.record(for: recordID)
                } catch {
                    record = CKRecord(
                        recordType: CaregiverDisplayNameService.recordType,
                        recordID: recordID
                    )
                }

                record[CaregiverDisplayNameService.valueField] = value as CKRecordValue?
                try await database.save(record)
            } catch {
                // Fire-and-forget: log but don't propagate
                AppLogger.cloudkit.warning("Failed to sync display name to CloudKit: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Initialization

    private init() {
        if let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID) {
            self.appGroupDefaults = defaults
        } else {
            self.appGroupDefaults = .standard
        }
        self.isCloudKitSyncEnabled = true
        // Suppress sync: @Published didSet fires during init (unlike regular stored properties).
        // Without this, the stale local cache would overwrite the CloudKit value on every launch.
        self.isSuppressingSync = true
        self.displayName = self.appGroupDefaults.string(forKey: Keys.displayName)
        self.isSuppressingSync = false
    }

    /// Testable initializer that uses the provided UserDefaults instead of app group
    init(testing defaults: UserDefaults) {
        self.appGroupDefaults = defaults
        self.isCloudKitSyncEnabled = false
        self.isSuppressingSync = true
        self.displayName = defaults.string(forKey: Keys.displayName)
        self.isSuppressingSync = false
    }
}
