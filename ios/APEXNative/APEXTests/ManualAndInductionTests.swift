import XCTest
@testable import APEX

/*
 * The pieces that write to a person's history: the marker that identifies a
 * manually logged session, the treadmill encoding that survives a round trip,
 * the reconciliation that lets an edit reuse rows, and the induction that
 * generates a whole starting programme.
 */
final class ManualWorkoutTests: XCTestCase {
    private let user = UUID()
    private let session = UUID()

    func testTitleSurvivesTheRoundTrip() {
        let notes = ManualWorkout.notes(title: "Sunday hill session")
        XCTAssertEqual(ManualWorkout.title(fromNotes: notes), "Sunday hill session")
        XCTAssertFalse(ManualWorkout.hasAutomaticTitle(notes))
    }

    func testAnUntitledWorkoutIsMarkedAutomatic() {
        let notes = ManualWorkout.notes(title: "   ")
        XCTAssertTrue(ManualWorkout.hasAutomaticTitle(notes))
        XCTAssertEqual(ManualWorkout.title(fromNotes: notes), "Workout")
    }

    func testManualLogConstructionKeepsReportedEffort() {
        let logs = ManualWorkout.logs(
            userID: user,
            sessionID: session,
            exercises: [
                ManualWorkout.ExerciseDraft(
                    name: "Squat",
                    sets: [ManualWorkout.SetDraft(reps: 8, weightKG: 42.5, rir: 3)]
                )
            ],
            base: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.rir, 3)
    }

    func testQuickAndGuidedDefaultsDoNotInventReportedEffort() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            nativeRoot.appending(path: "APEX/App/AppSession.swift"),
            nativeRoot.appending(path: "APEX/Features/Training/TrainingProgramView.swift")
        ]

        for path in paths {
            let source = try String(contentsOf: path)
            XCTAssertFalse(source.contains("rir: 2"), "\(path.lastPathComponent) fabricates reported effort")
        }
    }

    func testAPlannedSessionIsNotMistakenForAManualOne() {
        XCTAssertNil(ManualWorkout.title(fromNotes: ""))
        XCTAssertNil(ManualWorkout.title(fromNotes: "Felt strong today"))
        XCTAssertFalse(ManualWorkout.hasAutomaticTitle("Felt strong today"))
    }

    func testTreadmillMetricsRideInsideTheName() {
        let metrics = ManualWorkout.TreadmillDraft(distanceKM: 5.5, inclineDegrees: 3, durationMinutes: 32)
        let encoded = ManualWorkout.encodeTreadmill(name: "Treadmill", metrics: metrics)
        XCTAssertEqual(encoded, "Treadmill · 5.5 km · 3° · 32 min")
        let parsed = ManualWorkout.parseTreadmill(encoded)
        XCTAssertEqual(parsed?.name, "Treadmill")
        XCTAssertEqual(parsed?.metrics, metrics)
        XCTAssertEqual(ManualWorkout.baseName(encoded), "Treadmill")
    }

    func testAPlainNameIsLeftAlone() {
        XCTAssertNil(ManualWorkout.parseTreadmill("Goblet Squat"))
        XCTAssertEqual(ManualWorkout.baseName("Goblet Squat"), "Goblet Squat")
    }

    private func log(_ name: String, set: Int, id: UUID = UUID(), at: String = "2026-01-05T10:00:00Z") -> WorkoutLog {
        WorkoutLog(
            id: id, userID: user, sessionID: session, exerciseID: nil, exerciseName: name,
            setNumber: set, weightKG: nil, reps: 10, rir: nil, skipped: false,
            overrideFlag: false, createdAt: at
        )
    }

    func testAnEditReusesTheRowsItReplaces() {
        let firstID = UUID()
        let secondID = UUID()
        let existing = [log("Squat", set: 1, id: firstID), log("Squat", set: 2, id: secondID)]
        let next = [log("Squat", set: 1), log("Squat", set: 2)]
        let result = ManualWorkout.reconcile(existing: existing, next: next)
        XCTAssertEqual(result.logs.map(\.id), [firstID, secondID])
        XCTAssertTrue(result.staleIDs.isEmpty)
    }

    func testDroppedSetsAreReportedAsStale() {
        let keep = UUID()
        let drop = UUID()
        let existing = [log("Squat", set: 1, id: keep), log("Squat", set: 2, id: drop)]
        let result = ManualWorkout.reconcile(existing: existing, next: [log("Squat", set: 1)])
        XCTAssertEqual(result.logs.map(\.id), [keep])
        XCTAssertEqual(result.staleIDs, [drop])
    }

    func testANewMovementKeepsItsOwnIdentity() {
        let existing = [log("Squat", set: 1)]
        let fresh = log("Bench", set: 1)
        let result = ManualWorkout.reconcile(existing: existing, next: [fresh])
        XCTAssertEqual(result.logs.map(\.id), [fresh.id])
        XCTAssertEqual(result.staleIDs, existing.map(\.id))
    }

    func testTreadmillRowsMatchOnTheMovementNotTheMetrics() {
        let existingID = UUID()
        let before = ManualWorkout.encodeTreadmill(
            name: "Treadmill",
            metrics: .init(distanceKM: 4, inclineDegrees: 1, durationMinutes: 25)
        )
        let after = ManualWorkout.encodeTreadmill(
            name: "Treadmill",
            metrics: .init(distanceKM: 6, inclineDegrees: 2, durationMinutes: 40)
        )
        let result = ManualWorkout.reconcile(
            existing: [log(before, set: 1, id: existingID)],
            next: [log(after, set: 1)]
        )
        /* The run got longer; it is still the same row. */
        XCTAssertEqual(result.logs.map(\.id), [existingID])
        XCTAssertTrue(result.staleIDs.isEmpty)
    }

    func testASetOnlyCarriesEffortWhenTheUserReportsIt() {
        let unreported = ManualWorkout.SetDraft(reps: 8, weightKG: 42.5)
        let reported = ManualWorkout.SetDraft(reps: 8, weightKG: 42.5, rir: 1)

        XCTAssertNil(unreported.rir)
        XCTAssertEqual(reported.rir, 1)
    }

    func testReportedEffortIsKeptInsideTheSupportedRange() {
        XCTAssertEqual(ManualWorkout.SetDraft(rir: -3).rir, 0)
        XCTAssertEqual(ManualWorkout.SetDraft(rir: 12).rir, 5)
    }
}

final class TrainingInductionTests: XCTestCase {
    private let user = UUID()

    private func input(_ mutate: (inout TrainingInduction.Input) -> Void = { _ in })
        -> TrainingInduction.Input {
        var value = TrainingInduction.Input(startDate: "2026-01-05")
        mutate(&value)
        return value
    }

    func testARecentOperationStopsLoadedTraining() {
        let assessment = TrainingInduction.assess(input { $0.recentOperation = true; $0.sessionsPerWeek = 4 })
        XCTAssertEqual(assessment.caution, "clearance")
        XCTAssertEqual(assessment.sessionsPerWeek, 2)
        XCTAssertTrue(assessment.reasons.contains("Recent operation reported"))
    }

    func testALongLayoffTrimsAFourthSession() {
        let assessment = TrainingInduction.assess(input {
            $0.inactivity = "over_one_year"
            $0.sessionsPerWeek = 4
        })
        XCTAssertEqual(assessment.caution, "cautious")
        XCTAssertEqual(assessment.sessionsPerWeek, 3)
    }

    func testAReadyBodyKeepsWhatItAskedFor() {
        let assessment = TrainingInduction.assess(input { $0.sessionsPerWeek = 4 })
        XCTAssertEqual(assessment.caution, "standard")
        XCTAssertEqual(assessment.sessionsPerWeek, 4)
        XCTAssertTrue(assessment.reasons.isEmpty)
    }

    func testTheGeneratedPlanCoversBothPhases() {
        let plan = TrainingInduction.generate(userID: user, input: input { $0.sessionsPerWeek = 3 })
        XCTAssertEqual(plan.programs.map(\.slug).sorted(), ["main", "transition"])
        XCTAssertEqual(plan.programDays.count, 6)
        XCTAssertFalse(plan.exercises.isEmpty)
        /* Every generated day is claimed by the induction, which is what keeps
           the calendar narrowed to them. */
        let transitionIDs = plan.induction["transition_day_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(transitionIDs.count, 3)
    }

    func testTheMainPhaseOpensTwelveWeeksOut() {
        let plan = TrainingInduction.generate(userID: user, input: input())
        XCTAssertEqual(plan.induction["main_start_date"]?.stringValue, "2026-03-30")
        XCTAssertEqual(plan.induction["start_date"]?.stringValue, "2026-01-05")
    }

    func testClearanceReplacesTheWholeTemplateSet() {
        let plan = TrainingInduction.generate(userID: user, input: input { $0.recentOperation = true })
        XCTAssertTrue(plan.programDays.allSatisfy { $0.dayType == "mobility" })
        XCTAssertTrue(plan.programDays.contains { $0.name.hasPrefix("Clearance Reset") })
    }

    func testEquipmentDecidesTheMovements() {
        let bare = TrainingInduction.generate(userID: user, input: input())
        let equipped = TrainingInduction.generate(userID: user, input: input {
            $0.equipment = ["adjustable_dumbbells", "pullup_bar"]
        })
        XCTAssertTrue(bare.exercises.contains { $0.name == "Controlled Chair Squat" })
        XCTAssertTrue(equipped.exercises.contains { $0.name == "Goblet Squat" })
        XCTAssertTrue(equipped.exercises.contains { $0.name == "Assisted Pull-Up" })
    }

    func testGeneratedIdsAreStableForTheSamePerson() {
        let first = TrainingInduction.generate(userID: user, input: input())
        let second = TrainingInduction.generate(userID: user, input: input())
        XCTAssertEqual(first.programDays.map(\.id), second.programDays.map(\.id))
        XCTAssertEqual(first.exercises.map(\.id), second.exercises.map(\.id))
    }

    func testCautionSlowsTheTempoAndSaysWhy() {
        let plan = TrainingInduction.generate(userID: user, input: input { $0.chronicLowerBackPain = true })
        XCTAssertTrue(plan.programDays.allSatisfy { $0.warmupNote.contains("pain-free") })
        XCTAssertTrue(plan.exercises.allSatisfy { $0.tempoDown == 3 })
        XCTAssertEqual(plan.induction["caution"]?.stringValue, "cautious")
    }

    func testEveryDayCarriesALightVariant() {
        let plan = TrainingInduction.generate(userID: user, input: input { $0.sessionsPerWeek = 2 })
        for day in plan.programDays {
            let rows = plan.exercises.filter { $0.programDayID == day.id }
            XCTAssertFalse(rows.filter(\.isLite).isEmpty, "\(day.name) has no light rows")
            XCTAssertLessThanOrEqual(
                rows.filter(\.isLite).count, rows.filter { !$0.isLite }.count,
                "\(day.name) light should not exceed full"
            )
        }
    }
}
