import SwiftUI
import SwiftData
import CloudKit

@main
struct CareKeeperV2App: App {
    var sharedModelContainer: ModelContainer = {
        do {
            let schema = Schema([
                Caree.self,
                ActivityType.self,
                Activity.self
            ])

            // Configure for CloudKit sync with local storage
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier("group.com.kareemf.CareKeeper"),
                cloudKitDatabase: .private("iCloud.com.kareemf.CareKeeperCK")
            )

            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("   Error details: \(String(describing: error))")
            fatalError("Cannot create ModelContainer: \(error)")
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