/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A SwiftUI view that adds a caree to an existing share.
*/

import SwiftUI
import CoreData
import CloudKit

struct AddToExistingShareView: View {
    @Binding var activeSheet: ActiveSheet?
    var caree: Caree
    
    @State private var toggleProgress: Bool = false
    @State private var selection: String?
    
    let persistenceController = PersistenceController.shared

    var body: some View {
        ZStack {
            SharePickerView(activeSheet: $activeSheet, selection: $selection) {
                Button("Add") { shareCaree(caree, shareTitle: selection) }
                .disabled(selection == nil)
            }
            if toggleProgress {
                ProgressView()
            }
        }
    }
    
    private func shareCaree(_ unsharedCaree: Caree, shareTitle: String?) {
        toggleProgress.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {            
            if let shareTitle = shareTitle, let share = persistenceController.fetchShare(with: shareTitle) {
                persistenceController.shareObject(unsharedCaree, to: share)
            }
            toggleProgress.toggle()
            activeSheet = nil
        }
    }
}
