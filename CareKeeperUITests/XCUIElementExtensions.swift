import XCTest

extension XCUIElement {
    var hasFocus: Bool {
        return (self.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    var isOn: Bool {
        return (self.value as? String) == "1"
    }
}
