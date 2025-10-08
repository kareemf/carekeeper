import WidgetKit
import SwiftUI
import SwiftData
import CoreData

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
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(CloudKitConfig.appGroupID),
            cloudKitDatabase: .private(CloudKitConfig.containerID)
        )

        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            return SimpleEntry(date: Date(), careeCount: 0, todayActivities: 0)
        }

        let context = ModelContext(container)

        // Aggregate counts via Core Data bridge for performance.
        let careeCount = aggregateCount(entityName: "Caree", in: context) ?? 0

        // Today’s activities using a date predicate on Activity.dateTime
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let todayActivities = aggregateCount(
            entityName: "Activity",
            in: context,
            dateKey: "dateTime",
            from: startOfDay,
            to: startOfTomorrow
        ) ?? 0

        return SimpleEntry(date: Date(), careeCount: careeCount, todayActivities: todayActivities)
    }

    // MARK: - Aggregate helpers (SwiftData -> Core Data bridge)

    private func aggregateCount(entityName: String, in modelContext: ModelContext) -> Int? {
        guard let nsContext = (modelContext as AnyObject).value(forKey: "nsContext") as? NSManagedObjectContext else {
            return nil
        }

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType

        let countExpression = NSExpressionDescription()
        countExpression.name = "count"
        countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "self")])
        countExpression.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [countExpression]
        request.includesSubentities = true

        do {
            if let result = try nsContext.fetch(request).first,
               let count = result["count"] as? NSNumber {
                return count.intValue
            }
        } catch {
            // In widget process, avoid heavy logging; return nil on failure.
            return nil
        }

        return nil
    }

    private func aggregateCount(entityName: String,
                                in modelContext: ModelContext,
                                dateKey: String,
                                from start: Date,
                                to end: Date) -> Int? {
        guard let nsContext = (modelContext as AnyObject).value(forKey: "nsContext") as? NSManagedObjectContext else {
            return nil
        }

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType

        // dateKey BETWEEN {start, end}
        request.predicate = NSPredicate(format: "%K >= %@ AND %K < %@", dateKey as NSString, start as NSDate, dateKey as NSString, end as NSDate)

        let countExpression = NSExpressionDescription()
        countExpression.name = "count"
        countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "self")])
        countExpression.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [countExpression]
        request.includesSubentities = true

        do {
            if let result = try nsContext.fetch(request).first,
               let count = result["count"] as? NSNumber {
                return count.intValue
            }
        } catch {
            return nil
        }

        return nil
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
