import SwiftUI
import CloudKit

struct CareeListItem: View {
    @ObservedObject var caree: Caree
    
    let persistenceController = PersistenceController.shared

    var existingShare: CKShare? {
        persistenceController.existingShare(caree: caree)
    }
    
    var isCareeSharedWithYou: Bool {
        !persistenceController.privatePersistentStore.contains(manageObject: caree)
    }
    
    var body: some View {
        if let image = caree.image() {
            VStack(alignment: .trailing) {
                CircularProfileImage(imageState: .success(image))
            }
        }

        VStack(alignment: .leading) {
            Text(caree.name ?? "")
                .font(.system(.headline, design: .rounded))
            Text("Behaviors: \(caree.behaviors?.count ?? 0)")
            Text("Activities: \(caree.activities?.count ?? 0)")
            
            if let share = existingShare {
                Text("Participants: \(share.participants.count)")
            }
            
            if isCareeSharedWithYou {
                Label("Shared With You", systemImage: "person.line.dotted.person")
            }
        }
    }
}

struct CareeListItem_Previews: PreviewProvider {
    static var caree: Caree = {
        let viewContext = PersistenceController.preview.container.viewContext
        let fetchRequest = Caree.fetchRequest()

        // swiftlint:disable:next force_try
        let carees = try! viewContext.fetch(fetchRequest)

        let caree = carees[0]
        let photo = Photo(context: viewContext)

        photo.data = UIImage(named: "stmarylake")?.jpegData(compressionQuality: 0)
        caree.photo = photo

        return caree
    }()

    static var previews: some View {
        CareeListItem(caree: caree)
    }
}
