import SwiftUI

struct ActivityTrackingViewStep1: View {
    @ObservedObject var caree: Caree
    @Binding var isPresentingView: Bool
    var behaviors: [Behavior]
    @Environment(\.dismiss) var dismiss

    let saveAction: () -> Void
    
    var body: some View {
//        TODO: location
//        TODO: dynamic fields like quaintity, rating
        VStack{
            Text("Behavior To Track")
            List {
                if behaviors.count == 0 {
                    Text("Configure some behaviors to track for \(caree.name ?? "") first")
                }
                
                ForEach(behaviors) { behavior in
                    NavigationLink(destination: ActivityTrackingViewStep2(caree: caree, behavior: behavior, isPresentingView: $isPresentingView, saveAction: saveAction)) {
                        Text("\(behavior.icon ?? "")\(behavior.name ?? "")")
                    }
                }
            }
        }.onAppear(perform: {
//                TODO: not needed if isPresentingView works as intended
            if !isPresentingView {
                dismiss()
            }

        })
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
