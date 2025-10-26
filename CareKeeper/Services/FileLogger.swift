import Foundation
import os.log

/// Real-time file-based logger for immediate crash/error debugging
/// Unlike MetricKit (which takes 24-48h), this writes logs instantly to app group
/// Accessible from iPhone via WatchDiagnosticsView
@MainActor
class FileLogger {

    static let shared = FileLogger()

    private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "file-logger")
    private let maxLogFiles = 20
    private let maxLogSizeBytes = 1024 * 1024 // 1MB per log file

    private var currentLogFile: URL?
    private var currentLogHandle: FileHandle?

    private init() {
        setupLogFile()
    }

    deinit {
        try? currentLogHandle?.close()
    }

    // MARK: - Setup

    private func setupLogFile() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
        ) else {
            logger.error("❌ Failed to access app group container for logging")
            return
        }

        let logsURL = containerURL
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        // Create logs directory
        try? FileManager.default.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create new log file with timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        #if os(watchOS)
        let platform = "watch"
        #else
        let platform = "ios"
        #endif

        let filename = "log-\(platform)-\(timestamp).txt"
        currentLogFile = logsURL.appendingPathComponent(filename)

        // Create file and get handle
        if let logFile = currentLogFile {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            currentLogHandle = try? FileHandle(forWritingTo: logFile)

            // Write header
            let header = """
            ===========================================
            CareKeeper Log - \(platform.uppercased())
            Started: \(Date())
            Platform: \(platform)
            OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
            ===========================================

            """
            writeToFile(header)
            logger.info("📝 Log file created: \(filename)")
        }

        // Cleanup old logs
        cleanupOldLogs(in: logsURL)
    }

    // MARK: - Public Logging Methods

    /// Log informational message
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "INFO", message: message, file: file, function: function, line: line)
    }

    /// Log warning message
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "WARN", message: message, file: file, function: function, line: line)
    }

    /// Log error message
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "ERROR", message: message, file: file, function: function, line: line)
    }

    /// Log critical/fatal message
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "CRITICAL", message: message, file: file, function: function, line: line)
    }

    /// Log exception/crash
    func exception(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let message = """

        ========== EXCEPTION ==========
        Context: \(context)
        Error: \(error.localizedDescription)
        Details: \(String(describing: error))
        ===============================
        """
        log(level: "EXCEPTION", message: message, file: file, function: function, line: line)
    }

    // MARK: - Private Methods

    private func log(level: String, message: String, file: String, function: String, line: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = (file as NSString).lastPathComponent

        let logLine = "[\(timestamp)] [\(level)] [\(filename):\(line)] \(function)\n\(message)\n\n"

        writeToFile(logLine)

        // Also log to OSLog for Console.app
        logger.info("\(logLine)")

        // Check if we need to rotate log file
        checkLogRotation()
    }

    private func writeToFile(_ content: String) {
        guard let data = content.data(using: .utf8),
              let handle = currentLogHandle else {
            return
        }

        do {
            try handle.write(contentsOf: data)
            try handle.synchronize() // Force write to disk immediately
        } catch {
            logger.error("❌ Failed to write to log file: \(error.localizedDescription)")
        }
    }

    private func checkLogRotation() {
        guard let logFile = currentLogFile,
              let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let fileSize = attributes[.size] as? Int else {
            return
        }

        // Rotate if file exceeds max size
        if fileSize > maxLogSizeBytes {
            try? currentLogHandle?.close()
            setupLogFile()
        }
    }

    private func cleanupOldLogs(in directory: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            // Sort by creation date (newest first)
            let sortedFiles = files.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }

            // Delete files beyond the keep limit
            for file in sortedFiles.dropFirst(maxLogFiles) {
                try FileManager.default.removeItem(at: file)
                logger.info("🧹 Deleted old log: \(file.lastPathComponent)")
            }

        } catch {
            logger.error("❌ Failed to cleanup logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Log Retrieval

    /// Get all log files for sharing/viewing
    func getAllLogFiles() -> [URL] {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
        ) else {
            return []
        }

        let logsURL = containerURL
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        // Sort by creation date (newest first)
        return files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }
}
