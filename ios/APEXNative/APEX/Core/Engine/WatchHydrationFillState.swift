import Foundation

struct WatchHydrationFillState: Equatable, Sendable {
    let liters: Double
    let targetLiters: Double

    var progress: Double {
        guard targetLiters.isFinite, targetLiters > 0, liters.isFinite else { return 0 }
        return min(1, max(0, liters / targetLiters))
    }

    var baseWaterline: Double { 1 - progress }

    var primaryAmount: String {
        "\(liters.formatted(.number.precision(.fractionLength(2)))) L"
    }

    static func waterline(
        progress rawProgress: Double,
        normalizedX rawX: Double,
        phase: Double
    ) -> Double {
        let progress = min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
        let x = min(1, max(0, rawX.isFinite ? rawX : 0))
        let amplitude = min(0.018, progress * 0.08, (1 - progress) * 0.08)
        let wave = sin((x * .pi * 2) + phase) * amplitude
        return min(1, max(0, (1 - progress) + wave))
    }
}

struct HydrationCompositionStop: Equatable, Sendable {
    let paletteToken: String
    let location: Double
}

enum HydrationCompositionLayout {
    private static let maximumTransitionHalfWidth = 0.0023

    static func stops(
        for bands: [HydrationCompositionBand],
        mappedInto range: ClosedRange<Double> = 0 ... 1
    ) -> [HydrationCompositionStop] {
        let populated = bands.filter { $0.milliliters > 0 }
        guard !populated.isEmpty else { return [] }

        let lower = min(1, max(0, range.lowerBound.isFinite ? range.lowerBound : 0))
        let upper = min(1, max(lower, range.upperBound.isFinite ? range.upperBound : 1))
        let span = upper - lower

        let coalesced = populated.reduce(into: [(paletteToken: String, milliliters: Int)]()) {
            result, band in
            if result.last?.paletteToken == band.paletteToken {
                result[result.count - 1].milliliters += band.milliliters
            } else {
                result.append((band.paletteToken, band.milliliters))
            }
        }
        guard let first = coalesced.first, let last = coalesced.last else { return [] }
        guard coalesced.count > 1 else {
            return [
                HydrationCompositionStop(paletteToken: first.paletteToken, location: lower),
                HydrationCompositionStop(paletteToken: first.paletteToken, location: upper),
            ]
        }

        let total = Double(coalesced.reduce(0) { $0 + $1.milliliters })
        var stops = [HydrationCompositionStop(paletteToken: first.paletteToken, location: lower)]
        var cumulative = 0.0

        for index in 0 ..< (coalesced.count - 1) {
            let current = coalesced[index]
            let next = coalesced[index + 1]
            cumulative += Double(current.milliliters)

            let boundary = cumulative / total
            let currentShare = Double(current.milliliters) / total
            let nextShare = Double(next.milliliters) / total
            let transitionHalfWidth = min(
                maximumTransitionHalfWidth,
                currentShare * 0.092,
                nextShare * 0.092
            )

            stops.append(
                HydrationCompositionStop(
                    paletteToken: current.paletteToken,
                    location: lower + ((boundary - transitionHalfWidth) * span)
                )
            )
            stops.append(
                HydrationCompositionStop(
                    paletteToken: next.paletteToken,
                    location: lower + ((boundary + transitionHalfWidth) * span)
                )
            )
        }

        stops.append(HydrationCompositionStop(paletteToken: last.paletteToken, location: upper))
        return stops
    }
}

enum WatchHydrationAnimationPolicy {
    static func shouldAnimate(
        sceneIsActive: Bool,
        luminanceIsReduced: Bool,
        reduceMotion: Bool
    ) -> Bool {
        sceneIsActive && !luminanceIsReduced && !reduceMotion
    }
}

enum WatchHydrationAuthorship {
    static let phoneBundleIdentifier = "ch.apexperformance.APEX"
    static let watchBundleIdentifier = "ch.apexperformance.APEX.watchkitapp"
    static let watchSyncIdentifierPrefix = "apex.hydration.watch."

    static func canDelete(
        sourceBundleIdentifier: String,
        syncIdentifier: String? = nil
    ) -> Bool {
        if sourceBundleIdentifier == watchBundleIdentifier { return true }
        return sourceBundleIdentifier == phoneBundleIdentifier
            && syncIdentifier?.hasPrefix(watchSyncIdentifierPrefix) == true
    }
}

enum WatchHydrationDisplayMode: String, CaseIterable, Sendable {
    case percent
    case liters
    case gallons

    func shortValue(for state: WatchHydrationFillState) -> String {
        switch self {
        case .percent:
            return "\(Int((state.progress * 100).rounded()))%"
        case .liters:
            return "\(state.liters.formatted(.number.precision(.fractionLength(2))))L"
        case .gallons:
            let gallons = state.liters * 0.264_172_052
            return "\(gallons.formatted(.number.precision(.fractionLength(2))))gal"
        }
    }
}
