import Foundation
import ClockKit

class ComplicationController: NSObject, CLKComplicationDataSource {
    var cornerComplicationImage: UIImage? = imageFromText("❤️")
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(identifier: "complication", displayName: "Care Keeper", supportedFamilies: CLKComplicationFamily.allCases)
        ]

        handler(descriptors)
    }

    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        var entry: CLKComplicationTimelineEntry?

        switch complication.family {
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: CLKSimpleTextProvider(text: "Care Keeper", shortText: "CK"),
                imageProvider: CLKFullColorImageProvider(fullColorImage: cornerComplicationImage!)
            )

            entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        default:
            break
        }

        handler(entry)
    }
}
