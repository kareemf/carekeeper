import Foundation

extension Date {
    /// Returns the date rounded down to the nearest minute (dropping seconds/nanoseconds).
    func roundedDownToMinute() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        components.second = 0
        components.nanosecond = 0
        return Calendar.current.date(from: components) ?? self
    }
}
