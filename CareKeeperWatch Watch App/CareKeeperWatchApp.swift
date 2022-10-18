func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

import SwiftUI

@main
struct CareKeeperWatch_Watch_AppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            CareeListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
    
    
}
