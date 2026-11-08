/*
 * The guided player's timeline. The rules here all guard the same thing:
 * never manufacture work that did not happen.
 */
import XCTest
import SwiftUI
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

    @MainActor
    func testPackagedGuidedArtworkResolvesAndDecodesOffline() throws {
        var pushUp = exercise("Push-ups")
        guard case let .pair(id, cadence)? = GuidedArtwork.movement(pushUp) else {
            return XCTFail("Legacy push-ups must resolve to two bundled endpoint photographs.")
        }
        XCTAssertEqual(id, "push_up")
        XCTAssertEqual(cadence?.first, .eccentric)
        var bike = exercise("Custom activity label")
        bike.movementID = "air_bike"
        guard case let .reference(bikeID)? = GuidedArtwork.movement(bike),
              case let .reference(breakID)? = GuidedArtwork.waterBreak else {
            return XCTFail("The full movement reference and water break must be bundled.")
        }
        for stem in [id + "-1", id + "-2", bikeID, breakID] {
            let image = try XCTUnwrap(GuidedArtwork.image(stem), stem)
            let pixels = try XCTUnwrap(image.cgImage, stem)
            XCTAssertGreaterThan(pixels.height, 0)
            XCTAssertGreaterThan(pixels.width, 0)
        }
        func thumbnail(_ artwork: GuidedArtwork, elapsed: Double) throws -> [UInt8] {
            let playerImage = GuidedArtworkView(artwork: artwork, exercise: pushUp, elapsed: elapsed)
                .frame(width: 200, height: 160)
                .background(.white)
            let rendered = try XCTUnwrap(ImageRenderer(content: playerImage).cgImage)
            // A blank pastel panel passes an image-existence or accessibility check.
            // The photographed athlete and bottle contribute dark pixels in both panels.
            var samples = [UInt8](repeating: 255, count: 64 * 64)
            try samples.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                    bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ))
                context.draw(rendered, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            XCTAssertGreaterThan(samples.filter { $0 < 110 }.count, 20, "The player must render the bundled photograph.")
            return samples
        }
        let pushUpArtwork = GuidedArtwork.pair(id, cadence)
        let raised = try thumbnail(pushUpArtwork, elapsed: 0)
        let lowered = try thumbnail(pushUpArtwork, elapsed: 1)
        XCTAssertGreaterThan(zip(raised, lowered).filter { abs(Int($0) - Int($1)) > 25 }.count, 50)
        _ = try thumbnail(.reference(breakID), elapsed: 0)
        pushUp.movementID = "unknown-custom-id"
        XCTAssertNil(GuidedArtwork.movement(pushUp), "An unresolved stored ID cannot fall back to a different movement.")
        XCTAssertNil(GuidedArtwork.movement(exercise("Any 10-min HIIT video")))
        XCTAssertNil(GuidedArtwork.movement(exercise("abs")))
        XCTAssertNil(GuidedArtwork.movement(exercise("Suitcase Hold or March")))
        XCTAssertEqual(ExerciseCatalog.artworkMovementID(for: exercise("Weighted backpack push-up")), "weighted_push_up")
    }

    @MainActor
    func testEveryLibraryExerciseResolvesToItsOwnDecodablePlayerArtwork() throws {
        let items = ExerciseCatalog.all
        XCTAssertEqual(items.count, 549, "Update the art inventory when changing the exercise library.")
        for item in items {
            try autoreleasepool {
                var prescribed = exercise(item.name)
                prescribed.movementID = item.movementID
                let artwork = try XCTUnwrap(GuidedArtwork.movement(prescribed), item.movementID)
                let stems: [String]
                switch artwork {
                case .reference(let id):
                    XCTAssertEqual(id, item.movementID)
                    stems = [id]
                case .pair(let id, let cadence):
                    XCTAssertEqual(id, item.movementID)
                    XCTAssertNotNil(cadence, id)
                    stems = [id + "-1", id + "-2"]
                }
                for stem in stems {
                    let pixels = try XCTUnwrap(GuidedArtwork.image(stem)?.cgImage, stem)
                    XCTAssertGreaterThan(pixels.width, 0, stem)
                    XCTAssertGreaterThan(pixels.height, 0, stem)
                }
            }
        }
    }

    func testGuidedPhotosFollowOrderedPrescriptionAndPauseAtItsEndpoint() throws {
        var squat = exercise("Barbell Back Squat")
        squat.tempoDown = 3
        squat.tempoPause = 1
        squat.tempoUp = 1
        let downFirst = GuidedPoseCadence(first: .eccentric, pause: .eccentric)
        func cue(_ elapsed: Double, _ reduceMotion: Bool = false) throws -> GuidedPoseCadence.Cue {
            try XCTUnwrap(downFirst.cue(for: squat, elapsed: elapsed, reduceMotion: reduceMotion))
        }
        XCTAssertEqual(try cue(0).concentricOpacity, 1)
        XCTAssertEqual(try cue(0.21).concentricOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(try cue(0.21, true).concentricOpacity, 0)
        XCTAssertEqual(try cue(2.9).label, "Eccentric phase")
        XCTAssertEqual(try cue(3.5).label, "Hold")
        XCTAssertEqual(try cue(3.5).concentricOpacity, 0)
        XCTAssertEqual(try cue(4.6).label, "Concentric phase")
        XCTAssertEqual(try cue(4.6).concentricOpacity, 1)
        XCTAssertEqual(try cue(5.2).label, "Hold")
        XCTAssertEqual(try cue(5.6).label, "Eccentric phase")
        XCTAssertEqual(try cue(10 * PlayerTimeline.repDuration(squat) + 0.25).label, "Hold")

        let upFirst = GuidedPoseCadence(first: .concentric, pause: .concentric)
        XCTAssertEqual(upFirst.cue(for: squat, elapsed: 0, reduceMotion: false)?.concentricOpacity, 0)
        XCTAssertEqual(upFirst.cue(for: squat, elapsed: 1.5, reduceMotion: false)?.concentricOpacity, 1)
        XCTAssertEqual(upFirst.cue(for: squat, elapsed: 2.5, reduceMotion: false)?.concentricOpacity, 0)
        let mid = GuidedPoseCadence(first: .concentric, pause: .mid)
        XCTAssertNil(mid.cue(for: squat, elapsed: 1.5, reduceMotion: false))
        squat.repUnit = "seconds"
        XCTAssertNil(downFirst.cue(for: squat, elapsed: 1.5, reduceMotion: false))
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

    func testDecisionCheckpointRemainsSingleWhenLegacyDataCarriesMultipleSets() {
        let positions = PlayerTimeline.workSequence([
            exercise("Pain check", sets: 3, repUnit: "check")
        ])

        XCTAssertEqual(positions.count, 1)
    }

    func testCompletionFindsMissingJuneSplitSquatSetWithoutInventingWork() throws {
        let exercises = [
            exercise("Hip Thrust", sets: 4),
            exercise("Bulgarian Split Squat", sets: 3, perSide: true),
            exercise("DB Romanian Deadlift", sets: 3),
            exercise("Band Abduction", sets: 2),
        ]
        let recorded = PlayerTimeline.workSequence(exercises).compactMap { position -> WorkoutSetInput? in
            guard !(position.exerciseIndex == 1 && position.setNumber == 3) else { return nil }
            let exercise = exercises[position.exerciseIndex]
            return WorkoutSetInput(
                exerciseID: exercise.id, exerciseName: exercise.name,
                setNumber: position.setNumber, weightKG: 10, reps: 10, rir: 2,
                movementID: exercise.movementID, skipped: false
            )
        }
        XCTAssertEqual(recorded.count, 11)
        let review = PlayerTimeline.completionReviewInputs(exercises: exercises, recorded: recorded)
        XCTAssertEqual(review.count, 1)
        let missing = try XCTUnwrap(review.first)
        XCTAssertEqual(missing.exerciseID, exercises[1].id)
        XCTAssertEqual(missing.setNumber, 3)
        XCTAssertNil(missing.reps)
        XCTAssertNil(missing.weightKG)
        XCTAssertFalse(missing.skipped)
        let repaired = recorded + [ExerciseLogging.resolvingAsSkipped(missing)]
        XCTAssertTrue(PlayerTimeline.completionReviewInputs(exercises: exercises, recorded: repaired).isEmpty)
        XCTAssertEqual(Array(repaired.prefix(11)), recorded, "Repair must retain every actual set unchanged.")

        var unresolved = recorded
        unresolved[0].reps = nil
        XCTAssertEqual(PlayerTimeline.completionReviewInputs(exercises: exercises, recorded: unresolved).count, 2)

        let check = exercise("Pain check", sets: 3, repUnit: "check")
        let explicitCheck = WorkoutSetInput(
            exerciseID: check.id, exerciseName: check.name, setNumber: 1,
            weightKG: nil, reps: nil, rir: nil, skipped: true
        )
        XCTAssertTrue(PlayerTimeline.completionReviewInputs(exercises: [check], recorded: [explicitCheck]).isEmpty)
    }

    @MainActor
    func testRetryingCompletedWorkoutKeepsOneReceiptWithLatestEditedFacts() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.profile?.userID)
        session.data = APEXDebugFixture.dashboard(userID: owner)
        let exercise = try XCTUnwrap(session.data.exercises.first)
        let day = try XCTUnwrap(session.data.programDays.first { $0.id == exercise.programDayID })
        let operation = try XCTUnwrap(session.accountOperationLease())
        let inputs = [WorkoutSetInput(
            exerciseID: exercise.id, exerciseName: exercise.name, setNumber: 1,
            weightKG: nil, reps: 8, rir: 2, movementID: exercise.movementID, skipped: false
        )]
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try await session.completeWorkout(
            day: day, setInputs: inputs, lite: false, startedAt: start,
            completionDate: "2026-11-02", operation: operation
        )
        let receiptID = try XCTUnwrap(first)
        let originalLogs = session.data.workoutLogs.filter { $0.sessionID == receiptID }
        XCTAssertEqual(originalLogs.count, 1)
        var corrected = inputs
        corrected[0].reps = 10
        corrected[0].weightKG = 5
        let retry = try await session.completeWorkout(
            day: day, setInputs: corrected, lite: false, startedAt: start,
            qualityScore: 0.5,
            completionDate: "2026-11-02", operation: operation
        )
        XCTAssertEqual(retry, receiptID)
        XCTAssertEqual(session.data.workoutSessions.filter { $0.id == receiptID }.count, 1)
        XCTAssertEqual(session.data.workoutLogs.filter { $0.sessionID == receiptID }.map(\.id), originalLogs.map(\.id))
        XCTAssertEqual(session.data.workoutLogs.filter { $0.sessionID == receiptID }.first?.reps, 10)
        XCTAssertEqual(session.data.workoutLogs.filter { $0.sessionID == receiptID }.first?.weightKG, 5)
        XCTAssertEqual(session.data.workoutSessions.first { $0.id == receiptID }?.qualityScore, 0.5)
    }

    func testLinkedExercisesRunAsRoundsWithRecoveryAfterThePair() throws {
        let groupID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        func grouped(_ source: Exercise, position: Int) throws -> Exercise {
            let encoded = try JSONEncoder().encode(source)
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            object["work_group_id"] = groupID.uuidString.lowercased()
            object["work_group_position"] = position
            return try JSONDecoder().decode(
                Exercise.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let press = try grouped(exercise("Machine Chest Press", sets: 2, rest: 90), position: 1)
        let row = try grouped(exercise("Seated Cable Row", sets: 2, rest: 75), position: 2)
        let blocks = PlayerTimeline.build(plan([press, row], warmup: "", warmupDuration: 0))
        let order = blocks.compactMap { block -> String? in
            if case .set(let exerciseIndex, let setNumber, _, _, _, _, _, _) = block {
                return "\(exerciseIndex)-\(setNumber)"
            }
            return nil
        }
        XCTAssertEqual(order, ["0-1", "1-1", "0-2", "1-2"])

        let rests = blocks.compactMap { block -> (Int, Int, Int, String)? in
            if case .rest(let exerciseIndex, let afterSet, let duration, let nextLabel, _, _) = block {
                return (exerciseIndex, afterSet, duration, nextLabel)
            }
            return nil
        }
        XCTAssertTrue(rests.contains { $0.0 == 0 && $0.1 == 1 && $0.2 == 15 && $0.3 == "A2 · Seated Cable Row, round 1" })
        XCTAssertTrue(rests.contains { $0.0 == 1 && $0.1 == 1 && $0.2 == 90 && $0.3 == "A1 · Machine Chest Press, round 2" })
    }

    func testLinkedWorkIsCanonicalizedToPerformedRoundOrderBeforePersistence() throws {
        let groupID = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!
        func grouped(_ source: Exercise, position: Int) throws -> Exercise {
            let encoded = try JSONEncoder().encode(source)
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            object["work_group_id"] = groupID.uuidString.lowercased()
            object["work_group_position"] = position
            return try JSONDecoder().decode(
                Exercise.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let push = try grouped(exercise("Bench Press", sets: 2), position: 1)
        let pull = try grouped(exercise("Seated Row", sets: 2), position: 2)
        let exerciseMajor = [
            WorkoutSetInput(exerciseID: push.id, exerciseName: push.name, setNumber: 1, weightKG: 60, reps: 8, rir: 2, skipped: false),
            WorkoutSetInput(exerciseID: push.id, exerciseName: push.name, setNumber: 2, weightKG: 60, reps: 7, rir: 1, skipped: false),
            WorkoutSetInput(exerciseID: pull.id, exerciseName: pull.name, setNumber: 1, weightKG: 50, reps: 10, rir: 2, skipped: false),
            WorkoutSetInput(exerciseID: pull.id, exerciseName: pull.name, setNumber: 2, weightKG: 50, reps: 9, rir: 1, skipped: false),
        ]

        let ordered = PlayerTimeline.persistenceOrder(exerciseMajor, exercises: [push, pull])

        XCTAssertEqual(
            ordered.map { "\($0.exerciseID!.uuidString):\($0.setNumber)" },
            [push, pull, push, pull].enumerated().map {
                "\($0.element.id.uuidString):\($0.offset / 2 + 1)"
            }
        )
    }

    /// Every per-side movement gets a switch, and it lasts as long as that
    /// movement makes it last. Resetting a rear foot on a bench is not the same
    /// job as stepping off and swapping feet, so the two are not the same pause.
    func testEveryPerSideMovementGetsASwitchScaledToTheMovement() {
        func switchSeconds(_ blocks: [PlayerTimeline.Block]) -> Int? {
            for block in blocks {
                if case .sideSwitch(_, _, let duration) = block { return duration }
            }
            return nil
        }

        let split = PlayerTimeline.build(plan([exercise("Bulgarian split squat", sets: 1, perSide: true)]))
        let raise = PlayerTimeline.build(plan([exercise("Single-leg calf raise", sets: 1, perSide: true)]))

        guard let splitSwitch = switchSeconds(split), let raiseSwitch = switchSeconds(raise) else {
            return XCTFail("per-side work needs a moment to change sides")
        }
        XCTAssertGreaterThan(
            splitSwitch, raiseSwitch,
            "resetting a rear foot takes longer than swapping which foot is on the step"
        )
        XCTAssertEqual(raise.filter(\.isSet).count, 2, "per-side work is still two sets")
        XCTAssertEqual(split.filter(\.isSet).count, 2)
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

    func testPrescribedCountdownsKeepZeroAndCustomRestAndWarmupDuration() {
        let zero = PlayerTimeline.BreakPlan(
            kind: .ordinary,
            duration: 0,
            nextLabel: "next"
        )
        let custom = PlayerTimeline.BreakPlan(
            kind: .ordinary,
            duration: 37,
            nextLabel: "next"
        )

        XCTAssertEqual(PlayerTimeline.restCountdownSeconds(zero, fallback: 90), 0)
        XCTAssertEqual(PlayerTimeline.restCountdownSeconds(custom, fallback: 90), 37)
        XCTAssertEqual(PlayerTimeline.restCountdownSeconds(nil, fallback: 52), 52)
        XCTAssertEqual(PlayerTimeline.warmupCountdownSeconds(text: "Prime", duration: 75), 75)
        XCTAssertNil(PlayerTimeline.warmupCountdownSeconds(text: "", duration: 75))
        XCTAssertNil(PlayerTimeline.warmupCountdownSeconds(text: "Prime", duration: 0))
    }

    func testZeroRecoveryKeepsOnlyTheNextMovementsRealSetupTime() throws {
        let bridge = try XCTUnwrap(MovementTiming.movement(named: "Glute Bridge"))

        XCTAssertEqual(
            MovementTiming.transitionSeconds(
                finished: nil,
                next: bridge,
                authoredRest: 0
            ),
            15,
            "zero recovery may retain setup time, but must not become a default 60-second rest"
        )
        XCTAssertEqual(
            MovementTiming.transitionSeconds(
                finished: nil,
                next: bridge,
                authoredRest: 37
            ),
            37,
            "a custom rest remains exact when it already covers setup"
        )
        XCTAssertEqual(
            MovementTiming.transitionSeconds(
                finished: MovementTiming.movement(named: "Barbell Back Squat"),
                next: bridge,
                authoredRest: 37
            ),
            90,
            "positive rest after a high-fatigue movement retains its safety floor"
        )
    }

    func testPassiveCountdownUsesWallClockButInterruptedSetPauses() {
        let persisted = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_000))
        let now = Date(timeIntervalSince1970: 1_025)
        let rest = PlayerTimeline.Block.rest(
            exerciseIndex: 0,
            afterSet: 1,
            duration: 90,
            nextLabel: "next",
            captureLoad: false,
            reviewExercise: false
        )
        let passive = PlayerTimeline.reconcileCountdown(
            block: rest,
            remaining: 60,
            paused: false,
            persistedAt: persisted,
            now: now
        )
        XCTAssertEqual(passive.remaining, 35)
        XCTAssertFalse(passive.paused)
        XCTAssertEqual(
            PlayerTimeline.reconcileCountdown(
                block: rest,
                remaining: 10,
                paused: false,
                persistedAt: persisted,
                now: now
            ).remaining,
            0,
            "an elapsed passive timer restores as completed rather than wrapping or defaulting"
        )
        XCTAssertEqual(
            PlayerTimeline.reconcileCountdown(
                block: rest,
                remaining: 60,
                paused: true,
                persistedAt: persisted,
                now: now
            ).remaining,
            60,
            "a rest the user paused must remain paused across interruption"
        )

        let set = PlayerTimeline.Block.set(
            exerciseIndex: 0,
            setNumber: 1,
            totalSets: 3,
            side: nil,
            resultKey: "0-1",
            targetReps: 10,
            repDuration: 3.5,
            timed: nil
        )
        let active = PlayerTimeline.reconcileCountdown(
            block: set,
            remaining: 60,
            paused: false,
            persistedAt: persisted,
            now: now
        )
        XCTAssertEqual(active.remaining, 60)
        XCTAssertTrue(active.paused)
    }

    func testInterruptedDraftIsAccountScopedRestorableAndClearedOnCompletion() throws {
        let suite = "PlayerTimelineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let userID = UUID()
        let dayID = UUID()
        let exerciseID = UUID()
        let draft = PlayerTimeline.SessionDraft(
            userID: userID,
            dayID: dayID,
            date: "2026-08-25",
            lite: false,
            exerciseIDs: [exerciseID],
            phase: "rest",
            currentIndex: 0,
            currentSet: 1,
            actualReps: 8,
            currentWeight: 60,
            timerRemaining: 45,
            timerTotal: 90,
            paused: false,
            setInputs: [
                WorkoutSetInput(
                    exerciseID: exerciseID,
                    exerciseName: "Back squat",
                    setNumber: 1,
                    weightKG: 60,
                    reps: 8,
                    rir: 2,
                    skipped: false
                )
            ],
            startedAt: Date(timeIntervalSince1970: 1_000),
            repElapsed: 28,
            announcedRep: 8,
            persistedAt: "1970-01-01T00:16:40Z"
        )

        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "setExecution")
        let legacyDraft = try JSONDecoder().decode(
            PlayerTimeline.SessionDraft.self,
            from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        XCTAssertNil(legacyDraft.setExecution, "pre-side-sequencing drafts remain readable")

        var completedDraft = legacyDraft
        completedDraft.phase = "complete"
        XCTAssertNil(completedDraft.performedFinish, "An old draft has no trustworthy exact finish time.")
        completedDraft.performedFinish = "1970-01-01T00:17:40Z"
        completedDraft.persistedAt = "1970-01-02T12:00:00Z"
        PlayerTimeline.DraftStore.save(completedDraft, defaults: defaults)
        XCTAssertEqual(PlayerTimeline.DraftStore.load(
            userID: userID, dayID: dayID, date: draft.date, lite: false,
            exerciseIDs: [exerciseID], defaults: defaults
        ), completedDraft, "A completed but unsaved old draft must retain its actual facts.")

        var sideDraft = draft
        var sideExecution = GuidedSetExecution(perSide: true)
        XCTAssertEqual(sideExecution.finish(work: 8, skipped: false), .switchSide)
        sideDraft.phase = "sideSwitch"
        sideDraft.setExecution = sideExecution
        XCTAssertEqual(
            try JSONDecoder().decode(PlayerTimeline.SessionDraft.self, from: JSONEncoder().encode(sideDraft)),
            sideDraft,
            "the completed left side survives an interrupted side-change countdown"
        )

        PlayerTimeline.DraftStore.save(draft, defaults: defaults)
        XCTAssertEqual(
            PlayerTimeline.DraftStore.load(
                userID: userID,
                dayID: dayID,
                date: draft.date,
                lite: false,
                exerciseIDs: [exerciseID],
                defaults: defaults
            ),
            draft
        )
        XCTAssertNil(PlayerTimeline.DraftStore.load(
            userID: UUID(),
            dayID: dayID,
            date: draft.date,
            lite: false,
            exerciseIDs: [exerciseID],
            defaults: defaults
        ))

        PlayerTimeline.DraftStore.clear(
            userID: userID,
            dayID: dayID,
            date: draft.date,
            lite: false,
            defaults: defaults
        )
        XCTAssertNil(PlayerTimeline.DraftStore.load(
            userID: userID,
            dayID: dayID,
            date: draft.date,
            lite: false,
            exerciseIDs: [exerciseID],
            defaults: defaults
        ))
    }

    func testSideSwitchTimerUsesWallTimeButDoesNotCompleteTheRightSide() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-02T12:01:00Z"))
        var execution = GuidedSetExecution(perSide: true)
        XCTAssertEqual(execution.finish(work: 10, skipped: false), .switchSide)
        let block = PlayerTimeline.Block.sideSwitch(exerciseIndex: 0, setNumber: 1, duration: 27)
        let resumed = PlayerTimeline.reconcileCountdown(
            block: block, remaining: 20, paused: false,
            persistedAt: "2026-11-02T12:00:00Z",
            now: now
        )
        XCTAssertEqual(resumed.remaining, 0)
        XCTAssertEqual(execution.side, .left, "time away cannot manufacture the other side's repetitions")
        let paused = PlayerTimeline.reconcileCountdown(
            block: block, remaining: 20, paused: true,
            persistedAt: "2026-11-02T12:00:00Z",
            now: now
        )
        XCTAssertEqual(paused.remaining, 20)
        XCTAssertTrue(paused.paused)
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

    func testCompletionQualityMatchesWebForSkippedOptionalAndAdjustedSets() {
        func inputs(_ exercises: [Exercise]) -> [WorkoutSetInput] {
            PlayerTimeline.workSequence(exercises).map { position in
                let exercise = exercises[position.exerciseIndex]
                return WorkoutSetInput(
                    exerciseID: exercise.id, exerciseName: exercise.name,
                    setNumber: position.setNumber, weightKG: nil, reps: 10, rir: nil,
                    skipped: false
                )
            }
        }
        let june = [
            exercise("Hip Thrust", sets: 4),
            exercise("Bulgarian Split Squat", sets: 3, perSide: true),
            exercise("DB Romanian Deadlift", sets: 3),
            exercise("Band Abduction", sets: 2),
        ]
        var recorded = inputs(june)
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: june, recorded: recorded), 1)
        recorded[11].skipped = true
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: june, recorded: recorded), 11.0 / 12, accuracy: 0.000001)
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: june, recorded: []), 0)

        // The caller supplies the selected lite/deload prescription, not the
        // unadjusted programme. Optional sets do not increase its denominator.
        let adjusted = [exercise("Hip Thrust", sets: 2), exercise("Extra mobility", sets: 2, optional: true)]
        var adjustedInputs = Array(inputs(adjusted).prefix(2))
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: adjusted, recorded: adjustedInputs), 1)
        adjustedInputs[1].skipped = true
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: adjusted, recorded: adjustedInputs), 0.5)

        let check = [exercise("Pain check", sets: 3, repUnit: "check")]
        XCTAssertEqual(PlayerTimeline.completionQuality(exercises: check, recorded: inputs(check)), 1,
                       "A decision checkpoint is one planned result even when legacy sets exceed one.")
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
