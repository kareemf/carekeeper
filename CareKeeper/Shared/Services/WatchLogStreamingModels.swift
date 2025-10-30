import Foundation

enum SharedDefaultsKeys {
    static let watchLogStreamingLevel = "watchLogStreamingLevel"
}

enum LogSeverity: Int, Comparable, Codable {
    case info = 0
    case warning = 1
    case error = 2
    case critical = 3

    init(loggerLevel: String) {
        switch loggerLevel.uppercased() {
        case "WARN", "WARNING":
            self = .warning
        case "ERROR", "EXCEPTION":
            self = .error
        case "CRITICAL":
            self = .critical
        default:
            self = .info
        }
    }

    var label: String {
        switch self {
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }

    static func < (lhs: LogSeverity, rhs: LogSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum WatchLogStreamingLevel: String, CaseIterable, Identifiable, Codable {
    case off
    case warnError
    case info

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .warnError: return "Warn+"
        case .info: return "Info"
        }
    }

    var queueLimit: Int {
        switch self {
        case .off: return 0
        case .warnError: return 200
        case .info: return 50
        }
    }

    func allows(_ severity: LogSeverity) -> Bool {
        switch self {
        case .off:
            return false
        case .warnError:
            return severity >= .warning
        case .info:
            return true
        }
    }
}

struct WatchLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let severity: LogSeverity
    let message: String
    let file: String
    let function: String
    let line: Int

    init(id: UUID = UUID(), timestamp: Date, severity: LogSeverity, message: String, file: String, function: String, line: Int) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }

    init?(dictionary: [String: Any]) {
        guard
            let timestampString = dictionary["timestamp"] as? String,
            let levelString = dictionary["level"] as? String,
            let message = dictionary["message"] as? String,
            let file = dictionary["file"] as? String,
            let function = dictionary["function"] as? String,
            let line = dictionary["line"] as? Int,
            let timestamp = ISO8601DateFormatter().date(from: timestampString)
        else {
            return nil
        }

        self.id = UUID()
        self.timestamp = timestamp
        self.severity = LogSeverity(loggerLevel: levelString)
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }

    var dictionaryRepresentation: [String: Any] {
        [
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "level": severity.label,
            "message": message,
            "file": file,
            "function": function,
            "line": line
        ]
    }

    var formattedSummary: String {
        let formattedDate = ISO8601DateFormatter().string(from: timestamp)
        return "[\(formattedDate)] [\(severity.label)] \(message) (\(file):\(line))"
    }
}
