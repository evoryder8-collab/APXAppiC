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
            fit: (1, 1),
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

    /// The sensor's whole frame with a white band across its middle, or the
    /// rows of it that a photo keeps.
    private func banded(rows: Range<Int>) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 600, height: rows.count)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 300 - rows.lowerBound, width: 600, height: 200))
        }
    }

    private func photo(key: String, aspectRatio: Double) -> ProgressPhoto {
        ProgressPhoto(
            id: UUID(), userID: UUID(), localDate: "2026-10-01", capturedAt: "2026-10-01T07:00:00Z",
            pose: "front", storagePath: "a", thumbnailPath: "b", width: 3, height: 4,
            aspectRatio: aspectRatio, cropX: 0.5, cropY: 0.5, cropScale: 1, referencePhotoID: nil,
            weightKG: nil, note: "", clientIdempotencyKey: key
        )
    }

    /// A torso photo taken before the camera cut its pictures is the sensor's
    /// whole frame. One taken since keeps the full width and gives up some
    /// height. Each filled into a pane, the newer came out 6.7 percent
    /// larger, so the card showed the same person at two sizes.
    func testTorsoPhotosFromBeforeAndAfterTheCutShowTheSamePersonAtTheSameSizeOnTheCard() throws {
        let uncutFrame = banded(rows: 0..<800), cutFrame = banded(rows: 25..<775)
        let uncut = photo(key: "framing:torso:uncut", aspectRatio: 0.75)
        let cut = photo(key: "framing:torso:cut", aspectRatio: 0.8)

        /// How many pixels of the band each pane shows down its middle.
        func bands(
            _ before: (ProgressPhoto, UIImage), _ after: (ProgressPhoto, UIImage)
        ) throws -> (before: Int, after: Int) {
            var card = input(detailed: false)
            card.before = before.1
            card.after = after.1
            /* Two torso photos, so the card has its shorter photo block:
               panes 1120 tall, where the whole frame's band is 280. */
            card.torsoLayout = true
            card.fit = ProgressPhotoEngine.comparisonFit(before.0, after.0)
            let cg = try XCTUnwrap(ProgressPosterRenderer.render(card).cgImage)
            let data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            func band(column: Int) -> Int {
                (400..<1000).filter { row in
                    let offset = row * cg.bytesPerRow + column * (cg.bitsPerPixel / 8)
                    return Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) > 384
                }.count
            }
            /* The panes are 504 wide, from x 36 and from x 540. */
            return (band(column: 36 + 252), band(column: 540 + 252))
        }

        for (before, after) in [((uncut, uncutFrame), (cut, cutFrame)), ((cut, cutFrame), (uncut, uncutFrame))] {
            let shown = try bands(before, after)
            XCTAssertEqual(shown.before, shown.after, accuracy: 2, "the same person is a different size on each side")
            XCTAssertEqual(shown.before, 280, accuracy: 2, "the pair is no longer at the size the whole frame fills the pane")
        }

        let older = try bands((uncut, uncutFrame), (uncut, uncutFrame))
        XCTAssertEqual(older.before, 280, accuracy: 2, "two photos from before the cut fill their panes as before")
        XCTAssertEqual(older.after, 280, accuracy: 2, "two photos from before the cut fill their panes as before")
        let newer = try bands((cut, cutFrame), (cut, cutFrame))
        XCTAssertEqual(newer.before, 299, accuracy: 2, "two photos taken since the cut fill their panes as before")
        XCTAssertEqual(newer.after, 299, accuracy: 2, "two photos taken since the cut fill their panes as before")
    }

    /// C7. The card draws the pan as a share of its own pane, which is how the
    /// screen now applies it, so the export shows the arrangement on screen.
    func testThePanOnTheCardIsAShareOfItsPane() throws {
        /* Black on the left half, white on the right: the seam shows the pan. */
        let split = UIGraphicsImageRenderer(size: CGSize(width: 504, height: 1278)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 252, height: 1278))
            UIColor.white.setFill()
            context.fill(CGRect(x: 252, y: 0, width: 252, height: 1278))
        }
        func seam(panned x: Double) throws -> Int {
            var card = input(detailed: false)
            card.before = split
            card.views.left = .init(scale: 2, x: x, y: 0)
            let image = ProgressPosterRenderer.render(card)
            let cg = try XCTUnwrap(image.cgImage)
            let data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            let row = 700
            /* The left pane runs from x 36 to 540. */
            for column in 40..<536 {
                let offset = row * cg.bytesPerRow + column * (cg.bitsPerPixel / 8)
                if Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) > 384 { return column }
            }
            return -1
        }
        let centred = try seam(panned: 0)
        XCTAssertEqual(centred, 36 + 252, accuracy: 2, "unpanned, the seam is in the middle of the pane")
        XCTAssertEqual(try seam(panned: 10) - centred, 50, accuracy: 2, "ten percent of a 504 point pane")
        XCTAssertEqual(try seam(panned: -20) - centred, -101, accuracy: 2)
    }
}
