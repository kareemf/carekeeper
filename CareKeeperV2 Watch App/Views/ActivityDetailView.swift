import SwiftUI
import SwiftData
import MapKit

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let activityID: UUID
    @Query private var allActivities: [Activity]

    // Computed property to get the specific activity
    private var activity: Activity? {
        allActivities.first { $0.id == activityID }
    }

    init(activityID: UUID) {
        self.activityID = activityID
    }

    var body: some View {
        Group {
            if let activity = activity {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(for: activity)
                        detailsSection(for: activity)

                        if activity.hasLocation {
                            locationSection(for: activity)
                        }
                    }
                    .padding()
                }
                .navigationTitle(activity.activityType?.name ?? NSLocalizedString("Activity", comment: "Activity title"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text(NSLocalizedString("Activity not found", comment: "Activity not found message"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func headerSection(for activity: Activity) -> some View {
        VStack(spacing: 8) {
            Text(activity.activityType?.displayIcon ?? "⭐")
                .font(.system(size: 40))

            Text(activity.activityType?.name ?? NSLocalizedString("Unknown Activity", comment: "Unknown activity"))
                .font(.headline)

            Text(activity.formattedDateTime)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailsSection(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quantity section
            if let formattedQuantity = activity.formattedQuantity {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Quantity", comment: "Quantity section title"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedQuantity)
                        .font(.title3)
                }
            }

            // Notes section
            if let notes = activity.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Notes", comment: "Notes section title"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.body)
                }
            }
        }
    }

    @ViewBuilder
    private func locationSection(for activity: Activity) -> some View {
        if let location = activity.location {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Location", comment: "Location section title"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Map(position: .constant(.region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))) {
                    Marker("", coordinate: location.coordinate)
                }
                .frame(height: 120)
                .cornerRadius(8)

                Text(String(format: "%.6f, %.6f",
                           location.coordinate.latitude,
                           location.coordinate.longitude))
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ActivityDetailView(activityID: PreviewData.sampleActivity.id)
    }
    .modelContainer(PreviewContainer.shared)
}
