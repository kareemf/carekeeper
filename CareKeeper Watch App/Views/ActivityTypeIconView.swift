import SwiftUI

/// Renders an activity type icon, handling both emojis and SF Symbols
struct ActivityTypeIconView: View {
    let icon: String

    var body: some View {
        // Check if icon is an SF Symbol (contains a dot) or emoji
        if icon.contains(".") {
            // SF Symbol
            Image(systemName: icon.isEmpty ? "circle" : icon)
        } else if icon.isEmpty {
            // Empty - show placeholder
            Image(systemName: "circle")
        } else {
            // Emoji or text
            Text(icon)
        }
    }
}
