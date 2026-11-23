import XCTest
@testable import APEX

final class TrainTogetherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func exercise(
        _ name: String, sets: Int = 1, reps: Int = 10, unit: String = "reps",
        perSide: Bool = false, rest: Int = 60, order: Int = 0
    ) -> Exercise {
        Exercise(
            id: UUID(), userID: UUID(), programDayID: UUID(), name: name,
            sets: sets, repMin: reps, repMax: reps, repUnit: unit, perSide: perSide,
            restSeconds: rest, tempoUp: 1, tempoDown: 2, tempoPause: 0.5, tempoNote: "",
            notes: "", incrementKG: 2.5, isLite: false, optional: false, sortOrder: order
        )
    }

    /// Positions: 0 squat set 1, 1 squat set 2, 2 plank, 3 lunge (per side), 4 carry.
    private lazy var exercises = [
        exercise("Test squat", sets: 2, rest: 60, order: 0),
        exercise("Test plank", reps: 30, unit: "seconds", order: 1),
        exercise("Test lunge", reps: 8, perSide: true, rest: 45, order: 2),
        exercise("Test carry", reps: 40, unit: "metres", order: 3),
    ]
    private lazy var timeline = TrainTogether.Timeline(exercises: exercises, warmupText: "Prime", warmupDuration: 120)
    private let squatWork = 5 + 10 * 3.9 + 0.3

    private func started() -> TrainTogether.State {
        timeline.apply(.start, to: .lobby(at: t0), at: t0)
    }

    private func at(_ seconds: TimeInterval, _ state: TrainTogether.State? = nil) -> TrainTogether.Step {
        timeline.now(state ?? started(), at: t0.addingTimeInterval(seconds))
    }

    func testLobbyWaitsForTheHostAndStartOpensTheWarmUp() {
        let lobby = TrainTogether.State.lobby(at: t0)
        XCTAssertEqual(timeline.now(lobby, at: t0.addingTimeInterval(3_600)).phase, .lobby)
        XCTAssertEqual(at(119).phase, .warmup)
        XCTAssertEqual(at(119).remaining ?? -1, 1, accuracy: 0.001)
        let first = at(121)
        XCTAssertEqual(first.phase, .work)
        XCTAssertEqual(first.position, 0)
        XCTAssertEqual(first.elapsed, 1, accuracy: 0.001)
    }

    func testCountedSetsAndRestsRollOnWithoutAnyMessage() {
        let rest = at(120 + squatWork + 10)
        XCTAssertEqual(rest.phase, .rest)
        XCTAssertEqual(rest.position, 0)
        XCTAssertEqual(rest.remaining ?? -1, 50, accuracy: 0.001)

        // Someone joining much later lands exactly where the room is.
        let secondSet = at(120 + squatWork + 60 + 3)
        XCTAssertEqual(secondSet.phase, .work)
        XCTAssertEqual(secondSet.position, 1)
        XCTAssertEqual(timeline.counted(at: 1, side: nil, elapsed: secondSet.elapsed).reps, 0, "the lead-in counts no reps")
        XCTAssertEqual(timeline.counted(at: 1, side: nil, elapsed: 5 + 3.9 * 2 + 0.2).reps, 3)

        let plankStart = 120 + squatWork + 60 + squatWork + Double(timeline.restSeconds(after: 1))
        let plank = at(plankStart + 20)
        XCTAssertEqual(plank.phase, .work)
        XCTAssertEqual(plank.position, 2)
        XCTAssertEqual(timeline.counted(at: 2, side: nil, elapsed: plank.elapsed).holdLeft ?? -1, 15, accuracy: 0.001)
    }

    func testEachSideOfALungeAndTheSwitchBetweenThem() {
        let state = timeline.apply(.jump(position: 3), to: started(), at: t0)
        let lunge = timeline.now(state, at: t0)
        XCTAssertEqual(lunge.side, .left)
        let leftWork = 5 + 8 * 3.9 + 0.3
        let switching = timeline.now(state, at: t0.addingTimeInterval(leftWork + 1))
        XCTAssertEqual(switching.phase, .sideSwitch)
        XCTAssertEqual(switching.remaining ?? -1, 9, accuracy: 0.001)
        let right = timeline.now(state, at: t0.addingTimeInterval(leftWork + 10 + 1))
        XCTAssertEqual(right.phase, .work)
        XCTAssertEqual(right.side, .right)
        XCTAssertEqual(timeline.counted(at: 3, side: .right, elapsed: right.elapsed).reps, 1, "the right side starts straight after the switch")
    }

    func testAnUncountedSetWaitsForAPressAndTheLastSetEndsInReview() {
        var state = timeline.apply(.jump(position: 4), to: started(), at: t0)
        XCTAssertNil(timeline.now(state, at: t0.addingTimeInterval(3_600)).duration)
        XCTAssertEqual(timeline.now(state, at: t0.addingTimeInterval(3_600)).phase, .work)
        state = timeline.apply(.advance, to: state, at: t0.addingTimeInterval(90))
        XCTAssertEqual(timeline.now(state, at: t0.addingTimeInterval(9_000)).phase, .review)
        XCTAssertEqual(timeline.apply(.advance, to: state, at: t0.addingTimeInterval(9_000)), state, "review is each person's own")
    }

    func testPauseFreezesTheRoomAndResumeKeepsTheTimeThatWasLeft() {
        let restAt = 120 + squatWork + 10
        let paused = timeline.apply(.pause, to: started(), at: t0.addingTimeInterval(restAt))
        let frozen = timeline.now(paused, at: t0.addingTimeInterval(restAt + 600))
        XCTAssertTrue(frozen.paused)
        XCTAssertEqual(frozen.phase, .rest)
        XCTAssertEqual(frozen.remaining ?? -1, 50, accuracy: 0.001)

        let resumed = timeline.apply(.resume, to: paused, at: t0.addingTimeInterval(restAt + 600))
        let running = timeline.now(resumed, at: t0.addingTimeInterval(restAt + 610))
        XCTAssertFalse(running.paused)
        XCTAssertEqual(running.remaining ?? -1, 40, accuracy: 0.001)
    }

    func testAddedTimeBelongsToOneRestOnly() {
        let restAt = 120 + squatWork + 10
        let longer = timeline.apply(.addTime(30), to: started(), at: t0.addingTimeInterval(restAt))
        XCTAssertEqual(timeline.now(longer, at: t0.addingTimeInterval(restAt)).remaining ?? -1, 80, accuracy: 0.001)
        let nextRest = timeline.now(longer, at: t0.addingTimeInterval(restAt + 80 + squatWork + 10))
        XCTAssertEqual(nextRest.phase, .rest)
        XCTAssertEqual(nextRest.position, 1)
        XCTAssertEqual(nextRest.remaining ?? -1, Double(timeline.restSeconds(after: 1)) - 10, accuracy: 0.001)
    }

    func testTwoPartnersPressingTogetherGiveTheSameNextState() {
        let restAt = t0.addingTimeInterval(120 + squatWork + 10)
        let base = started()
        // Both phones compute from the same version; the server keeps one.
        XCTAssertEqual(timeline.apply(.addTime(30), to: base, at: restAt),
                       timeline.apply(.addTime(30), to: base, at: restAt))
        let skipped = timeline.apply(.advance, to: base, at: restAt)
        XCTAssertEqual(timeline.now(skipped, at: restAt).phase, .work)
        XCTAssertEqual(timeline.now(skipped, at: restAt).position, 1)
    }

    func testRoomSoundSwitchesLeaveTheClockAlone() {
        let lobby = TrainTogether.State.lobby(at: t0)
        XCTAssertFalse(lobby.voice, "rooms start with the voice off")
        XCTAssertTrue(lobby.sound)
        let running = started()
        let quiet = timeline.apply(.sound(false), to: running, at: t0.addingTimeInterval(30))
        XCTAssertFalse(quiet.sound)
        XCTAssertEqual(quiet.anchor, running.anchor)
        XCTAssertTrue(timeline.apply(.voice(true), to: lobby, at: t0).voice)
        XCTAssertEqual(timeline.apply(.addTime(30), to: timeline.apply(.jump(position: 0), to: running, at: t0), at: t0).extraSeconds, 0,
                       "time is added to rests and countdowns, never to a counted set")
    }

    func testStateTravelsAsSnakeCaseJSONWithFractionalSeconds() throws {
        let state = timeline.apply(.pause, to: started(), at: t0.addingTimeInterval(10.25))
        let data = try TrainTogetherCoding.encoder.encode(state)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"paused_at\""))
        XCTAssertTrue(json.contains("\"extra_seconds\""))
        let decoded = try TrainTogetherCoding.decoder.decode(TrainTogether.State.self, from: data)
        XCTAssertEqual(decoded.pausedAt?.timeIntervalSince1970 ?? 0, state.pausedAt?.timeIntervalSince1970 ?? 1, accuracy: 0.001)
        XCTAssertEqual(decoded.phase, state.phase)
        XCTAssertEqual(TrainTogetherCoding.decoder.dateDecodingStrategy == nil, false)
    }

    func testCodesAreFoundInWhateverWasPasted() {
        XCTAssertEqual(TrainTogether.code(in: "k7q4px"), "K7Q4PX")
        XCTAssertEqual(TrainTogether.code(in: "K7Q-4PX"), "K7Q4PX")
        XCTAssertEqual(TrainTogether.code(in: "https://evoryder8-collab.github.io/APXAppiC/#/join/K7Q4PX"), "K7Q4PX")
        XCTAssertEqual(TrainTogether.code(in: "Train with me! https://x.example/#/join/k7q4px see you"), "K7Q4PX")
        XCTAssertEqual(TrainTogether.code(in: "apex://join/K7Q4PX"), "K7Q4PX")
        XCTAssertNil(TrainTogether.code(in: "K7Q4P0"), "zero is never in a code")
        XCTAssertNil(TrainTogether.code(in: "hello"))
        XCTAssertEqual(TrainTogether.shareURL(code: "K7Q4PX")?.absoluteString,
                       "https://evoryder8-collab.github.io/APXAppiC/#/join/K7Q4PX")
    }

    func testAJoinersRowsAreTheirOwnStableAndOffThePlan() {
        let owner = UUID()
        let room = UUID()
        let plan = TrainTogether.Plan(name: "Full body", warmupText: "Prime", warmupDuration: 120,
                                      exercises: exercises.map(TrainTogether.PlanExercise.init))
        let rows = TrainTogether.anchorRows(plan: plan, roomID: room, title: "Workout with Anna", ownerID: owner)
        XCTAssertEqual(rows, TrainTogether.anchorRows(plan: plan, roomID: room, title: "Workout with Anna", ownerID: owner))
        XCTAssertFalse(rows.day.isActive, "a shared workout never enters the weekly plan")
        XCTAssertEqual(rows.program.slug, "group")
        XCTAssertTrue(rows.exercises.allSatisfy { $0.userID == owner && $0.programDayID == rows.day.id })
        XCTAssertEqual(rows.exercises.map(\.sets), [2, 1, 1, 1])
        XCTAssertEqual(rows.exercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertNotEqual(rows.day.id, TrainTogether.anchorRows(plan: plan, roomID: UUID(), title: "x", ownerID: owner).day.id)
        XCTAssertEqual(PlayerTimeline.workSequence(rows.exercises).count, timeline.sequence.count)
    }

    func testTheClockOffsetComesFromTheQuickestRoundTrip() {
        let samples = [
            TrainTogether.ClockSample(sent: t0, received: t0.addingTimeInterval(0.8), server: t0.addingTimeInterval(3.0)),
            TrainTogether.ClockSample(sent: t0, received: t0.addingTimeInterval(0.2), server: t0.addingTimeInterval(2.6)),
        ]
        XCTAssertEqual(TrainTogether.clockOffset(samples), 2.5, accuracy: 0.0001)
        XCTAssertEqual(TrainTogether.clockOffset([]), 0)
    }

    func testAResentOrPausedSnapshotIsStillTheSameStep() throws {
        // A press at an uneven time, sent to the server and back, must not look like a new set.
        let pressed = timeline.apply(.advance, to: started(), at: t0.addingTimeInterval(12.3456789))
        let roundTrip = try TrainTogetherCoding.decoder.decode(
            TrainTogether.State.self, from: TrainTogetherCoding.encoder.encode(pressed)
        )
        let here = timeline.now(pressed, at: t0.addingTimeInterval(14))
        let there = timeline.now(roundTrip, at: t0.addingTimeInterval(14))
        XCTAssertEqual(here.phase, .work)
        XCTAssertTrue(here.isSameStep(as: there))
        XCTAssertEqual(here.start.timeIntervalSince1970, there.start.timeIntervalSince1970, accuracy: 0.0005)

        let paused = timeline.apply(.pause, to: pressed, at: t0.addingTimeInterval(20))
        let resumed = timeline.apply(.resume, to: paused, at: t0.addingTimeInterval(80))
        XCTAssertTrue(timeline.now(resumed, at: t0.addingTimeInterval(81)).isSameStep(as: here),
                      "a pause in the middle of a set does not end it")
        XCTAssertFalse(timeline.now(timeline.apply(.advance, to: resumed, at: t0.addingTimeInterval(90)),
                                    at: t0.addingTimeInterval(91)).isSameStep(as: here))
    }

    func testSetsSleptThroughAreFoundOnlyWhenTheRoomRanOn() {
        let state = started()
        let early = timeline.now(state, at: t0.addingTimeInterval(125))
        XCTAssertEqual(early.phase, .work)
        // Woken in the rest after the plank: squat sets 1 and 2 and the plank were done meanwhile.
        let plankStart = 120 + squatWork + 60 + squatWork + Double(timeline.restSeconds(after: 1))
        let woke = timeline.now(state, at: t0.addingTimeInterval(plankStart + 35 + 5))
        XCTAssertEqual(woke.phase, .rest)
        XCTAssertEqual(woke.position, 2)
        XCTAssertEqual(timeline.workPassed(from: early, to: woke).map(\.position), [0, 1, 2])

        // After a jump the sets in between were never done: only the one on screen counts.
        let jumped = timeline.apply(.jump(position: 4), to: state, at: t0.addingTimeInterval(126))
        let later = timeline.now(jumped, at: t0.addingTimeInterval(127))
        XCTAssertEqual(timeline.workPassed(from: early, to: later).map(\.position), [0])
    }

    func testARoomCanNotSendNumbersAPhoneCanNotCountWith() {
        var wild = TrainTogether.PlanExercise(exercise("Test wild"))
        wild.sets = 1_000_000_000
        wild.repMax = Int.max / 2
        wild.restSeconds = -5
        let made = wild.exercise(id: UUID(), userID: UUID(), programDayID: UUID(), sortOrder: 0)
        XCTAssertEqual(made.sets, 20)
        XCTAssertEqual(made.repMax, 1_000)
        XCTAssertEqual(made.restSeconds, 0)
        var state = started()
        state.extraSeconds = Int.max
        XCTAssertEqual(timeline.now(state, at: t0.addingTimeInterval(1)).duration ?? 0, 120 + 3_600, accuracy: 0.001)
    }

    func testAHostsPrivateNotesStayWithTheHost() {
        var private_ = exercise("Test squat")
        private_.notes = "Knee still sore, go light"
        XCTAssertEqual(TrainTogether.PlanExercise(private_).notes, "")
    }
}
