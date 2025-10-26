import SwiftUI
import MapKit

/// ActivityDetailView rebuilt with snapshots
/// Currently read-only for simplicity and stability
/// Edit functionality can be added later if needed
struct ActivityDetailView: View {

    let activitySnapshot: ActivitySnapshot

    @EnvironmentObject private var dataProvider: WatchDataProvider

    private var activityType: ActivityTypeSnapshot? {
        // Find activity type across all loaded carees
        for (_, types) in dataProvider.activityTypesByCaree {
            if let type = types.first(where: { $0.id == activitySnapshot.activityTypeID }) {
                return type
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with icon and name
                VStack(spacing: 8) {
                    Text(activityType?.icon ?? "⭐")
                        .font(.system(size: 50))

                    Text(activityType?.name ?? "Activity")
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Sync state if not synced
                    if activitySnapshot.syncState != .synced {
                        syncStateBadge
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()

                // Details sections
                detailsSection
                    .padding(.horizontal)

                if activitySnapshot.notes != nil || activitySnapshot.quantity != nil {
                    Divider()
                    additionalInfoSection
                        .padding(.horizontal)
                }

                if activitySnapshot.latitude != nil && activitySnapshot.longitude != nil {
                    Divider()
                    locationSection
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(Text(activitySnapshot.dateTime, style: .date))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var syncStateBadge: some View {
        HStack(spacing: 4) {
            switch activitySnapshot.syncState {
            case .pending:
                Image(systemName: "clock")
                Text("Pending")
            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Syncing...")
            case .failed(_):
                Image(systemName: "exclamationmark.triangle")
                Text("Failed")
            case .synced:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundColor(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.2))
        .cornerRadius(12)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time
            HStack {
                Label("Time", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(activitySnapshot.dateTime, style: .time)
                    .font(.body)
            }

            // Date
            HStack {
                Label("Date", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(activitySnapshot.dateTime, style: .date)
                    .font(.body)
            }
        }
    }

    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quantity
            if let quantity = activitySnapshot.quantity {
                HStack {
                    Label("Quantity", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let unit = activityType?.quantityUnit {
                        Text("\(String(format: "%.1f", quantity)) \(unit)")
                            .font(.body)
                    } else {
                        Text(String(format: "%.1f", quantity))
                            .font(.body)
                    }
                }
            }

            // Notes
            if let notes = activitySnapshot.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Notes", systemImage: "note.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        if let latitude = activitySnapshot.latitude,
           let longitude = activitySnapshot.longitude {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location", systemImage: "location")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Map(initialPosition: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )) {
                    Marker("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
                .frame(height: 120)
                .cornerRadius(8)

                Text("Lat: \(String(format: "%.6f", latitude)), Lon: \(String(format: "%.6f", longitude))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    let activity = ActivitySnapshot(
        dateTime: Date(),
        notes: "Sample notes",
        quantity: 8.0,
        latitude: 37.7749,
        longitude: -122.4194,
        activityTypeID: UUID(),
        careeID: UUID()
    )

    return NavigationStack {
        ActivityDetailView(activitySnapshot: activity)
            .environmentObject(WatchDataProvider())
    }
}
