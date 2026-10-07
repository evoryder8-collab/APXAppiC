import Foundation

// Run with the production policy, without launching an app or writing Health samples:
// swiftc APEX/Core/Engine/WatchHydrationAmountAdjustment.swift Tools/test-watch-water-scrub.swift -o /tmp/apex-water-scrub-tests
@main
struct WatchWaterScrubChecks {
    static func main() {
        var scrub = WatchHydrationAmountAdjustment()
        expect(scrub.update(current: 350, horizontal: 7, vertical: 0), 350, "touch slop")
        expect(scrub.update(current: 350, horizontal: 8, vertical: 0), 360, "first right step")
        expect(scrub.update(current: 360, horizontal: 24, vertical: 0), 380, "cumulative drag")
        expect(scrub.update(current: 380, horizontal: 16, vertical: 0), 370, "reverse while dragging")
        expect(scrub.update(current: 370, horizontal: 16, vertical: 0), 370, "duplicate gesture event")

        var left = WatchHydrationAmountAdjustment()
        expect(left.update(current: 350, horizontal: -24, vertical: 0), 320, "left swipe")
        var scroll = WatchHydrationAmountAdjustment()
        expect(scroll.update(current: 350, horizontal: 2, vertical: 12), 350, "vertical scrolling")
        expect(scroll.update(current: 350, horizontal: 80, vertical: 20), 350, "vertical axis stays locked")

        var upper = WatchHydrationAmountAdjustment()
        expect(upper.update(current: 2_990, horizontal: 160, vertical: 0), 3_000, "upper bound")
        expect(upper.update(current: 3_000, horizontal: 152, vertical: 0), 2_990, "reverse after upper overshoot")
        var lower = WatchHydrationAmountAdjustment()
        expect(lower.update(current: 60, horizontal: -160, vertical: 0), 50, "lower bound")
        expect(lower.update(current: 50, horizontal: -152, vertical: 0), 60, "reverse after lower overshoot")

        var fresh = WatchHydrationAmountAdjustment()
        expect(fresh.update(current: 380, horizontal: 8, vertical: 0), 390, "new gesture starts from current value")
        expect(fresh.update(current: 390, horizontal: .nan, vertical: 0), 390, "invalid coordinates ignored")
        expect(WatchHydrationAmountAdjustment.clamped(40), 50, "minus button bound")
        expect(WatchHydrationAmountAdjustment.clamped(3_010), 3_000, "plus button bound")
        print("Watch water scrub: 16 checks passed")
    }

    private static func expect(_ actual: Int, _ expected: Int, _ name: String) {
        precondition(actual == expected, "\(name): expected \(expected), got \(actual)")
    }
}
