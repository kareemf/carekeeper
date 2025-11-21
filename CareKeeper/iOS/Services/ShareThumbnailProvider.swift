import Foundation
import UIKit

enum ShareThumbnailProvider {
    private static let targetSize = CGSize(width: 300, height: 300)
    private static let logger = AppLogger.sharing

    /// Generates thumbnail-ready PNG data, preferring the caree photo and falling back to the branded share logo or app icon.
    static func thumbnailData(for caree: Caree?) -> Data? {
        guard let sourceImage = thumbnailImage(for: caree) else { return nil }

        if let prepared = sourceImage.preparingThumbnail(of: targetSize),
           let data = prepared.pngData()
        {
            return data
        }

        return sourceImage.pngData()
    }

    /// Provides a thumbnail UIImage for UICloudSharingController delegates.
    static func thumbnailImage(for caree: Caree?) -> UIImage? {
        if let caree, let imageData = caree.image, let image = UIImage(data: imageData) {
            return image
        }

        return shareLogoImage()
    }

    /// Writes thumbnail data to a temporary file so CKShare metadata can reference it.
    static func thumbnailFileURL(for data: Data) -> URL? {
        let fileName = "share-thumbnail-\(UUID().uuidString).png"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            logger.warning("⚠️ Failed to write thumbnail to disk: \(error.localizedDescription)")
            return nil
        }
    }

    private static func shareLogoImage() -> UIImage? {
        if let logo = UIImage(named: "ShareLogo") {
            return logo
        }
        return appIconImage()
    }

    private static func appIconImage() -> UIImage? {
        guard
            let iconsDict = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last,
            let icon = UIImage(named: lastIcon)
        else {
            return nil
        }

        return icon
    }
}
