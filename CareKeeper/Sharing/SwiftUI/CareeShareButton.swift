import SwiftUI
import CoreData
import CloudKit

struct CareeShareButton: View {
    let persistenceController = PersistenceController.shared
    
    var caree: Caree
    
    @Binding var activeSheet: ActiveSheet?
    @Binding var nextSheet: ActiveSheet?
    
//    @State private var isCareeShared: Bool
    private var isCareeShared: Bool {
        persistenceController.existingShare(caree: caree) != nil
    }
    
    private var hasAnyShare: Bool {
        persistenceController.fetchAllShares().isEmpty ? false : true
    }

//    @State private var hasAnyShare: Bool
    @State private var toggleProgress: Bool = false
    
    var body: some View {
        if toggleProgress {
            ProgressView()
        }
        
        Button(action: {
            if persistenceController.privatePersistentStore.contains(manageObject: caree) {
                createNewShare(caree: caree)
            } else {
                manageParticipation(caree: caree)
            }

        }) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
    
    /**
     Use UICloudSharingController to manage the share in iOS.
     In watchOS, UICloudSharingController is unavailable, so create the share using Core Data API.
     */
    #if os(iOS)
    private func createNewShare(caree: Caree) {
         persistenceController.presentCloudSharingController(caree: caree)
    }
    
    private func manageParticipation(caree: Caree) {
        persistenceController.presentCloudSharingController(caree: caree)
    }
    
    #elseif os(watchOS)
    /**
     Sharing a caree can take a while, so dispatch to a global queue so SwiftUI has a chance to show the progress view.
     @State variables are thread-safe, so there's no need to dispatch back the main queue.
     */
    private func createNewShare(caree: Caree) {
        toggleProgress.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            persistenceController.shareObject(caree, to: nil) { share, error in
                toggleProgress.toggle()
                if let share = share {
                    activeSheet = .participantView(share)
                }
            }
        }
    }
    
//    TODO: this won't do anything
    private func manageParticipation(caree: Caree) {
        activeSheet = .managingSharesView
    }
    #endif
}

//struct CareeShareButton_Previews: PreviewProvider {
//    static var previews: some View {
//        CareeShareButton()
//    }
//}
