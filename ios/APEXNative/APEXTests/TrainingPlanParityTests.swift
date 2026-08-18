import XCTest
@testable import APEX

/*
 * The native planner must prescribe exactly what the web planner prescribes.
 *
 * Each fixture carries a whole seeded programme plus the shape that bends it
 * (an event window, a marked deload, a layoff), and the session the TypeScript
 * produced for that date. Regenerate with:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-plan-fixtures.mts
 */
final class TrainingPlanParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let user_id: UUID
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }

    private struct Input: Decodable {
        let persona: String
        let slug: String
        let date: String
        let lite: Bool
        let programs: [Program]
        let program_days: [ProgramDay]
        let exercises: [Exercise]
        let events: [EventRecord]
        let deload_marks: [DeloadMark]
        let workout_sessions: [WorkoutSession]
        let baseline_date: String
        let protocol_start: String?
    }

    private struct Expected: Decodable {
        let program_day_name: String?
        let day_type: String?
        let warmup: String
        let warmup_duration: Int
        let badges: [String]
        let is_deload: Bool
        let is_event_day: Bool
        let is_recovery_micro: Bool
        let taper_factor: Double
        let legs_blocked: Bool
        let layoff_deload: Bool
        let exercises: [Row]
    }

    private struct Row: Decodable {
        let name: String
        let planned_sets: Int
        let rep_min: Int
        let rep_max: Int
        let rep_unit: String
        let rest_sec: Int
        let optional: Bool
        let swapped: Bool
        let notes: String
    }

    private static let fixture: Fixture = {
        guard let url = Bundle(for: TrainingPlanParityTests.self)
            .url(forResource: "plan-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("plan-parity.json missing from test bundle")
        }
        return try! JSONDecoder().decode(Fixture.self, from: data)
    }()

    private func dashboard(_ input: Input, userID: UUID) -> DashboardData {
        var data = DashboardData()
        data.profile = Profile(
            id: userID,
            userID: userID,
            persona: Persona(rawValue: input.persona) ?? .constantine,
            displayName: input.persona,
            sex: "male",
            weightKG: 70,
            bodyFatPercent: 15,
            customBMR: nil,
            heightCM: 175,
            birthdate: "1990-01-01",
            activityLevel: .moderate,
            goal: .recomp,
            targetKcal: nil,
            targetProteinG: nil,
            targetFatG: nil,
            targetCarbsG: nil,
            trainingTime: "18:00",
            baselineDate: input.baseline_date,
            profileNote: "",
            seedVersion: 7,
            calibrationK: 1,
            calibrationHistory: [],
            updatedAt: ""
        )
        var addons: [String: JSONValue] = [:]
        if let start = input.protocol_start {
            addons["training_protocol"] = .object(["start_date": .string(start)])
        }
        data.settings = UserSettings(
            userID: userID,
            voiceOn: false,
            ticksOn: false,
            notificationsOn: false,
            guardianFactor: 1,
            addons: addons
        )
        data.programs = input.programs
        data.programDays = input.program_days
        data.exercises = input.exercises
        data.events = input.events
        data.deloadMarks = input.deload_marks
        data.workoutSessions = input.workout_sessions
        return data
    }

    func testEveryScenarioMatchesTheWebPlanner() {
        let fixture = Self.fixture
        XCTAssertFalse(fixture.cases.isEmpty, "no plan scenarios were generated")

        for testCase in fixture.cases {
            let data = dashboard(testCase.input, userID: fixture.user_id)
            let plan = TrainingPlanEngine.plan(
                data,
                slug: testCase.input.slug,
                date: testCase.input.date,
                lite: testCase.input.lite
            )
            let want = testCase.expected
            let name = testCase.name

            XCTAssertEqual(plan.programDay?.name, want.program_day_name, "\(name): programme day")
            XCTAssertEqual(plan.programDay?.dayType, want.day_type, "\(name): day type")
            XCTAssertEqual(plan.warmup, want.warmup, "\(name): warm-up")
            XCTAssertEqual(plan.warmupDuration, want.warmup_duration, "\(name): warm-up duration")
            XCTAssertEqual(plan.badges, want.badges, "\(name): badges")
            XCTAssertEqual(plan.isDeload, want.is_deload, "\(name): deload")
            XCTAssertEqual(plan.isEventDay, want.is_event_day, "\(name): event day")
            XCTAssertEqual(plan.isRecoveryMicro, want.is_recovery_micro, "\(name): recovery micro")
            XCTAssertEqual(plan.taperFactor, want.taper_factor, accuracy: 1e-9, "\(name): taper")
            XCTAssertEqual(plan.legsBlocked, want.legs_blocked, "\(name): legs blocked")
            XCTAssertEqual(plan.layoffDeload, want.layoff_deload, "\(name): layoff deload")

            XCTAssertEqual(
                plan.exercises.map(\.name), want.exercises.map(\.name),
                "\(name): exercise names"
            )
            guard plan.exercises.count == want.exercises.count else { continue }
            for (got, expected) in zip(plan.exercises, want.exercises) {
                let label = "\(name)/\(expected.name)"
                XCTAssertEqual(got.plannedSets, expected.planned_sets, "\(label): planned sets")
                XCTAssertEqual(got.exercise.repMin, expected.rep_min, "\(label): rep min")
                XCTAssertEqual(got.exercise.repMax, expected.rep_max, "\(label): rep max")
                XCTAssertEqual(got.exercise.repUnit, expected.rep_unit, "\(label): rep unit")
                XCTAssertEqual(got.exercise.restSeconds, expected.rest_sec, "\(label): rest")
                XCTAssertEqual(got.exercise.optional, expected.optional, "\(label): optional")
                XCTAssertEqual(got.swapped, expected.swapped, "\(label): swapped")
                XCTAssertEqual(got.exercise.notes, expected.notes, "\(label): notes")
            }
        }
    }

    func testProtocolWeekCountsFromTheStartDate() {
        XCTAssertEqual(FocusT25.protocolWeek(start: "2026-01-05", date: "2026-01-05"), 1)
        XCTAssertEqual(FocusT25.protocolWeek(start: "2026-01-05", date: "2026-01-11"), 1)
        XCTAssertEqual(FocusT25.protocolWeek(start: "2026-01-05", date: "2026-01-12"), 2)
        XCTAssertEqual(FocusT25.protocolWeek(start: "2026-01-05", date: "2026-03-30"), 13)
        /* A date before the start still reads as week one, never zero. */
        XCTAssertEqual(FocusT25.protocolWeek(start: "2026-01-05", date: "2025-12-01"), 1)
    }

    func testBenchmarkIsPeriodicRatherThanWeekly() {
        for week in 1...16 {
            XCTAssertEqual(
                FocusT25.isPushupTestWeek(week),
                [1, 5, 9, 13].contains(week),
                "week \(week)"
            )
        }
    }

    func testTaperTightensAsTheEventApproaches() {
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 6), 1)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 5), 1)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 4), 0.75)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 3), 0.75)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 2), 0.5)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 1), 0.5)
        XCTAssertEqual(TrainingPlanEngine.taperFactor(daysUntilStart: 0), 1)
    }

    func testWeekdaysUseMondayAsOne() {
        XCTAssertEqual(APEXDateMath.isoWeekday("2026-01-05"), 1)
        XCTAssertEqual(APEXDateMath.isoWeekday("2026-01-11"), 7)
        XCTAssertEqual(APEXDateMath.calendarDaysBetween(from: "2026-01-05", to: "2026-01-12"), 7)
        XCTAssertEqual(APEXDateMath.adding(days: 30, to: "2026-01-05"), "2026-02-04")
    }
}
