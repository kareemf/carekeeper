import Foundation

enum ReminderSource: String, Codable, Sendable {
    case phone
    case watch

    static var current: ReminderSource {
        #if os(watchOS)
            return .watch
        #else
            return .phone
        #endif
    }

    var glyph: String {
        switch self {
        case .phone:
            "📱"
        case .watch:
            "⌚️"
        }
    }
}
