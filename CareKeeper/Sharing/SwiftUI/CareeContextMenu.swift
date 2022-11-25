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
    
    init(activeSheet: Binding<ActiveSheet?>, nextSheet: Binding<ActiveSheet?>, caree: Caree) {
        _activeSheet = activeSheet
        _nextSheet = nextSheet
        self.caree = caree
        isCareeShared = (PersistenceController.shared.existingShare(caree: caree) != nil)
        hasAnyShare = PersistenceController.shared.shareTitles().isEmpty ? false : true
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
//        .onReceive(NotificationCenter.default.storeDidChangePublisher) { notification in
//            processStoreChangeNotification(notification)
//        }
    }
    
    @ViewBuilder
    private func menuButtons() -> some View {
        /**
         For carees in the private database, allow creating a new share or adding to an existing share.
         For carees in the shared database, allow managing participation.
         */
        if PersistenceController.shared.privatePersistentStore.contains(manageObject: caree) {
            Button("Create New Share") { createNewShare(caree: caree) }
            .disabled(isCareeShared)
            
            Button("Add to Existing Share") { activeSheet = .sharePicker(caree) }
            .disabled(isCareeShared || !hasAnyShare)
        } else {
            Button("Manage Participation") { manageParticipation(caree: caree) }
        }

        /**
         Show the Delete button if the user is editing carees and has the permission to delete.
         */
//        TODO: migrate to existing delete button
        if PersistenceController.shared.container.canDeleteRecord(forManagedObjectWith: caree.objectID) {
            Divider()
            Button("Delete", role: .destructive) {
//                PersistenceController.shared.delete(caree: caree)
//                caree
                activeSheet = nil
            }
        }
    }

    /**
     Use UICloudSharingController to manage the share in iOS.
     In watchOS, UICloudSharingController is unavailable, so create the share using Core Data API.
     */
    #if os(iOS)
    private func createNewShare(caree: Caree) {
         PersistenceController.shared.presentCloudSharingController(caree: caree)
    }
    
    private func manageParticipation(caree: Caree) {
        PersistenceController.shared.presentCloudSharingController(caree: caree)
    }
    
    #elseif os(watchOS)
    /**
     Sharing a caree can take a while, so dispatch to a global queue so SwiftUI has a chance to show the progress view.
     @State variables are thread-safe, so there's no need to dispatch back the main queue.
     */
    private func createNewShare(caree: Caree) {
        toggleProgress.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PersistenceController.shared.shareObject(caree, to: nil) { share, error in
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
    
    /**
     Ignore the notification in the following cases:
     - It isn't relevant to the private database.
     - It doesn't have a transaction. When a share changes, Core Data triggers a store remote change notification with no transaction.
     */
//    private func processStoreChangeNotification(_ notification: Notification) {
//        guard let storeUUID = notification.userInfo?[UserInfoKey.storeUUID] as? String,
//              storeUUID == PersistenceController.shared.privatePersistentStore.identifier else {
//            return
//        }
//        guard let transactions = notification.userInfo?[UserInfoKey.transactions] as? [NSPersistentHistoryTransaction],
//              transactions.isEmpty else {
//            return
//        }
//        isCareeShared = (PersistenceController.shared.existingShare(caree: caree) != nil)
//        hasAnyShare = PersistenceController.shared.shareTitles().isEmpty ? false : true
//    }
}
