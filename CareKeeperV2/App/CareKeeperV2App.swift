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

        // Try CloudKit configuration first
        let cloudKitConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.kareemf.CareKeeper"),
            cloudKitDatabase: .private("iCloud.com.kareemf.CareKeeperCK")
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudKitConfig])
        } catch {
            print("⚠️ CloudKit ModelContainer failed: \(error.localizedDescription)")
            print("   Attempting local storage without CloudKit...")

            // Fallback to local storage without CloudKit
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier("group.com.kareemf.CareKeeper")
            )

            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                print("⚠️ Local storage failed: \(error.localizedDescription)")
                print("   Using in-memory storage (data will not persist)")

                // Last resort: in-memory storage
                let memoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )

                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    // If even in-memory fails, there's a fundamental issue
                    fatalError("Cannot create ModelContainer even with in-memory storage: \(error)")
                }
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