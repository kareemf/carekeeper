import Foundation
import Combine

@MainActor
final class WatchLogStreamingSettings: ObservableObject {

    @Published var level: WatchLogStreamingLevel {
        didSet {
            guard level != oldValue else { return }
            persist(level)
            WatchLogStreamController.shared.sendLevelUpdate(level)
        }
    }
    @Published var isFileLoggerEnabled: Bool {
        didSet {
            guard isFileLoggerEnabled != oldValue else { return }
            guard !isUpdatingFromController else { return }
            persistFileLogger(isFileLoggerEnabled)
            WatchLogStreamController.shared.sendFileLoggingEnabled(isFileLoggerEnabled)
        }
    }

    private let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID)
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromController = false

    init() {
        if let raw = defaults?.string(forKey: SharedDefaultsKeys.watchLogStreamingLevel),
           let stored = WatchLogStreamingLevel(rawValue: raw) {
            level = stored
        } else {
            level = .off
        }

        isFileLoggerEnabled = defaults?.bool(forKey: SharedDefaultsKeys.watchFileLoggingEnabled) ?? false

        WatchLogStreamController.shared.$fileLoggingEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                guard self.isFileLoggerEnabled != enabled else { return }
                self.isUpdatingFromController = true
                self.isFileLoggerEnabled = enabled
                self.isUpdatingFromController = false
            }
            .store(in: &cancellables)

        WatchLogStreamController.shared.enqueueFromDefaults()
    }

    private func persist(_ level: WatchLogStreamingLevel) {
        defaults?.set(level.rawValue, forKey: SharedDefaultsKeys.watchLogStreamingLevel)
    }

    private func persistFileLogger(_ enabled: Bool) {
        defaults?.set(enabled, forKey: SharedDefaultsKeys.watchFileLoggingEnabled)
    }
}
