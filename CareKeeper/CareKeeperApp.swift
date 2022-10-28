import SwiftUI

func ??<T>(lhs: Binding<T?>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

@main
struct CareKeeperApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            CareeListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .withErrorHandling()
                .withPersistenceErrorHandling()
        }
    }
}
