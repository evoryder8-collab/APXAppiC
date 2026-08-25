/*
 * Golden parity: the Swift StrengthProgress engine must reproduce
 * src/lib/strengthProgress.ts exactly. Fixtures come from running the REAL
 * TypeScript engine (Tools/generate-strength-fixtures.mts).
 */
import XCTest
@testable import APEX

private struct StrengthFixture: Decodable {
    let sessions: [FixtureSession]
    let logs: [FixtureLog]
    let one_rep_max: [OneRepMaxCase]
    let series: [SeriesCase]
    let insights: [InsightCase]
    let joint: [JointCase]
    let checkin_due: [DueCase]
    let checkins: [FixtureCheckin]
}

private struct FixtureSession: Decodable { let id: UUID; let date: String; let completed: Bool }
private struct FixtureLog: Decodable {
    let id: UUID; let session_id: UUID; let exercise_id: UUID?
    let exercise_name: String; let set_no: Int
    let weight_kg: Double?; let reps: Int?; let skipped: Bool
}
private struct OneRepMaxCase: Decodable { let weight: Double; let reps: Int?; let expected: Double }
private struct SeriesCase: Decodable { let key: String; let name: String; let points: [PointCase] }
private struct PointCase: Decodable {
    let session_id: UUID; let date: String
    let top_weight: Double; let estimated_1rm: Double; let volume: Double
}
private struct InsightCase: Decodable { let session_id: UUID; let rows: [InsightRow] }
private struct InsightRow: Decodable {
    let key: String; let name: String
    let days_compared: Int?; let load_delta: Double?; let estimated_1rm_delta: Double?
}
private struct FixtureCheckin: Decodable { let date: String; let arms: Int; let core: Int; let legs: Int }
private struct JointCase: Decodable {
    let current: FixtureCheckin; let previous: FixtureCheckin?; let expected: JointExpectation
}
private struct JointExpectation: Decodable {
    let state: String; let affected: [String]; let average: Double; let highest: Int; let rising: [String]
}
private struct DueCase: Decodable { let today: String; let empty: Bool?; let expected: Bool }

final class StrengthProgressParityTests: XCTestCase {
    private static let fixture: StrengthFixture = {
        guard let url = Bundle(for: StrengthProgressParityTests.self)
            .url(forResource: "strength-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("strength-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(StrengthFixture.self, from: data)
    }()

    private var sessions: [WorkoutSession] {
        Self.fixture.sessions.map { row in
            WorkoutSession(
                id: row.id, userID: UUID(), date: row.date, programDayID: UUID(),
                isLite: false, isDeload: false, isEventRecovery: false,
                completed: row.completed, qualityScore: 1, startedAt: nil, completedAt: nil,
                notes: ""
            )
        }
    }

    private var logs: [WorkoutLog] {
        Self.fixture.logs.map { row in
            WorkoutLog(
                id: row.id, userID: UUID(), sessionID: row.session_id,
                exerciseID: row.exercise_id, exerciseName: row.exercise_name,
                setNumber: row.set_no, weightKG: row.weight_kg, reps: row.reps,
                rir: nil, skipped: row.skipped, overrideFlag: false,
                createdAt: "2026-06-01T12:00:00.000Z"
            )
        }
    }

    private func checkin(_ row: FixtureCheckin) -> StrengthProgress.JointCheckin {
        .init(date: row.date, arms: row.arms, core: row.core, legs: row.legs)
    }

    func testEstimatedOneRepMaxMatchesTheWeb() {
        for scenario in Self.fixture.one_rep_max {
            XCTAssertEqual(
                StrengthProgress.estimatedOneRepMax(weight: scenario.weight, reps: scenario.reps),
                scenario.expected,
                accuracy: 0.0001,
                "\(scenario.weight) kg x \(String(describing: scenario.reps))"
            )
        }
    }

    func testSeriesMatchesTheWeb() {
        let built = StrengthProgress.buildSeries(sessions: sessions, logs: logs)
        XCTAssertEqual(built.map(\.name), Self.fixture.series.map(\.name), "series order drifted")
        for (actual, expected) in zip(built, Self.fixture.series) {
            XCTAssertEqual(actual.key, expected.key)
            XCTAssertEqual(actual.points.map(\.date), expected.points.map(\.date), expected.name)
            for (point, want) in zip(actual.points, expected.points) {
                XCTAssertEqual(point.sessionID, want.session_id, expected.name)
                XCTAssertEqual(point.topWeight, want.top_weight, accuracy: 0.0001, expected.name)
                XCTAssertEqual(point.estimated1RM, want.estimated_1rm, accuracy: 0.0001, expected.name)
                XCTAssertEqual(point.volume, want.volume, accuracy: 0.0001, expected.name)
            }
        }
    }

    func testLegacyStrengthSeriesExcludesSignedBodyweightLoad() {
        let userID = UUID()
        let sessionID = UUID()
        let session = WorkoutSession(
            id: sessionID, userID: userID, date: "2026-08-23", programDayID: UUID(),
            isLite: false, isDeload: false, isEventRecovery: false,
            completed: true, qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
        )
        let rows = [
            WorkoutLog(
                id: UUID(), userID: userID, sessionID: sessionID, exerciseID: nil,
                exerciseName: "Bench Press", setNumber: 1, weightKG: 50, reps: 10,
                rir: 2, skipped: false, overrideFlag: false, createdAt: "2026-08-23T08:00:00Z"
            ),
            WorkoutLog(
                id: UUID(), userID: userID, sessionID: sessionID, exerciseID: nil,
                exerciseName: "Pull-Up", setNumber: 1, weightKG: 10, reps: 8,
                rir: 2, movementID: "pull_up", skipped: false, overrideFlag: false,
                createdAt: "2026-08-23T08:01:00Z"
            ),
        ]

        XCTAssertEqual(
            StrengthProgress.buildSeries(sessions: [session], logs: rows).map(\.name),
            ["Bench Press"]
        )
    }

    func testTrackedHistoryKeepsOnePointPerSessionAcrossRegeneratedExerciseRows() {
        let userID = UUID()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let firstExerciseID = UUID()
        let secondExerciseID = UUID()
        let sessions = [
            WorkoutSession(
                id: firstSessionID, userID: userID, date: "2026-08-01", programDayID: UUID(),
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
            ),
            WorkoutSession(
                id: secondSessionID, userID: userID, date: "2026-08-21", programDayID: UUID(),
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
            ),
        ]
        let rows = [
            (firstSessionID, firstExerciseID, 1, 20.0),
            (firstSessionID, firstExerciseID, 2, 20.0),
            (secondSessionID, secondExerciseID, 1, 25.0),
            (secondSessionID, secondExerciseID, 2, 25.0),
        ].map { sessionID, exerciseID, setNumber, weight in
            WorkoutLog(
                id: UUID(), userID: userID, sessionID: sessionID, exerciseID: exerciseID,
                exerciseName: "Front Lunge", setNumber: setNumber, weightKG: weight, reps: 12,
                rir: 2, movementID: "forward_lunge", skipped: false, overrideFlag: false,
                createdAt: "2026-08-21T08:00:00Z"
            )
        }

        let series = StrengthProgress.buildSeries(sessions: sessions, logs: rows)

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.key, "movement:forward_lunge")
        XCTAssertEqual(series.first?.points.map(\.date), ["2026-08-01", "2026-08-21"])
        XCTAssertEqual(series.first?.points.map(\.topWeight), [20, 25])
        XCTAssertEqual(series.first?.points.map(\.volume), [480, 600])
    }

    func testSessionInsightsMatchTheWeb() {
        for scenario in Self.fixture.insights {
            let rows = StrengthProgress.sessionInsights(
                sessions: sessions, logs: logs, sessionID: scenario.session_id
            )
            XCTAssertEqual(rows.map(\.name), scenario.rows.map(\.name), "insight order drifted")
            for (row, want) in zip(rows, scenario.rows) {
                XCTAssertEqual(row.key, want.key)
                XCTAssertEqual(row.daysCompared, want.days_compared, want.name)
                /* Same reason as the weight trend: two nils compared through
                   NaN prove nothing, so absence is asserted as absence. */
                XCTAssertEqual(row.loadDelta == nil, want.load_delta == nil, want.name)
                XCTAssertEqual(row.estimated1RMDelta == nil, want.estimated_1rm_delta == nil, want.name)
                if let expected = want.load_delta {
                    XCTAssertEqual(row.loadDelta ?? .nan, expected, accuracy: 0.0001, want.name)
                }
                if let expected = want.estimated_1rm_delta {
                    XCTAssertEqual(row.estimated1RMDelta ?? .nan, expected, accuracy: 0.0001, want.name)
                }
            }
        }
    }

    func testJointAssessmentMatchesTheWeb() {
        for scenario in Self.fixture.joint {
            let result = StrengthProgress.assess(
                checkin(scenario.current),
                previous: scenario.previous.map(checkin)
            )
            XCTAssertEqual(result.state.rawValue, scenario.expected.state)
            XCTAssertEqual(result.affected.map(\.rawValue), scenario.expected.affected)
            XCTAssertEqual(result.rising.map(\.rawValue), scenario.expected.rising)
            XCTAssertEqual(result.average, scenario.expected.average, accuracy: 0.0001)
            XCTAssertEqual(result.highest, scenario.expected.highest)
        }
    }

    func testCheckinDueMatchesTheWeb() {
        let rows = Self.fixture.checkins.map(checkin)
        for scenario in Self.fixture.checkin_due {
            XCTAssertEqual(
                StrengthProgress.checkinDue(scenario.empty == true ? [] : rows, today: scenario.today),
                scenario.expected,
                scenario.today
            )
        }
    }

    /// An abandoned session and a skipped set are not strength history.
    func testIncompleteWorkIsExcluded() {
        let built = StrengthProgress.buildSeries(sessions: sessions, logs: logs)
        let bench = built.first { $0.name == "Barbell bench press" }
        XCTAssertNotNil(bench)
        XCTAssertFalse(
            bench?.points.contains { $0.topWeight == 70 } ?? true,
            "a set from an abandoned session reached the series"
        )
        XCTAssertEqual(bench?.points.last?.topWeight, 67.5, "the skipped set should not raise the top weight")
    }

    func testCheckinsDecodeFromSettingsAddons() {
        let addons: [String: JSONValue] = ["joint_checkins": .array([
            .object(["date": .string("2026-08-10"), "arms": .number(7), "core": .number(3), "legs": .number(4)]),
            .object(["date": .string("2026-08-03"), "arms": .number(5), "core": .number(3), "legs": .number(4)]),
            .object(["arms": .number(5)]),
        ])]
        let rows = StrengthProgress.checkins(from: addons)
        XCTAssertEqual(rows.count, 2, "a row without a date is not a check-in")
        XCTAssertEqual(rows.first?.arms, 7)
        XCTAssertEqual(StrengthProgress.checkins(from: [:]).count, 0)
    }
}
