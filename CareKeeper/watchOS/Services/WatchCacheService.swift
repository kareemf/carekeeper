import Foundation

/// Persists watch snapshots to the shared app-group so data survives relaunches.
@MainActor
final class WatchCacheService {

    // MARK: - Nested Types

    private enum Keys {
        static let carees = "watch_carees"
        static let activityTypesPrefix = "watch_activityTypes_"
        static let recentActivitiesPrefix = "watch_recentActivities_"
    }

    // MARK: - Properties

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = AppLogger.app
    private let isUsingFallbackDefaults: Bool
    private var hasLoggedFallbackWarning = false
    private let containerURL: URL?
    private let cacheDirectory: URL?

    // MARK: - Init

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: CloudKitConfig.appGroupID)) {
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID)
        cacheDirectory = containerURL?.appendingPathComponent("watch-cache", isDirectory: true)

        var fallbackReason: String?

        if let providedDefaults = userDefaults, containerURL != nil {
            defaults = providedDefaults
            isUsingFallbackDefaults = false
        } else {
            defaults = .standard
            isUsingFallbackDefaults = true
            fallbackReason = containerURL == nil ? "App group container unavailable" : "UserDefaults(suiteName:) returned nil"
        }

        if let cacheDirectory {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("❌ WatchCacheService failed to create cache directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if isUsingFallbackDefaults {
            logFallbackWarning(reason: fallbackReason ?? "Unknown reason")
        }
    }

    // MARK: - Public API

    var isAppGroupAvailable: Bool { containerURL != nil }

    func loadCarees() -> [CareeSnapshot] {
        guard checkAvailability(for: "carees") else { return [] }
        return decode([CareeSnapshot].self, forKey: Keys.carees)
    }

    func saveCarees(_ carees: [CareeSnapshot]) {
        guard checkAvailability(for: "carees") else { return }
        encode(carees, forKey: Keys.carees)
    }

    func loadActivityTypes(for careeID: UUID) -> [ActivityTypeSnapshot] {
        guard checkAvailability(for: "activityTypes_\(careeID.uuidString)") else { return [] }
        return decode([ActivityTypeSnapshot].self, forKey: activityTypesKey(for: careeID))
    }

    func saveActivityTypes(_ activityTypes: [ActivityTypeSnapshot], for careeID: UUID) {
        guard checkAvailability(for: "activityTypes_\(careeID.uuidString)") else { return }
        encode(activityTypes, forKey: activityTypesKey(for: careeID))
    }

    func loadRecentActivities(for careeID: UUID) -> [ActivitySnapshot] {
        guard checkAvailability(for: "recentActivities_\(careeID.uuidString)") else { return [] }
        return decode([ActivitySnapshot].self, forKey: recentActivitiesKey(for: careeID))
    }

    func saveRecentActivities(_ activities: [ActivitySnapshot], for careeID: UUID) {
        guard checkAvailability(for: "recentActivities_\(careeID.uuidString)") else { return }
        encode(activities, forKey: recentActivitiesKey(for: careeID))
    }

    #if DEBUG
    func clearAll() {
        if let cacheDirectory {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for url in fileURLs {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                logger.error("❌ WatchCacheService failed to clear cache directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif

    // MARK: - Helpers

    private func activityTypesKey(for careeID: UUID) -> String {
        Keys.activityTypesPrefix + careeID.uuidString
    }

    private func recentActivitiesKey(for careeID: UUID) -> String {
        Keys.recentActivitiesPrefix + careeID.uuidString
    }

    private func encode<T>(_ value: T, forKey key: String) where T: Encodable {
        do {
            let data = try encoder.encode(value)
            guard let fileURL = cacheURL(for: key) else {
                logFallbackWarning(reason: "Missing cache URL for key \(key)")
                return
            }

            try data.write(to: fileURL, options: .atomic)
            defaults.removeObject(forKey: key) // Clean up any legacy cache entries that might remain
        } catch {
            logger.error("❌ Failed to encode cache for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func decode<T>(_ type: T.Type, forKey key: String) -> T where T: Decodable, T: ExpressibleByArrayLiteral {
        guard let fileURL = cacheURL(for: key) else {
            logFallbackWarning(reason: "Missing cache URL for key \(key)")
            return []
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("❌ Failed to decode cache file for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }

    private func cacheURL(for key: String) -> URL? {
        guard let cacheDirectory else { return nil }
        return cacheDirectory.appendingPathComponent("\(key).json")
    }
}

private extension WatchCacheService {
    func checkAvailability(for key: String) -> Bool {
        guard isAppGroupAvailable else {
            logFallbackWarning(reason: "Attempted cache access for \(key)")
            return false
        }
        return true
    }

    func logFallbackWarning(reason: String) {
        guard !hasLoggedFallbackWarning else { return }
        hasLoggedFallbackWarning = true
        logger.warning("⚠️ WatchCacheService using fallback defaults. Context: \(reason)")
        logger.warning("   Ensure app group \(CloudKitConfig.appGroupID, privacy: .public) is enabled for watch targets.")
    }
}
