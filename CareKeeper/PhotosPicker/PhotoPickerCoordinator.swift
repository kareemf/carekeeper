/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A view controller representable that wraps the picker view controller.
 */

import SwiftUI

struct PhotoPickerCoordinator {
    public static func thumbnail(with imageData: Data, pixelSize: Int = 120) -> UIImage? {
        let options = [kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceThumbnailMaxPixelSize: pixelSize] as CFDictionary
        
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        
        let imageReference = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options)!
        return UIImage(cgImage: imageReference)
    }
}
