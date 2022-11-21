import SwiftUI

struct CareeListItem: View {
    @ObservedObject var caree: Caree
    
    var body: some View {
        if let image = caree.image() {
            VStack(alignment: .trailing) {
                CircularProfileImage(imageState: .success(image))
            }
        }
        
        VStack(alignment: .leading) {
            Text(caree.name ?? "")
                .font(.system(.headline, design: .rounded))
            Text("\(caree.behaviors?.count ?? 0) behaviors")
            Text("\(caree.activities?.count ?? 0) activities")
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
