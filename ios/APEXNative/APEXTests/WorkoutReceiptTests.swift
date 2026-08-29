/*
 * The receipt numbers, matching the web's WorkoutStatsSheet:
 *   volume = sum of weight x reps over non-skipped strength sets
 *   working sets = non-skipped strength sets
 *   movements = every exercise performed, conditioning included
 */
import XCTest
import HealthKit
@testable import APEX

final class WorkoutReceiptTests: XCTestCase {
    private func workout(
        id: UUID = UUID(), userID: UUID, date: String = "2026-08-26",
        dayID: UUID, completed: Bool = true, completedAt: String,
        notes: String = "Completed in tracked mode"
    ) -> WorkoutSession {
        WorkoutSession(
            id: id, userID: userID, date: date, programDayID: dayID,
            isLite: false, isDeload: false, isEventRecovery: false,
            completed: completed, qualityScore: 1,
            startedAt: "\(date)T08:00:00.000Z", completedAt: completedAt,
            notes: notes
        )
    }

    private func log(
        _ name: String, set: Int, weight: Double?, reps: Int?,
        skipped: Bool = false, session: UUID = UUID(), exerciseID: UUID? = nil,
        movementID: String? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), userID: UUID(), sessionID: session, exerciseID: exerciseID,
            exerciseName: name, setNumber: set, weightKG: weight, reps: reps,
            rir: 2, movementID: movementID, skipped: skipped,
            overrideFlag: false, createdAt: "2026-08-19T10:00:00.000Z"
        )
    }

    func testVolumeIsWeightTimesReps() {
        let summary = WorkoutReceipt.summarize([
            log("Back squat", set: 1, weight: 100, reps: 5),
            log("Back squat", set: 2, weight: 100, reps: 5),
            log("Bench press", set: 1, weight: 60, reps: 8),
        ])
        // 100x5 + 100x5 + 60x8 = 1480
        XCTAssertEqual(summary.loadedVolumeKG, 1480, accuracy: 0.0001)
        XCTAssertEqual(summary.workingSets, 3)
        XCTAssertEqual(summary.movements, 2)
        XCTAssertTrue(summary.hasLoad)
    }

    func testASkippedSetContributesNothing() {
        let summary = WorkoutReceipt.summarize([
            log("Back squat", set: 1, weight: 100, reps: 5),
            log("Back squat", set: 2, weight: 100, reps: 5, skipped: true),
        ])
        XCTAssertEqual(summary.loadedVolumeKG, 500, accuracy: 0.0001)
        XCTAssertEqual(summary.workingSets, 1)
        XCTAssertEqual(summary.movements, 1, "a skipped set is still a movement performed")
    }

    /// A bodyweight conditioning episode has no load to report, and counting
    /// it would read as a session of zero effort.
    func testConditioningIsExcludedFromLoadButNotFromMovements() {
        let summary = WorkoutReceipt.summarize([
            log("Back squat", set: 1, weight: 100, reps: 5),
            log("Focus T25 Alpha Cardio", set: 1, weight: nil, reps: nil),
        ])
        XCTAssertEqual(summary.loadedVolumeKG, 500, accuracy: 0.0001)
        XCTAssertEqual(summary.workingSets, 1, "conditioning is not a working set")
        XCTAssertEqual(summary.movements, 2, "but it was still performed")
    }

    func testAMissingWeightOrRepCountsAsNothing() {
        let summary = WorkoutReceipt.summarize([
            log("Pull-up", set: 1, weight: nil, reps: 8),
            log("Plank", set: 1, weight: 0, reps: nil),
        ])
        XCTAssertEqual(summary.loadedVolumeKG, 0, accuracy: 0.0001)
        XCTAssertFalse(summary.hasLoad)
        XCTAssertEqual(summary.workingSets, 2)
    }

    func testAddedBodyweightLoadCountsButAssistanceDoesNot() {
        let summary = WorkoutReceipt.summarize([
            log("Bench Press", set: 1, weight: 50, reps: 10),
            log("Pull-Up", set: 1, weight: -20, reps: 8, movementID: "pull_up"),
            log("Weighted Push-Up", set: 1, weight: 7, reps: 10, movementID: "weighted_push_up"),
        ])

        XCTAssertEqual(summary.loadedVolumeKG, 570, accuracy: 0.0001)
        XCTAssertEqual(summary.workingSets, 3)
    }

    func testReceiptCorrectionUpdatesFactsWithoutChangingTheRecordedSetIdentity() {
        let original = log(
            "Weighted Push-Up", set: 1, weight: 7, reps: 10,
            movementID: "weighted_push_up"
        )
        var correction = WorkoutReceipt.editInput(original)
        correction.weightKG = 12
        correction.reps = 8
        correction.rir = nil

        let updated = WorkoutReceipt.correctedLog(original, with: correction)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.sessionID, original.sessionID)
        XCTAssertEqual(updated.weightKG, 12)
        XCTAssertEqual(updated.reps, 8)
        XCTAssertNil(updated.rir, "an unrated set must remain unrated after correction")
        XCTAssertEqual(WorkoutReceipt.summarize([updated]).loadedVolumeKG, 96, accuracy: 0.0001)
    }

    func testHistoryIncludesQuickAndTrackedSessionsWithoutDependingOnTheCurrentPlanDay() {
        let owner = UUID()
        let trackedDay = UUID()
        let customDay = UUID()
        let tracked = workout(
            userID: owner, dayID: trackedDay,
            completedAt: "2026-08-26T09:00:00.000Z"
        )
        let quick = workout(
            userID: owner, dayID: customDay,
            completedAt: "2026-08-26T12:00:00.000Z",
            notes: ManualWorkout.notes(title: "Lunch break lift")
        )
        let unfinished = workout(
            userID: owner, dayID: trackedDay, completed: false,
            completedAt: "2026-08-26T13:00:00.000Z"
        )
        let foreign = workout(
            userID: UUID(), dayID: trackedDay,
            completedAt: "2026-08-26T14:00:00.000Z"
        )
        let day = ProgramDay(
            id: trackedDay, userID: owner, programID: UUID(), weekday: 3,
            name: "Tracked legs", dayType: "legs_a", estimatedMinutes: 45,
            warmupNote: "", sortOrder: 0
        )

        let history = WorkoutReceipt.history(
            sessions: [tracked, quick, unfinished, foreign],
            days: [day], date: "2026-08-26", ownerID: owner
        )

        XCTAssertEqual(history.map(\.session.id), [quick.id, tracked.id])
        XCTAssertEqual(history.map(\.title), ["Lunch break lift", "Tracked legs"])
        XCTAssertEqual(history.map(\.isQuickLog), [true, false])
    }

    func testRecentHistoryCrossesCalendarDatesButRemainsOwnerScopedAndBounded() {
        let owner = UUID()
        let dayID = UUID()
        let older = workout(
            userID: owner, date: "2026-08-25", dayID: dayID,
            completedAt: "2026-08-25T09:00:00.000Z"
        )
        let newer = workout(
            userID: owner, date: "2026-08-26", dayID: dayID,
            completedAt: "2026-08-26T09:00:00.000Z"
        )
        let foreign = workout(
            userID: UUID(), date: "2026-08-27", dayID: dayID,
            completedAt: "2026-08-27T09:00:00.000Z"
        )

        let history = WorkoutReceipt.history(
            sessions: [older, newer, foreign],
            days: [], date: nil, ownerID: owner, limit: 1
        )

        XCTAssertEqual(history.map(\.session.id), [newer.id])
    }

    func testUnboundedRecentHistoryReturnsEveryOwnedCompletedWorkout() {
        let owner = UUID()
        let dayID = UUID()
        let workouts = (1...10).map { day in
            workout(
                userID: owner,
                date: String(format: "2026-08-%02d", day),
                dayID: dayID,
                completedAt: String(format: "2026-08-%02dT19:00:00.000Z", day)
            )
        }

        let history = WorkoutReceipt.history(
            sessions: workouts, days: [], date: nil, ownerID: owner
        )

        XCTAssertEqual(history.count, 10)
        XCTAssertEqual(history.map(\.session.id), workouts.reversed().map(\.id))
    }

    func testDeletionPlanIncludesOnlyTheOwnedSessionAndItsOwnedSetRows() {
        let owner = UUID()
        let sessionID = UUID()
        let foreignSessionID = UUID()
        let dayID = UUID()
        let owned = workout(
            id: sessionID, userID: owner, dayID: dayID,
            completedAt: "2026-08-26T09:00:00.000Z"
        )
        let foreign = workout(
            id: foreignSessionID, userID: UUID(), dayID: dayID,
            completedAt: "2026-08-26T10:00:00.000Z"
        )
        let first = WorkoutLog(
            id: UUID(), userID: owner, sessionID: sessionID, exerciseID: nil,
            exerciseName: "Front Lunge", setNumber: 1, weightKG: 25, reps: 12,
            rir: 2, skipped: false, overrideFlag: false,
            createdAt: "2026-08-26T08:15:00.000Z"
        )
        let second = WorkoutLog(
            id: UUID(), userID: owner, sessionID: sessionID, exerciseID: nil,
            exerciseName: "Front Lunge", setNumber: 2, weightKG: 25, reps: 12,
            rir: nil, skipped: false, overrideFlag: false,
            createdAt: "2026-08-26T08:17:00.000Z"
        )
        let foreignSet = WorkoutLog(
            id: UUID(), userID: UUID(), sessionID: sessionID, exerciseID: nil,
            exerciseName: "Injected", setNumber: 3, weightKG: 999, reps: 1,
            rir: 0, skipped: false, overrideFlag: false,
            createdAt: "2026-08-26T08:18:00.000Z"
        )

        XCTAssertEqual(
            WorkoutReceipt.deletionPlan(
                sessions: [owned, foreign], logs: [first, second, foreignSet],
                sessionID: sessionID, ownerID: owner
            ),
            WorkoutReceipt.DeletionPlan(sessionID: sessionID, logIDs: [first.id, second.id])
        )
        XCTAssertNil(
            WorkoutReceipt.deletionPlan(
                sessions: [owned, foreign], logs: [first, second],
                sessionID: foreignSessionID, ownerID: owner
            )
        )
    }

    func testExpandedHistoryCardShowsTheReceiptBeforeOfferingOneEditActionAndDeletion() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/WorkoutReceiptSheet.swift")
        )

        XCTAssertTrue(source.contains("ExerciseLogging.factSummary(log)"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 16)"))
        XCTAssertTrue(source.contains("WorkoutReceipt.collapsedDeleteTrayVisible"))
        XCTAssertTrue(source.contains("Delete this finished workout?"))
        XCTAssertTrue(source.contains("Text(language.text(\"Edit receipt\"))"))
        XCTAssertFalse(source.contains("View & edit receipt"))
        XCTAssertFalse(source.contains("Text(language.text(\"Edit workout\"))"))
    }

    func testFinishedHistoryMergesVisibleOwnedHealthKitReceiptsWithoutTreatingThemAsAPEXSessions() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let visibleID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let hiddenID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let visible = ImportedActivity(
            id: visibleID,
            userID: ownerID,
            date: "2026-08-29",
            kind: "endurance",
            activity: "Outdoor Run",
            durationMinutes: 44,
            source: "Constantin’s Apple Watch",
            healthKitWorkoutID: UUID(),
            startedAt: "2026-08-29T07:30:00Z",
            endedAt: "2026-08-29T08:14:00Z",
            workoutNameKey: "health.workout.outdoor_run",
            distanceKM: 8.4,
            activeEnergyKcal: 612,
            sourceBundleIdentifier: "com.apple.health",
            activityTypeRaw: Int(HKWorkoutActivityType.running.rawValue)
        )
        let hidden = ImportedActivity(
            id: hiddenID,
            userID: ownerID,
            date: "2026-08-28",
            kind: "strength",
            activity: "Traditional Strength Training",
            durationMinutes: 50,
            source: "Apple Watch",
            healthKitWorkoutID: UUID(),
            hiddenAt: "2026-08-29T08:00:00Z"
        )
        let foreign = ImportedActivity(
            id: UUID(), userID: UUID(), date: "2026-08-29", kind: "endurance",
            activity: "Cycling", durationMinutes: 30, source: "Apple Watch",
            healthKitWorkoutID: UUID()
        )
        let legacyImport = ImportedActivity(
            id: UUID(), userID: ownerID, date: "2026-08-29", kind: "endurance",
            activity: "Legacy XML row", durationMinutes: 30, source: "Health import"
        )

        let history = WorkoutReceipt.finishedHistory(
            sessions: [],
            days: [],
            importedActivities: [hidden, foreign, legacyImport, visible],
            date: nil,
            ownerID: ownerID,
            limit: nil
        )

        XCTAssertEqual(history.map(\.id), [visibleID])
        guard case let .external(row) = history[0] else {
            return XCTFail("HealthKit row must remain a read-only external receipt")
        }
        XCTAssertEqual(row.distanceKM, 8.4)
        XCTAssertEqual(row.activeEnergyKcal, 612)
    }

    func testLinkedWearableEvidenceNestsUnderItsAPEXReceiptInsteadOfAppearingTwice() {
        let ownerID = UUID()
        let sessionID = UUID()
        let session = workout(
            id: sessionID, userID: ownerID, date: "2026-08-29",
            dayID: UUID(), completedAt: "2026-08-29T11:00:00.000Z"
        )
        let linked = ImportedActivity(
            id: UUID(), userID: ownerID, date: "2026-08-29", kind: "strength",
            activity: "Traditional Strength Training", durationMinutes: 60,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-29T07:58:00.000Z",
            endedAt: "2026-08-29T08:58:00.000Z",
            sourceBundleIdentifier: "com.apple.health",
            apexWorkoutSessionID: sessionID
        )

        let history = WorkoutReceipt.finishedHistory(
            sessions: [session], days: [], importedActivities: [linked],
            date: nil, ownerID: ownerID, limit: nil
        )

        XCTAssertEqual(history.count, 1)
        guard case let .apex(item) = history[0] else {
            return XCTFail("the linked evidence must stay inside the APEX receipt")
        }
        XCTAssertEqual(item.linkedWearable?.id, linked.id)
    }

    func testExternalReceiptOffersHideFromAPEXAndNeverAppleHealthDeletionOrEditing() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/WorkoutReceiptSheet.swift")
        )

        XCTAssertTrue(source.contains("Hide from APEX"))
        XCTAssertTrue(source.contains("The original workout stays in Apple Health."))
        XCTAssertTrue(source.contains("hideExternalWorkoutFromAPEX"))
        XCTAssertTrue(source.contains("externalHistoryCard"))
        XCTAssertFalse(source.contains("deleteHealthKitWorkout"))
    }

    func testExternalReceiptDateUsesTheSelectedLocaleAndParsesFractionalSeconds() {
        let value = WorkoutReceipt.externalDateText(
            "2026-08-29T07:30:00.123Z",
            locale: Locale(identifier: "ro_RO"),
            timeZone: TimeZone(secondsFromGMT: 7_200)!
        )

        XCTAssertTrue(value.contains("09:30"), value)
        XCTAssertFalse(value.contains("2026-08-29T07:30:00.123Z"), value)
    }

    func testFinishedHistoryDefensivelyExcludesAnAPEXHealthKitMirrorImportedBeforeCompletion() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let dayID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let session = workout(
            id: sessionID,
            userID: ownerID,
            date: "2026-08-29",
            dayID: dayID,
            completedAt: "2026-08-29T08:15:00.000Z"
        )
        let mirror = ImportedActivity(
            id: UUID(), userID: ownerID, date: "2026-08-29", kind: "strength",
            activity: "Traditional Strength Training", durationMinutes: 15,
            source: "APEX Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-29T08:00:20.000Z",
            sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"
        )

        let history = WorkoutReceipt.finishedHistory(
            sessions: [session], days: [], importedActivities: [mirror],
            date: nil, ownerID: ownerID, limit: nil
        )

        XCTAssertEqual(history.count, 1)
        guard case let .apex(item) = history[0] else {
            return XCTFail("the native APEX session must win over its HealthKit mirror")
        }
        XCTAssertEqual(item.session.id, sessionID)
    }

    func testHideFromAPEXAlsoRemovesTheExternalWorkoutFromFitnessSignals() throws {
        var data = APEXDebugFixture.dashboard()
        let ownerID = try XCTUnwrap(data.profile?.userID)
        let apexSession = workout(
            userID: ownerID,
            date: "2026-08-29",
            dayID: UUID(),
            completedAt: "2026-08-29T08:45:00.000Z"
        )
        data.workoutSessions = [apexSession]
        data.importedActivities = [
            ImportedActivity(
                id: UUID(), userID: ownerID, date: "2026-08-28", kind: "strength",
                activity: "Hidden", durationMinutes: 45, source: "Apple Health",
                healthKitWorkoutID: UUID(), hiddenAt: "2026-08-29T09:00:00Z"
            ),
            ImportedActivity(
                id: UUID(), userID: ownerID, date: "2026-08-29", kind: "endurance",
                activity: "Visible", durationMinutes: 30, source: "Apple Health",
                healthKitWorkoutID: UUID()
            ),
            ImportedActivity(
                id: UUID(), userID: ownerID, date: "2026-08-29", kind: "strength",
                activity: "APEX mirror", durationMinutes: 45, source: "APEX Watch",
                healthKitWorkoutID: UUID(), startedAt: "2026-08-29T08:00:20.000Z",
                sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"
            ),
            ImportedActivity(
                id: UUID(), userID: ownerID, date: "2026-08-29", kind: "strength",
                activity: "Linked device evidence", durationMinutes: 45,
                source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
                startedAt: "2026-08-29T08:00:30.000Z",
                sourceBundleIdentifier: "com.apple.health",
                apexWorkoutSessionID: apexSession.id
            ),
        ]

        let input = try XCTUnwrap(FitnessBrainService.engineInput(from: data))

        XCTAssertEqual(input.importedActivities.count, 1)
        XCTAssertEqual(input.importedActivities[0].date, "2026-08-29")
        XCTAssertEqual(input.importedActivities[0].kind, .endurance)
    }

    func testCollapsedDeleteTrayRequiresANegativeSwipeOffsetAndNeverReplacesExpandedContent() {
        XCTAssertFalse(WorkoutReceipt.collapsedDeleteTrayVisible(isExpanded: false, revealOffset: 0))
        XCTAssertFalse(WorkoutReceipt.collapsedDeleteTrayVisible(isExpanded: false, revealOffset: 18))
        XCTAssertTrue(WorkoutReceipt.collapsedDeleteTrayVisible(isExpanded: false, revealOffset: -1))
        XCTAssertFalse(WorkoutReceipt.collapsedDeleteTrayVisible(isExpanded: true, revealOffset: -82))
    }

    func testGroupingKeepsThePerformedOrder() {
        let grouped = WorkoutReceipt.grouped([
            log("Bench press", set: 1, weight: 60, reps: 8),
            log("Back squat", set: 1, weight: 100, reps: 5),
            log("Bench press", set: 2, weight: 60, reps: 8),
        ])
        XCTAssertEqual(grouped.map(\.name), ["Bench press", "Back squat"])
        XCTAssertEqual(grouped.first?.logs.count, 2)
    }

    func testLinkedWorkHistoryKeepsThePerformedRoundOrder() throws {
        let userID = UUID()
        let programID = UUID()
        let dayID = UUID()
        let sessionID = UUID()
        let groupID = UUID(uuidString: "cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa")!
        let day = ProgramDay(
            id: dayID, userID: userID, programID: programID, weekday: 1,
            name: "Upper", dayType: "strength", estimatedMinutes: 30,
            warmupNote: "", sortOrder: 0
        )
        func grouped(_ name: String, position: Int) throws -> Exercise {
            let source = Exercise(
                id: UUID(), userID: userID, programDayID: dayID, name: name,
                sets: 2, repMin: 8, repMax: 10, repUnit: "reps", perSide: false,
                restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
                tempoNote: "", notes: "", incrementKG: 2.5,
                isLite: false, optional: false, sortOrder: position - 1
            )
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any]
            )
            object["work_group_id"] = groupID.uuidString.lowercased()
            object["work_group_position"] = position
            return try JSONDecoder().decode(
                Exercise.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        let push = try grouped("Bench Press", position: 1)
        let pull = try grouped("Seated Row", position: 2)
        let workout = WorkoutSession(
            id: sessionID, userID: userID, date: "2026-08-23",
            programDayID: dayID, isLite: false, isDeload: false,
            isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: nil, completedAt: nil, notes: ""
        )
        var data = DashboardData()
        data.programDays = [day]
        data.exercises = [push, pull]
        data.workoutSessions = [workout]
        data.workoutLogs = [
            log(push.name, set: 1, weight: 60, reps: 8, session: sessionID, exerciseID: push.id),
            log(push.name, set: 2, weight: 60, reps: 7, session: sessionID, exerciseID: push.id),
            log(pull.name, set: 1, weight: 50, reps: 10, session: sessionID, exerciseID: pull.id),
            log(pull.name, set: 2, weight: 50, reps: 9, session: sessionID, exerciseID: pull.id),
        ]

        XCTAssertEqual(
            WorkoutLogOrder.performedOrder(data, sessionID: sessionID)
                .map { "\($0.exerciseName):\($0.setNumber)" },
            ["Bench Press:1", "Seated Row:1", "Bench Press:2", "Seated Row:2"]
        )
    }

    func testInsightTextReportsDirection() {
        let point = StrengthProgress.Point(
            sessionID: UUID(), date: "2026-08-19", topWeight: 70,
            estimated1RM: 84, volume: 700, setWeights: [1: 70]
        )
        let reference = StrengthProgress.Point(
            sessionID: UUID(), date: "2026-07-19", topWeight: 65,
            estimated1RM: 78, volume: 650, setWeights: [1: 65]
        )
        let up = StrengthProgress.SessionInsight(
            key: "id:bench", name: "Bench press", current: point,
            previous: reference, reference: reference, daysCompared: 31,
            loadDelta: 5, estimated1RMDelta: 6
        )
        XCTAssertTrue(WorkoutReceipt.insightText(up, language: .english).contains("increased"))
        XCTAssertTrue(WorkoutReceipt.insightText(up, language: .english).contains("5 kg"))

        let flat = StrengthProgress.SessionInsight(
            key: "id:bench", name: "Bench press", current: point,
            previous: reference, reference: reference, daysCompared: 31,
            loadDelta: 0, estimated1RMDelta: 0
        )
        XCTAssertTrue(WorkoutReceipt.insightText(flat, language: .english).contains("held steady"))

        /* Nothing to compare against yet: say so rather than claim a change. */
        let baseline = StrengthProgress.SessionInsight(
            key: "id:bench", name: "Bench press", current: point,
            previous: nil, reference: nil, daysCompared: nil,
            loadDelta: nil, estimated1RMDelta: nil
        )
        XCTAssertTrue(WorkoutReceipt.insightText(baseline, language: .english).contains("baseline"))
    }

    func testStrengthSignalDeduplicatesIdenticalBaselineCopy() {
        let point = StrengthProgress.Point(
            sessionID: UUID(), date: "2026-08-25", topWeight: 25,
            estimated1RM: 35, volume: 600, setWeights: [1: 25, 2: 25]
        )
        let insights = ["Front Lunge", "Reverse Lunge", "Calf Raise"].map { name in
            StrengthProgress.SessionInsight(
                key: "movement:\(name.lowercased())", name: name, current: point,
                previous: nil, reference: nil, daysCompared: nil,
                loadDelta: nil, estimated1RMDelta: nil
            )
        }

        let lines = WorkoutReceipt.distinctInsightTexts(insights, language: .english)

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("baseline"))
    }
}
