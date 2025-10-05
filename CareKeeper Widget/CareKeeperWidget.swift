import WidgetKit
import SwiftUI
import SwiftData

struct CareKeeperWidget: Widget {
    let kind: String = "CareKeeperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CareKeeperWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CareKeeper")
        .description("Quick access to track activities")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), careeCount: 2, todayActivities: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), careeCount: 2, todayActivities: 5)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Fetch data from shared app group
        let entry = fetchCurrentData()

        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func fetchCurrentData() -> SimpleEntry {
        // Try to read from app group container
        // This would require accessing the shared ModelContainer
        // For now, return placeholder data
        return SimpleEntry(date: Date(), careeCount: 0, todayActivities: 0)
    }
}

// MARK: - Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let careeCount: Int
    let todayActivities: Int
}

// MARK: - Views

struct CareKeeperWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryCorner:
            CornerView(entry: entry)
        default:
            Text("CK")
        }
    }
}

struct CircularView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                Text("\(entry.todayActivities)")
                    .font(.caption2)
            }
        }
    }
}

struct RectangularView: View {
    let entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.caption)
                Text("CareKeeper")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("\(entry.todayActivities)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("activities today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            Text("\(entry.todayActivities) activities")
        }
    }
}

struct CornerView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                Text("\(entry.todayActivities)")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now, careeCount: 2, todayActivities: 5)
    SimpleEntry(date: .now, careeCount: 2, todayActivities: 8)
}

#Preview(as: .accessoryRectangular) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now, careeCount: 2, todayActivities: 5)
}

#Preview(as: .accessoryInline) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now, careeCount: 2, todayActivities: 5)
}
