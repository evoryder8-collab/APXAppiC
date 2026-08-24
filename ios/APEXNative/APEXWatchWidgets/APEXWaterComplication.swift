/*
 * APEX Water complications for the watch face. Reads today's dietary
 * water straight from HealthKit so the ring is current even when the
 * watch app has not been opened, and tapping any family launches the
 * app for a one-tap log.
 *
 * Uses the async AppIntent timeline provider: under Swift 6 strict
 * concurrency the older completion-handler provider cannot hand its
 * callback to an async HealthKit query without a data race.
 */
import AppIntents
import HealthKit
import SwiftUI
import WidgetKit

private let targetLiters = 2.75

enum WaterDisplayMode: String, AppEnum {
    case percent
    case liters
    case gallons

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Hydration display" }
    static var caseDisplayRepresentations: [WaterDisplayMode: DisplayRepresentation] {
        [
            .percent: "Percent",
            .liters: "Litres",
            .gallons: "US gallons",
        ]
    }

    var sharedMode: WatchHydrationDisplayMode {
        WatchHydrationDisplayMode(rawValue: rawValue) ?? .percent
    }
}

struct WaterConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "APEX Water" }
    static var description: IntentDescription { "Today's hydration against your target." }

    @Parameter(title: "Show")
    var displayMode: WaterDisplayMode?

    init() {
        displayMode = .percent
    }
}

struct WaterEntry: TimelineEntry {
    let date: Date
    let liters: Double
    let displayMode: WaterDisplayMode

    var progress: Double { min(1, max(0, liters / targetLiters)) }
    var shortText: String {
        displayMode.sharedMode.shortValue(
            for: WatchHydrationFillState(liters: liters, targetLiters: targetLiters)
        )
    }
    var detailText: String {
        switch displayMode {
        case .percent:
            return "\(String(format: "%.2f", liters)) of \(String(format: "%.2f", targetLiters)) L"
        case .liters:
            return "of \(String(format: "%.2f", targetLiters)) L today"
        case .gallons:
            return "of \(String(format: "%.2f", targetLiters * 0.264_172_052)) gal today"
        }
    }
}

struct WaterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(date: Date(), liters: 1.5, displayMode: .percent)
    }

    func snapshot(for configuration: WaterConfigurationIntent, in context: Context) async -> WaterEntry {
        WaterEntry(
            date: Date(),
            liters: await Self.todayLiters(),
            displayMode: configuration.displayMode ?? .percent
        )
    }

    func timeline(for configuration: WaterConfigurationIntent, in context: Context) async -> Timeline<WaterEntry> {
        let entry = WaterEntry(
            date: Date(),
            liters: await Self.todayLiters(),
            displayMode: configuration.displayMode ?? .percent
        )
        /* Refresh on the half hour. Logging from the watch app or the phone
           also reloads timelines directly. */
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    /* Offered in the watch-face complication gallery. */
    func recommendations() -> [AppIntentRecommendation<WaterConfigurationIntent>] {
        WaterDisplayMode.allCases.map { mode in
            let intent = WaterConfigurationIntent()
            intent.displayMode = mode
            return AppIntentRecommendation(intent: intent, description: "APEX Water · \(mode.rawValue)")
        }
    }

    private static func todayLiters() async -> Double {
        guard HKHealthStore.isHealthDataAvailable(),
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return 0 }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double, Never>) in
            let query = HKStatisticsQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .liter()) ?? 0
                continuation.resume(returning: max(0, value))
            }
            store.execute(query)
        }
    }
}

struct APEXWaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(entry.shortText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.cyan, .blue]))

        case .accessoryCorner:
            Text(entry.shortText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: entry.progress) { Text("H2O") }
                        .tint(Gradient(colors: [.cyan, .blue]))
                }

        case .accessoryInline:
            Label("\(entry.shortText) · \(entry.detailText)", systemImage: "drop.fill")

        case .accessoryRectangular:
            HStack(spacing: 10) {
                Gauge(value: entry.progress) {
                    Image(systemName: "drop.fill")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.cyan, .blue]))
                VStack(alignment: .leading, spacing: 1) {
                    Text("APEX WATER")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text(entry.shortText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(entry.detailText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    ProgressView(value: entry.progress)
                        .tint(.cyan)
                }
                Spacer(minLength: 0)
            }

        default:
            Gauge(value: entry.progress) { Image(systemName: "drop.fill") }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.cyan, .blue]))
        }
    }
}

@main
struct APEXWaterComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ch.apexperformance.APEX.water",
            intent: WaterConfigurationIntent.self,
            provider: WaterProvider()
        ) { entry in
            APEXWaterComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("APEX Water")
        .description("Today's hydration against your target.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}
