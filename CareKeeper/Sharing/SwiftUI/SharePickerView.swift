/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A SwiftUI view that picks an existing share.
*/

import SwiftUI
import CoreData
import CloudKit

struct SharePickerView<ActionView: View>: View {
    @Binding private var activeSheet: ActiveSheet?
    @Binding private var selection: CKShare?
    
    private let actionView: ActionView
        
    @State private var shares = PersistenceController.shared.fetchAllShares()

    init(activeSheet: Binding<ActiveSheet?>, selection: Binding<CKShare?>, @ViewBuilder actionView: () -> ActionView) {
        _activeSheet = activeSheet
        _selection = selection
        self.actionView = actionView()
    }

    var body: some View {
        NavigationView {
            VStack {
               if shares.isEmpty {
                   Text("No share exists. You can share on your phone, then try again.").padding()
                   Spacer()
               } else {
                   Form {
                       Section(header: Text("Pick a share")) {
                           ShareListView(selection: $selection, shares: $shares)
                       }
                       Section {
                           actionView
                       }
                   }
               }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Dismiss") { activeSheet = nil }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Shares")
        }
    }
}

private struct ShareListView: View {
    @Binding var selection: CKShare?
    @Binding var shares: [CKShare]

    var body: some View {
        List(shares, id: \.recordID) { share in
            let title = share.title
            let selectionTitle = selection?.title
            
            HStack {
                Text(title)
                Spacer()
                if selectionTitle == title {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selection = (selectionTitle == title) ? nil : share
            }
        }
    }
}

