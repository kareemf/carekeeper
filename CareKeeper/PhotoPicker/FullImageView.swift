/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A SwiftUI view that shows a scrollable full-size image.
*/

import SwiftUI
import CoreData

struct FullImageView: View {
    @Binding var activeSheet: ActiveSheet?
    var photo: Photo?

    private var photoImage: UIImage? {
        guard let photoData = photo?.data else { return nil }
        return UIImage(data: photoData)
    }

    var body: some View {
        NavigationView {
            VStack {
                if let image = photoImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                    }
                } else {
                    Text("Something went wrong").padding()
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { activeSheet = nil }
                }
            }
        }
    }
}
