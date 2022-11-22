import SwiftUI
import CoreData

extension ProfileImageModel {
    public func createPhotoFromSelection(context: NSManagedObjectContext) -> Photo? {
        guard let imageData = self.data else {
            //     TODO: error handling
            print("\(#function): Failed to extract data from selected image")

            return nil
        }
        
        
        guard let thumbnailData = PhotoPickerCoordinator.thumbnail(with: imageData)?.jpegData(compressionQuality: 1) else {
            //                TODO: error handling
            print("\(#function): Failed to create thumbnail for selected image.")
            
            return nil
        }
        
        let photo = Photo(context: context)
        
        photo.data = thumbnailData
        
        return photo
    }
}

