/*
 * The receipt numbers, matching the web's WorkoutStatsSheet:
 *   volume = sum of weight x reps over non-skipped strength sets
 *   working sets = non-skipped strength sets
 *   movements = every exercise performed, conditioning included
 */
import XCTest
@testable import APEX

final class WorkoutReceiptTests: XCTestCase {
    private func log(
        _ name: String, set: Int, weight: Double?, reps: Int?,
        skipped: Bool = false, session: UUID = UUID(), exerciseID: UUID? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), userID: UUID(), sessionID: session, exerciseID: exerciseID,
            exerciseName: name, setNumber: set, weightKG: weight, reps: reps,
            rir: 2, skipped: skipped, overrideFlag: false,
            createdAt: "2026-08-19T10:00:00.000Z"
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

    func testSignedBodyweightLoadNeverChangesExternalLoadedVolume() {
        let summary = WorkoutReceipt.summarize([
            log("Bench Press", set: 1, weight: 50, reps: 10),
            log("Pull-Up", set: 1, weight: -20, reps: 8),
            log("Pull-Up", set: 2, weight: 10, reps: 5),
        ])

        XCTAssertEqual(summary.loadedVolumeKG, 500, accuracy: 0.0001)
        XCTAssertEqual(summary.workingSets, 3)
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
