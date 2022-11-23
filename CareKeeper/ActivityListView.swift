import SwiftUI
import CoreData

struct ActivityListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var errorHandling: ErrorHandling

    @ObservedObject var caree: Caree
    @State private var activities: [Activity] = []

    init(caree: Caree) {
        self.caree = caree
    }

    var body: some View {
        List {
            if activities.isEmpty {
                Text("No activities tracked yet")
            }

            ForEach(activities) { activity in
                NavigationLink(destination: ActivityDetailView(activity: activity)) {
                    ActivityListItem(activity: activity)
                }
            }
        }
        .onAppear(perform: {
            do {
                try activities = caree.fetchActivities(fetchLimit: .max)
            } catch {
                errorHandling.handle(error: error)
            }
        })
    }
}

struct ActivityListView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Caree.fetchRequest()

    // swiftlint:disable:next force_try
    static let carees = try! viewContext.fetch(fetchRequest)

    static var previews: some View {
        ActivityListView(
            caree: carees[0]
        )
        .environment(\.managedObjectContext, viewContext)
    }
}
