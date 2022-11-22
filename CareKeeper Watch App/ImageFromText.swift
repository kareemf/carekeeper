import SwiftUI

// See https://stackoverflow.com/a/55339365/1377016
func imageFromText(_ text: String) -> UIImage? {
    let nsString = (text as NSString)
    // Font size = min from docs (https://developer.apple.com/design/human-interface-guidelines/components/system-experiences/complications#corner)
    let font = UIFont.systemFont(ofSize: 20)
    let stringAttributes = [NSAttributedString.Key.font: font]
    let imageSize = nsString.size(withAttributes: stringAttributes)

    UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
    UIColor.clear.set()
    UIRectFill(CGRect(origin: CGPoint(), size: imageSize))
    nsString.draw(at: CGPoint.zero, withAttributes: stringAttributes)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
}
