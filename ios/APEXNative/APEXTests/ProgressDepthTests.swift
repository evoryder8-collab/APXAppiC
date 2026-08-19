/*
 * Distance is the variable that quietly ruins a comparison, so the range it
 * accepts and the advice it gives are pinned here rather than left to drift.
 */
import XCTest
@testable import APEX

@MainActor
final class ProgressDepthTests: XCTestCase {
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
}
