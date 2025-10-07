import SwiftUI
import SwiftData

@main
struct CareKeeperWatchApp: App {
    var sharedModelContainer: ModelContainer = {
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
            CareeListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
