import Foundation

struct WatchHydrationFillState: Equatable, Sendable {
    let liters: Double
    let targetLiters: Double

    var progress: Double {
        guard targetLiters.isFinite, targetLiters > 0, liters.isFinite else { return 0 }
        return min(1, max(0, liters / targetLiters))
    }

    var baseWaterline: Double { 1 - progress }

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
