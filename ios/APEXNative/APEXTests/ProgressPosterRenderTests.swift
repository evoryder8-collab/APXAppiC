/*
 * Renders the export card and writes it out, so the layout can be looked at
 * rather than assumed. A poster is a visual artefact; asserting numbers about
 * it proves very little on its own.
 */
import XCTest
@testable import APEX

final class ProgressPosterRenderTests: XCTestCase {
    private func swatch(_ colours: [UIColor], size: CGSize = .init(width: 900, height: 1600)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours.map(\.cgColor) as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(
                gradient, start: .zero,
                end: CGPoint(x: size.width, y: size.height), options: []
            )
            /* A shape in the middle, so the cover crop and the zoom are
               visible rather than a flat wash. */
            UIColor.white.withAlphaComponent(0.5).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.3, y: size.height * 0.3,
                                      width: size.width * 0.4, height: size.height * 0.3))
        }
    }

    private func input(detailed: Bool) -> ProgressPosterRenderer.Input {
        ProgressPosterRenderer.Input(
            before: swatch([.systemTeal, .black]),
            after: swatch([.systemIndigo, .black]),
            beforeMoment: "4 May 2026 at 07:12",
            afterMoment: "19 Aug 2026 at 06:37",
            beforePose: "FRONT",
            afterPose: "FRONT",
            views: .init(left: .init(scale: 1, x: 0, y: 0), right: .init(scale: 1, x: 0, y: 0)),
            content: ProgressComparison.posterContent(detailed ? .detailed : .minimal),
            torsoLayout: false,
            athleteName: "Constantine",
            daysApart: 107,
            workouts: 42,
            averageLoadDeltaKG: 7.5,
            matchedExercises: 6,
            loadedSets: 148,
            beforeWeightKG: 74.4,
            afterWeightKG: 71.0
        )
    }

    func testRendersAtTheWebCanvasSize() {
        let card = ProgressPosterRenderer.render(input(detailed: true))
        XCTAssertEqual(card.size.width, 1080)
        XCTAssertEqual(card.size.height, 1350)
    }

    func testBothModesProduceAFile() throws {
        for detailed in [true, false] {
            let card = ProgressPosterRenderer.render(input(detailed: detailed))
            let url = try XCTUnwrap(ProgressPosterRenderer.write(card))
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 20_000, "a card this size should not be nearly empty")

            /* Copied somewhere stable so the layout can actually be inspected. */
            let out = URL(fileURLWithPath: "/tmp/apex-poster-\(detailed ? "detailed" : "minimal").png")
            try? FileManager.default.removeItem(at: out)
            try data.write(to: out)
        }
    }

    /// Minimal must not leak the stats it exists to withhold.
    func testMinimalDropsTheStatsBlock() {
        let minimal = ProgressComparison.posterContent(.minimal)
        XCTAssertFalse(minimal.stats)
        XCTAssertFalse(minimal.athlete)
        XCTAssertFalse(minimal.pose)
        XCTAssertFalse(minimal.privateFooter)
        let detailed = ProgressComparison.posterContent(.detailed)
        XCTAssertTrue(detailed.stats)
        XCTAssertTrue(detailed.privateFooter)
    }
}
