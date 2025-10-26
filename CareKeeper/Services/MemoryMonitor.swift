import Foundation
import os.log

/// Monitors and logs memory usage at critical checkpoints
/// Helps identify memory pressure issues on watchOS
struct MemoryMonitor {

    private static let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "memory")

    /// Log current memory usage with context
    /// - Parameter context: Description of when this measurement was taken
    static func logMemoryUsage(context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard kerr == KERN_SUCCESS else {
            logger.error("❌ Failed to get task info")
            return
        }

        let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
        logger.info("💾 Memory [\(context)]: \(String(format: "%.1f", usedMB)) MB")

        // Warn if memory usage is high (>25MB on watch is concerning)
        #if os(watchOS)
        if usedMB > 25.0 {
            logger.warning("⚠️ High memory usage on watchOS: \(String(format: "%.1f", usedMB)) MB")
        }
        #endif
    }

    /// Log memory usage with additional object count information
    /// - Parameters:
    ///   - context: Description of when this measurement was taken
    ///   - objectCount: Number of objects loaded (e.g., carees, activities)
    ///   - objectType: Type of objects (e.g., "carees", "activities")
    static func logMemoryUsage(context: String, objectCount: Int, objectType: String) {
        logMemoryUsage(context: "\(context) - \(objectCount) \(objectType)")
    }

    /// Get current memory usage in megabytes
    /// - Returns: Memory usage in MB, or nil if measurement failed
    static func currentMemoryUsageMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard kerr == KERN_SUCCESS else {
            return nil
        }

        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    /// Check if memory usage is approaching limits
    /// - Returns: true if memory pressure is detected
    static func isMemoryPressureHigh() -> Bool {
        guard let usedMB = currentMemoryUsageMB() else {
            return false
        }

        #if os(watchOS)
        // watchOS has stricter limits
        return usedMB > 25.0
        #else
        // iOS can handle more
        return usedMB > 100.0
        #endif
    }

    /// Log a memory warning event
    static func logMemoryWarning() {
        logger.warning("⚠️ Memory warning received!")
        logMemoryUsage(context: "Memory Warning")
    }
}
