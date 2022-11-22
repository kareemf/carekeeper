import SwiftUI
import CoreData

extension ProfileImageModel {
    enum PhotoError: LocalizedError {
        case dataExtractionFailed(String)
        case thumbnailCreatiomFailed(String)
    }

    public func createPhotoFromSelection(context: NSManagedObjectContext) throws -> Photo? {
        guard let imageData = self.data else {
            print("\(#function): Failed to extract data from selected image")

            throw PhotoError.dataExtractionFailed("Failed to extract data from selected image")
        }

        guard let thumbnailData = PhotoPickerCoordinator.thumbnail(with: imageData)?.jpegData(compressionQuality: 1) else {
            print("\(#function): Failed to create thumbnail for selected image")

            throw PhotoError.thumbnailCreatiomFailed("Failed to create thumbnail for selected image")
        }

        let photo = Photo(context: context)

        photo.data = thumbnailData

        return photo
    }
}
