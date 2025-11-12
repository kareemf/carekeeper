import SwiftData
import SwiftUI
import WidgetKit

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
                .accessoryCorner,
            ])
        #else
                .supportedFamilies([
                    .systemSmall,
                    .accessoryCircular,
                    .accessoryRectangular,
                    .accessoryInline,
                ])
        #endif
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = SimpleEntry(date: Date())

        // Update once per day (widget is just a launcher, no dynamic data)
        let nextUpdate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }
}

// MARK: - Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
}

// MARK: - Views

struct CareKeeperWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SystemSmallView(entry: entry)
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
            Image(systemName: "heart.fill")
                .font(.title2)
        }
    }
}

struct RectangularView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack {
            Image(systemName: "heart.fill")
                .font(.title3)
            Text("CareKeeper")
                .font(.body)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            Text("CareKeeper")
        }
    }
}

struct CornerView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "heart.fill")
                .font(.caption)
        }
    }
}

struct SystemSmallView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.85))

            VStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Text("CareKeeper")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .multilineTextAlignment(.center)
            .padding()
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .accessoryInline) {
    CareKeeperWidget()
} timeline: {
    SimpleEntry(date: .now)
}
