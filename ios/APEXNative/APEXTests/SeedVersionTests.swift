/*
 * Native does not repair seed definitions, so it must at least never present
 * an out-of-date plan as if it were current.
 */
import XCTest
@testable import APEX

final class SeedVersionTests: XCTestCase {
    private func profile(seedVersion: Int) -> Profile {
        var value = APEXDebugFixture.dashboard().profile!
        value.seedVersion = seedVersion
        return value
    }

    func testCurrentVersionNeedsNothing() {
        let state = SeedVersion.state(of: profile(seedVersion: SeedVersion.current))
        XCTAssertEqual(state, .current)
        XCTAssertFalse(state.needsRepair)
        XCTAssertNil(SeedVersion.notice(for: state))
    }

    func testAnOlderAccountIsReportedAsBehind() {
        let state = SeedVersion.state(of: profile(seedVersion: 3))
        XCTAssertEqual(state, .behind(stored: 3))
        XCTAssertTrue(state.needsRepair)
        XCTAssertNotNil(SeedVersion.notice(for: state))
    }

    /// A newer account than this build knows about is not behind.
    func testAFutureVersionIsNotTreatedAsStale() {
        let state = SeedVersion.state(of: profile(seedVersion: SeedVersion.current + 1))
        XCTAssertEqual(state, .current)
        XCTAssertFalse(state.needsRepair)
    }

    func testNoProfileIsUnknownRatherThanCurrent() {
        let state = SeedVersion.state(of: nil)
        XCTAssertEqual(state, .unknown)
        XCTAssertTrue(state.needsRepair, "absence of a profile is not evidence of a current one")
    }
}
