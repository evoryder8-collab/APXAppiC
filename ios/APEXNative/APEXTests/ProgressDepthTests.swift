/*
 * Distance is the variable that quietly ruins a comparison, so the range it
 * accepts and the advice it gives are pinned here rather than left to drift.
 */
import CoreVideo
import XCTest
@testable import APEX

@MainActor
final class ProgressDepthTests: XCTestCase {
    func testCaptureWeightAndExportStatsRespectExplicitChoices() {
        var intent = ProgressCaptureIntent()
        XCTAssertNil(intent.resolvedWeightKG)
        intent.weightKG = " 72,5 "
        XCTAssertEqual(intent.resolvedWeightKG, 72.5)
        for invalid in ["NaN", "-5", "0", "not a weight"] {
            intent.weightKG = invalid
            XCTAssertNil(intent.resolvedWeightKG)
        }
        XCTAssertFalse(ProgressComparison.posterContent(.detailed, includeStats: false).stats)
        XCTAssertTrue(ProgressComparison.posterContent(.detailed, includeStats: true).stats)
        XCTAssertFalse(ProgressComparison.posterContent(.minimal, includeStats: true).stats)
        XCTAssertTrue(ProgressComparison.posterContent(.detailed, includeStats: false).athlete)
    }
    func testPlacementRangeMatchesAFullBodyFrame() {
        let reading = ProgressDepthAnalyzer()

        reading.update(distance: 2.4, subject: .facingCamera, hasDepth: true)
        XCTAssertTrue(reading.isWellPlaced)
        XCTAssertNil(reading.placementHint, "no advice is needed when the placement is right")

        reading.update(distance: 1.2, subject: .facingCamera, hasDepth: true)
        XCTAssertFalse(reading.isWellPlaced)
        XCTAssertEqual(reading.placementHint, "Step back")

        reading.update(distance: 4.0, subject: .facingCamera, hasDepth: true)
        XCTAssertFalse(reading.isWellPlaced)
        XCTAssertEqual(reading.placementHint, "Step closer")
    }

    /// The boundaries themselves, so a later tweak is deliberate.
    func testRangeBoundariesAreInclusive() {
        let reading = ProgressDepthAnalyzer()
        reading.update(distance: 1.6, subject: .facingCamera, hasDepth: true)
        XCTAssertTrue(reading.isWellPlaced)
        reading.update(distance: 3.2, subject: .facingCamera, hasDepth: true)
        XCTAssertTrue(reading.isWellPlaced)
        reading.update(distance: 3.21, subject: .facingCamera, hasDepth: true)
        XCTAssertFalse(reading.isWellPlaced)
    }

    /// A device with no depth camera must say nothing rather than guess.
    func testNoDepthMeansNoClaim() {
        let reading = ProgressDepthAnalyzer()
        reading.update(distance: nil, subject: .facingAway, hasDepth: false)
        XCTAssertNil(reading.distanceText)
        XCTAssertNil(reading.placementHint)
        XCTAssertFalse(reading.isWellPlaced, "an unknown distance is never well placed")
        XCTAssertEqual(reading.subject, .facingAway, "orientation still reads without depth")
    }

    func testDistanceIsShownInMetresToTwoPlaces() {
        let reading = ProgressDepthAnalyzer()
        reading.update(distance: 2.375, subject: .facingCamera, hasDepth: true)
        XCTAssertEqual(reading.distanceText, "2.38 m")
    }

    /// Facing away is the back pose the feature asks for, so it is a real
    /// state rather than a failure to detect a face.
    func testSubjectLabelsCoverEveryState() {
        XCTAssertEqual(ProgressDepthAnalyzer.Subject.facingAway.label, "Facing away")
        XCTAssertEqual(ProgressDepthAnalyzer.Subject.facingCamera.label, "Facing camera")
        XCTAssertEqual(ProgressDepthAnalyzer.Subject.profile.label, "Profile")
        XCTAssertEqual(ProgressDepthAnalyzer.Subject.none.label, "No subject")
        for subject in [ProgressDepthAnalyzer.Subject.none, .facingCamera, .profile, .facingAway] {
            XCTAssertFalse(subject.systemImage.isEmpty, subject.rawValue)
        }
    }

    /// C11. The camera delivers its frames as the sensor is mounted, on its
    /// side, and Vision is told to turn them upright before it looks for a
    /// person. Its answer is therefore in the upright picture, and has to be
    /// turned back before it is used to read the depth map, which is not
    /// turned. Read unturned, the pill reports the wall beside the person.
    func testDistanceIsReadFromThePersonNotTheWallBesideThem() throws {
        let width = 64, height = 48
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_DepthFloat32,
            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &buffer
        )
        let map = try XCTUnwrap(buffer)

        /* A person two metres away, standing left of centre in the upright
           picture: 15 to 45 percent across, 10 to 90 percent of the height.
           Upright x runs down the map's rows and upright y, from the top,
           along its columns, so they fill rows 15 to 45 percent and columns
           10 to 90 percent. Everything else is a wall at 3.2 metres. */
        CVPixelBufferLockBaseAddress(map, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(map))
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        for row in 0..<height {
            let values = base.advanced(by: row * rowBytes).assumingMemoryBound(to: Float32.self)
            for column in 0..<width {
                let onPerson = (Int(0.15 * 48)..<Int(0.45 * 48)).contains(row)
                    && (Int(0.10 * 64)..<Int(0.90 * 64)).contains(column)
                values[column] = onPerson ? 2.0 : 3.2
            }
        }
        CVPixelBufferUnlockBaseAddress(map, [])

        /* Vision's box for that person: bottom-left origin, upright. */
        let person = CGRect(x: 0.15, y: 0.10, width: 0.30, height: 0.80)
        let distance = try XCTUnwrap(ProgressFrameAnalyzer.medianDepth(in: map, region: person))
        XCTAssertEqual(distance, 2.0, accuracy: 0.01, "the pill read the wall, not the person")

        /* With nobody found, the middle of the frame is read either way up. */
        XCTAssertEqual(try XCTUnwrap(ProgressFrameAnalyzer.medianDepth(in: map, region: nil)), 3.2, accuracy: 0.01)
    }
}
