import SwiftUI

struct BehaviorListItemView: View {
    let behavior: Behavior
    
    var body: some View {
        HStack {
            if !(behavior.icon?.isEmpty ?? true) {
                Text("\(behavior.icon!)")
            }
            
            Text("\(behavior.name ?? "")")
        }
    }
}
