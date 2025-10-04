import SwiftUI
import SwiftData
import CloudKit

@main
struct CareKeeperV2App: App {
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
                print("   Container: iCloud.com.kareemf.CareKeeperCloudKit")
                print("   App Group: group.com.kareemf.CareKeeper")

                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true,
                    groupContainer: .identifier("group.com.kareemf.CareKeeper"),
                    cloudKitDatabase: .private("iCloud.com.kareemf.CareKeeperCloudKit")
                )

                let container = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )

                print("✅ ModelContainer created successfully")
                return container
            }
        } catch {
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("   Error details: \(String(describing: error))")
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
        let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCloudKit")

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

        let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCloudKit")

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