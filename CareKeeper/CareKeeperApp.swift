// Bridge file to use v2 app structure
// This allows the existing Xcode project to build while using v2 code

import SwiftUI

@main
struct CareKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            // Use the v2 ContentView directly
            CareKeeperV2ContentView()
        }
    }
}

// Bridge to v2 ContentView
struct CareKeeperV2ContentView: View {
    var body: some View {
        Text("CareKeeper v2 - Bridge Implementation")
            .font(.title)
            .padding()
    }
}