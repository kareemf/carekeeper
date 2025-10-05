import SwiftUI
import SwiftData
import CloudKit
import CoreData

@main
struct CareKeeperApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self
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
                print("🔧 Initializing ModelContainer with CloudKit sync")
                print("   Container: \(CloudKitConfig.containerID)")
                print("   App Group: \(CloudKitConfig.appGroupID)")

                // Configure for both local (iOS↔️watchOS) and cloud (iCloud) sync
                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    groupContainer: .identifier(CloudKitConfig.appGroupID),
                    cloudKitDatabase: .private(CloudKitConfig.containerID)
                )

                print("   📋 Configuration details:")
                print("      - isStoredInMemoryOnly: false")
                print("      - groupContainer: \(CloudKitConfig.appGroupID)")
                print("      - cloudKitDatabase: private(\(CloudKitConfig.containerID))")

                let container = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )

                print("✅ ModelContainer created successfully")
                if let url = container.configurations.first?.url {
                    print("   📦 Container URL: \(url.path)")
                }

                // Monitor for sync errors
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("NSPersistentStoreRemoteChange"),
                    object: nil,
                    queue: nil
                ) { notification in
                    print("📡 Persistent store remote change notification: \(notification)")
                }

                // Monitor for delete operations and CloudKit export
                NotificationCenter.default.addObserver(
                    forName: .NSManagedObjectContextDidSave,
                    object: nil,
                    queue: nil
                ) { notification in
                    if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
                        if !deleted.isEmpty {
                            print("⚠️ DELETE DETECTED: \(deleted.count) objects deleted")
                            for obj in deleted {
                                print("   - Deleted: \(type(of: obj)) - \(obj)")
                            }
                        }
                    }
                    if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                        if !inserted.isEmpty {
                            print("➕ INSERT DETECTED: \(inserted.count) objects inserted")
                            for obj in inserted {
                                print("   - Inserted: \(type(of: obj)) - \(obj)")
                            }
                            print("   ⏳ Waiting for CloudKit export (should happen within 5-30 seconds)...")
                        }
                    }
                    if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                        if !updated.isEmpty {
                            print("✏️ UPDATE DETECTED: \(updated.count) objects updated")
                        }
                    }
                }

                // Monitor for CloudKit import/export events
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("NSPersistentCloudKitContainer.eventChangedNotification"),
                    object: nil,
                    queue: nil
                ) { notification in
                    print("☁️ CloudKit event notification: \(notification)")
                }

                return container
            }
        } catch {
            print("❌ CRITICAL: Failed to create ModelContainer")
            print("   Error: \(error)")
            print("   Error details: \(String(describing: error))")
            if let nsError = error as NSError? {
                print("   Domain: \(nsError.domain)")
                print("   Code: \(nsError.code)")
                print("   UserInfo: \(nsError.userInfo)")
            }
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    checkCloudKitStatus()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func checkCloudKitStatus() {
        let container = CKContainer(identifier: CloudKitConfig.containerID)

        Task {
            do {
                let status = try await container.accountStatus()
                switch status {
                case .available:
                    print("✅ iCloud account: Available")
                case .noAccount:
                    print("❌ iCloud account: No account signed in")
                case .restricted:
                    print("❌ iCloud account: Restricted")
                case .couldNotDetermine:
                    print("⚠️ iCloud account: Could not determine")
                case .temporarilyUnavailable:
                    print("⚠️ iCloud account: Temporarily unavailable")
                @unknown default:
                    print("⚠️ iCloud account: Unknown status")
                }
            } catch {
                print("❌ Failed to check iCloud account status: \(error)")
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Handle CloudKit share acceptance
        guard url.scheme == "https" && url.host == "www.icloud.com" else {
            return
        }

        let container = CKContainer(identifier: CloudKitConfig.containerID)

        // Fetch the share metadata from the URL
        container.fetchShareMetadata(with: url) { metadata, error in
            if let error = error {
                print("❌ Failed to fetch share metadata: \(error.localizedDescription)")
                return
            }

            guard let metadata = metadata else {
                print("❌ No metadata found for share")
                return
            }

            // Accept the share
            container.accept(metadata) { acceptedShare, error in
                if let error = error {
                    print("❌ Failed to accept share: \(error.localizedDescription)")
                    return
                }

                if let acceptedShare = acceptedShare {
                    print("✅ Successfully accepted share: \(acceptedShare.recordID)")
                    // The shared data will automatically sync to the local store
                    // SwiftData + CloudKit handles the rest
                }
            }
        }
    }
}