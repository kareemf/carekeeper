import SwiftUI
import SwiftData

@main
struct CareKeeperWatchApp: App {
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var sharedDataService = CloudKitSharedDataService()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    @StateObject private var notificationService = CloudKitNotificationService()
    @State private var cacheService: LocalCacheService?
    
    private let logger = AppLogger.cloudkit

    let sharedModelContainer: ModelContainer

    init() {
        let logger = AppLogger.cloudkit

        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self
        ])

        // Configure CloudKit sync with private database
        // Use app group for shared data with iOS app
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(CloudKitConfig.appGroupID),
            cloudKitDatabase: .private(CloudKitConfig.containerID)
        )

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error and fall back to in-memory storage
            logger.info("⚠️ Failed to create CloudKit-enabled ModelContainer: \(error.localizedDescription)")
            logger.info("   Falling back to in-memory storage (data will not persist)")

            // Fallback to in-memory store for development
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            CareeListView()
                .environmentObject(cloudKitService)
                .environmentObject(sharedDataService)
                .environmentObject(sharedRecordsService)
                .task {
                    // Initialize cache service with modelContainer's mainContext
                    if cacheService == nil {
                        let cache = LocalCacheService(modelContext: sharedModelContainer.mainContext)
                        cacheService = cache

                        // Wire services to the cache
                        cloudKitService.setCacheService(cache)
                        sharedRecordsService.setCacheService(cache)
                        sharedDataService.setCacheService(cache)
                        
                        AppLogger.app.info("✅ Shared CloudKitDataService and LocalCacheService initialized (watchOS)")

                        // Seed cache with owned records once (avoid redundant invalidateAndRefresh)
                        do {
                            try await cloudKitService.refreshOwnedCareesFromCloudKit()
                            AppLogger.app.info("✅ Initial owned records loaded into cache (watchOS)")
                        } catch {
                            AppLogger.app.warning("⚠️ Initial owned refresh failed (watchOS): \(error.localizedDescription)")
                        }
                    }
                }
                .task {
                    // Set up CloudKit database subscriptions and shared-records refresh on watchOS
                    await notificationService.setupNotifications(sharedRecordsService: sharedRecordsService)
                    AppLogger.cloudkit.info("✅ CloudKit notification service setup complete (watchOS)")
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
