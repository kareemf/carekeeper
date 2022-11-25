/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A SwiftUI view that manages the actions on a caree.
*/

import SwiftUI
import CoreData
import CloudKit

struct CareeContextMenu: View {
    @Binding var activeSheet: ActiveSheet?
    @Binding var nextSheet: ActiveSheet?
    private let caree: Caree

    @State private var isCareeShared: Bool
    @State private var hasAnyShare: Bool
    @State private var toggleProgress: Bool = false
    
    let persistenceController = PersistenceController.shared
    
    init(activeSheet: Binding<ActiveSheet?>, nextSheet: Binding<ActiveSheet?>, caree: Caree) {
        _activeSheet = activeSheet
        _nextSheet = nextSheet
        self.caree = caree
        isCareeShared = (persistenceController.existingShare(caree: caree) != nil)
        hasAnyShare = persistenceController.shareTitles().isEmpty ? false : true
    }

    var body: some View {
        /**
         CloudKit has a limit on how many zones a database can have. To avoid reaching the limit,
         apps use the existing share, if possible.
         */
        ZStack {
            ScrollView {
                menuButtons()
            }
            if toggleProgress {
                ProgressView()
            }
        }
    }
    
    @ViewBuilder
    private func menuButtons() -> some View {
        /**
         For carees in the private database, allow creating a new share or adding to an existing share.
         For carees in the shared database, allow managing participation.
         */
        if persistenceController.privatePersistentStore.contains(manageObject: caree) {
            Button("Create New Share") { createNewShare(caree: caree) }
            .disabled(isCareeShared)
            
            Button("Add to Existing Share") { activeSheet = .sharePicker(caree) }
            .disabled(isCareeShared || !hasAnyShare)
            
            Button("Manage Shares") { activeSheet = .managingSharesView }
        } else {
            Button("Manage Participation") { manageParticipation(caree: caree) }
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
                    nextSheet = .participantView(share)
                    activeSheet = nil
                }
            }
        }
    }
    
    private func manageParticipation(caree: Caree) {
        nextSheet = .managingSharesView
        activeSheet = nil
    }
    #endif
}
