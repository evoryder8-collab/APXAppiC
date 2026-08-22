import XCTest
@testable import APEX

/*
 * The progression rule decides what load appears on the day sheet, and the
 * Guardian decides when a jump needs a second look. Both are arithmetic that a
 * person trusts without checking, so they are pinned here.
 */
final class ProgressionEngineTests: XCTestCase {
    private let user = UUID()
    private let dayID = UUID()

    private func exercise(repMax: Int = 12, increment: Double = 2.5) -> Exercise {
        Exercise(
            id: UUID(),
            userID: user,
            programDayID: dayID,
            name: "Bench",
            sets: 3,
            repMin: 8,
            repMax: repMax,
            repUnit: "reps",
            perSide: false,
            restSeconds: 120,
            tempoUp: 1,
            tempoDown: 2,
            tempoPause: 0,
            tempoNote: "",
            notes: "",
            incrementKG: increment,
            isLite: false,
            optional: false,
            sortOrder: 0
        )
    }

    private func data(
        _ exercise: Exercise,
        sets: [(date: String, weight: Double, reps: Int, rir: Int?)]
    ) -> DashboardData {
        var data = DashboardData()
        var sessions: [WorkoutSession] = []
        var logs: [WorkoutLog] = []
        var sessionByDate: [String: UUID] = [:]
        for (index, entry) in sets.enumerated() {
            let sessionID = sessionByDate[entry.date] ?? UUID()
            if sessionByDate[entry.date] == nil {
                sessionByDate[entry.date] = sessionID
                sessions.append(
                    WorkoutSession(
                        id: sessionID,
                        userID: user,
                        date: entry.date,
                        programDayID: dayID,
                        isLite: false,
                        isDeload: false,
                        isEventRecovery: false,
                        completed: true,
                        qualityScore: 1,
                        startedAt: nil,
                        completedAt: nil,
                        notes: ""
                    )
                )
            }
            logs.append(
                WorkoutLog(
                    id: UUID(),
                    userID: user,
                    sessionID: sessionID,
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    setNumber: index + 1,
                    weightKG: entry.weight,
                    reps: entry.reps,
                    rir: entry.rir,
                    skipped: false,
                    overrideFlag: false,
                    createdAt: entry.date
                )
            )
        }
        data.workoutSessions = sessions
        data.workoutLogs = logs
        return data
    }

    func testFirstSessionHasNoNumberToRepeat() {
        let move = exercise()
        let recommendation = ProgressionEngine.recommend(DashboardData(), exercise: move)
        XCTAssertNil(recommendation.weight)
        XCTAssertTrue(recommendation.history.isEmpty)
        /* With no history at all the increment itself is the typical step. */
        XCTAssertEqual(recommendation.typicalIncrement, 2.5)
    }

    func testTopOfRangeOnEverySetEarnsTheIncrement() {
        let move = exercise()
        let history = data(move, sets: [
            (date: "2026-01-05", weight: 60, reps: 12, rir: 2),
            (date: "2026-01-05", weight: 60, reps: 12, rir: 2),
        ])
        let recommendation = ProgressionEngine.recommend(history, exercise: move)
        XCTAssertEqual(recommendation.weight, 62.5)
        XCTAssertEqual(recommendation.previous?.weight, 60)
    }

    func testMissingReserveDoesNotEarnTheIncrement() {
        let move = exercise()
        let history = data(move, sets: [
            (date: "2026-01-05", weight: 60, reps: 12, rir: nil),
        ])

        XCTAssertEqual(ProgressionEngine.recommend(history, exercise: move).weight, 60)
    }

    func testZeroOrOneReserveDoesNotEarnTheIncrement() {
        for rir in [0, 1] {
            let move = exercise()
            let history = data(move, sets: [
                (date: "2026-01-05", weight: 60, reps: 12, rir: rir),
            ])

            XCTAssertEqual(ProgressionEngine.recommend(history, exercise: move).weight, 60, "RIR \(rir)")
        }
    }

    func testReserveAtOrAboveTheTargetEarnsTheIncrement() {
        let move = exercise()
        let history = data(move, sets: [
            (date: "2026-01-05", weight: 60, reps: 12, rir: 3),
        ])

        XCTAssertEqual(ProgressionEngine.recommend(history, exercise: move).weight, 62.5)
    }

    func testFallingShortOfTheRangeRepeatsTheLoad() {
        let move = exercise()
        let history = data(move, sets: [
            (date: "2026-01-05", weight: 60, reps: 12, rir: 1),
            (date: "2026-01-05", weight: 60, reps: 10, rir: 1),
        ])
        XCTAssertEqual(ProgressionEngine.recommend(history, exercise: move).weight, 60)
    }

    func testReserveAboveTheTargetEarnsAJump() {
        let move = exercise()
        let history = data(move, sets: [
            (date: "2026-01-05", weight: 60, reps: 12, rir: 3),
        ])
        XCTAssertEqual(ProgressionEngine.recommend(history, exercise: move).weight, 62.5)
    }

    func testBodyweightWorkNeverRecommendsALoad() {
        let move = exercise(increment: 0)
        let history = data(move, sets: [(date: "2026-01-05", weight: 0, reps: 12, rir: 1)])
        XCTAssertNil(ProgressionEngine.recommend(history, exercise: move).weight)
    }

    func testTypicalIncrementIsTheMedianOfRealJumps() {
        let points = [
            ExerciseHistoryPoint(date: "2026-01-01", topWeight: 60, allTopReps: true, atTargetRIR: true),
            ExerciseHistoryPoint(date: "2026-01-08", topWeight: 62.5, allTopReps: true, atTargetRIR: true),
            ExerciseHistoryPoint(date: "2026-01-15", topWeight: 72.5, allTopReps: true, atTargetRIR: true),
            ExerciseHistoryPoint(date: "2026-01-22", topWeight: 75, allTopReps: true, atTargetRIR: true),
        ]
        /* Jumps of 2.5, 10 and 2.5: the outlier must not set the expectation. */
        XCTAssertEqual(ProgressionEngine.typicalIncrement(points, fallback: 5), 2.5)
    }

    func testGuardianLetsAnOrdinaryStepThrough() {
        let move = exercise()
        let history = data(move, sets: [(date: "2026-01-05", weight: 60, reps: 12, rir: 1)])
        let recommendation = ProgressionEngine.recommend(history, exercise: move)
        let verdict = ProgressionEngine.guardianCheck(entered: 62.5, recommendation: recommendation, factor: 1.5)
        XCTAssertFalse(verdict.triggered)
        XCTAssertEqual(verdict.safeLoad, 62.5)
    }

    func testGuardianCatchesASpikeAndOffersASaferLoad() {
        let move = exercise()
        let history = data(move, sets: [(date: "2026-01-05", weight: 60, reps: 12, rir: 1)])
        let recommendation = ProgressionEngine.recommend(history, exercise: move)
        let verdict = ProgressionEngine.guardianCheck(entered: 80, recommendation: recommendation, factor: 1.5)
        XCTAssertTrue(verdict.triggered)
        XCTAssertEqual(verdict.jump, 20)
        XCTAssertEqual(verdict.safeLoad, 62.5)
    }

    func testGoingLighterIsNeverQuestioned() {
        let move = exercise()
        let history = data(move, sets: [(date: "2026-01-05", weight: 60, reps: 12, rir: 1)])
        let recommendation = ProgressionEngine.recommend(history, exercise: move)
        let verdict = ProgressionEngine.guardianCheck(entered: 50, recommendation: recommendation, factor: 1.5)
        XCTAssertFalse(verdict.triggered)
        XCTAssertEqual(verdict.safeLoad, 50)
    }
}
