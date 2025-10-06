import os

struct Logger {
    static func logError(_ message: String, error: Error) {
        os_log("❌ %{public}@ - Error: %{public}@", log: OSLog.default, type: .error, message, error.localizedDescription)
    }
}
