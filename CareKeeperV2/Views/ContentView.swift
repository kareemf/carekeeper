import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CareeListView()
                .tabItem {
                    Label(NSLocalizedString("Carees", comment: "Tab title for carees list"), 
                          systemImage: "person.crop.rectangle.stack")
                }
                .tag(0)
            
            SharingView()
                .tabItem {
                    Label(NSLocalizedString("Sharing", comment: "Tab title for sharing"), 
                          systemImage: "person.2")
                }
                .tag(1)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}