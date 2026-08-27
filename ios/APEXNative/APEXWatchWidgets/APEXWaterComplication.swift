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
import Foundation
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
        let widgetHealthState = shared.flatMap(sharedHealthState)
        let resolvedShared = shared.map {
            HydrationWidgetStateResolver.resolve(
                canonical: $0,
                healthState: widgetHealthState
            )
        }
        let health = await todayHydration(
            ownerID: shared?.ownerID,
            queryAnchorData: resolvedShared?.healthQueryAnchorData
        )
        let source = HydrationComplicationRefreshPolicy.readingSource(
            hasSharedState: shared != nil,
            hasHealthData: health != nil
        )
        let totalML: Int
        let composition: [HydrationCompositionBand]
        switch source {
        case .sharedState:
            let reconciled: HydrationReconciledState
            if let shared, let health {
                let previousOverlay = resolvedShared?.healthOverlay ?? []
                let update = HydrationHealthReconciler.updatedHealthOverlay(
                    previousOverlay,
                    ownerID: shared.ownerID,
                    localDate: shared.localDate,
                    canonicalSampleIDs: Set(shared.canonicalSampleIDs ?? []),
                    anchor: resolvedShared?.healthAnchor,
                    current: health.samples,
                    deletedSampleIDs: health.deletedSampleIDs
                )
                reconciled = HydrationHealthReconciler.replacingOverlay(
                    previousOverlay,
                    with: update.mutations,
                    inTotalML: resolvedShared?.totalML ?? shared.totalML,
                    composition: resolvedShared?.composition ?? shared.composition
                )
                persistReconciledHealthState(
                    shared: shared,
                    health: health,
                    update: update,
                    reconciled: reconciled
                )
            } else {
                reconciled = HydrationReconciledState(
                    totalML: resolvedShared?.totalML ?? shared?.totalML ?? 0,
                    composition: resolvedShared?.composition ?? shared?.composition ?? []
                )
            }
            totalML = reconciled.totalML
            composition = reconciled.composition
        case .healthKit:
            totalML = health?.totalML ?? 0
            composition = health?.composition ?? []
        case .empty:
            totalML = 0
            composition = []
        }
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

    private static func sharedHealthState(
        matching state: HydrationWidgetState
    ) -> HydrationWidgetHealthState? {
        guard let data = UserDefaults(suiteName: HydrationWidgetStorage.suiteName)?
            .data(forKey: HydrationWidgetStorage.healthStateKey),
              let healthState = try? HydrationWidgetHealthState.decode(data),
              healthState.matches(state)
        else { return nil }
        return healthState
    }

    private struct HealthHydration {
        let totalML: Int
        let composition: [HydrationCompositionBand]
        let samples: [HydrationHealthSampleAnchor]
        let deletedSampleIDs: Set<UUID>
        let queryAnchorData: Data?
    }

    private struct AnchoredHealthChanges: Sendable {
        let deletedSampleIDs: Set<UUID>
        let queryAnchorData: Data?
    }

    private static func persistReconciledHealthState(
        shared: HydrationWidgetState,
        health: HealthHydration,
        update: HydrationHealthOverlayUpdate,
        reconciled: HydrationReconciledState
    ) {
        guard let defaults = UserDefaults(suiteName: HydrationWidgetStorage.suiteName),
              let latestData = defaults.data(forKey: HydrationWidgetStorage.stateKey),
              let latest = try? HydrationWidgetState.decode(latestData),
              latest.ownerID == shared.ownerID,
              latest.localDate == shared.localDate,
              latest.revision == shared.revision
        else { return }

        let updated = HydrationWidgetHealthState(
            ownerID: latest.ownerID,
            localDate: latest.localDate,
            baseRevision: latest.revision,
            totalML: reconciled.totalML,
            composition: reconciled.composition,
            healthAnchor: update.nextAnchor,
            healthQueryAnchorData: health.queryAnchorData ?? latest.healthQueryAnchorData,
            healthOverlay: update.mutations
        )
        if let data = try? updated.encoded() {
            defaults.set(data, forKey: HydrationWidgetStorage.healthStateKey)
        }
    }

    private static func todayHydration(
        ownerID: UUID?,
        queryAnchorData: Data?
    ) async -> HealthHydration? {
        guard HKHealthStore.isHealthDataAvailable(),
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return nil }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        do {
            let rawSamples = try await healthSamples(
                store: store,
                waterType: waterType,
                predicate: predicate
            )
            let healthChanges = try await anchoredHealthChanges(
                store: store,
                waterType: waterType,
                predicate: predicate,
                anchorData: queryAnchorData
            )

            struct Key: Hashable {
                let kind: HydrationKind
                let palette: String
                let icon: String
            }
            var totals: [Key: Int] = [:]
            var sampleAnchors: [HydrationHealthSampleAnchor] = []
            for sample in rawSamples {
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
                sampleAnchors.append(HydrationHealthSampleAnchor(
                    id: sample.uuid,
                    milliliters: milliliters,
                    kind: kind,
                    paletteToken: palette,
                    iconToken: icon
                ))
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
            return HealthHydration(
                totalML: composition.reduce(0) { $0 + $1.milliliters },
                composition: composition,
                samples: sampleAnchors,
                deletedSampleIDs: healthChanges.deletedSampleIDs,
                queryAnchorData: healthChanges.queryAnchorData
            )
        } catch {
            return nil
        }
    }

    private static func healthSamples(
        store: HKHealthStore,
        waterType: HKQuantityType,
        predicate: NSPredicate
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, rawSamples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: rawSamples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    private static func anchoredHealthChanges(
        store: HKHealthStore,
        waterType: HKQuantityType,
        predicate: NSPredicate,
        anchorData: Data?
    ) async throws -> AnchoredHealthChanges {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AnchoredHealthChanges, Error>) in
            let query = HKAnchoredObjectQuery(
                type: waterType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, _, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let encodedAnchor = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(
                        withRootObject: $0,
                        requiringSecureCoding: true
                    )
                }
                continuation.resume(returning: AnchoredHealthChanges(
                    deletedSampleIDs: Set((deletedObjects ?? []).map(\.uuid)),
                    queryAnchorData: encodedAnchor
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
