import SwiftUI

extension Caree {
    func image() -> Image? {
        guard let photoData = self.photo?.data,
              let uiImage = UIImage(data: photoData) else {
            return nil
        }

        return Image(uiImage: uiImage)
    }
}
