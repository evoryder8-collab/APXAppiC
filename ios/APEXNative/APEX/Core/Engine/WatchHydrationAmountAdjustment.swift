import Foundation

/// A deliberate horizontal scrub: ten millilitres per eight points, with no inertia.
/// Vertical drags stay vertical for their entire lifetime so scrolling cannot edit water.
struct WatchHydrationAmountAdjustment {
    static let range = 50...3_000
    static let step = 10
    private static let pointsPerStep = 8.0

    private var isHorizontal: Bool?
    private var lastTranslation = 0.0
    private var remainder = 0.0

    mutating func update(current: Int, horizontal: Double, vertical: Double) -> Int {
        guard horizontal.isFinite, vertical.isFinite else { return current }
        if isHorizontal == nil {
            guard max(abs(horizontal), abs(vertical)) >= Self.pointsPerStep else { return current }
            isHorizontal = abs(horizontal) > abs(vertical) * 1.2
        }
        guard isHorizontal == true else { return current }

        remainder += horizontal - lastTranslation
        lastTranslation = horizontal
        // Real touch distances are small; bound input before converting to Int as well.
        let steps = Int(max(-300, min(300, remainder / Self.pointsPerStep)))
        guard steps != 0 else { return current }
        remainder -= Double(steps) * Self.pointsPerStep
        let result = Self.clamped(current + steps * Self.step)
        if result == Self.range.lowerBound || result == Self.range.upperBound {
            // Reversing at an edge responds immediately, even after a long overshoot.
            remainder = 0
        }
        return result
    }

    static func clamped(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
