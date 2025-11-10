import Foundation

/// CloudKit configuration constants with environment/plist fallbacks.
enum CloudKitConfig {
    private struct Values {
        let zoneName: String
        let containerID: String
        let appGroupID: String
        let configurationError: AppError?
    }

    private static func loadPlist(named name: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    private static let placeholders = (
        zone: "com.example.carekeeper.zone",
        container: "iCloud.com.example.CareKeeper",
        appGroup: "group.com.example.CareKeeper"
    )

    private static let resolved: Values = {
        let environment = ProcessInfo.processInfo.environment
        let userConfig = loadPlist(named: "Config") ?? [:]
        let defaultConfig = loadPlist(named: "Config.default") ?? [:]

        func value(for key: String) -> String? {
            let envKey = key.uppercased()
            if let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
            if let raw = userConfig[key] as? String, !raw.isEmpty {
                return raw
            }
            if let raw = defaultConfig[key] as? String, !raw.isEmpty {
                return raw
            }
            return nil
        }

        var missing: [String] = []
        let zone = value(for: "ZONE_NAME") ?? placeholders.zone
        if zone == placeholders.zone { missing.append("ZONE_NAME") }

        let container = value(for: "CLOUDKIT_CONTAINER_ID") ?? placeholders.container
        if container == placeholders.container { missing.append("CLOUDKIT_CONTAINER_ID") }

        let appGroup = value(for: "APP_GROUP_IDENTIFIER") ?? placeholders.appGroup
        if appGroup == placeholders.appGroup { missing.append("APP_GROUP_IDENTIFIER") }

        let error: AppError? = missing.isEmpty
            ? nil
            : .missingConfiguration(
                "Missing configuration for: \(missing.joined(separator: ", ")). Provide values via Config.plist or environment variables."
            )

        return Values(
            zoneName: zone,
            containerID: container,
            appGroupID: appGroup,
            configurationError: error
        )
    }()

    static let zoneName = resolved.zoneName
    static let containerID = resolved.containerID
    static let appGroupID = resolved.appGroupID
    static var configurationError: AppError? { resolved.configurationError }
}
