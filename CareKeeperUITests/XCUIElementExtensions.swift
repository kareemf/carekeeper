import XCTest

extension XCUIElement {
    var hasFocus: Bool {
        (self.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    var isOn: Bool {
        (self.value as? String) == "1"
    }
}
