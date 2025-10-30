import Foundation
import WatchConnectivity
import os.log

@MainActor
final class WatchLogStreamController: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchLogStreamController()

    @Published private(set) var entries: [WatchLogEntry] = []
    @Published private(set) var lastReceived: Date?

    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "watch-log-stream-controller")
    private var session: WCSession?
    private lazy var fileURL: URL? = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID) else {
            logger.error("❌ Unable to resolve app group container for log stream store.")
            return nil
        }

        let logsURL = containerURL
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        } catch {
            logger.error("❌ Failed to create stream log directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return logsURL.appendingPathComponent("log-stream.txt")
    }()
    private let ioQueue = DispatchQueue(label: "com.kareemf.CareKeeper.watchLogStreamIO")
    private let maxEntries = 200

    private override init() {
        super.init()

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
        } else {
            logger.warning("⚠️ WCSession not supported on this device.")
        }

        enqueueFromDefaults()
    }

    // MARK: - Public API

    func sendLevelUpdate(_ level: WatchLogStreamingLevel) {
        guard let session = session, session.activationState == .activated else { return }

        let payload = ["logStreamingLevel": level.rawValue]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("❌ Failed to send streaming level: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                try session.updateApplicationContext(payload)
            } catch {
                logger.error("❌ Failed to update application context: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func enqueueFromDefaults() {
        guard let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID),
              let raw = defaults.string(forKey: SharedDefaultsKeys.watchLogStreamingLevel),
              let level = WatchLogStreamingLevel(rawValue: raw) else {
            sendLevelUpdate(.off)
            return
        }
        sendLevelUpdate(level)
    }

    // MARK: - WCSessionDelegate

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation error: \(error.localizedDescription, privacy: .public)")
        }
        enqueueFromDefaults()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let batch = userInfo["logEntries"] as? [[String: Any]] {
            for item in batch {
                appendEntry(from: item)
            }
        } else {
            handleMessage(userInfo)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleMessage(applicationContext)
    }

    // MARK: - Helpers

    private func handleMessage(_ payload: [String: Any]) {
        if let rawValue = payload["logStreamingLevel"] as? String,
           let level = WatchLogStreamingLevel(rawValue: rawValue) {
            // Persist incoming level so UI reflects watch-originated changes (if any)
            UserDefaults(suiteName: CloudKitConfig.appGroupID)?.set(level.rawValue, forKey: SharedDefaultsKeys.watchLogStreamingLevel)
        }

        if let entry = WatchLogEntry(dictionary: payload) {
            appendEntry(entry)
        }
    }

    private func appendEntry(from dictionary: [String: Any]) {
        guard let entry = WatchLogEntry(dictionary: dictionary) else { return }
        appendEntry(entry)
    }

    private func appendEntry(_ entry: WatchLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        lastReceived = Date()
        persist(entry: entry)
    }

    private func persist(entry: WatchLogEntry) {
        guard let fileURL else { return }
        let line = entry.formattedSummary + "\n"

        ioQueue.async {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    self.logger.error("❌ Failed to append stream log: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    try data.write(to: fileURL)
                } catch {
                    self.logger.error("❌ Failed to create stream log file: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
