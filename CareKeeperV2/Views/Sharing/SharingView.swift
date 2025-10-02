import SwiftUI

struct SharingView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text(NSLocalizedString("Sharing", comment: "Sharing view title"))
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(NSLocalizedString("CloudKit sharing functionality will be implemented in Phase 2.", 
                                     comment: "Sharing placeholder description"))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle(NSLocalizedString("Sharing", comment: "Sharing navigation title"))
        }
    }
}

#Preview {
    SharingView()
}