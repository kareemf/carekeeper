import SwiftUI
import SwiftData

@main
struct CareKeeperV2WatchApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self
        ])

        // Use app group for shared data with iOS app
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.kareemf.CareKeeper")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error for debugging
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("⚠️ Error details: \(error.localizedDescription)")

            // Fallback to in-memory store for development
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
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
