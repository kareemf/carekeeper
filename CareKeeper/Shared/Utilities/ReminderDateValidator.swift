import Foundation

enum ReminderDateValidationError: LocalizedError, Equatable {
    case dueDateInPast

    var errorDescription: String? {
        switch self {
        case .dueDateInPast:
            return NSLocalizedString("Reminder time must be in the future.", comment: "Reminder validation error")
        }
    }
}

struct ReminderDateValidator {
    static func validate(dueDate: Date, now: Date = Date()) throws {
        if dueDate < now {
            throw ReminderDateValidationError.dueDateInPast
        }
    }
}
