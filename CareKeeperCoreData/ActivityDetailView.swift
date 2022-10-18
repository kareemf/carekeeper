import SwiftUI

struct ActivityDetailView: View {
    @ObservedObject var data: Activity
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Notes")) {
                    TextField("Notes", text: $data.notes ?? "")
                }
                
                Section(header: Text("Behavior")) {
                    BehaviorListItemView(behavior: data.behavior!)
                }
            }
        }
    }
}

struct ActivityDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
//            ActivityDetailView(data: .constant(Activity.sampleData[0].data))
            Text("TODO")
        }
    }
}
