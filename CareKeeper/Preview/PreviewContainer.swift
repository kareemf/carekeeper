import Foundation
import SwiftData

@MainActor
class PreviewContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self,
        ])
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        
        let container = try! ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        
        // Add sample data
        PreviewData.addSampleData(to: container.mainContext)
        
        return container
    }()
}
