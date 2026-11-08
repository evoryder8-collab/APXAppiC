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

    func testLegacyTimedAndChecklistQuantitiesCountOnlyAsPerformedSets() throws {
        let session = try XCTUnwrap(sessions.first(where: \.completed))
        func prescription(_ name: String, owner: UUID? = nil, unit: String = "seconds") -> Exercise {
            Exercise(id: UUID(), userID: owner ?? session.userID, programDayID: session.programDayID,
                     name: name, sets: 1, repMin: 1, repMax: 30, repUnit: unit, perSide: false,
                     restSeconds: 30, tempoUp: 1, tempoDown: 1, tempoPause: 0, tempoNote: "", notes: "",
                     incrementKG: 0, isLite: false, optional: false, sortOrder: 0)
        }
        let side = prescription("Side Plank")
        func row(_ name: String, _ reps: Int?, id: UUID? = nil, seconds: Int? = nil, skipped: Bool = false) -> WorkoutLog {
            WorkoutLog(id: UUID(), userID: session.userID, sessionID: session.id, exerciseID: id,
                       exerciseName: name, setNumber: 1, weightKG: 10, reps: reps, rir: nil,
                       durationSeconds: seconds, skipped: skipped, overrideFlag: false, createdAt: session.date)
        }
        let rows = (0..<4).map { _ in row("Dead Hang", 30) } + (0..<2).map { _ in row("Side Plank", 25, id: side.id) } + [
            row("Cable hold practice", 12, id: UUID()), row("Focus T25 · Stretch", 1),
            row("FocusT25 session (Shaun T), Alpha or Beta cycle", 25),
            row("Dead Hang", 999, seconds: 0), row("Dead Hang", nil, seconds: 15), row("Dead Hang", 35, skipped: true),
            row("Custom set", 8),
        ]
        let history = StrengthProgress.exerciseHistory(ownerID: session.userID, sessions: [session], logs: rows,
            exercises: [side, prescription("Cable hold practice"), prescription("Cable hold practice", owner: UUID(), unit: "reps")])
        XCTAssertEqual(history.first { $0.name == "Dead Hang" }?.totals.sets, 5)
        XCTAssertEqual(history.first { $0.name == "Side Plank" }?.totals.sets, 2)
        let totals = history.reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
        XCTAssertEqual(totals.sets, 11)
        XCTAssertEqual(totals.recordedReps, 8)
        XCTAssertEqual(totals.liftedVolumeKG, 80)
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

    func testAvatarRanksOwnedCompletedSessionsAndKeepsOnlyComparableLoads() throws {
        let owner = UUID(), other = UUID()
        func session(_ date: String, ownerID: UUID? = nil, completed: Bool = true) -> WorkoutSession {
            WorkoutSession(
                id: UUID(), userID: ownerID ?? owner, date: date, programDayID: UUID(),
                isLite: false, isDeload: false, isEventRecovery: false, completed: completed,
                qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
            )
        }
        func set(_ session: WorkoutSession, _ name: String, _ movement: String?, _ kg: Double? = nil,
                 reps: Int? = 8, seconds: Int? = nil, skipped: Bool = false, ownerID: UUID? = nil) -> WorkoutLog {
            WorkoutLog(
                id: UUID(), userID: ownerID ?? session.userID, sessionID: session.id, exerciseID: UUID(),
                exerciseName: name, setNumber: 1, weightKG: kg, reps: reps, rir: nil, movementID: movement,
                durationSeconds: seconds, skipped: skipped, overrideFlag: false, createdAt: session.date
            )
        }
        let old = session("2024-01-10"), recent = session("2026-09-06"), today = session("2026-09-07")
        let unfinished = session("2026-09-08", completed: false), foreign = session("2026-09-01", ownerID: other)
        let rows = [
            set(old, "Leg press", "leg_press", 60, reps: 12),
            set(old, "Leg press", "leg_press", 80, reps: 6),
            set(old, "Leg press", "leg_press", 80, reps: 7),
            set(recent, "Leg press", "leg_press"), set(today, "Leg press", "leg_press", 70),
            set(recent, "Bench press", "barbell_bench_press", 40, reps: nil),
            set(today, "Bench press", "barbell_bench_press", 50),
            set(today, "Dead hang", "dead_hang", 20, reps: nil, seconds: 40),
            set(today, "Band Abduction", "hip_abduction", 10),
            set(today, "Hip Abduction", "hip_abduction", 45),
            set(today, "Treadmill · 2 km · 0° · 15 min", nil, reps: nil),
            set(today, "Cable Crunch", "cable_crunch", 30),
            set(today, "Cable Crunch", "cable_crunch", 90, skipped: true),
            set(today, "Empty row", nil, reps: nil), set(foreign, "Foreign session", nil, 15),
            set(today, "Foreign set", nil, 20, ownerID: other), set(unfinished, "Unfinished", nil, 50),
            set(today, "Pending", nil, .infinity, reps: nil),
        ]
        let history = StrengthProgress.exerciseHistory(ownerID: owner,
            sessions: [today, unfinished, foreign, old, recent], logs: Array(rows.reversed()) + [rows[0]])
        XCTAssertEqual(history.map(\.name), ["Leg press", "Bench press", "Band Abduction", "Cable Crunch", "Dead hang", "Hip Abduction", "Treadmill"])
        let leg = try XCTUnwrap(history.first)
        XCTAssertEqual(leg.region, .lower)
        XCTAssertEqual(leg.sessionCount, 3)
        XCTAssertEqual(leg.totals.sets, 5)
        XCTAssertEqual(leg.points.map(\.topWeight), [80, 70])
        XCTAssertEqual(leg.points.map(\.topReps), [7, 8])
        XCTAssertEqual(leg.loadGain, -10)
        XCTAssertEqual(leg.totals.recordedReps, 41)
        XCTAssertEqual(leg.totals.liftedVolumeKG, 2_320)
        XCTAssertEqual(leg.totals.loadedReps, 33)
        XCTAssertEqual(leg.totals.averageLoadKG ?? 0, 2_320.0 / 33, accuracy: 0.001)
        XCTAssertTrue(leg.totals.missingVolume)
        let bench = try XCTUnwrap(history.first { $0.name == "Bench press" })
        XCTAssertEqual(bench.region, .upper)
        XCTAssertEqual(bench.totals.recordedReps, 8)
        XCTAssertEqual(bench.totals.liftedVolumeKG, 400)
        XCTAssertTrue(bench.totals.missingReps)
        XCTAssertTrue(bench.totals.missingVolume)
        let totals = StrengthProgress.rankedFamilies(history).reduce(into: StrengthProgress.LifetimeTotals()) { $0.add($1.totals) }
        XCTAssertEqual(totals.sets, 12)
        XCTAssertEqual(totals.recordedReps, 73)
        XCTAssertEqual(totals.liftedVolumeKG, 3_320)
        XCTAssertTrue(totals.missingReps)
        XCTAssertTrue(totals.missingVolume)
        XCTAssertNil(history.first { $0.name == "Dead hang" }?.totals.recordedReps)
        XCTAssertNil(history.first { $0.name == "Band Abduction" }?.totals.liftedVolumeKG)
        XCTAssertEqual(bench.loadGain, 10)
        XCTAssertNil(bench.points.first?.topReps)
        let crunch = try XCTUnwrap(history.first { $0.name == "Cable Crunch" })
        XCTAssertEqual(crunch.region, .core)
        XCTAssertEqual(crunch.points.map(\.topWeight), [30])
        XCTAssertNil(crunch.loadGain)
        XCTAssertEqual(history.filter { $0.points.isEmpty }.map(\.name), ["Band Abduction", "Dead hang", "Treadmill"])
        XCTAssertTrue(StrengthProgress.exerciseHistory(ownerID: owner, sessions: [today], logs: []).isEmpty)

        let curls = StrengthProgress.exerciseHistory(ownerID: owner, sessions: [old, recent, today], logs: [
            set(old, "Dumbbell Curl", "dumbbell_curl", 12), set(recent, "DB Curl", "dumbbell_curl", 15),
            set(today, "Barbell Curl", "dumbbell_curl", 40),
        ])
        XCTAssertEqual(curls.map(\.key), ["movement:dumbbell_curl", "name:barbell curl"])
        XCTAssertEqual(curls.map { $0.points.map(\.topWeight) }, [[12, 15], [40]])
    }

    func testFamilyFrequencyUnionsSessionsAndPreservesVariantLoads() throws {
        let owner = UUID()
        let sessions = (0..<5).map { hour in
            WorkoutSession(id: UUID(), userID: owner, date: "2026-10-10", programDayID: UUID(),
                           isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                           qualityScore: 1, startedAt: "2026-10-10T1\(hour):00:00Z", completedAt: nil, notes: "")
        }
        func row(_ index: Int, _ name: String, _ movement: String?, _ kg: Double? = nil) -> WorkoutLog {
            WorkoutLog(id: UUID(), userID: owner, sessionID: sessions[index].id, exerciseID: nil,
                       exerciseName: name, setNumber: 1, weightKG: kg, reps: 8, rir: nil,
                       movementID: movement, skipped: false, overrideFlag: false, createdAt: "")
        }
        let logs = [
            row(0, "Weighted Dumbbell Hip Thrust", nil, 20), row(0, "Weighted Dumbbell Hip Thrust", nil, 25),
            row(0, "Machine Hip Thrust", "machine_hip_thrust", 70), row(1, "Machine Hip Thrust", "machine_hip_thrust", 75),
            row(2, "B-Stance Hip Thrust", "b_stance_hip_thrust", 30),
            row(3, "Weighted Dumbbell Hip Thrust", nil, 26),
            row(0, "Leg Press", "leg_press", 100), row(1, "Leg Press", "leg_press", 110), row(2, "Leg Press", "leg_press", 120),
            row(0, "Strict Push-Up", nil), row(0, "Diamond or Close-Grip Push-Up", nil),
            row(1, "Strict Push-Up", nil), row(2, "Incline Push-Up", "incline_push_up"),
            row(4, "Cable Curl + Rope Pressdown", "dumbbell_curl", 30),
            row(3, "Weighted Push-Up", "weighted_push_up", 10),
            row(4, "Heel Walk", "heel_walk", 10),
        ]
        let variants = StrengthProgress.exerciseHistory(ownerID: owner, sessions: sessions, logs: logs)
        let families = StrengthProgress.rankedFamilies(variants)
        let hip = try XCTUnwrap(families.first)
        XCTAssertEqual(hip.key, "family:hip_thrust")
        XCTAssertEqual(hip.region, .lower)
        XCTAssertEqual(hip.sessionCount, 4)
        XCTAssertEqual(hip.variants.count, 3)
        XCTAssertEqual(hip.variants.map(\.sessionCount).sorted(), [1, 2, 2])
        XCTAssertEqual(hip.variants.first { $0.name == "Weighted Dumbbell Hip Thrust" }?.points.map(\.topWeight), [25, 26])
        XCTAssertEqual(hip.variants.first { $0.name == "Machine Hip Thrust" }?.points.map(\.topWeight), [70, 75])
        let pushUp = try XCTUnwrap(families.first { $0.key == "family:push_up" })
        XCTAssertEqual(pushUp.region, .upper)
        XCTAssertEqual(pushUp.sessionCount, 4)
        XCTAssertEqual(pushUp.sessions.map { $0.totals.recordedReps }, [16, 8, 8, 8])
        XCTAssertEqual(pushUp.sessions.map(\.sessionID), Array(sessions.prefix(4)).map(\.id))
        let axis = try XCTUnwrap(WorkoutChartCalendar(from: sessions[0].date, to: sessions[3].date))
        let positions = axis.positions(for: Array(repeating: axis.first, count: 4))
        XCTAssertEqual(positions.sorted(), positions)
        XCTAssertEqual(Set(positions).count, 4)
        XCTAssertEqual(pushUp.totals.recordedReps, 40)
        XCTAssertEqual(pushUp.totals.liftedVolumeKG, 80)
        XCTAssertEqual(pushUp.totals.averageLoadKG, 10)
        XCTAssertEqual(hip.totals.liftedVolumeKG, (20 + 25 + 70 + 75 + 30 + 26) * 8 as Double)
        XCTAssertNil(families.first { $0.name == "Heel Walk" }?.totals.recordedReps)
        XCTAssertTrue(pushUp.variants.allSatisfy { $0.points.isEmpty })
        let combined = try XCTUnwrap(families.first { $0.name == "Cable Curl + Rope Pressdown" })
        XCTAssertTrue(combined.key.hasPrefix("name:"))
        XCTAssertEqual(combined.sessionCount, 1)
        XCTAssertTrue(combined.variants.allSatisfy { $0.points.isEmpty })
        XCTAssertEqual(families.count, 5)
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
