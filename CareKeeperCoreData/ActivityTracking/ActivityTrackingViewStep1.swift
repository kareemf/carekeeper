import SwiftUI

struct ActivityTrackingViewStep1: View {
    @ObservedObject var caree: Caree
    @Binding var isPresentingView: Bool
    var behaviors: [Behavior]

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
        }
    }
}

struct TrackActivityView_Previews: PreviewProvider {
//    static var caree = Caree.sampleData[0]
    
    static var previews: some View {
        NavigationView {
            Text("TODO")
//            ActivityTrackingViewStep1(
//                caree: .constant(caree),
//                isPresentingView: .constant(true),
//                saveAction: {}
//            )
        }
    }
}
