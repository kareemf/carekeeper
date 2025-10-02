import SwiftUI

struct CareeListRowView: View {
    let caree: Caree
    
    var body: some View {
        HStack {
            profileImageView
            
            VStack(alignment: .leading, spacing: 4) {
                Text(caree.name)
                    .font(.headline)
                
                Text(NSLocalizedString("\(caree.activityTypes.count) activity types", 
                                     comment: "Activity types count in caree row"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var profileImageView: some View {
        Group {
            if let imageData = caree.image, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
    }
}

#Preview {
    List {
        CareeListRowView(caree: PreviewData.sampleCaree)
        CareeListRowView(caree: PreviewData.sampleCareeWithImage)
    }
    .modelContainer(PreviewContainer.shared)
}