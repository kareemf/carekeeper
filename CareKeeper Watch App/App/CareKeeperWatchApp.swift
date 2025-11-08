import SwiftUI

/// CareKeeperWatchApp rebuilt with WatchDataProvider
/// Simplified initialization - no SwiftData container, no multiple services
/// All data comes from WatchDataProvider using selective CloudKit queries
@main
struct CareKeeperWatchApp: App {
    // Initialize diagnostics
    private let metricsManager = MetricsManager.shared
    private let fileLogger = FileLogger.shared

    init() {
        // Log initial memory state
        MemoryMonitor.logMemoryUsage(context: "App Init Start (watchOS)")

        // Log app startup
        fileLogger.info("🚀 watchOS app launched")
        fileLogger.info("   OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    var body: some Scene {
        WindowGroup {
            CareeListView()
                .onAppear {
                    MemoryMonitor.logMemoryUsage(context: "CareeListView Appeared")
                }
        }
    }
}
