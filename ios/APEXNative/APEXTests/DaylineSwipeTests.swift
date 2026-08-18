import XCTest

/*
 * Swipe-to-delete on the Dayline, pinned after two wrong fixes.
 *
 * First failure: the reveal lived in the row's own @State, and rows are
 * rebuilt whenever the day's data changes, so a refresh discarded it.
 * Second failure: the card is a Button and the swipe is a simultaneous
 * gesture, so releasing the swipe also delivered a tap; the tap saw an open
 * card and closed it a frame later. Neither is expressible as a pure
 * function, but the settle decision is, and it is what decides whether the
 * delete button is reachable at all.
 */
final class DaylineSwipeTests: XCTestCase {

    private let revealWidth: CGFloat = 96

    /// Mirrors APEXDaylineView.endReveal.
    private func settles(open wasOpen: Bool, translation: CGFloat) -> Bool {
        let base: CGFloat = wasOpen ? -revealWidth : 0
        let settled = base + translation
        return settled < -revealWidth / 3
    }

    func testAnOrdinarySwipeOpensAndStaysOpen() {
        /* 40pt is a normal thumb swipe. Requiring half the width meant this
           fell back to closed and the delete button was unreachable. */
        XCTAssertTrue(settles(open: false, translation: -40))
    }

    func testATinyDragDoesNotOpen() {
        XCTAssertFalse(settles(open: false, translation: -12))
    }

    func testAFullSwipeOpens() {
        XCTAssertTrue(settles(open: false, translation: -96))
    }

    func testAnOpenCardStaysOpenWhenTheFingerBarelyMoves() {
        /* Re-touching an open card must not close it by accident. */
        XCTAssertTrue(settles(open: true, translation: 0))
        XCTAssertTrue(settles(open: true, translation: 8))
    }

    func testADeliberateSwipeBackCloses() {
        XCTAssertFalse(settles(open: true, translation: 70))
    }

    func testTappingAnOpenCardClosesIt() {
        /* The card's tap handler passes +revealWidth to the same settle. */
        XCTAssertFalse(settles(open: true, translation: revealWidth))
    }

    func testAFlickCommitsOnPredictedTravel() {
        /* onEnded settles on min(translation, predictedEndTranslation), so a
           short fast flick still opens. */
        let translation: CGFloat = -22
        let predicted: CGFloat = -140
        XCTAssertTrue(settles(open: false, translation: min(translation, predicted)))
    }

    func testAxisLockPrefersHorizontalOnlyWhenClearlySideways() {
        /* dx > dy * 1.4, so a diagonal drag keeps moving the meal's time
           rather than half-revealing the delete. */
        func locksHorizontal(dx: CGFloat, dy: CGFloat) -> Bool { dx > dy * 1.4 }
        XCTAssertTrue(locksHorizontal(dx: 40, dy: 10))
        XCTAssertFalse(locksHorizontal(dx: 20, dy: 30))
        XCTAssertFalse(locksHorizontal(dx: 21, dy: 20))
    }
}
