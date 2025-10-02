import SwiftUI
import SwiftData

@main
struct CareKeeperV2App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self
        ])

        // Start with local storage only - CloudKit sync will be added in Phase 2
        // Use app group to share data with watchOS
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.kareemf.CareKeeper")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error and fall back to in-memory storage
            print("⚠️ Failed to create persistent ModelContainer: \(error.localizedDescription)")
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
        }
        .modelContainer(sharedModelContainer)
    }
}