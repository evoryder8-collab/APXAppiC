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

    func testTrackedAndGuidedDefaultsDoNotInventReportedEffort() {
        let exercise = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Bench Press",
            sets: 2, repMin: 8, repMax: 10, repUnit: "reps", perSide: false,
            restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )
        let tracked = TrackedWorkout.setInputs(for: [exercise])
        let guided = [
            GuidedWorkout.setInput(
                for: exercise, setNumber: 1, measuredWork: 8,
                signedLoadKG: 42.5, skipped: false
            ),
            GuidedWorkout.setInput(
                for: exercise, setNumber: 2, measuredWork: 9,
                signedLoadKG: 42.5, skipped: false
            ),
        ]

        XCTAssertEqual(tracked.map(\.rir), [nil, nil])
        XCTAssertEqual(guided.map(\.rir), [nil, nil])
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

    func testLegacyDraftPreservesUnknownStrengthLoadAndResolvesBodyweightToZero() {
        let strength = WorkoutLog(
            id: UUID(), userID: user, sessionID: session, exerciseID: nil,
            exerciseName: "Seated Cable Row", setNumber: 1, weightKG: nil,
            reps: 10, rir: nil, movementID: "seated_cable_row",
            skipped: false, overrideFlag: false, createdAt: "2026-01-05T10:00:00Z"
        )
        let bodyweight = WorkoutLog(
            id: UUID(), userID: user, sessionID: session, exerciseID: nil,
            exerciseName: "Pull-Up", setNumber: 1, weightKG: nil,
            reps: 8, rir: nil, movementID: "pull_up",
            skipped: false, overrideFlag: false, createdAt: "2026-01-05T10:01:00Z"
        )

        let drafts = ManualWorkout.drafts(from: [strength, bodyweight])

        XCTAssertNil(drafts[0].sets[0].weightKG)
        XCTAssertEqual(drafts[1].sets[0].weightKG, 0)
    }

    func testReportedEffortIsKeptInsideTheSupportedRange() {
        XCTAssertEqual(ManualWorkout.SetDraft(rir: -3).rir, 0)
        XCTAssertEqual(ManualWorkout.SetDraft(rir: 12).rir, 5)
    }

    func testTheLastSessionChoiceWinsOverThePlanDefault() {
        XCTAssertEqual(
            WorkoutSessionMode.resolve(lastUsed: "tracked", dayDefault: "guided"),
            .tracked
        )
        XCTAssertEqual(
            WorkoutSessionMode.resolve(lastUsed: nil, dayDefault: "tracked"),
            .tracked
        )
        XCTAssertEqual(
            WorkoutSessionMode.resolve(lastUsed: "not-a-mode", dayDefault: "not-a-mode"),
            .guided
        )
    }
}

final class WorkoutSessionModeContractTests: XCTestCase {
    private let user = UUID()
    private let program = UUID()

    func testMissingSessionModeDecodesToGuidedAndAuthoredModeRoundTrips() throws {
        let id = UUID()
        let oldPayload = """
        {
          "id": "\(id.uuidString)",
          "user_id": "\(user.uuidString)",
          "program_id": "\(program.uuidString)",
          "weekday": 2,
          "name": "Upper",
          "day_type": "strength",
          "est_minutes": 45,
          "warmup_note": "Move well",
          "sort_order": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProgramDay.self, from: oldPayload)
        XCTAssertEqual(decoded.sessionMode, WorkoutSessionMode.guided.rawValue)

        var tracked = decoded
        tracked.sessionMode = WorkoutSessionMode.tracked.rawValue
        let roundTrip = try JSONDecoder().decode(
            ProgramDay.self,
            from: JSONEncoder().encode(tracked)
        )
        XCTAssertEqual(roundTrip.sessionMode, WorkoutSessionMode.tracked.rawValue)
    }

    func testResolutionUsesOnlyValidLastChoiceThenValidAuthoredDefault() {
        XCTAssertEqual(WorkoutSessionMode.resolve(lastUsed: nil, dayDefault: nil), .guided)
        XCTAssertEqual(WorkoutSessionMode.resolve(lastUsed: "invalid", dayDefault: "tracked"), .tracked)
        XCTAssertEqual(WorkoutSessionMode.resolve(lastUsed: "guided", dayDefault: "tracked"), .guided)
    }

    func testTrackedDraftsNeedExplicitActualWorkAndKeepPerSetFactsSeparate() {
        let exercise = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Row",
            sets: 2, repMin: 8, repMax: 10, repUnit: "reps", perSide: false,
            restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )
        var drafts = TrackedWorkout.setInputs(for: [exercise])

        XCTAssertEqual(drafts.map(\.setNumber), [1, 2])
        XCTAssertEqual(drafts.map(\.reps), [nil, nil])
        XCTAssertEqual(drafts.map(\.weightKG), [nil, nil])
        XCTAssertEqual(drafts.map(\.rir), [nil, nil])
        XCTAssertFalse(drafts[1].skipped)
        XCTAssertFalse(TrackedWorkout.isReadyToFinish(drafts))

        drafts[0].reps = 8
        drafts[0].weightKG = 42.5
        drafts[0].rir = 3
        drafts[1].reps = 10
        drafts[1].weightKG = 47.5
        XCTAssertEqual(drafts[0].rir, 3)
        XCTAssertEqual(drafts.map(\.weightKG), [42.5, 47.5])
        XCTAssertTrue(TrackedWorkout.isReadyToFinish(drafts))
    }

    func testTrackedBodyweightDraftStartsAtNeutralSignedLoad() {
        let exercise = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Pull-Up",
            sets: 2, repMin: 5, repMax: 8, repUnit: "reps", perSide: false,
            restSeconds: 120, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )

        let drafts = TrackedWorkout.setInputs(for: [exercise])

        XCTAssertEqual(drafts.map(\.weightKG), [0, 0])
        XCTAssertEqual(drafts.map(\.rir), [nil, nil])
    }

    func testSkippingASetClearsEveryMeasurementAtTheSharedPersistenceBoundary() {
        let input = WorkoutSetInput(
            exerciseID: UUID(), exerciseName: "Row", setNumber: 1,
            weightKG: 42.5, reps: 8, rir: 3, skipped: true
        )

        let persisted = input.normalizedForPersistence()
        XCTAssertTrue(persisted.skipped)
        XCTAssertNil(persisted.weightKG)
        XCTAssertNil(persisted.reps)
        XCTAssertNil(persisted.rir)
    }

    func testTimedTrackedWorkUsesItsAuthoredUnitWithoutRIR() {
        let seconds = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Dead Hang",
            sets: 1, repMin: 30, repMax: 45, repUnit: "seconds", perSide: false,
            restSeconds: 60, tempoUp: 0, tempoDown: 0, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 0, isLite: false,
            optional: false, sortOrder: 0
        )
        let minutes = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Mobility Flow",
            sets: 1, repMin: 5, repMax: 8, repUnit: "minutes", perSide: false,
            restSeconds: 0, tempoUp: 0, tempoDown: 0, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 0, isLite: false,
            optional: false, sortOrder: 1
        )

        XCTAssertEqual(TrackedWorkout.workUnit(for: seconds), .seconds)
        XCTAssertEqual(TrackedWorkout.workUnit(for: minutes), .minutes)
        XCTAssertEqual(TrackedWorkout.plannedWork(for: seconds), 45)
        XCTAssertEqual(TrackedWorkout.plannedWork(for: minutes), 8)
        XCTAssertFalse(TrackedWorkout.allowsRIR(for: seconds))
        XCTAssertFalse(TrackedWorkout.allowsRIR(for: minutes))
        XCTAssertEqual(TrackedWorkout.setInputs(for: [seconds, minutes]).map(\.reps), [nil, nil])
    }

    func testTrackedOptionalNumericEntryParsesAndClearsIndependentSetFacts() {
        XCTAssertEqual(TrackedWorkout.optionalWholeNumber(from: "10", maximum: 600), 10)
        XCTAssertNil(TrackedWorkout.optionalWholeNumber(from: "", maximum: 600))
        XCTAssertNil(TrackedWorkout.optionalWholeNumber(from: "10.5", maximum: 600))

        XCTAssertEqual(TrackedWorkout.optionalDecimal(from: "80", maximum: 1_000), 80)
        XCTAssertEqual(TrackedWorkout.optionalDecimal(from: "80.25", maximum: 1_000), 80.25)
        XCTAssertEqual(TrackedWorkout.optionalDecimal(from: "42.5", maximum: 1_000), 42.5)
        XCTAssertNil(TrackedWorkout.optionalDecimal(from: "", maximum: 1_000))
    }

    func testTrackedPlanTargetsKeepEqualAndRangedAuthoringWithTheirUnits() {
        let exact = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Press",
            sets: 2, repMin: 10, repMax: 10, repUnit: "reps", perSide: false,
            restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )
        let ranged = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Dead Hang",
            sets: 2, repMin: 30, repMax: 45, repUnit: "seconds", perSide: false,
            restSeconds: 90, tempoUp: 0, tempoDown: 0, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 0, isLite: false,
            optional: false, sortOrder: 1
        )

        XCTAssertEqual(TrackedWorkout.plannedRange(for: exact), 10...10)
        XCTAssertEqual(TrackedWorkout.workUnit(for: exact), .reps)
        XCTAssertEqual(TrackedWorkout.plannedRange(for: ranged), 30...45)
        XCTAssertEqual(TrackedWorkout.workUnit(for: ranged), .seconds)
    }

    func testMaxTrackedWorkKeepsItsAuthoredModeAndRequiresCountedActuals() {
        let max = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Pull-up",
            sets: 1, repMin: 1, repMax: 99, repUnit: "max", perSide: false,
            restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )
        var input = TrackedWorkout.setInputs(for: [max])[0]

        XCTAssertEqual(TrackedWorkout.workUnit(for: max), .max)
        XCTAssertEqual(TrackedWorkout.plannedTarget(for: max), "MAX")
        XCTAssertFalse(TrackedWorkout.allowsRIR(for: max))
        XCTAssertFalse(TrackedWorkout.isReadyToFinish([input], exercises: [max], checkDecisions: [:]))

        input.reps = 12
        input.weightKG = 10
        XCTAssertTrue(TrackedWorkout.isReadyToFinish([input], exercises: [max], checkDecisions: [:]))
        XCTAssertNil(input.rir)
    }

    func testCheckTrackedWorkNeedsAnExplicitDecisionAndPersistsNoMeasurements() {
        let check = Exercise(
            id: UUID(), userID: user, programDayID: UUID(), name: "Warm-up",
            sets: 1, repMin: 0, repMax: 0, repUnit: "check", perSide: false,
            restSeconds: 0, tempoUp: 0, tempoDown: 0, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 0, isLite: false,
            optional: false, sortOrder: 0
        )
        let draft = TrackedWorkout.setInputs(for: [check])[0]
        let key = TrackedWorkout.setKey(for: draft)

        XCTAssertEqual(TrackedWorkout.workUnit(for: check), .check)
        XCTAssertEqual(TrackedWorkout.plannedTarget(for: check), "Check")
        XCTAssertFalse(TrackedWorkout.allowsRIR(for: check))
        XCTAssertFalse(TrackedWorkout.isReadyToFinish([draft], exercises: [check], checkDecisions: [:]))

        let completed = TrackedWorkout.applying(.completed, to: draft)
        XCTAssertFalse(completed.skipped)
        XCTAssertNil(completed.reps)
        XCTAssertNil(completed.weightKG)
        XCTAssertNil(completed.rir)
        XCTAssertTrue(TrackedWorkout.isReadyToFinish(
            [completed], exercises: [check], checkDecisions: [key: .completed]
        ))

        let skipped = TrackedWorkout.applying(.skipped, to: draft)
        XCTAssertTrue(skipped.skipped)
        XCTAssertNil(skipped.reps)
        XCTAssertNil(skipped.weightKG)
        XCTAssertNil(skipped.rir)
        XCTAssertTrue(TrackedWorkout.isReadyToFinish(
            [skipped], exercises: [check], checkDecisions: [key: .skipped]
        ))
    }

    func testTrackedEntryUsesDirectNumberAndDecimalKeyboards() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fields = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Training/ExerciseFactFieldsView.swift"))

        XCTAssertTrue(fields.contains("TextField("))
        XCTAssertTrue(fields.contains(".numbersAndPunctuation"))
        XCTAssertTrue(fields.contains(".decimalPad"))
        XCTAssertTrue(fields.contains("exercise-fact-signed-load"))
    }

    func testEveryPlannedStartOffersAndRoutesBothSessionModes() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let daySheet = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Training/WorkoutDaySheet.swift"))
        let programView = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Training/TrainingProgramView.swift"))

        XCTAssertTrue(daySheet.contains("WorkoutSessionModeButtons("))
        XCTAssertTrue(programView.contains("WorkoutSessionModeButtons("))
        XCTAssertTrue(daySheet.contains("TrackedWorkoutView("))
        XCTAssertTrue(programView.contains("TrackedWorkoutView("))
        XCTAssertTrue(programView.contains("session.completeWorkout(\n                day: day, setInputs: setInputs, lite: lite, startedAt: startedAt\n            )"))
    }

    func testCustomBuilderPersistsItsAuthoredSessionMode() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let builder = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Training/CustomWorkoutBuilder.swift"))
        let appSession = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"))

        XCTAssertTrue(builder.contains("@State private var sessionMode"))
        XCTAssertTrue(builder.contains("sessionMode: sessionMode"))
        XCTAssertTrue(appSession.contains("sessionMode: WorkoutSessionMode"))
        XCTAssertTrue(appSession.contains("sessionMode: sessionMode.rawValue"))
    }
}

final class TrainingInductionTests: XCTestCase {
    private let user = UUID()

    private struct CrossClientRevisionFixture: Decodable {
        struct Input: Decodable {
            let start_date: String
            let inactivity: String
            let venue: String
            let equipment: [String]
            let pain_areas: [String]
            let recent_operation: Bool
            let chronic_lower_back_pain: Bool
            let sessions_per_week: Int
            let goal: String
        }

        struct Expected: Decodable {
            let first_day_id: UUID
            let first_exercise_id: UUID
        }

        let user_id: UUID
        let generation_revision: Int
        let input: Input
        let expected: Expected
    }

    private func input(_ mutate: (inout TrainingInduction.Input) -> Void = { _ in })
        -> TrainingInduction.Input {
        var value = TrainingInduction.Input(startDate: "2026-01-05")
        mutate(&value)
        return value
    }

    func testSkippingSubmitsNoQuestionnaireAnswersAndBuildsNoPlan() throws {
        let submission = TrainingInduction.Submission.skipped

        XCTAssertFalse(submission.requiresProfile)
        XCTAssertNil(submission.profileGoal)
        XCTAssertNil(submission.generatedPlan(userID: user, existingPrograms: []))

        let settingsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SettingsCreationRequest(userID: user))
            ) as? [String: Any]
        )
        XCTAssertEqual(Set(settingsObject.keys), ["user_id"])
    }

    func testSkippedAccountRoundTripKeepsProfileAndDerivedFactsAbsent() throws {
        let base = try XCTUnwrap(APEXDebugFixture.dashboard().settings?.rebound(to: user))
        let stored = TrainingInduction.Submission.skipped
            .applyingAccountMetadata(to: base, plan: nil)
        let decoded = try JSONDecoder().decode(
            UserSettings.self,
            from: JSONEncoder().encode(stored)
        )

        var data = APEXDebugFixture.dashboard()
        data.profile = nil
        data.settings = decoded
        data.programs = []
        data.programDays = []
        data.exercises = []
        data.snapshots = []

        XCTAssertNil(data.profile)
        XCTAssertEqual(decoded.addons[TrainingInduction.skippedMarkerKey], .bool(true))
        XCTAssertTrue(TrainingInduction.belongsToAccount(data, userID: user))
        XCTAssertTrue(TrainingInduction.isCompatibleDashboard(data, userID: user))
        XCTAssertFalse(TrainingInduction.belongsToAccount(data, userID: UUID()))
        XCTAssertFalse(TrainingInduction.isCompatibleDashboard(data, userID: UUID()))
        XCTAssertTrue(TrainingInduction.shouldEnterPortal(profile: nil, settings: decoded))
        XCTAssertNil(FitnessBrainService.engineInput(from: data))
        XCTAssertTrue(data.programs.isEmpty)
        XCTAssertTrue(data.programDays.isEmpty)
        XCTAssertTrue(data.exercises.isEmpty)
        XCTAssertTrue(data.snapshots.isEmpty)
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: data, slug: "transition"))

        var uninitialized = data
        uninitialized.settings = nil
        XCTAssertTrue(
            TrainingInduction.isCompatibleDashboard(uninitialized, userID: user),
            "an authenticated account with no rows yet is a valid first run"
        )
    }

    func testProfilelessWebInstalledPlanStillEntersPortal() throws {
        var settings = try XCTUnwrap(APEXDebugFixture.dashboard().settings?.rebound(to: user))
        settings.addons.removeValue(forKey: TrainingInduction.skippedMarkerKey)
        settings.addons["newbie_mode"] = .bool(true)
        settings.addons["training_induction"] = .object([
            "generation_revision": .number(2),
        ])

        XCTAssertTrue(TrainingInduction.shouldEnterPortal(profile: nil, settings: settings))
    }

    func testProfilelessRestoredPlanStillEntersPortalButBlankSettingsDoNot() throws {
        var settings = try XCTUnwrap(APEXDebugFixture.dashboard().settings?.rebound(to: user))
        settings.addons = [:]
        XCTAssertFalse(TrainingInduction.shouldEnterPortal(profile: nil, settings: settings))

        settings.addons[TrainingInduction.archivedMarkerKey] = .array([.string(UUID().uuidString)])
        settings.addons[TrainingInduction.generationRevisionKey] = .number(3)
        XCTAssertTrue(TrainingInduction.shouldEnterPortal(profile: nil, settings: settings))
    }

    func testProfilelessInstalledPlanCanOwnWorkoutFactsWithoutInventedWeight() throws {
        var data = APEXDebugFixture.dashboard()
        data.profile = nil
        data.settings = try XCTUnwrap(data.settings?.rebound(to: user))
        let plan = TrainingInduction.generate(
            userID: user,
            input: input(),
            existingPrograms: []
        )
        let day = try XCTUnwrap(plan.programDays.first)
        XCTAssertEqual(TrainingInduction.workoutOwnerID(in: data, day: day), user)

        let foreignPlan = TrainingInduction.generate(
            userID: UUID(),
            input: input(),
            existingPrograms: []
        )
        XCTAssertNil(TrainingInduction.workoutOwnerID(
            in: data,
            day: try XCTUnwrap(foreignPlan.programDays.first)
        ))

        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(appSession.range(of: "func completeWorkout(\n        day: ProgramDay,\n        setInputs:"))
        let end = try XCTUnwrap(
            appSession.range(of: "func toggleDeload", range: start.upperBound..<appSession.endIndex)
        )
        let completion = String(appSession[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(completion.contains("guard let ownerID = TrainingInduction.workoutOwnerID"))
        XCTAssertFalse(completion.contains("guard let profile else { return nil }"))
        XCTAssertTrue(completion.contains("if let profile, profile.userID == ownerID"))
        XCTAssertGreaterThanOrEqual(
            completion.components(separatedBy: "ownerID: ownerID").count - 1,
            2,
            "profileless session and set failures must enqueue under the verified account owner"
        )

        let persistStart = try XCTUnwrap(appSession.range(of: "private func persistUpsert"))
        let persistEnd = try XCTUnwrap(
            appSession.range(of: "private func saveLocalSnapshot", range: persistStart.upperBound..<appSession.endIndex)
        )
        let persistence = String(appSession[persistStart.lowerBound..<persistEnd.lowerBound])
        XCTAssertTrue(persistence.contains("let persistenceOwnerID = verifiedPersistenceOwnerID(ownerID)"))
        XCTAssertGreaterThanOrEqual(
            persistence.components(separatedBy: "guard let userID = persistenceOwnerID else { return }").count - 1,
            2,
            "both upsert and delete failures must retain settings-only account writes"
        )

        let waterStart = try XCTUnwrap(appSession.range(of: "func adjustWater"))
        let waterEnd = try XCTUnwrap(appSession.range(of: "func setWaterTotal", range: waterStart.upperBound..<appSession.endIndex))
        let water = String(appSession[waterStart.lowerBound..<waterEnd.lowerBound])
        XCTAssertTrue(water.contains("guard let ownerID = verifiedPersistenceOwnerID()"))
        XCTAssertFalse(water.contains("guard let profile"))

        let deloadStart = try XCTUnwrap(appSession.range(of: "func toggleDeload"))
        let deloadEnd = try XCTUnwrap(appSession.range(of: "func exportOrbitData", range: deloadStart.upperBound..<appSession.endIndex))
        let deload = String(appSession[deloadStart.lowerBound..<deloadEnd.lowerBound])
        XCTAssertTrue(deload.contains("guard let ownerID = verifiedPersistenceOwnerID()"))
        XCTAssertFalse(deload.contains("guard let profile"))
    }

    func testSkipArchivesAnInterruptedAnsweredAttemptAndClearsItsMarkers() throws {
        let activeDay = UUID()
        let pendingDay = UUID()
        var settings = try XCTUnwrap(APEXDebugFixture.dashboard().settings?.rebound(to: user))
        settings.addons["newbie_mode"] = .bool(true)
        settings.addons["training_induction"] = .object([
            "generation_revision": .number(1),
            "transition_day_ids": .array([.string(activeDay.uuidString)]),
            "main_day_ids": .array([]),
        ])
        settings.addons[TrainingInduction.pendingMarkerKey] = .array([
            .string(pendingDay.uuidString),
        ])

        let skipped = TrainingInduction.Submission.skipped
            .applyingAccountMetadata(to: settings, plan: nil)

        XCTAssertEqual(TrainingInduction.archivedDayIDs(skipped), [activeDay, pendingDay])
        XCTAssertNil(skipped.addons["training_induction"])
        XCTAssertNil(skipped.addons[TrainingInduction.pendingMarkerKey])
        XCTAssertEqual(skipped.addons["newbie_mode"], .bool(false))
        XCTAssertEqual(skipped.addons[TrainingInduction.skippedMarkerKey], .bool(true))
        XCTAssertEqual(TrainingInduction.generationRevision(skipped), 2)
    }

    func testSkipArchivesUnmarkedLegacyGeneratedRows() throws {
        let plan = TrainingInduction.generate(
            userID: user,
            input: input(),
            existingPrograms: [],
            generationRevision: 0
        )
        var settings = try XCTUnwrap(APEXDebugFixture.dashboard().settings?.rebound(to: user))
        settings.addons.removeValue(forKey: "training_induction")
        settings.addons.removeValue(forKey: TrainingInduction.pendingMarkerKey)
        settings.addons.removeValue(forKey: TrainingInduction.archivedMarkerKey)

        var legacy = DashboardData.empty
        legacy.settings = settings
        legacy.programs = plan.programs
        legacy.programDays = plan.programDays
        legacy.exercises = plan.exercises
        XCTAssertFalse(TrainingInduction.legacyGeneratedDayIDs(in: legacy, userID: user).isEmpty)
        XCTAssertTrue(TrainingInduction.hasUsablePrescription(in: legacy, slug: "transition"))

        legacy.settings = TrainingInduction.Submission.skipped.applyingAccountMetadata(
            to: settings,
            plan: nil,
            existingData: legacy
        )

        XCTAssertTrue(
            Set(plan.programDays.map(\.id)).isSubset(of: TrainingInduction.archivedDayIDs(try XCTUnwrap(legacy.settings)))
        )
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: legacy, slug: "transition"))
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: legacy, slug: "main"))
    }

    func testAnsweredSubmissionKeepsItsGoalAndProducesTheRequestedPlan() throws {
        let answers = input {
            $0.goal = "strength"
            $0.venue = "outdoors"
            $0.equipment = ["barbell_plates", "rack"]
            $0.sessionsPerWeek = 5
        }
        let submission = TrainingInduction.Submission.answered(answers)

        XCTAssertTrue(submission.requiresProfile)
        XCTAssertEqual(submission.profileGoal, "maintain")
        let plan = try XCTUnwrap(submission.generatedPlan(userID: user, existingPrograms: []))
        XCTAssertEqual(plan.induction["venue"]?.stringValue, "outdoors")
        XCTAssertEqual(
            plan.induction["equipment"]?.arrayValue?.compactMap(\.stringValue),
            ["barbell_plates", "rack"]
        )
        XCTAssertEqual(plan.induction["sessions_per_week"]?.numberValue, 5)
        for slug in ["transition", "main"] {
            let program = try XCTUnwrap(plan.programs.first { $0.slug == slug })
            let days = plan.programDays.filter { $0.programID == program.id }
            XCTAssertEqual(days.count, 5, "a five-session answer needs five \(slug) days")
            XCTAssertTrue(days.allSatisfy { $0.name.hasPrefix("Outdoor ") })
            XCTAssertTrue(days.allSatisfy { day in
                plan.exercises.contains { $0.programDayID == day.id && !$0.isLite }
            })
            let key = slug == "transition" ? "transition_day_ids" : "main_day_ids"
            XCTAssertEqual(plan.induction[key]?.arrayValue?.count, 5)
        }

        let settings = try XCTUnwrap(APEXDebugFixture.dashboard().settings)
        let installed = submission.applyingAccountMetadata(to: settings, plan: plan)
        XCTAssertEqual(installed.addons["newbie_mode"], .bool(true))
        XCTAssertEqual(installed.addons["training_induction"], .object(plan.induction))

        let skipped = TrainingInduction.Submission.skipped
            .applyingAccountMetadata(to: settings, plan: nil)
        XCTAssertEqual(skipped.addons[TrainingInduction.skippedMarkerKey], .bool(true))
    }

    func testRebuildDraftRoundTripsEveryPersistedAnswer() {
        let answers = input {
            $0.startDate = "2026-04-03"
            $0.inactivity = "over_one_year"
            $0.venue = "outdoors"
            $0.equipment = ["adjustable_dumbbells", "resistance_bands"]
            $0.painAreas = ["knee", "shoulder"]
            $0.recentOperation = false
            $0.chronicLowerBackPain = true
            $0.sessionsPerWeek = 5
            $0.goal = "strength"
        }
        let plan = TrainingInduction.generate(userID: user, input: answers)

        let restored = TrainingInduction.input(
            from: plan.induction,
            fallbackStartDate: "2099-01-01"
        )

        XCTAssertEqual(restored.startDate, answers.startDate)
        XCTAssertEqual(restored.inactivity, answers.inactivity)
        XCTAssertEqual(restored.venue, answers.venue)
        XCTAssertEqual(restored.equipment, answers.equipment)
        XCTAssertEqual(restored.painAreas, answers.painAreas)
        XCTAssertEqual(restored.recentOperation, answers.recentOperation)
        XCTAssertEqual(restored.chronicLowerBackPain, answers.chronicLowerBackPain)
        XCTAssertEqual(restored.sessionsPerWeek, 3, "the form must show the persisted safety-resolved frequency")
        XCTAssertEqual(restored.goal, answers.goal)
    }

    func testWebMetadataNormalizesIntoNativeReturnBuilderVocabulary() {
        let restored = TrainingInduction.input(
            from: [
                "start_date": .string("2026-08-22"),
                "inactivity": .string("one_to_three_months"),
                "venue": .string("outdoors"),
                "equipment": .array([.string("resistance_bands")]),
                "pain_areas": .array([.string("knees"), .string("shoulders")]),
                "recent_operation": .bool(false),
                "chronic_lower_back_pain": .bool(true),
                "sessions_per_week": .number(5),
                "goal": .string("rebuild"),
            ],
            fallbackStartDate: "2099-01-01"
        )

        XCTAssertEqual(restored.inactivity, "under_three_months")
        XCTAssertEqual(restored.painAreas, ["knee", "shoulder"])
        XCTAssertEqual(restored.goal, "general")
        XCTAssertEqual(restored.venue, "outdoors")
        XCTAssertEqual(restored.sessionsPerWeek, 5)
    }

    func testReturnBuilderOffersEveryStoredQuestionAndChoice() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/TrainingInductionPanel.swift")
        )

        for requiredControl in [
            "$draft.goal", "$draft.inactivity", "$draft.venue",
            "draft.equipment", "$draft.sessionsPerWeek", "$draft.recentOperation",
            "$draft.chronicLowerBackPain", "draft.painAreas",
        ] {
            XCTAssertTrue(panel.contains(requiredControl), "missing return-builder control: \(requiredControl)")
        }
        XCTAssertTrue(panel.contains("Text(language.text(\"Outdoors\")).tag(\"outdoors\")"))
        XCTAssertTrue(panel.contains("ForEach(2...5"))
        XCTAssertFalse(
            panel.contains("if draft.venue == \"home\""),
            "equipment answers must remain available for gym and outdoor training"
        )
        XCTAssertTrue(panel.contains("session.installInductionPlan(draft)"))
        XCTAssertFalse(
            panel.contains("input.startDate = Date().apexDateKey"),
            "rebuilding must preserve the persisted phase boundary instead of silently restarting it today"
        )
    }

    func testReturnBuilderInstallAndRestoreAreSingleFlight() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let panel = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/TrainingInductionPanel.swift")
        )
        let settings = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/SettingsView.swift")
        )

        let installStart = try XCTUnwrap(appSession.range(of: "func installInductionPlan"))
        let installEnd = try XCTUnwrap(
            appSession.range(of: "private func applyInductionPlan", range: installStart.upperBound..<appSession.endIndex)
        )
        let install = String(appSession[installStart.lowerBound..<installEnd.lowerBound])
        XCTAssertTrue(install.contains("guard !isBusy else { return }\n        isBusy = true"))
        XCTAssertTrue(install.contains(
            "if accountGeneration.accepts(accountToken) { isBusy = false }"
        ))

        let restoreStart = try XCTUnwrap(appSession.range(of: "func restoreOriginalProgramme"))
        let restore = String(appSession[restoreStart.lowerBound...])
        XCTAssertTrue(restore.contains("guard !isBusy else { return }\n        isBusy = true"))
        XCTAssertTrue(restore.contains(
            "if accountGeneration.accepts(accountToken) { isBusy = false }"
        ))

        XCTAssertGreaterThanOrEqual(
            panel.components(separatedBy: ".disabled(session.isBusy)").count - 1,
            3,
            "open, install, and restore must reject another tap while a plan mutation is running"
        )
        XCTAssertGreaterThanOrEqual(
            settings.components(separatedBy: ".disabled(session.isBusy)").count - 1,
            2,
            "both Settings restore entry points must stop accepting taps during a plan mutation"
        )
    }

    func testOnlyACompleteGeneratedPlanIsDescribedAsActive() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/TrainingInductionPanel.swift")
        )

        XCTAssertTrue(panel.contains(
            "TrainingInduction.hasCompleteGeneratedPlan(in: session.data, slug: slug)"
        ))
        XCTAssertTrue(panel.contains("if hasActiveGeneratedPlan, let current"))
        XCTAssertTrue(panel.contains(
            "hasActiveGeneratedPlan ? \"Your generated plan is active. Rebuild it any time, or restore your original programme from Settings.\""
        ))
        XCTAssertTrue(panel.contains(
            "hasActiveGeneratedPlan ? \"Rebuild my plan\" : \"Build my plan\""
        ))
    }

    func testSettingsRestoresGeneratedRowsThroughTheCleanupAPI() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/SettingsView.swift")
        )
        let service = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Core/Networking/SupabaseService.swift")
        )

        XCTAssertEqual(
            settingsView.components(separatedBy: "Task { await session.restoreOriginalProgramme() }").count - 1,
            2,
            "both switching starter mode off and the explicit Restore action must archive generated rows"
        )
        XCTAssertFalse(
            settingsView.contains("setAddon(\"training_induction\", .null)"),
            "clearing only the marker strands generated rows in every calendar"
        )
        XCTAssertFalse(
            service.contains("func deleteInductionRows"),
            "deleting a generated day cascades through its completed workout sessions and logs"
        )
    }

    func testFirstRunSubmissionIsSingleFlightAndDisablesEveryDecisionControl() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let inductionView = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Onboarding/InductionView.swift")
        )

        XCTAssertTrue(appSession.contains("guard !isBusy else { return }\n        isBusy = true"))
        XCTAssertGreaterThanOrEqual(
            inductionView.components(separatedBy: ".disabled(session.isBusy)").count - 1,
            3,
            "Back, Build/Continue, and Skip must all stop accepting a second choice during submission"
        )
    }

    func testCommittedInductionRefreshIsBestEffortAndCachesSettingsOnlyAccounts() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )

        XCTAssertTrue(appSession.contains("profile?.userID ?? data.settings?.userID"))
        let submitStart = try XCTUnwrap(appSession.range(of: "private func submitInduction"))
        let submitEnd = try XCTUnwrap(
            appSession.range(
                of: "/// Deterministic authenticated first-run",
                range: submitStart.upperBound..<appSession.endIndex
            )
        )
        let submit = String(appSession[submitStart.lowerBound..<submitEnd.lowerBound])
        let pendingApply = try XCTUnwrap(submit.range(of: "data.settings = settings"))
        let pendingSnapshot = try XCTUnwrap(
            submit.range(of: "await saveLocalSnapshot()", range: pendingApply.upperBound..<submit.endIndex)
        )
        let generatedRowWrite = try XCTUnwrap(submit.range(of: "service.saveInductionPlan(plan)"))
        XCTAssertLessThan(pendingApply.lowerBound, pendingSnapshot.lowerBound)
        XCTAssertLessThan(
            pendingSnapshot.lowerBound,
            generatedRowWrite.lowerBound,
            "first-run pending metadata must reach the account cache before generated row writes"
        )
        let finalSnapshot = try XCTUnwrap(submit.range(of: "await saveLocalSnapshot()", options: .backwards))
        let refresh = try XCTUnwrap(submit.range(of: "refreshDashboard(expectedUserID: userID)"))
        let bestEffortFallback = try XCTUnwrap(submit.range(of: "lastSyncAt = .now"))
        XCTAssertLessThan(finalSnapshot.lowerBound, refresh.lowerBound)
        XCTAssertLessThan(refresh.lowerBound, bestEffortFallback.lowerBound)
        let finalMetadata = try XCTUnwrap(submit.range(of: "submission.applyingAccountMetadata"))
        let profileCreation = try XCTUnwrap(submit.range(of: "service.createProfileIfNeeded"))
        XCTAssertLessThan(
            finalMetadata.lowerBound,
            profileCreation.lowerBound,
            "a failed plan write must never strand a synthetic profile before Skip can recover"
        )
        let installStart = try XCTUnwrap(appSession.range(of: "func installInductionPlan"))
        let installEnd = try XCTUnwrap(
            appSession.range(of: "private func applyInductionPlan", range: installStart.upperBound..<appSession.endIndex)
        )
        let install = String(appSession[installStart.lowerBound..<installEnd.lowerBound])
        XCTAssertEqual(
            install.components(separatedBy: "await saveLocalSnapshot()").count - 1,
            3,
            "offline relaunch must retain invalidated, pending, and finally committed plan state"
        )
        XCTAssertFalse(
            install.contains("service.createProfileIfNeeded"),
            "a profileless Skip account must remain settings-only instead of persisting unanswered body defaults"
        )
    }

    func testPlanBuilderIgnoresNewbieModeAndWaitsForScopedGeneratedRows() throws {
        var data = APEXDebugFixture.dashboard()
        data.settings?.addons["newbie_mode"] = .bool(false)

        XCTAssertTrue(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))
        XCTAssertFalse(TrainingInduction.hasCompleteGeneratedPlan(in: data, slug: "transition"))
        XCTAssertFalse(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "custom"))

        let transitionProgram = try XCTUnwrap(data.programs.first { $0.slug == "transition" })
        let transitionDay = try XCTUnwrap(data.programDays.first { $0.programID == transitionProgram.id })
        data.settings?.addons["training_induction"] = .object([
            "transition_day_ids": .array([.string(UUID().uuidString)]),
        ])
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"),
            "a stale marker is not a generated plan"
        )

        let generated = TrainingInduction.generate(
            userID: transitionDay.userID,
            input: input(),
            existingPrograms: data.programs
        )
        data.programs = generated.programs
        data.programDays = generated.programDays
        data.settings?.addons["training_induction"] = .object(generated.induction)
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: data, slug: "transition"))
        XCTAssertTrue(
            TrainingInduction.visibleProgramDays(in: data, slug: "transition").isEmpty,
            "interrupted rows must not remain runnable in the phase list"
        )
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"),
            "days without exercises are an interrupted save, not a usable plan"
        )
        data.exercises = generated.exercises.filter(\.isLite)
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"),
            "a lite-only save cannot satisfy the default Full prescription"
        )
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: data, slug: "transition"))
        data.exercises = generated.exercises
        XCTAssertTrue(TrainingInduction.hasUsablePrescription(in: data, slug: "transition"))
        XCTAssertFalse(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))

        var wrongCount = generated.induction
        wrongCount["sessions_per_week"] = .number(5)
        data.settings?.addons["training_induction"] = .object(wrongCount)
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"),
            "a marker claiming five sessions cannot hide a three-day saved plan"
        )
    }

    func testSimpleHomeSeparatesMissingPrescriptionFromARealRestDay() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let simpleHome = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Portal/SimpleHomeView.swift")
        )

        XCTAssertTrue(simpleHome.contains("private var hasUsableTrainingPlan"))
        XCTAssertTrue(simpleHome.contains("guard hasUsableTrainingPlan else { return false }"))
        XCTAssertTrue(simpleHome.contains("language.text(\"No plan\")"))
        XCTAssertTrue(simpleHome.contains("hasUsablePrescription: hasUsableTrainingPlan"))
        XCTAssertTrue(simpleHome.contains("Text(language.text(\"No training plan yet\"))"))
        XCTAssertTrue(simpleHome.contains("Text(language.text(\"Build plan\"))"))
    }

    func testMarkerlessGeneratedRowsKeepTheRepairRouteVisible() throws {
        var data = APEXDebugFixture.dashboard()
        let profile = try XCTUnwrap(data.profile)
        let generated = TrainingInduction.generate(
            userID: profile.userID,
            input: input(),
            existingPrograms: data.programs
        )
        data.programs = generated.programs
        data.programDays = generated.programDays
        data.exercises = generated.exercises
        data.settings?.addons.removeValue(forKey: "training_induction")

        XCTAssertTrue(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))
        XCTAssertTrue(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "main"))
    }

    func testRelaunchAfterInterruptedExerciseSaveKeepsBuilderAvailable() throws {
        var data = APEXDebugFixture.dashboard()
        let profile = try XCTUnwrap(data.profile)
        let generated = TrainingInduction.generate(
            userID: profile.userID,
            input: input(),
            existingPrograms: data.programs
        )
        let transitionProgram = try XCTUnwrap(generated.programs.first { $0.slug == "transition" })
        let transitionDays = generated.programDays.filter { $0.programID == transitionProgram.id }
        let unfinishedDay = try XCTUnwrap(transitionDays.last?.id)

        data.programs = generated.programs
        data.programDays = generated.programDays
        data.exercises = generated.exercises.filter { $0.programDayID != unfinishedDay }
        data.settings?.addons["training_induction"] = .object(generated.induction)

        let relaunched = data
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: relaunched, slug: "transition"),
            "a failed exercise batch must recover through the builder on relaunch"
        )

        data.exercises = generated.exercises
        XCTAssertFalse(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))
    }

    func testRebuildInvalidatesTheOldMarkerBeforeReplacementRows() throws {
        var data = APEXDebugFixture.dashboard()
        let profile = try XCTUnwrap(data.profile)
        let generated = TrainingInduction.generate(
            userID: profile.userID,
            input: input(),
            existingPrograms: data.programs
        )
        data.programs = generated.programs
        data.programDays = generated.programDays
        data.exercises = generated.exercises
        data.settings?.addons["training_induction"] = .object(generated.induction)
        XCTAssertFalse(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))

        data.settings = data.settings.map { TrainingInduction.invalidatingPlanMetadata($0) }

        XCTAssertNil(data.settings?.addons["training_induction"])
        XCTAssertEqual(
            data.settings.map(TrainingInduction.archivedDayIDs),
            Set(generated.programDays.map(\.id))
        )
        XCTAssertEqual(data.settings.map(TrainingInduction.generationRevision), 1)
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"),
            "a failed rebuild must not let complete old rows hide the repair route"
        )
        XCTAssertFalse(
            TrainingInduction.hasUsablePrescription(in: data, slug: "transition"),
            "invalidated rows pending cleanup cannot drive Today, the calendar, or muscle signal"
        )
    }

    func testPendingRebuildRevisionSurvivesRetryUntilTheNewMarkerCommits() throws {
        var data = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(data.profile?.userID)
        let generated = TrainingInduction.generate(
            userID: owner,
            input: input { $0.sessionsPerWeek = 5 },
            existingPrograms: data.programs
        )
        data = TrainingInduction.applyingGeneratedPlan(
            generated,
            settings: TrainingInduction.Submission.answered(input { $0.sessionsPerWeek = 5 })
                .applyingAccountMetadata(to: try XCTUnwrap(data.settings), plan: generated),
            to: data
        )

        data.settings = data.settings.map { TrainingInduction.invalidatingPlanMetadata($0) }
        data.settings = data.settings.map { TrainingInduction.invalidatingPlanMetadata($0) }
        XCTAssertEqual(
            data.settings.map(TrainingInduction.archivedDayIDs),
            Set(generated.programDays.map(\.id))
        )
        XCTAssertEqual(data.settings.map(TrainingInduction.generationRevision), 1)
        XCTAssertTrue(
            Set(TrainingInduction.activeProgramDays(in: data).map(\.id))
                .isDisjoint(with: Set(generated.programDays.map(\.id)))
        )

        let retrySettings = try XCTUnwrap(data.settings)
        let replacement = TrainingInduction.generate(
            userID: owner,
            input: input(),
            existingPrograms: data.programs,
            generationRevision: TrainingInduction.generationRevision(retrySettings)
        )
        XCTAssertTrue(
            Set(replacement.programDays.map(\.id)).isDisjoint(with: Set(generated.programDays.map(\.id)))
        )
        let committed = TrainingInduction.Submission.answered(input())
            .applyingAccountMetadata(
                to: retrySettings,
                plan: replacement
            )
        XCTAssertEqual(TrainingInduction.archivedDayIDs(committed), Set(generated.programDays.map(\.id)))
        XCTAssertEqual(TrainingInduction.generationRevision(committed), 1)
        XCTAssertNotNil(committed.addons["training_induction"])
    }

    func testRowsSavedBeforeFinalMarkerStayInactiveAndRestorable() throws {
        var data = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(data.profile?.userID)
        let plan = TrainingInduction.generate(
            userID: owner,
            input: input(),
            existingPrograms: data.programs
        )
        let pending = TrainingInduction.markingPendingPlan(
            try XCTUnwrap(data.settings),
            plan: plan
        )
        data.programs = plan.programs
        data.programDays = plan.programDays
        data.exercises = plan.exercises
        data.settings = pending

        XCTAssertNil(pending.addons["training_induction"])
        XCTAssertEqual(TrainingInduction.pendingDayIDs(pending), Set(plan.programDays.map(\.id)))
        XCTAssertFalse(TrainingInduction.hasUsablePrescription(in: data, slug: "transition"))
        XCTAssertTrue(TrainingInduction.visibleProgramDays(in: data, slug: "transition").isEmpty)

        let restored = try XCTUnwrap(
            TrainingInduction.restoration(in: data, userID: owner)
        ).dashboard
        XCTAssertEqual(restored.settings.map(TrainingInduction.archivedDayIDs), Set(plan.programDays.map(\.id)))
        XCTAssertTrue(restored.programDays.contains { $0.id == plan.programDays[0].id })
    }

    func testGeneratedPlanDetectionIsAccountAndPhaseScoped() throws {
        var data = APEXDebugFixture.dashboard()
        let profile = try XCTUnwrap(data.profile)
        let generated = TrainingInduction.generate(
            userID: profile.userID,
            input: input(),
            existingPrograms: data.programs
        )
        let mainProgram = try XCTUnwrap(generated.programs.first { $0.slug == "main" })
        data.programs = generated.programs
        data.programDays = generated.programDays.filter { $0.programID == mainProgram.id }
        let mainDayIDs = Set(data.programDays.map(\.id))
        data.exercises = generated.exercises.filter { mainDayIDs.contains($0.programDayID) }
        data.settings?.addons["training_induction"] = .object(generated.induction)

        XCTAssertFalse(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "main"))
        XCTAssertTrue(TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "transition"))

        data.settings = data.settings?.rebound(to: UUID())
        XCTAssertTrue(
            TrainingInduction.shouldOfferPlanBuilder(in: data, slug: "main"),
            "another account's generated row must not hide this account's plan route"
        )
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

    func testJointPainCapsAFiveSessionRequestAtThree() throws {
        let answers = input {
            $0.painAreas = ["knee"]
            $0.sessionsPerWeek = 5
        }
        let assessment = TrainingInduction.assess(answers)
        XCTAssertEqual(assessment.caution, "cautious")
        XCTAssertEqual(assessment.sessionsPerWeek, 3)

        let plan = TrainingInduction.generate(userID: user, input: answers)
        XCTAssertEqual(
            plan.induction["pain_areas"]?.arrayValue?.compactMap(\.stringValue),
            ["knee"]
        )
        XCTAssertEqual(plan.induction["sessions_per_week"]?.numberValue, 3)
        for program in plan.programs {
            XCTAssertEqual(plan.programDays.filter { $0.programID == program.id }.count, 3)
        }
    }

    func testAReadyBodyKeepsWhatItAskedFor() {
        let assessment = TrainingInduction.assess(input { $0.sessionsPerWeek = 4 })
        XCTAssertEqual(assessment.caution, "standard")
        XCTAssertEqual(assessment.sessionsPerWeek, 4)
        XCTAssertTrue(assessment.reasons.isEmpty)
    }

    func testVenueDisplayNamesKeepOutdoorsDistinctFromHome() {
        XCTAssertEqual(TrainingInduction.venueDisplayName(for: "home"), "Home")
        XCTAssertEqual(TrainingInduction.venueDisplayName(for: "gym"), "Gym")
        XCTAssertEqual(TrainingInduction.venueDisplayName(for: "outdoors"), "Outdoors")
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

    func testShortGeneratedSessionsPersistOneGenericWorkGroupForThePair() throws {
        let plan = TrainingInduction.generate(userID: user, input: input {
            $0.venue = "home"
            $0.equipment = ["adjustable_dumbbells", "resistance_bands"]
            $0.sessionsPerWeek = 3
        })
        let transitionIDs = Set(
            plan.induction["transition_day_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        )
        let day = try XCTUnwrap(plan.programDays.first {
            transitionIDs.contains($0.id.uuidString.lowercased()) && $0.name.contains("Full Body A")
        })
        let encoded = try JSONEncoder().encode(
            plan.exercises.filter { $0.programDayID == day.id && !$0.isLite }
        )
        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        let grouped = rows.filter { $0["work_group_id"] is String }

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(Set(grouped.compactMap { $0["work_group_id"] as? String }).count, 1)
        XCTAssertEqual(grouped.compactMap { $0["work_group_position"] as? Int }, [1, 2])
        XCTAssertEqual(grouped.compactMap { $0["name"] as? String }, ["Dumbbell Floor Press", "One-Arm Dumbbell Row"])

        let runnable = PlannedDay(
            programDay: day,
            exercises: plan.exercises
                .filter { $0.programDayID == day.id && !$0.isLite }
                .map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) },
            warmup: day.warmupNote,
            warmupDuration: 180
        )
        XCTAssertEqual(
            day.estimatedMinutes,
            PlayerTimeline.estimatedMinutes(runnable),
            "the session card must advertise the grouped timeline it actually runs"
        )
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

    func testNativeGenerationMatchesTheSharedWebRevisionFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/training-induction-revision.json")
        let fixture = try JSONDecoder().decode(
            CrossClientRevisionFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        var answers = TrainingInduction.Input(startDate: fixture.input.start_date)
        answers.inactivity = fixture.input.inactivity
        answers.venue = fixture.input.venue
        answers.equipment = fixture.input.equipment
        answers.painAreas = fixture.input.pain_areas
        answers.recentOperation = fixture.input.recent_operation
        answers.chronicLowerBackPain = fixture.input.chronic_lower_back_pain
        answers.sessionsPerWeek = fixture.input.sessions_per_week
        answers.goal = fixture.input.goal

        let generated = TrainingInduction.generate(
            userID: fixture.user_id,
            input: answers,
            generationRevision: fixture.generation_revision
        )

        XCTAssertEqual(generated.programDays.first?.id, fixture.expected.first_day_id)
        XCTAssertEqual(generated.exercises.first?.id, fixture.expected.first_exercise_id)
    }

    func testGenerationNeverReusesAnotherAccountsProgram() throws {
        let foreign = Program(
            id: UUID(),
            userID: UUID(),
            slug: "transition",
            name: "Someone else's plan",
            description: "Foreign"
        )

        let plan = TrainingInduction.generate(
            userID: user,
            input: input(),
            existingPrograms: [foreign]
        )
        let transition = try XCTUnwrap(plan.programs.first { $0.slug == "transition" })
        XCTAssertEqual(transition.userID, user)
        XCTAssertNotEqual(transition.id, foreign.id)
    }

    func testRebuildRefreshesGeneratorOwnedVenueButPreservesAuthoredMetadata() throws {
        let home = TrainingInduction.generate(
            userID: user,
            input: input { $0.venue = "home" }
        )
        let outdoors = TrainingInduction.generate(
            userID: user,
            input: input { $0.venue = "outdoors" },
            existingPrograms: home.programs,
            generationRevision: 1
        )
        let outdoorTransition = try XCTUnwrap(outdoors.programs.first { $0.slug == "transition" })
        XCTAssertEqual(outdoorTransition.id, home.programs.first { $0.slug == "transition" }?.id)
        XCTAssertTrue(outdoorTransition.name.contains("Outdoor"))
        XCTAssertFalse(outdoorTransition.name.contains("Home"))

        let authored = Program(
            id: UUID(),
            userID: user,
            slug: "transition",
            name: "My own foundation",
            description: "Keep this exact text"
        )
        let withAuthored = TrainingInduction.generate(
            userID: user,
            input: input { $0.venue = "outdoors" },
            existingPrograms: [authored]
        )
        XCTAssertEqual(withAuthored.programs.first { $0.slug == "transition" }, authored)
    }

    func testRestoreRoundTripPreservesAuthoredProgramAndArchivesGeneratedRows() throws {
        var installed = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(installed.profile?.userID)
        let originalPrograms = installed.programs
        let originalDayIDs = Set(installed.programDays.map(\.id))
        let originalExerciseIDs = Set(installed.exercises.map(\.id))
        let generated = TrainingInduction.generate(
            userID: owner,
            input: input(),
            existingPrograms: installed.programs
        )
        for program in generated.programs {
            let index = try XCTUnwrap(installed.programs.firstIndex { $0.id == program.id })
            installed.programs[index] = program
        }
        installed.programDays.append(contentsOf: generated.programDays)
        installed.exercises.append(contentsOf: generated.exercises)
        installed.settings = installed.settings.map {
            TrainingInduction.Submission.answered(input())
                .applyingAccountMetadata(to: $0, plan: generated)
        }

        let restoration = try XCTUnwrap(
            TrainingInduction.restoration(in: installed, userID: owner)
        )
        XCTAssertEqual(restoration.dashboard.programs, originalPrograms)
        XCTAssertEqual(
            Set(restoration.dashboard.programDays.map(\.id)),
            originalDayIDs.union(generated.programDays.map(\.id))
        )
        XCTAssertEqual(
            Set(restoration.dashboard.exercises.map(\.id)),
            originalExerciseIDs.union(generated.exercises.map(\.id))
        )
        XCTAssertEqual(Set(restoration.archivedProgramDays.map(\.id)), Set(generated.programDays.map(\.id)))
        XCTAssertEqual(Set(restoration.preservedExercises.map(\.id)), Set(generated.exercises.map(\.id)))
        XCTAssertEqual(
            restoration.dashboard.settings.map(TrainingInduction.archivedDayIDs),
            Set(generated.programDays.map(\.id))
        )
        XCTAssertEqual(
            Set(TrainingInduction.activeProgramDays(in: restoration.dashboard).map(\.id)),
            originalDayIDs
        )
        XCTAssertNil(restoration.dashboard.settings?.addons["training_induction"])
        XCTAssertEqual(restoration.dashboard.settings?.addons["newbie_mode"], .bool(false))
    }

    func testRestorePreservesCompletedGeneratedWorkoutHistoryAndItsReferences() throws {
        let original = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(original.profile?.userID)
        let answers = input()
        let generated = TrainingInduction.generate(
            userID: owner,
            input: answers,
            existingPrograms: original.programs
        )
        let settings = TrainingInduction.Submission.answered(answers)
            .applyingAccountMetadata(to: try XCTUnwrap(original.settings), plan: generated)
        var installed = TrainingInduction.applyingGeneratedPlan(
            generated,
            settings: settings,
            to: original
        )
        let completedDay = try XCTUnwrap(generated.programDays.first)
        let completedExercise = try XCTUnwrap(
            generated.exercises.first { $0.programDayID == completedDay.id }
        )
        let session = WorkoutSession(
            id: UUID(),
            userID: owner,
            date: "2026-08-22",
            programDayID: completedDay.id,
            isLite: false,
            isDeload: false,
            isEventRecovery: false,
            completed: true,
            qualityScore: 1,
            startedAt: "2026-08-22T10:00:00Z",
            completedAt: "2026-08-22T11:00:00Z",
            notes: "Completed"
        )
        let log = WorkoutLog(
            id: UUID(),
            userID: owner,
            sessionID: session.id,
            exerciseID: completedExercise.id,
            exerciseName: completedExercise.name,
            setNumber: 1,
            weightKG: 40,
            reps: 8,
            rir: 2,
            skipped: false,
            overrideFlag: false,
            createdAt: "2026-08-22T11:00:00Z"
        )
        installed.workoutSessions.append(session)
        installed.workoutLogs.append(log)

        let restored = try XCTUnwrap(
            TrainingInduction.restoration(in: installed, userID: owner)
        ).dashboard

        XCTAssertTrue(restored.programDays.contains { $0.id == completedDay.id })
        XCTAssertTrue(restored.exercises.contains { $0.id == completedExercise.id })
        XCTAssertTrue(restored.workoutSessions.contains(session))
        XCTAssertTrue(restored.workoutLogs.contains(log))
        XCTAssertTrue(
            restored.settings.map(TrainingInduction.archivedDayIDs)?.contains(completedDay.id) == true
        )
    }

    func testRebuildKeepsProgressionHistoryForTheSameOwnedMovement() throws {
        var data = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(data.profile?.userID)
        let answers = input()
        let original = TrainingInduction.generate(
            userID: owner,
            input: answers,
            existingPrograms: data.programs
        )
        let originalExercise = try XCTUnwrap(original.exercises.first { !$0.isLite })
        let session = WorkoutSession(
            id: UUID(), userID: owner, date: "2026-08-22",
            programDayID: originalExercise.programDayID,
            isLite: false, isDeload: false, isEventRecovery: false,
            completed: true, qualityScore: 1, startedAt: nil,
            completedAt: "2026-08-22T11:00:00Z", notes: "Completed"
        )
        data.workoutSessions = [session]
        data.workoutLogs = [WorkoutLog(
            id: UUID(), userID: owner, sessionID: session.id,
            exerciseID: originalExercise.id, exerciseName: originalExercise.name,
            setNumber: 1, weightKG: 40, reps: originalExercise.repMax, rir: 2,
            skipped: false, overrideFlag: false, createdAt: "2026-08-22T11:00:00Z"
        )]
        let rebuilt = TrainingInduction.generate(
            userID: owner,
            input: answers,
            existingPrograms: original.programs,
            generationRevision: 1
        )
        let rebuiltExercise = try XCTUnwrap(
            rebuilt.exercises.first {
                !$0.isLite && $0.name == originalExercise.name
            }
        )

        XCTAssertNotEqual(rebuiltExercise.id, originalExercise.id)
        let recommendation = ProgressionEngine.recommend(data, exercise: rebuiltExercise)
        XCTAssertEqual(recommendation.history.count, 1)
        XCTAssertEqual(recommendation.weight, 40 + rebuiltExercise.incrementKG)
    }

    func testRestoreCanClearLegacyEmptyMarkerOrNewbieFlagWithoutGeneratedRows() throws {
        var data = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(data.profile?.userID)
        data.settings?.addons["training_induction"] = .object([:])
        data.settings?.addons["newbie_mode"] = .bool(true)

        let restoration = try XCTUnwrap(
            TrainingInduction.restoration(in: data, userID: owner)
        )
        XCTAssertTrue(restoration.claimedProgramDayIDs.isEmpty)
        XCTAssertNil(restoration.dashboard.settings?.addons["training_induction"])
        XCTAssertEqual(restoration.dashboard.settings?.addons["newbie_mode"], .bool(false))

        data.settings?.addons.removeValue(forKey: "training_induction")
        XCTAssertNotNil(
            TrainingInduction.restoration(in: data, userID: owner),
            "the historical newbie toggle remains reversible even without marker metadata"
        )
    }

    func testGeneratedOverlayListsOnlyItsClaimedDaysFromTheOwnedProgram() throws {
        let original = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(original.profile?.userID)
        let authoredProgram = try XCTUnwrap(
            original.programs.first { $0.userID == owner && $0.slug == "transition" }
        )
        let authoredDayIDs = Set(
            original.programDays.filter { $0.programID == authoredProgram.id }.map(\.id)
        )
        let generated = TrainingInduction.generate(
            userID: owner,
            input: input(),
            existingPrograms: original.programs
        )
        let settings = TrainingInduction.Submission.answered(input())
            .applyingAccountMetadata(to: try XCTUnwrap(original.settings), plan: generated)
        var installed = TrainingInduction.applyingGeneratedPlan(
            generated,
            settings: settings,
            to: original
        )
        let expectedIDs = Set(
            generated.programDays.filter { $0.programID == authoredProgram.id }.map(\.id)
        )

        XCTAssertEqual(
            Set(TrainingInduction.visibleProgramDays(in: installed, slug: "transition").map(\.id)),
            expectedIDs
        )
        XCTAssertTrue(authoredDayIDs.isDisjoint(with: expectedIDs))

        installed.programs.insert(
            Program(
                id: UUID(),
                userID: UUID(),
                slug: "transition",
                name: "Foreign transition",
                description: "Another account"
            ),
            at: 0
        )
        XCTAssertEqual(
            TrainingInduction.ownedProgram(in: installed, slug: "transition")?.id,
            authoredProgram.id,
            "profileless and profiled dashboards must never select another account's same-slug programme"
        )
    }

    func testFiveToThreeRebuildArchivesBothGenerationsAndRestoresOnlyAuthoredRows() throws {
        let original = APEXDebugFixture.dashboard()
        let owner = try XCTUnwrap(original.profile?.userID)
        let originalDayIDs = Set(original.programDays.map(\.id))
        let originalExerciseIDs = Set(original.exercises.map(\.id))

        let fiveInput = input { $0.sessionsPerWeek = 5 }
        let five = TrainingInduction.generate(
            userID: owner,
            input: fiveInput,
            existingPrograms: original.programs
        )
        let fiveSettings = TrainingInduction.Submission.answered(fiveInput)
            .applyingAccountMetadata(to: try XCTUnwrap(original.settings), plan: five)
        let firstInstall = TrainingInduction.applyingGeneratedPlan(
            five,
            settings: fiveSettings,
            to: original
        )

        var rebuilding = firstInstall
        rebuilding.settings = rebuilding.settings.map { TrainingInduction.invalidatingPlanMetadata($0) }
        let rebuildSettings = try XCTUnwrap(rebuilding.settings)
        let threeInput = input { $0.sessionsPerWeek = 3 }
        let three = TrainingInduction.generate(
            userID: owner,
            input: threeInput,
            existingPrograms: rebuilding.programs,
            generationRevision: TrainingInduction.generationRevision(rebuildSettings)
        )
        let threeSettings = TrainingInduction.Submission.answered(threeInput)
            .applyingAccountMetadata(to: rebuildSettings, plan: three)
        let secondInstall = TrainingInduction.applyingGeneratedPlan(
            three,
            settings: threeSettings,
            to: rebuilding
        )
        let restored = try XCTUnwrap(
            TrainingInduction.restoration(in: secondInstall, userID: owner)
        ).dashboard

        let generatedDayIDs = Set(five.programDays.map(\.id)).union(three.programDays.map(\.id))
        let generatedExerciseIDs = Set(five.exercises.map(\.id)).union(three.exercises.map(\.id))
        XCTAssertTrue(Set(five.programDays.map(\.id)).isDisjoint(with: Set(three.programDays.map(\.id))))
        XCTAssertEqual(Set(restored.programDays.map(\.id)), originalDayIDs.union(generatedDayIDs))
        XCTAssertEqual(Set(restored.exercises.map(\.id)), originalExerciseIDs.union(generatedExerciseIDs))
        XCTAssertEqual(restored.settings.map(TrainingInduction.archivedDayIDs), generatedDayIDs)
        XCTAssertEqual(Set(TrainingInduction.activeProgramDays(in: restored).map(\.id)), originalDayIDs)
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
