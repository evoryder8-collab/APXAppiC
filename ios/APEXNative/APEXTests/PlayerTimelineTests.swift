/*
 * The guided player's timeline. The rules here all guard the same thing:
 * never manufacture work that did not happen.
 */
import XCTest
@testable import APEX

final class PlayerTimelineTests: XCTestCase {
    private func exercise(
        _ name: String,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        repUnit: String = "reps",
        perSide: Bool = false,
        rest: Int = 90,
        increment: Double = 2.5,
        optional: Bool = false,
        notes: String = ""
    ) -> Exercise {
        Exercise(
            id: UUID(), userID: UUID(), programDayID: UUID(), name: name,
            sets: sets, repMin: repMin, repMax: repMax, repUnit: repUnit,
            perSide: perSide, restSeconds: rest, tempoUp: 1, tempoDown: 2,
            tempoPause: 0.5, tempoNote: "", notes: notes, incrementKG: increment,
            isLite: false, optional: optional, sortOrder: 0
        )
    }

    private func plan(_ exercises: [Exercise], warmup: String = "Prime", warmupDuration: Int = 120) -> PlannedDay {
        PlannedDay(
            programDay: nil,
            exercises: exercises.map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) },
            warmup: warmup,
            warmupDuration: warmupDuration
        )
    }

    func testTimelineOrdersWarmupSetsRestsAndLog() {
        let blocks = PlayerTimeline.build(plan([exercise("Back squat", sets: 2)]))
        guard case .warmup(let text, let duration) = blocks.first else {
            return XCTFail("a warm-up should open the session")
        }
        XCTAssertEqual(text, "Prime")
        XCTAssertEqual(duration, 120)
        // warmup, set 1, rest, set 2, log, done
        XCTAssertEqual(blocks.count, 6)
        XCTAssertTrue(blocks[1].isSet)
        if case .rest(_, let afterSet, _, let nextLabel, let captureLoad, _) = blocks[2] {
            XCTAssertEqual(afterSet, 1)
            XCTAssertEqual(nextLabel, "Back squat, set 2")
            XCTAssertTrue(captureLoad, "a progressible lift captures its load in the break")
        } else {
            XCTFail("a rest should follow every set but the last")
        }
        XCTAssertEqual(blocks.last, .done)
    }

    /// The rear foot needs resetting; other per-side work does not.
    func testOnlySplitSquatsGetASideSwitch() {
        let split = PlayerTimeline.build(plan([exercise("Bulgarian split squat", sets: 1, perSide: true)]))
        XCTAssertTrue(split.contains { if case .sideSwitch = $0 { return true } else { return false } })

        let raise = PlayerTimeline.build(plan([exercise("Single-leg calf raise", sets: 1, perSide: true)]))
        XCTAssertFalse(raise.contains { if case .sideSwitch = $0 { return true } else { return false } })
        XCTAssertEqual(raise.filter(\.isSet).count, 2, "per-side work is still two sets")
    }

    func testTimedAndMaxSetsCarryTheRightShape() {
        let hold = PlayerTimeline.build(plan([exercise("Plank", sets: 1, repMin: 40, repMax: 60, repUnit: "seconds")]))
        if case .set(_, _, _, _, _, let target, _, let timed) = hold[1] {
            /* A hold still carries the midpoint, exactly as the web does;
               `timed` being present is what makes the player run a clock
               instead of counting repetitions. */
            XCTAssertEqual(target, 50)
            XCTAssertEqual(timed, 50, "the clock is what a hold is actually run by")
        } else { XCTFail("expected a set") }

        let amrap = PlayerTimeline.build(plan([exercise("Pull-up", sets: 1, repUnit: "max")]))
        if case .set(_, _, _, _, _, let target, _, let timed) = amrap[1] {
            XCTAssertNil(target, "a max set counts up rather than to a target")
            XCTAssertNil(timed)
        } else { XCTFail("expected a set") }
    }

    /// A throttled or backgrounded app must never invent repetitions.
    func testABackgroundedSetNeverAccruesTime() {
        let persisted = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        let set = PlayerTimeline.Block.set(
            exerciseIndex: 0, setNumber: 1, totalSets: 3, side: nil,
            resultKey: "0-1", targetReps: 10, repDuration: 3.5, timed: nil
        )
        let restored = PlayerTimeline.reconcileElapsed(
            block: set, elapsed: 12, paused: false, persistedAt: persisted
        )
        XCTAssertEqual(restored.elapsed, 12, "an active set gains nothing from time away")
        XCTAssertTrue(restored.paused, "and waits for an explicit resume")

        let rest = PlayerTimeline.Block.rest(
            exerciseIndex: 0, afterSet: 1, duration: 90,
            nextLabel: "next", captureLoad: false, reviewExercise: false
        )
        let counted = PlayerTimeline.reconcileElapsed(
            block: rest, elapsed: 12, paused: false, persistedAt: persisted
        )
        XCTAssertGreaterThan(counted.elapsed, 100, "a rest keeps counting in the background")
        XCTAssertFalse(counted.paused)
    }

    func testPrefillsPreferTheClosestRealEntry() {
        XCTAssertEqual(
            PlayerTimeline.prefillWeight(setWeights: [60, 62.5, nil], setNumber: 3, exerciseWeight: 50, recommendedWeight: 2.5),
            62.5,
            "the closest captured load wins over a stale recommendation"
        )
        XCTAssertEqual(
            PlayerTimeline.prefillWeight(setWeights: [nil, nil], setNumber: 2, exerciseWeight: 50, recommendedWeight: 2.5),
            50
        )
        XCTAssertNil(
            PlayerTimeline.prefillWeight(setWeights: [nil], setNumber: 1, exerciseWeight: nil, recommendedWeight: nil)
        )
        XCTAssertEqual(
            PlayerTimeline.prefillReps(setReps: [10, 9], setNumber: 2, countedReps: 4, targetReps: 12),
            9,
            "a correction entered in the break beats the counted number"
        )
        XCTAssertEqual(
            PlayerTimeline.prefillReps(setReps: [nil], setNumber: 1, countedReps: 7, targetReps: 12),
            7
        )
        XCTAssertEqual(
            PlayerTimeline.prefillReps(setReps: [], setNumber: 1, countedReps: nil, targetReps: 12),
            12
        )
    }

    /// A set is only as strong as the weaker side.
    func testPerSideCountsTakeTheWeakerSide() {
        let counted = ["0-1-left": 8, "0-1-right": 6]
        XCTAssertEqual(PlayerTimeline.countedReps(counted, exerciseIndex: 0, setNumber: 1, perSide: true), 6)
        XCTAssertEqual(
            PlayerTimeline.countedReps(["0-1-left": 8], exerciseIndex: 0, setNumber: 1, perSide: true),
            8,
            "one side recorded is better than nothing"
        )
        XCTAssertNil(PlayerTimeline.countedReps([:], exerciseIndex: 0, setNumber: 1, perSide: true))
    }

    func testEstimateAndPlannedSetCount() {
        let day = plan([exercise("Back squat", sets: 3), exercise("Mobility", sets: 2, optional: true)])
        XCTAssertGreaterThan(PlayerTimeline.estimatedMinutes(day), 1)
        XCTAssertEqual(
            PlayerTimeline.plannedSetCount(day), 3,
            "optional work is offered, not planned, so it is not counted"
        )
    }
}
