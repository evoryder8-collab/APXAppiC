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

enum WaterDisplayMode: String, AppEnum {
    case percent
    case liters
    case gallons
    case progress

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Hydration display" }
    static var caseDisplayRepresentations: [WaterDisplayMode: DisplayRepresentation] {
        [
            .percent: "Percent",
            .liters: "Litres",
            .gallons: "US gallons",
            .progress: "Progress only",
        ]
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
    let targetLiters: Double
    let displayMode: WaterDisplayMode
    let composition: [HydrationCompositionBand]

    var progress: Double { min(1, max(0, liters / targetLiters)) }
    var shortText: String {
        switch displayMode {
        case .percent: return "\(Int((progress * 100).rounded()))%"
        case .liters: return "\(String(format: "%.2f", liters)) L"
        case .gallons: return "\(String(format: "%.2f", liters * 0.264_172_052)) gal"
        case .progress: return ""
        }
    }
    var detailText: String {
        switch displayMode {
        case .percent:
            return "\(String(format: "%.2f", liters)) of \(String(format: "%.2f", targetLiters)) L"
        case .liters:
            return "of \(String(format: "%.2f", targetLiters)) L today"
        case .gallons:
            return "of \(String(format: "%.2f", targetLiters * 0.264_172_052)) gal"
        case .progress:
            return "\(Int((progress * 100).rounded()))% hydrated"
        }
    }
}

struct WaterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(
            date: Date(), liters: 1.5, targetLiters: 3.0, displayMode: .percent,
            composition: [
                HydrationCompositionBand(
                    kind: .water, paletteToken: "aqua", iconToken: "drop.fill", milliliters: 1_000
                ),
                HydrationCompositionBand(
                    kind: .coffee, paletteToken: "espresso", iconToken: "cup.and.saucer.fill", milliliters: 500
                ),
            ]
        )
    }

    func snapshot(for configuration: WaterConfigurationIntent, in context: Context) async -> WaterEntry {
        await Self.entry(for: configuration)
    }

    func timeline(for configuration: WaterConfigurationIntent, in context: Context) async -> Timeline<WaterEntry> {
        let entry = await Self.entry(for: configuration)
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

    private static func entry(for configuration: WaterConfigurationIntent) async -> WaterEntry {
        let shared = sharedState()
        let health = await todayHydration(ownerID: shared?.ownerID)
        let totalML = health?.totalML ?? shared?.totalML ?? 0
        let composition = health?.composition ?? shared?.composition ?? []
        return WaterEntry(
            date: Date(),
            liters: Double(totalML) / 1_000,
            targetLiters: Double(shared?.targetML ?? 2_750) / 1_000,
            displayMode: configuration.displayMode ?? .percent,
            composition: composition
        )
    }

    private static func sharedState() -> HydrationWidgetState? {
        guard let data = UserDefaults(suiteName: HydrationWidgetStorage.suiteName)?
            .data(forKey: HydrationWidgetStorage.stateKey),
              let state = try? HydrationWidgetState.decode(data),
              state.localDate == Date().apexDateKey
        else { return nil }
        return state
    }

    private struct HealthHydration {
        let totalML: Int
        let composition: [HydrationCompositionBand]
    }

    private static func todayHydration(ownerID: UUID?) async -> HealthHydration? {
        guard HKHealthStore.isHealthDataAvailable(),
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return nil }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<HealthHydration?, Never>) in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, rawSamples, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                struct Key: Hashable {
                    let kind: HydrationKind
                    let palette: String
                    let icon: String
                }
                var totals: [Key: Int] = [:]
                for sample in rawSamples as? [HKQuantitySample] ?? [] {
                    if let rawOwner = sample.metadata?[HydrationMetadata.ownerID] as? String,
                       let sampleOwner = UUID(uuidString: rawOwner),
                       let ownerID,
                       sampleOwner != ownerID {
                        continue
                    }
                    let milliliters = Int(max(0, sample.quantity.doubleValue(
                        for: .literUnit(with: .milli)
                    )).rounded())
                    guard milliliters > 0 else { continue }
                    let kind = (sample.metadata?[HydrationMetadata.kind] as? String)
                        .flatMap(HydrationKind.init(rawValue:)) ?? .external
                    let palette = sample.metadata?[HydrationMetadata.palette] as? String
                        ?? (kind == .external ? "external" : "aqua")
                    let icon = sample.metadata?[HydrationMetadata.icon] as? String
                        ?? (kind == .external ? "heart.fill" : "drop.fill")
                    totals[Key(kind: kind, palette: palette, icon: icon), default: 0] += milliliters
                }
                let order: [HydrationKind] = [
                    .water, .coffee, .tea, .juice, .shake, .other, .external, .legacy, .food,
                ]
                let composition = totals.map { key, amount in
                    HydrationCompositionBand(
                        kind: key.kind,
                        paletteToken: key.palette,
                        iconToken: key.icon,
                        milliliters: amount
                    )
                }.sorted {
                    let lhs = order.firstIndex(of: $0.kind) ?? order.count
                    let rhs = order.firstIndex(of: $1.kind) ?? order.count
                    return (lhs, $0.paletteToken) < (rhs, $1.paletteToken)
                }
                continuation.resume(returning: HealthHydration(
                    totalML: composition.reduce(0) { $0 + $1.milliliters },
                    composition: composition
                ))
            }
            store.execute(query)
        }
    }
}

private func hydrationComplicationColor(_ token: String) -> Color {
    switch token {
    case "espresso": return Color(red: 0.46, green: 0.25, blue: 0.12)
    case "tea": return Color(red: 0.20, green: 0.68, blue: 0.42)
    case "citrus": return Color(red: 1.00, green: 0.55, blue: 0.08)
    case "cocoa": return Color(red: 0.60, green: 0.36, blue: 0.22)
    case "violet": return Color(red: 0.55, green: 0.34, blue: 0.94)
    case "food": return Color(red: 0.13, green: 0.76, blue: 0.65)
    case "external": return Color(red: 0.43, green: 0.55, blue: 0.76)
    case "legacy": return Color(red: 0.35, green: 0.65, blue: 0.93)
    default: return Color(red: 0.10, green: 0.74, blue: 0.94)
    }
}

private struct CompositionProgressBar: View {
    let progress: Double
    let composition: [HydrationCompositionBand]

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, composition.reduce(0) { $0 + $1.milliliters })
            let width = proxy.size.width * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(.secondary.opacity(0.45), lineWidth: 1.4)
                HStack(spacing: 0) {
                    ForEach(Array(composition.enumerated()), id: \.offset) { _, band in
                        hydrationComplicationColor(band.paletteToken)
                            .frame(width: width * Double(band.milliliters) / Double(total))
                    }
                }
                .frame(width: width, alignment: .leading)
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}

private struct CompositionRing: View {
    let entry: WaterEntry
    let showsValue: Bool

    private var colors: [Color] {
        let colors = entry.composition.map { hydrationComplicationColor($0.paletteToken) }
        return colors.isEmpty ? [hydrationComplicationColor("aqua")] : colors
    }

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.32), lineWidth: 5)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsValue {
                Text(entry.shortText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
            } else {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(colors[0])
            }
        }
    }
}

struct APEXWaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CompositionRing(entry: entry, showsValue: entry.displayMode != .progress)

        case .accessoryCorner:
            Text(entry.shortText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: entry.progress) { Text("H2O") }
                        .tint(Gradient(colors: [.cyan, .blue]))
                }

        case .accessoryInline:
            Label(
                entry.displayMode == .progress
                    ? entry.detailText
                    : "\(entry.shortText) · \(entry.detailText)",
                systemImage: "drop.fill"
            )

        case .accessoryRectangular:
            HStack(spacing: 9) {
                CompositionRing(entry: entry, showsValue: entry.displayMode != .progress)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("APEX WATER")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                    if entry.displayMode != .progress {
                        Text(entry.shortText)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text(entry.detailText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    CompositionProgressBar(progress: entry.progress, composition: entry.composition)
                }
                Spacer(minLength: 0)
            }

        default:
            CompositionRing(entry: entry, showsValue: entry.displayMode != .progress)
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
