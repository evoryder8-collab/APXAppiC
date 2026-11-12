import SwiftUI
import WidgetKit

enum WaterDisplayMode: String, CaseIterable, Sendable {
    case percent
    case liters
    case gallons
    case progress
}

struct WaterEntry: TimelineEntry {
    let date: Date
    let liters: Double
    let targetLiters: Double
    let displayMode: WaterDisplayMode
    let composition: [HydrationCompositionBand]

    var progress: Double { targetLiters > 0 ? min(1, max(0, liters / targetLiters)) : 0 }
    var reachedGoal: Bool { progress >= 1 }

    /// Whole percent that reads 100 only once the goal is reached, as in the Watch app.
    var percent: Int { reachedGoal ? 100 : min(99, Int((progress * 100).rounded(.down))) }

    private static let gallonsPerLiter = 0.264_172_052

    private func amount(_ liters: Double) -> String {
        displayMode == .gallons
            ? String(format: "%.2f", liters * Self.gallonsPerLiter)
            : String(format: "%.2f", liters)
    }

    private var unit: String { displayMode == .gallons ? "gal" : "L" }

    /// The headline figure and its unit, kept apart so the unit can sit smaller beside it.
    var headline: (value: String, unit: String) {
        switch displayMode {
        case .percent, .progress: ("\(percent)", "%")
        case .liters, .gallons: (amount(liters), unit)
        }
    }

    var shortText: String {
        switch displayMode {
        case .percent: "\(percent)%"
        case .liters, .gallons: "\(amount(liters))\u{00A0}\(unit)"
        case .progress: ""
        }
    }

    var detailText: String {
        if reachedGoal { return "Goal reached" }
        switch displayMode {
        case .percent: return "\(amount(liters)) of \(amount(targetLiters))\u{00A0}\(unit)"
        case .liters, .gallons: return "\(percent)% of \(amount(targetLiters))\u{00A0}\(unit)"
        case .progress: return "\(percent)% hydrated"
        }
    }

    var inlineText: String {
        switch displayMode {
        case .percent: "\(percent)%, \(amount(liters)) of \(amount(targetLiters))\u{00A0}\(unit)"
        case .liters, .gallons: "\(amount(liters)) of \(amount(targetLiters))\u{00A0}\(unit)"
        case .progress: reachedGoal ? "Goal reached" : "\(percent)% hydrated"
        }
    }
}

private func hydrationComplicationColor(_ token: String) -> Color {
    switch token {
    case "espresso": Color(red: 0.62, green: 0.36, blue: 0.18)
    case "tea": Color(red: 0.20, green: 0.74, blue: 0.46)
    case "citrus": Color(red: 1.00, green: 0.55, blue: 0.08)
    case "cocoa": Color(red: 0.68, green: 0.42, blue: 0.26)
    case "violet": Color(red: 0.60, green: 0.40, blue: 0.98)
    case "food": Color(red: 0.13, green: 0.76, blue: 0.65)
    case "external": Color(red: 0.43, green: 0.55, blue: 0.76)
    case "legacy": Color(red: 0.35, green: 0.65, blue: 0.93)
    default: Color(red: 0.10, green: 0.80, blue: 0.96)
    }
}

private extension WaterEntry {
    /// The day's drinks in the order they are stacked, first at the bottom; plain water when nothing is logged.
    var drinkColors: [Color] {
        let colors = composition.map { hydrationComplicationColor($0.paletteToken) }
        return colors.isEmpty ? [hydrationComplicationColor("aqua")] : colors
    }

    /// Bottom-to-top stops sized by how much of each drink there is.
    var drinkStops: [Gradient.Stop] {
        let total = Double(max(1, composition.reduce(0) { $0 + $1.milliliters }))
        var reached = 0.0
        var stops: [Gradient.Stop] = []
        for band in composition {
            let color = hydrationComplicationColor(band.paletteToken)
            let next = reached + Double(band.milliliters) / total
            // A short blend between neighbours, so the drinks read as layers in one liquid.
            stops.append(.init(color: color, location: min(next, reached + 0.04)))
            stops.append(.init(color: color, location: max(reached, next - 0.04)))
            reached = next
        }
        return stops.isEmpty ? [.init(color: drinkColors[0], location: 0)] : stops
    }
}

/// The body in glass, filled from the feet with the day's drinks.
struct WaterFigure: View {
    let entry: WaterEntry

    var body: some View {
        GeometryReader { proxy in
            let level = proxy.size.height * (1 - entry.progress)
            ZStack {
                WaterFigureShape().fill(.white.opacity(0.14))
                Rectangle()
                    .fill(LinearGradient(stops: entry.drinkStops, startPoint: .bottom, endPoint: .init(x: 0.5, y: 1 - max(entry.progress, 0.01))))
                    .overlay(alignment: .top) {
                        // The surface catches the light.
                        Rectangle().fill(.white.opacity(0.75)).frame(height: 1.2).offset(y: level)
                    }
                    .mask(alignment: .bottom) { Rectangle().frame(height: proxy.size.height * entry.progress) }
                    .mask { WaterFigureShape() }
                    .widgetAccentable()
                WaterFigureShape().stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
        }
        .aspectRatio(WaterFigureShape.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct WaterRing: View {
    let entry: WaterEntry
    var lineWidth: CGFloat = 5

    var body: some View {
        let colors = entry.drinkColors
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(entry.progress, 0.004))
                .stroke(
                    AngularGradient(
                        colors: colors + [colors[colors.count - 1]], center: .center,
                        startAngle: .zero, endAngle: .degrees(360 * max(entry.progress, 0.05))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

private struct WaterBar: View {
    let entry: WaterEntry

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(stops: entry.drinkStops, startPoint: .leading, endPoint: .trailing))
                    .frame(width: entry.progress > 0 ? max(proxy.size.height, proxy.size.width * entry.progress) : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: 5)
    }
}

/// One complication, drawn for the family it is asked for.
struct WaterComplicationContent: View {
    let family: WidgetFamily
    let entry: WaterEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            Text(entry.displayMode == .progress ? "\(entry.percent)%" : entry.shortText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: entry.progress) { Text("Water") }
                        .tint(Gradient(colors: entry.drinkColors + [entry.drinkColors[entry.drinkColors.count - 1]]))
                }
        case .accessoryInline:
            Label(entry.inlineText, systemImage: "drop.fill")
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private var circular: some View {
        ZStack {
            WaterRing(entry: entry)
            if entry.displayMode == .progress {
                WaterFigure(entry: entry).padding(.vertical, 9)
            } else {
                VStack(spacing: -2) {
                    ViewThatFits(in: .horizontal) {
                        ForEach([15, 13, 11], id: \.self) { size in
                            Text(entry.headline.value)
                                .font(.system(size: CGFloat(size), weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    Text(entry.headline.unit)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydration")
        .accessibilityValue(entry.inlineText)
    }

    private var rectangular: some View {
        HStack(spacing: 10) {
            WaterFigure(entry: entry)
            VStack(alignment: .leading, spacing: 2) {
                // "Progress only" keeps to one quiet line; the other styles lead with their number.
                if entry.displayMode != .progress {
                    (Text(entry.headline.value).font(.system(size: 25, weight: .bold, design: .rounded))
                        + Text("\u{00A0}" + entry.headline.unit).font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(entry.drinkColors[entry.drinkColors.count - 1]))
                        .monospacedDigit()
                        .lineLimit(1)
                        .widgetAccentable()
                }
                Text(entry.detailText)
                    .font(.system(size: entry.displayMode == .progress ? 15 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry.reachedGoal || entry.displayMode == .progress ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                WaterBar(entry: entry).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydration")
        .accessibilityValue(entry.inlineText)
    }
}

#if DEBUG
/// Draws the complications at watch-face size inside the Watch app, so their pixels can be checked without a face.
struct WaterComplicationGallery: View {
    private func entry(_ liters: Double, _ mode: WaterDisplayMode) -> WaterEntry {
        WaterEntry(
            date: .now, liters: liters, targetLiters: 2.75, displayMode: mode,
            composition: liters <= 0 ? [] : [
                HydrationCompositionBand(kind: .water, paletteToken: "aqua", iconToken: "drop.fill", milliliters: Int(liters * 620)),
                HydrationCompositionBand(kind: .coffee, paletteToken: "espresso", iconToken: "cup.and.saucer.fill", milliliters: Int(liters * 190)),
                HydrationCompositionBand(kind: .shake, paletteToken: "violet", iconToken: "waterbottle.fill", milliliters: Int(liters * 190)),
            ]
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(Array([(1.4, WaterDisplayMode.percent), (1.4, .liters), (1.4, .progress), (2.9, .progress)].enumerated()), id: \.offset) { _, item in
                        WaterComplicationContent(family: .accessoryCircular, entry: entry(item.0, item.1))
                            .frame(width: 44, height: 44)
                    }
                }
                ForEach(Array([(0.0, WaterDisplayMode.liters), (1.4, .liters), (2.2, .percent), (2.9, .liters), (1.4, .progress)].enumerated()), id: \.offset) { _, item in
                    WaterComplicationContent(family: .accessoryRectangular, entry: entry(item.0, item.1))
                        .frame(width: 176, height: 62)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(.black)
    }
}
#endif
