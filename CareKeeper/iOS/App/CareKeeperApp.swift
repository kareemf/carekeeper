import CloudKit
import CoreData
import SwiftData
import SwiftUI

@main
struct CareKeeperApp: App {
    // @see https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app
    @UIApplicationDelegateAdaptor var appDelegate: AppDelegate

    @StateObject private var shareNotifier = ShareAcceptanceNotifier()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()
    @StateObject private var sharedDataService = CloudKitSharedDataService()
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var notificationService = CloudKitNotificationService()
    @StateObject private var pendingActivityBuffer = PendingActivityBuffer()
    @State private var cacheService: LocalCacheService?
    @State private var shareAcceptanceRefresher: ShareAcceptanceRefresher?
    @State private var startupError: Error?

    // Initialize diagnostics
    private let metricsManager = MetricsManager.shared

    init() {
        _startupError = State(initialValue: CloudKitConfig.configurationError)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self,
        ])

        // Check if running UI tests
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI-Testing")

        do {
            if isUITesting {
                // Use in-memory container for UI tests to ensure clean state
                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )

                return try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } else {
                // Configure for CloudKit sync with local storage
                AppLogger.app.info("🔧 Initializing ModelContainer with CloudKit sync")
                AppLogger.app.info("   Container: \(CloudKitConfig.containerID)")
                AppLogger.app.info("   App Group: \(CloudKitConfig.appGroupID)")

                // Configure for both local (iOS↔️watchOS) and cloud (iCloud) sync
                let modelConfiguration = if let groupContainer = Self.resolvedGroupContainer() {
                    ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        groupContainer: groupContainer,
                        cloudKitDatabase: .private(CloudKitConfig.containerID)
                    )
                } else {
                    ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        cloudKitDatabase: .private(CloudKitConfig.containerID)
                    )
                }

                let container = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )

                AppLogger.app.info("✅ ModelContainer created successfully")
                if let url = container.configurations.first?.url {
                    AppLogger.app.info("   📦 Container URL: \(url.path)")
                }

                // Monitor for sync errors
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("NSPersistentStoreRemoteChange"),
                    object: nil,
                    queue: nil
                ) { notification in
                    AppLogger.cloudkit.info("📡 Persistent store remote change notification: \(String(describing: notification))")
                }

                // Monitor for delete operations and CloudKit export
                NotificationCenter.default.addObserver(
                    forName: .NSManagedObjectContextDidSave,
                    object: nil,
                    queue: nil
                ) { notification in
                    if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
                        if !deleted.isEmpty {
                            AppLogger.cloudkit.info("⚠️ DELETE DETECTED: \(deleted.count) objects deleted")
                            for obj in deleted {
                                AppLogger.cloudkit.debug("   - Deleted: \(type(of: obj)) - \(String(describing: obj))")
                            }
                        }
                    }
                    if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                        if !inserted.isEmpty {
                            AppLogger.cloudkit.info("➕ INSERT DETECTED: \(inserted.count) objects inserted")
                            for obj in inserted {
                                AppLogger.cloudkit.debug("   - Inserted: \(type(of: obj)) - \(String(describing: obj))")
                            }
                            AppLogger.cloudkit.info("   ⏳ Waiting for CloudKit export (should happen within 5-30 seconds)...")
                        }
                    }
                    if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                        if !updated.isEmpty {
                            AppLogger.cloudkit.info("✏️ UPDATE DETECTED: \(updated.count) objects updated")
                        }
                    }
                }

                // Monitor for CloudKit import/export events
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("NSPersistentCloudKitContainer.eventChangedNotification"),
                    object: nil,
                    queue: nil
                ) { notification in
                    AppLogger.cloudkit.info("☁️ CloudKit event notification: \(String(describing: notification))")
                }

                return container
            }
        } catch {
            AppLogger.app.error("❌ CRITICAL: Failed to create ModelContainer")
            AppLogger.app.error("   Error: \(error.localizedDescription)")
            AppLogger.app.error("   Error details: \(String(describing: error))")
            if let nsError = error as NSError? {
                AppLogger.app.error("   Domain: \(nsError.domain)")
                AppLogger.app.error("   Code: \(nsError.code)")
                AppLogger.app.error("   UserInfo: \(String(describing: nsError.userInfo))")
            }
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }()

    // Separate, local-only cache container that persists across launches (no CloudKit mirroring)
    private var cacheModelContainer: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self,
        ])

        do {
            // Persisted on disk so cache survives relaunch; no cloudKitDatabase means local-only.
            let config = if let groupContainer = Self.resolvedGroupContainer() {
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    groupContainer: groupContainer
                )
            } else {
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false
                )
            }
            let container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
            AppLogger.app.info("🧠 Initialized persisted ModelContainer for LocalCacheService (local-only)")
            if let url = container.configurations.first?.url {
                AppLogger.app.info("   🗂️ Cache Container URL: \(url.path)")
            }
            return container
        } catch {
            AppLogger.app.error("❌ Failed to create persisted cache ModelContainer: \(error.localizedDescription)")
            fatalError("Cannot create cache ModelContainer: \(error)")
        }
    }()

    private static func resolvedGroupContainer() -> ModelConfiguration.GroupContainer? {
        // GitHub Actions builds run unsigned (“Sign to Run Locally”), so the app
        // lacks the shared App Group entitlement and the container lookup fails.
        // Xcode Cloud (and local signed installs) do have the entitlement, so the
        // same lookup succeeds. Detect the missing container and fall back to a
        // sandbox-only store so CI tests don’t crash before they even start.
        let appGroupID = CloudKitConfig.appGroupID
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        {
            AppLogger.app.debug("✅ App group container reachable at \(url.path)")
            return .identifier(appGroupID)
        } else {
            let isCI = ProcessInfo.processInfo.environment["CI"] != nil
            let context = isCI ? "CI environment" : "runtime"
            AppLogger
                .app
                .warning(
                    "⚠️ App group \(appGroupID) unavailable in \(context); falling back to local sandbox storage."
                )
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cloudKitService)
                .environmentObject(sharedRecordsService)
                .environmentObject(sharedDataService)
                .environmentObject(pendingActivityBuffer)
                .task {
                    // Initialize cache service with its own persisted ModelContainer
                    if cacheService == nil {
                        let cacheContext = cacheModelContainer.mainContext
                        let newCacheService = LocalCacheService(modelContext: cacheContext)

                        // Wire services to the cache
                        cloudKitService.setCacheService(newCacheService)
                        sharedRecordsService.setCacheService(newCacheService)
                        sharedDataService.setCacheService(newCacheService)

                        // Wire sharedDataService to cloudKitService for unified API
                        cloudKitService.setSharedDataService(sharedDataService)
                        cloudKitService.setPendingActivityBuffer(pendingActivityBuffer)

                        // Wire services to CloudKitSyncMonitor for status tracking
                        CloudKitSyncMonitor.shared.configureServices(
                            cloudKitService: cloudKitService,
                            sharedRecordsService: sharedRecordsService,
                            cacheService: newCacheService
                        )

                        shareAcceptanceRefresher = ShareAcceptanceRefresher(
                            sharedRecordsService: sharedRecordsService,
                            cacheService: newCacheService
                        )

                        // Store on @State
                        cacheService = newCacheService

                        AppLogger.app.info("✅ Shared CloudKitDataService and LocalCacheService initialized")

                        // Initial owned refresh to seed cache on first launch
                        do {
                            try await cloudKitService.refreshOwnedCareesFromCloudKit()
                            AppLogger.app.info("✅ Initial owned records loaded into cache")
                        } catch {
                            AppLogger.app.warning("⚠️ Initial owned refresh failed: \(error.localizedDescription)")
                        }
                    }
                }
                .onAppear {
                    checkCloudKitStatus()
                    setupNotificationService()
                }
                // App-wide alert to surface share acceptance/failure from SceneDelegate notifications.
                .alert(shareNotifier.alertTitle, isPresented: $shareNotifier.isPresentingAlert) {
                    Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {
                        shareNotifier.isPresentingAlert = false
                    }
                } message: {
                    Text(shareNotifier.alertMessage)
                }
                .errorAlert($startupError)
        }
        // Keep the app’s main environment bound to the CloudKit-synced container
        .modelContainer(sharedModelContainer)
    }

    private func checkCloudKitStatus() {
        let container = CKContainer(identifier: CloudKitConfig.containerID)

        Task {
            do {
                let status = try await container.accountStatus()
                switch status {
                case .available:
                    AppLogger.cloudkit.info("✅ iCloud account: Available")
                case .noAccount:
                    AppLogger.cloudkit.error("❌ iCloud account: No account signed in")
                case .restricted:
                    AppLogger.cloudkit.error("❌ iCloud account: Restricted")
                case .couldNotDetermine:
                    AppLogger.cloudkit.warning("⚠️ iCloud account: Could not determine")
                case .temporarilyUnavailable:
                    AppLogger.cloudkit.warning("⚠️ iCloud account: Temporarily unavailable")
                @unknown default:
                    AppLogger.cloudkit.warning("⚠️ iCloud account: Unknown status")
                }
            } catch {
                AppLogger.cloudkit.error("❌ Failed to check iCloud account status: \(error.localizedDescription)")
            }
        }
    }

    private func setupNotificationService() {
        Task {
            // Setup CloudKit notifications
            await notificationService.setupNotifications(sharedRecordsService: sharedRecordsService)
            AppLogger.cloudkit.info("✅ CloudKit notification service setup complete")
        }
    }
}
