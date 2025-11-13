import SwiftUI

struct ActivityRowView: View {
    let activity: Activity
    @State private var showingDetail = false

    private let bellSymbol = "🔔"
    
    var body: some View {
        HStack {
            // Activity type icon
            ActivityTypeIconView(icon: activity.activityType?.displayIcon ?? "")
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.activityType?.name ?? NSLocalizedString("Unknown", comment: "Unknown activity type"))
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(activity.formattedDateTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let notes = activity.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 16) {
                    if let formattedQuantity = activity.formattedQuantity {
                        Label(formattedQuantity, systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if activity.hasLocation {
                        Label(
                            NSLocalizedString("Location", comment: "Location label"),
                            systemImage: "location.fill"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if let reminderInfo = reminderStatus(for: activity) {
                        HStack(spacing: 4) {
                            Text(bellSymbol)
                            Text("\(reminderInfo.deviceGlyph) \(reminderInfo.timeText)")
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            ActivityDetailView(activityID: activity.id)
        }
    }
}

private extension ActivityRowView {
    func reminderStatus(for activity: Activity) -> (deviceGlyph: String, timeText: String)? {
        guard activity.reminderIdentifier != nil else { return nil }
        let glyph = activity.reminderSource?.glyph ?? ReminderSource.phone.glyph
        let timeText = activity.reminderDueDateRelativeDescription ?? NSLocalizedString(
            "scheduled",
            comment: "Reminder scheduled fallback"
        )
        return (glyph, timeText)
    }
}

#Preview {
    VStack(spacing: 12) {
        ActivityRowView(activity: PreviewData.sampleActivity)
        
        // Activity with location
        ActivityRowView(activity: {
            let caree = Caree(name: "Sample")
            let activityType = ActivityType(name: "Walk", icon: "🚶", hasLocation: true, caree: caree)
            return Activity(
                notes: "Great walk in the park",
                latitude: 37.7749,
                longitude: -122.4194,
                activityType: activityType,
                caree: caree
            )
        }())
    }
    .padding()
    .modelContainer(PreviewContainer.shared)
}
