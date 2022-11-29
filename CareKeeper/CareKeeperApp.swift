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
    
    @State private var activeSheet: ActiveSheet?
    
    var body: some Scene {
        WindowGroup {
            TabView {
                CareeListView()
                    .tabItem {
                        Label("Carees", systemImage: "person.crop.rectangle.stack")
                    }
                
                NavigationView {
                    ManagingSharesView(activeSheet: $activeSheet)
                }
                .onChange(of: activeSheet, perform: {value in
                    switch activeSheet {
                    case .cloudSharingSheet(let share):
                        persistenceController.presentCloudSharingController(share: share)
                    default:
                        return
                    }
                })
                .sheet(item: $activeSheet) { item in
                    sheetView(with: item)
                }
                .tabItem {
                    Label("Sharing", systemImage: "person.line.dotted.person.fill")
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .withErrorHandling()
            .withPersistenceErrorHandling()
        }
    }
    
    @ViewBuilder
    private func sheetView(with item: ActiveSheet) -> some View {
        
        switch item {
        case .cloudSharingSheet(_):
            /**
             Reserve this case for something like CloudSharingSheet(activeSheet: $activeSheet, share: share).
             */
            EmptyView()
        case .participantView(let share):
            ParticipantView(activeSheet: $activeSheet, share: share)
        default:
            EmptyView()
        }
    }
}
