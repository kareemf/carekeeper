/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A SwiftUI view that manages existing shares.
*/

import SwiftUI
import CoreData
import CloudKit

struct ManagingSharesView: View {
    @Binding var activeSheet: ActiveSheet?
    @Binding var nextSheet: ActiveSheet?

    @State private var toggleProgress: Bool = false
    @State private var selection: CKShare?
    
    let persistenceController = PersistenceController.shared

    var body: some View {
        ZStack {
            SharePickerView(activeSheet: $activeSheet, selection: $selection) {
                if let share = selection {
                    actionButtons(for: share)
                }
            }
            if toggleProgress {
                ProgressView()
            }
        }
    }
    
    @ViewBuilder
    private func actionButtons(for share: CKShare) -> some View {
        let persistentStore = share.persistentStore
        let isPrivateStore = (persistentStore == persistenceController.privatePersistentStore)
        
        Button(isPrivateStore ? "Manage Participants" : "View Participants") {
            if let share = persistenceController.fetchShare(with: selection!.recordID) {
                activeSheet = .participantView(share)
            }
        }
        .disabled(selection == nil)
        
        #if os(iOS)
        Button("Manage With UICloudSharingController") {
            if let share = persistenceController.fetchShare(with: selection!.recordID) {
                activeSheet = .cloudSharingSheet(share)
            }
        }
        .disabled(selection == nil)
        #endif
        
        Button(isPrivateStore ? "Stop Sharing" : "Remove Me") {
            if let share = persistenceController.fetchShare(with: selection!.recordID) {
                purgeShare(share, in: persistentStore)
            }
        }
        .disabled(selection == nil)
        
//        TODO: REMOVE DISMISS BUTTON
    }
    
    private func purgeShare(_ share: CKShare, in persistentStore: NSPersistentStore?) {
        toggleProgress.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            persistenceController.purgeObjectsAndRecords(with: share, in: persistentStore)
            toggleProgress.toggle()
            activeSheet = nil
        }
    }
}
