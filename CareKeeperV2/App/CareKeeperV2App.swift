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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}