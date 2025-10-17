import SwiftUI
import SwiftData
import WidgetKit

@main
struct CareKeeperWatchApp: App {
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var sharedDataService = CloudKitSharedDataService()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    @StateObject private var notificationService = CloudKitNotificationService()
    @State private var cacheService: LocalCacheService?

    private let logger = AppLogger.cloudkit

    // Local-only cache container (no CloudKit mirroring)
    // Data comes from pure CloudKit services, SwiftData is only for local caching
    let cacheModelContainer: ModelContainer

    init() {
        let logger = AppLogger.cloudkit

        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self
        ])

        // Local-only cache container - no CloudKit sync
        // This matches iOS behavior where cache is separate from CloudKit operations
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(CloudKitConfig.appGroupID)
            // Intentionally omit cloudKitDatabase to keep this store local-only
        )

        do {
            cacheModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.info("🧠 Initialized local-only cache ModelContainer (watchOS)")
        } catch {
            // Log the error and fall back to in-memory storage
            logger.info("⚠️ Failed to create cache ModelContainer: \(error.localizedDescription)")
            logger.info("   Falling back to in-memory storage (data will not persist)")

            // Fallback to in-memory store for development
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            do {
                cacheModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            CareeListView()
                .environment(CloudKitSyncMonitor.shared)
                .environmentObject(cloudKitService)
                .environmentObject(sharedDataService)
                .environmentObject(sharedRecordsService)
                .task {
                    // Initialize cache service with cacheModelContainer's mainContext
                    if cacheService == nil {
                        let cache = LocalCacheService(modelContext: cacheModelContainer.mainContext)
                        cacheService = cache

                        // Wire services to the cache
                        cloudKitService.setCacheService(cache)
                        sharedRecordsService.setCacheService(cache)
                        sharedDataService.setCacheService(cache)

                        // Wire sharedDataService to cloudKitService for unified API
                        cloudKitService.setSharedDataService(sharedDataService)

                        // Wire services to CloudKitSyncMonitor for status tracking
                        CloudKitSyncMonitor.shared.configureServices(
                            cloudKitService: cloudKitService,
                            sharedRecordsService: sharedRecordsService,
                            cacheService: cache
                        )

                        AppLogger.app.info("✅ Shared CloudKitDataService and LocalCacheService initialized (watchOS)")

                        // Seed cache with owned records once (avoid redundant invalidateAndRefresh)
                        do {
                            try await cloudKitService.refreshOwnedCareesFromCloudKit()
                            AppLogger.app.info("✅ Initial owned records loaded into cache (watchOS)")

                            // Reload widget timelines after loading initial data
                            WidgetCenter.shared.reloadAllTimelines()
                        } catch {
                            AppLogger.app.warning("⚠️ Initial owned refresh failed (watchOS): \(error.localizedDescription)")
                        }
                    }
                }
                .task {
                    // Set up CloudKit database subscriptions and shared-records refresh on watchOS
                    await notificationService.setupNotifications(sharedRecordsService: sharedRecordsService)
                    AppLogger.cloudkit.info("✅ CloudKit notification service setup complete (watchOS)")

                    // Also reload widget after shared records are fetched
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
