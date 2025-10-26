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
        #if os(watchOS)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
        #else
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        #endif
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), careeCount: 2, todayActivities: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        // In previews, return a quick snapshot without touching disk.
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        let entry = fetchCurrentData()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = fetchCurrentData()

        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func fetchCurrentData() -> SimpleEntry {
        let schema = Schema([Caree.self, ActivityType.self, Activity.self])

        // Read from the local-only cache container (same as watch app)
        // The cache is populated by CloudKit services in the main app
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(CloudKitConfig.appGroupID)
            // Intentionally omit cloudKitDatabase - widget reads from local cache only
        )

        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            return SimpleEntry(date: Date(), careeCount: 0, todayActivities: 0)
        }

        let context = ModelContext(container)

        // Count Carees via SwiftData fetch
        let careeCount: Int = {
            do {
                let descriptor = FetchDescriptor<Caree>()
                let carees = try context.fetch(descriptor)
                return carees.count
            } catch {
                return 0
            }
        }()

        // Today’s activities using a SwiftData predicate on Activity.dateTime
        let todayActivities: Int = {
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

            let predicate = #Predicate<Activity> { activity in
                activity.dateTime >= startOfDay && activity.dateTime < startOfTomorrow
            }

            do {
                var descriptor = FetchDescriptor<Activity>(predicate: predicate)
                // We only need the count; avoid heavy sort/relationships
                descriptor.fetchLimit = 0 // fetch all; counting after fetch
                let activities = try context.fetch(descriptor)
                return activities.count
            } catch {
                return 0
            }
        }()

        return SimpleEntry(date: Date(), careeCount: careeCount, todayActivities: todayActivities)
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
        #if os(watchOS)
        case .accessoryCorner:
            CornerView(entry: entry)
        #endif
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
