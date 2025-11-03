#if os(watchOS)
import Foundation
import WatchConnectivity
import os.log

@MainActor
final class WatchLogStreamService: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchLogStreamService()

    @Published private(set) var streamingLevel: WatchLogStreamingLevel = .off

    private var session: WCSession?
    private var queue: [WatchLogEntry] = []
    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "watch-log-stream")
    private var defaults: UserDefaults?

    private override init() {
        super.init()

        defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID)
        streamingLevel = currentLevelFromDefaults()

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
        } else {
            logger.warning("⚠️ WCSession not supported on this device.")
        }
    }

    func processLog(severity: LogSeverity, message: String, file: String, function: String, line: Int) {
        guard streamingLevel != .off else { return }
        guard streamingLevel.allows(severity) else { return }

        let entry = WatchLogEntry(
            timestamp: Date(),
            severity: severity,
            message: message,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line
        )

        queue.append(entry)
        trimQueue()
        flushQueue()
    }

    // MARK: - Helpers

    private func trimQueue() {
        let limit = streamingLevel.queueLimit
        guard limit > 0, queue.count > limit else { return }
        queue.removeFirst(queue.count - limit)
    }

    private func flushQueue() {
        guard !queue.isEmpty else { return }
        guard let session = session else { return }

        switch session.activationState {
        case .activated:
            if session.isReachable {
                sendEntriesViaMessage(queue)
                queue.removeAll()
            } else {
                let payload = queue.map { $0.dictionaryRepresentation }
                session.transferUserInfo(["logEntries": payload])
                queue.removeAll()
            }
        case .inactive, .notActivated:
            // Wait for activation callbacks
            break
        @unknown default:
            break
        }
    }

    private func sendEntriesViaMessage(_ entries: [WatchLogEntry]) {
        guard let session = session else { return }

        for entry in entries {
            session.sendMessage(entry.dictionaryRepresentation, replyHandler: nil) { [weak self] error in
                guard let self else { return }
                self.logger.error("❌ Failed to stream log entry: \(error.localizedDescription, privacy: .public)")
                // Requeue on failure (respecting limit)
                self.queue.append(entry)
                self.trimQueue()
            }
        }
    }

    private func updateLevel(_ level: WatchLogStreamingLevel) {
        guard level != streamingLevel else { return }
        streamingLevel = level
        defaults?.set(level.rawValue, forKey: SharedDefaultsKeys.watchLogStreamingLevel)
        if level == .off {
            queue.removeAll()
        }
        logger.info("ℹ️ Updated log streaming level: \(level.rawValue, privacy: .public)")
        trimQueue()
        flushQueue()
    }

    private func currentLevelFromDefaults() -> WatchLogStreamingLevel {
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: SharedDefaultsKeys.watchLogStreamingLevel),
              let level = WatchLogStreamingLevel(rawValue: rawValue) else {
            return .off
        }
        return level
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("✅ WCSession activated with state \(activationState.rawValue)")
        }
        flushQueue()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        flushQueue()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let rawValue = message["logStreamingLevel"] as? String,
           let level = WatchLogStreamingLevel(rawValue: rawValue) {
            updateLevel(level)
        }
        if let enabled = message["fileLoggingEnabled"] as? Bool {
            FileLogger.shared.setLoggingEnabled(enabled)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let rawValue = userInfo["logStreamingLevel"] as? String,
           let level = WatchLogStreamingLevel(rawValue: rawValue) {
            updateLevel(level)
        }
        if let enabled = userInfo["fileLoggingEnabled"] as? Bool {
            FileLogger.shared.setLoggingEnabled(enabled)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let rawValue = applicationContext["logStreamingLevel"] as? String,
           let level = WatchLogStreamingLevel(rawValue: rawValue) {
            updateLevel(level)
        }
        if let enabled = applicationContext["fileLoggingEnabled"] as? Bool {
            FileLogger.shared.setLoggingEnabled(enabled)
        }
    }
}
#endif
