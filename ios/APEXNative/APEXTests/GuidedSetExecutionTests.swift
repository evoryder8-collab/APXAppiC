import XCTest
@testable import APEX

final class GuidedSetExecutionTests: XCTestCase {
    func testUnilateralSetRequiresBothSidesBeforeRecordingOneSet() {
        var execution = GuidedSetExecution(perSide: true)
        XCTAssertEqual(execution.side, .left)
        XCTAssertEqual(execution.finish(work: 12, skipped: false), .switchSide)
        execution.beginRightSide()
        XCTAssertEqual(execution.side, .right)
        XCTAssertEqual(execution.finish(work: 10, skipped: false), .record(work: 10, skipped: false))
    }

    func testBilateralAndExplicitlySkippedSetsDoNotInventSecondSideWork() {
        var bilateral = GuidedSetExecution(perSide: false)
        XCTAssertEqual(bilateral.finish(work: 8, skipped: false), .record(work: 8, skipped: false))
        var skippedLeft = GuidedSetExecution(perSide: true)
        XCTAssertEqual(skippedLeft.finish(work: 8, skipped: true), .record(work: 0, skipped: true))
        var skippedRight = GuidedSetExecution(perSide: true)
        XCTAssertEqual(skippedRight.finish(work: 8, skipped: false), .switchSide)
        skippedRight.beginRightSide()
        XCTAssertEqual(skippedRight.finish(work: 3, skipped: true), .record(work: 0, skipped: true))
    }

    func testInterruptedSideSwitchKeepsFirstSideWithoutCompletingTheSet() throws {
        var execution = GuidedSetExecution(perSide: true)
        XCTAssertEqual(execution.finish(work: 45, skipped: false), .switchSide)
        var restored = try JSONDecoder().decode(GuidedSetExecution.self, from: JSONEncoder().encode(execution))
        XCTAssertEqual(restored.side, .left)
        restored.beginRightSide()
        XCTAssertEqual(restored.finish(work: 40, skipped: false), .record(work: 40, skipped: false))
    }

    func testNarrationBlocksCadenceUntilCurrentAnnouncementFinishes() throws {
        var gate = GuidedCadenceGate()
        let token = try XCTUnwrap(gate.begin(voiceEnabled: true))
        XCTAssertFalse(gate.allowsTick(paused: false, foreground: true))
        XCTAssertFalse(gate.finish(UUID()))
        XCTAssertTrue(gate.finish(token))
        XCTAssertTrue(gate.allowsTick(paused: false, foreground: true))
        XCTAssertFalse(gate.allowsTick(paused: true, foreground: true))
        XCTAssertFalse(gate.allowsTick(paused: false, foreground: false))
    }

    func testLateNarrationCannotReleaseAnotherSetAndMutedSetNeedsNoWait() throws {
        var gate = GuidedCadenceGate()
        let old = try XCTUnwrap(gate.begin(voiceEnabled: true))
        gate.cancel()
        let current = try XCTUnwrap(gate.begin(voiceEnabled: true))
        XCTAssertFalse(gate.finish(old))
        XCTAssertFalse(gate.allowsTick(paused: false, foreground: true))
        XCTAssertTrue(gate.finish(current))
        XCTAssertNil(gate.begin(voiceEnabled: false))
        XCTAssertTrue(gate.allowsTick(paused: false, foreground: true))
    }
}
