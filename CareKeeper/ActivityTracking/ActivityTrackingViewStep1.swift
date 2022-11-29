import SwiftUI

struct ActivityTrackingViewStep1: View {
    @ObservedObject var caree: Caree
    @Binding var activeSheet: ActiveSheet?
    var behaviors: [Behavior]

    var body: some View {
        NavigationView {
            VStack {
                List {
                    if behaviors.count == 0 {
                        Text("Configure some behaviors to track for \(caree.name ?? "") first")
                    }
                    
                    ForEach(behaviors) { behavior in
                        NavigationLink(destination: ActivityTrackingViewStep2(caree: caree, behavior: behavior, activeSheet: $activeSheet)) {
                            BehaviorListItem(behavior: behavior, activeSheet: $activeSheet)
                                .frame(height: 100.0)
                                .foregroundColor(.mint)
                        }
                    }
                }
#if os(watchOS)
                .listStyle(CarouselListStyle())
#endif
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        activeSheet = nil
                    }
                }
            }
#if os(watchOS)
            .navigationTitle("Activity")
#else
            .navigationTitle("Activity for \(caree.name ?? "")")
#endif
        }
    }
}

struct BehaviorListItem: View {
    var behavior: Behavior
    
    @Binding var activeSheet: ActiveSheet?
    
    var body: some View {        
        HStack {
            if behavior.icon != nil {
                Text(behavior.icon ?? "")
                    .font(.title)
            }
            
            VStack(alignment: .leading) {
                Text(behavior.name ?? "")
                    .font(.system(.headline, design: .rounded))
                Text("\(behavior.activities?.count ?? 0) activities")
                
                if behavior.enableLocations {
                    HStack {
                        Image(systemName: "location")
                        Text("requests allowed")
                    }
                }
            }
        }
    }
}

struct TrackActivityView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchCareeRequest = Caree.fetchRequest()

    // swiftlint:disable:next force_try
    static let carees = try! viewContext.fetch(fetchCareeRequest)

    static var previews: some View {
        ActivityTrackingViewStep1(
            caree: carees[0],
            activeSheet: .constant(.activityTracking1),
            // swiftlint:disable:next force_cast
            behaviors: carees[0].behaviors!.allObjects as! [Behavior]
        )
        .environment(\.managedObjectContext, viewContext)
    }
}
