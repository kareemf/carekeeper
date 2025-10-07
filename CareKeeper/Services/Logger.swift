import os

struct Logger {
    static func logError(_ message: String, error: Error) {
        os_log("❌ %{public}@ - Error: %{public}@", log: OSLog.default, type: .error, message, error.localizedDescription)
        print("❌ \(message): \(error.localizedDescription)")
    }
    
    static func log(_ message: String) {
        os_log("ℹ️ %{public}@ - Info", log: OSLog.default, type: .info, message)
        print("ℹ️ \(message)")
    }
}
