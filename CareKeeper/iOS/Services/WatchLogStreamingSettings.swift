import Foundation

@MainActor
final class WatchLogStreamingSettings: ObservableObject {

    @Published var level: WatchLogStreamingLevel {
        didSet {
            guard level != oldValue else { return }
            persist(level)
            WatchLogStreamController.shared.sendLevelUpdate(level)
        }
    }

    private let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID)

    init() {
        if let raw = defaults?.string(forKey: SharedDefaultsKeys.watchLogStreamingLevel),
           let stored = WatchLogStreamingLevel(rawValue: raw) {
            level = stored
        } else {
            level = .off
        }

        WatchLogStreamController.shared.enqueueFromDefaults()
    }

    private func persist(_ level: WatchLogStreamingLevel) {
        defaults?.set(level.rawValue, forKey: SharedDefaultsKeys.watchLogStreamingLevel)
    }
}
