import SwiftUI

struct ActivityTrackingViewStep1: View {
    @ObservedObject var caree: Caree
    @Binding var isPresentingView: Bool
    var behaviors: [Behavior]
    @Environment(\.dismiss) var dismiss

    let saveAction: () -> Void
    
    var body: some View {
//        TODO: dynamic fields like quaintity, rating
        VStack{
            List {
                if behaviors.count == 0 {
                    Text("Configure some behaviors to track for \(caree.name ?? "") first")
                }
                
                ForEach(behaviors) { behavior in
                    NavigationLink(destination: ActivityTrackingViewStep2(caree: caree, behavior: behavior, isPresentingView: $isPresentingView, saveAction: saveAction)) {
                        BehaviorListItem(behavior: behavior)
                            .frame(height: 100.0)
                            .foregroundColor(.mint)
                    }
                }
            }
#if os(watchOS)
            .listStyle(CarouselListStyle())
#endif
        }
        .navigationTitle("\(caree.name ?? "") - Behavior To Track")
        .onAppear(perform: {
//            TODO: not needed if isPresentingView works as intended
            if !isPresentingView {
                dismiss()
            }

        })
    }
}

struct BehaviorListItem: View {
    var behavior: Behavior

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
    static let carees = try! viewContext.fetch(fetchCareeRequest)
    
    static var previews: some View {
        NavigationView {
            ActivityTrackingViewStep1(
                caree: carees[0],
                isPresentingView: .constant(true),
                behaviors: carees[0].behaviors!.allObjects as! [Behavior],
                saveAction: {}
            )
            .environment(\.managedObjectContext, viewContext)
        }
    }
}
