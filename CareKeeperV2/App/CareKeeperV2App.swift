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

        // Configure CloudKit sync with private database
        // Use app group to share data with watchOS
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.kareemf.CareKeeper"),
            cloudKitDatabase: .private("iCloud.com.kareemf.CareKeeperCK")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error and fall back to in-memory storage
            print("⚠️ Failed to create CloudKit-enabled ModelContainer: \(error.localizedDescription)")
            print("   Falling back to in-memory storage (data will not persist)")

            // Fallback to in-memory store for development
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleIncomingURL(_ url: URL) {
        // Handle CloudKit share acceptance
        guard url.scheme == "https" && url.host == "www.icloud.com" else {
            return
        }

        let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCK")

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