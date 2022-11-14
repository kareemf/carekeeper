import SwiftUI

struct ActivityListItem: View {
    @ObservedObject var activity: Activity
    var body: some View {
        VStack(alignment: .leading) {
            if let behavior = activity.behavior {
                BehaviorListItemView(behavior: behavior)
            }

            Text("🗓 \(activity.when?.formatted(date: .abbreviated, time: .shortened) ?? "")")

            if !(activity.notes?.isEmpty ?? true) {
                Text("🗒 \(activity.notes!)")
            }

            if activity.latitude != 0 || activity.longitude != 0 {
                Image(systemName: "location")
            }
        }
    }
}

struct ActivityListItem_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Activity.fetchRequest()

    // swiftlint:disable:next force_try
    static let activities = try! viewContext.fetch(fetchRequest)

    static var previews: some View {
        ActivityListItem(activity: activities[0])
    }
}
