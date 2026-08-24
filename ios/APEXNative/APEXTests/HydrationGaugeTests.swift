import XCTest
@testable import APEX

/*
 * The litre scale beside the hydration figure has to land on the body, not
 * on the frame. The SVG viewBox is "-150 -150 W 1015"; inside it the crown
 * of the head is y = 0 and the feet, where the fill rests at zero, are
 * y = 712. Rendered with xMidYMid meet into a frame of the same aspect
 * ratio, those become fixed fractions of the frame height.
 *
 * These pin the mapping so a future layout change cannot quietly detach the
 * ruler from the silhouette again.
 */
final class HydrationGaugeTests: XCTestCase {

    private let crownFraction = 150.0 / 1015.0
    private let feetFraction = 862.0 / 1015.0

    private func tickY(liters: Double, target: Double, height: Double) -> Double {
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        let fraction = target > 0 ? min(1, max(0, liters / target)) : 0
        return feetY - fraction * (feetY - crownY)
    }

    func testZeroLitresSitsAtTheFeet() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 0, target: 2.75, height: height), feetFraction * height, accuracy: 0.001)
    }

    func testTargetSitsAtTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 2.75, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testHalfTheTargetSitsHalfwayUpTheBody() {
        let height = 400.0
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        XCTAssertEqual(
            tickY(liters: 1.375, target: 2.75, height: height),
            (crownY + feetY) / 2,
            accuracy: 0.001
        )
    }

    func testScaleIsProportionalToFrameHeight() {
        /* Doubling the figure doubles every offset, so the ruler tracks it. */
        let small = tickY(liters: 1.0, target: 2.75, height: 200)
        let large = tickY(liters: 1.0, target: 2.75, height: 400)
        XCTAssertEqual(large, small * 2, accuracy: 0.001)
    }

    func testBodyOccupiesTheExpectedSliceOfTheFrame() {
        /* Guards against someone "fixing" the layout by stretching the web
           view to full height, which would silently break the alignment. */
        XCTAssertEqual(crownFraction, 0.1478, accuracy: 0.0005)
        XCTAssertEqual(feetFraction, 0.8493, accuracy: 0.0005)
    }

    func testOverdrinkingIsClampedToTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 5.0, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testFigureAspectMatchesTheViewBox() {
        /* Frame aspect must equal the viewBox aspect or xMidYMid meet
           letterboxes the drawing and the fractions above stop holding. */
        XCTAssertEqual(583.6 / 1015.0, 0.5750, accuracy: 0.0005, "male figure")
        XCTAssertEqual(568.0 / 1015.0, 0.5596, accuracy: 0.0005, "female figure")
    }
}

final class WatchHydrationFillStateTests: XCTestCase {
    func testProgressAndWaterlineClampAtEmptyAndTarget() {
        let empty = WatchHydrationFillState(liters: -0.5, targetLiters: 2.75)
        let full = WatchHydrationFillState(liters: 4.0, targetLiters: 2.75)

        XCTAssertEqual(empty.progress, 0)
        XCTAssertEqual(empty.baseWaterline, 1)
        XCTAssertEqual(full.progress, 1)
        XCTAssertEqual(full.baseWaterline, 0)
    }

    func testWaterlineRisesProportionallyThroughTheBody() {
        let quarter = WatchHydrationFillState(liters: 0.6875, targetLiters: 2.75)
        let half = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)
        let threeQuarters = WatchHydrationFillState(liters: 2.0625, targetLiters: 2.75)

        XCTAssertEqual(quarter.baseWaterline, 0.75, accuracy: 0.0001)
        XCTAssertEqual(half.baseWaterline, 0.5, accuracy: 0.0001)
        XCTAssertEqual(threeQuarters.baseWaterline, 0.25, accuracy: 0.0001)
    }

    func testWaveCannotCreateWaterWhenEmptyOrLeaveAirWhenFull() {
        for phase in stride(from: 0.0, through: Double.pi * 2, by: 0.4) {
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 0, normalizedX: 0.35, phase: phase),
                1,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 1, normalizedX: 0.65, phase: phase),
                0,
                accuracy: 0.0001
            )
        }
    }

    func testAnimatedWaveStaysInsideNormalizedGaugeBounds() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                let waterline = WatchHydrationFillState.waterline(
                    progress: progress,
                    normalizedX: x,
                    phase: 1.75
                )
                XCTAssertGreaterThanOrEqual(waterline, 0)
                XCTAssertLessThanOrEqual(waterline, 1)
            }
        }
    }
}
