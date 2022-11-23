import SwiftUI

struct BehavioDetailView: View {
    @ObservedObject var behavior: Behavior
    @Binding var activeSheet: ActiveSheet?
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var icon = ""
    
    var onSave: () -> Void
    
    private var isNew: Bool {
        behavior.objectID.isTemporaryID
    }
    
    private var navTitle: String {
        return isNew ? "New Behavior" : "Behavior - \(behavior.name ?? "")"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Info")) {
                    TextField("Name", text: $name)
                        .onAppear(perform: {
                            if let realName = behavior.name {
                                name = realName
                            }
                            
                            if isNew {
                                isNameFocused = true
                            }
                        })
                        .onChange(of: name, perform: { _ in
                            behavior.name = name
                        })
                        .focused($isNameFocused)
                    
                    
                    iconTextUI()
                        .onAppear(perform: {
                            if let realIcon = behavior.icon {
                                icon = realIcon
                            }
                        })
                        .onChange(of: icon, perform: { _ in
                            behavior.icon = icon
                        })
                }
                
                Section(header: Text("Properties")) {
                    Toggle(isOn: $behavior.enableLocations) {
                        Text("Allow Locations Requests")
                    }
                }
                
                if !isNew {
                    Section(header: Text("Activity").foregroundColor(.green)) {
                        Button(action: {
                            activeSheet = .activityTracking2(behavior)
                        }) {
                            Label("Track Activity", systemImage: "timer")
                                .font(.headline)
                        }
                        .foregroundColor(.green)
                        
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if  isNew {
                            behavior.managedObjectContext?.delete(behavior)
                        }
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if  isNew {
                            behavior.dateCreated = Date()
                        }
                        
                        if let name = behavior.name {
                            behavior.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                        }
                        
                        onSave()
                        activeSheet = nil
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .navigationTitle(.constant(navTitle))
    }
    
    @ViewBuilder
    private func iconTextUI() -> some View {
#if os(iOS)
        EmojiTextField(text: $icon, placeholder: "Icon")
#else
        TextField("Icon", text: $icon)
#endif
    }
}

struct BehaviorEditView_Previews: PreviewProvider {
    static let viewContext = PersistenceController.preview.container.viewContext
    static let fetchRequest = Behavior.fetchRequest()
    
    // swiftlint:disable:next force_try
    static let behaviors = try! viewContext.fetch(fetchRequest)
    
    static var previews: some View {
        BehavioDetailView(
            behavior: behaviors[0],
            activeSheet: .constant(.behaviorDetail(behaviors[0])),
            onSave: {}
        )
    }
}
