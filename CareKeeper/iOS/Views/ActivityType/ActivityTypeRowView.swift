import SwiftData
import SwiftUI

struct ActivityTypeRowView: View {
    let activityType: ActivityType
    @State private var showingEdit = false
    @Query private var allActivities: [Activity]

    private var activitiesCount: Int {
        allActivities.count(where: { $0.activityType?.id == activityType.id })
    }

    var body: some View {
        HStack {
            // Icon
            Text(activityType.displayIcon)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activityType.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    if activityType.hasQuantity {
                        Label(
                            activityType.quantityUnit ?? NSLocalizedString("Quantity", comment: "Quantity label"),
                            systemImage: "number"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    if activityType.hasLocation {
                        Label(
                            NSLocalizedString("Location", comment: "Location label"),
                            systemImage: "location"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()

            VStack(alignment: .trailing) {
                Text("\(activitiesCount)")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("activities", comment: "Activities count label"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            showingEdit = true
        }
        .sheet(isPresented: $showingEdit) {
            if let caree = activityType.caree {
                ActivityTypeEditView(caree: caree, activityType: activityType)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ActivityTypeRowView(activityType: PreviewData.sampleActivityType)
        
        // Activity type without quantity or location
        ActivityTypeRowView(activityType: {
            let caree = Caree(name: "Sample")
            return ActivityType(name: "Simple Activity", icon: "⭐", caree: caree)
        }())
    }
    .padding()
    .modelContainer(PreviewContainer.shared)
}
