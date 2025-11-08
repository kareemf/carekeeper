import Foundation
import os.log

/// Minimal logger placeholder while file logging is disabled.
@MainActor
final class FileLogger {
    static let shared = FileLogger()

    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "file-logger")

    /// File logging is disabled, so no log files are produced.
    var isLoggingAvailable: Bool { false }

    private init() {}

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .default, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .fault, file: file, function: function, line: line)
    }

    func exception(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let description = """
        Exception: \(context)
        Error: \(error.localizedDescription)
        Details: \(String(describing: error))
        """
        log(description, level: .error, file: file, function: function, line: line)
    }

    func getAllLogFiles() -> [URL] { [] }

    private func log(_ message: String, level: OSLogType, file: String, function: String, line: Int) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.log(
            level: level,
            "\(filename, privacy: .public):\(line) \(function, privacy: .public) — \(message, privacy: .public)"
        )
    }
}
