/*
 * Golden parity for the HealthImport merge policy against
 * src/lib/healthImport.ts (Tools/generate-health-import-fixtures.mts).
 *
 * The policy is the whole point: an import is a positive signal only, a
 * manual entry always wins, water rises but never falls, and re-importing
 * does not duplicate work already recorded.
 */
import XCTest
@testable import APEX

private struct HealthFixture: Decodable {
    let user_id: UUID
    let existing: Existing
    let parsed: ParsedRows
    let expected: Expected
}

private struct Existing: Decodable {
    let daily_logs: [DailyLogRow]
    let metrics: [MetricRow]
    let activities: [ActivityRow]
}

private struct DailyLogRow: Decodable {
    let id: UUID?; let date: String
    let kcal: Int?; let protein_g: Int?; let fat_g: Int?; let carbs_g: Int?
    let water_l: Double
}

private struct MetricRow: Decodable {
    let id: UUID?; let date: String
    let weight_kg: Double?; let vo2max: Double?; let resting_hr: Double?
}

private struct ActivityRow: Decodable {
    let date: String; let kind: String; let activity: String
    let duration_min: Int; let source: String
}

private struct ParsedRows: Decodable {
    let nutrition: [NutritionRow]
    let water: [WaterRow]
    let weight: [ValueRow]
    let vo2max: [ValueRow]
    let resting_hr: [ValueRow]
    let workouts: [WorkoutRow]
}

private struct NutritionRow: Decodable { let date: String; let kcal: Double; let protein: Double; let fat: Double; let carbs: Double }
private struct WaterRow: Decodable { let date: String; let litres: Double }
private struct ValueRow: Decodable { let date: String; let kg: Double?; let value: Double? }
private struct WorkoutRow: Decodable { let date: String; let activity: String; let kind: String; let durationMin: Int; let source: String }

private struct Expected: Decodable {
    let daily_logs: [DailyLogRow]
    let metrics: [MetricRow]
    let activities: [ActivityRow]
    let result: ResultRow
}

private struct ResultRow: Decodable {
    let dailyLogsTouched: Int
    let metricsTouched: Int
    let workoutsAdded: Int
    let latestWeight: Double?
    let latestVo2max: Double?
    let dateRange: [String]?
}

final class HealthImportParityTests: XCTestCase {
    private static let fixture: HealthFixture = {
        guard let url = Bundle(for: HealthImportParityTests.self)
            .url(forResource: "health-import-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("health-import-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(HealthFixture.self, from: data)
    }()

    private func built() -> HealthImport.Rows {
        let fixture = Self.fixture
        var parsed = HealthImport.Parsed()
        for row in fixture.parsed.nutrition {
            parsed.nutrition[row.date] = .init(kcal: row.kcal, protein: row.protein, fat: row.fat, carbs: row.carbs)
        }
        for row in fixture.parsed.water { parsed.water[row.date] = row.litres }
        for row in fixture.parsed.weight { parsed.weight[row.date] = row.kg ?? row.value ?? 0 }
        for row in fixture.parsed.vo2max { parsed.vo2Max[row.date] = row.value ?? row.kg ?? 0 }
        for row in fixture.parsed.resting_hr { parsed.restingHeartRate[row.date] = row.value ?? row.kg ?? 0 }
        parsed.workouts = fixture.parsed.workouts.map {
            .init(date: $0.date, activity: $0.activity, kind: $0.kind, durationMinutes: $0.durationMin, source: $0.source)
        }

        let logs = fixture.existing.daily_logs.map { row in
            DailyLog(
                id: row.id ?? UUID(), userID: fixture.user_id, date: row.date,
                kcal: row.kcal, proteinG: row.protein_g, fatG: row.fat_g, carbsG: row.carbs_g,
                waterL: row.water_l, estimatedTDEE: nil, computedPAL: nil,
                activityMode: "quick", weightKG: nil
            )
        }
        let metrics = fixture.existing.metrics.map { row in
            HealthMetric(
                id: row.id ?? UUID(), userID: fixture.user_id, date: row.date,
                weightKG: row.weight_kg, vo2Max: row.vo2max, restingHeartRate: row.resting_hr
            )
        }
        let activities = fixture.existing.activities.map { row in
            ImportedActivity(
                id: UUID(), userID: fixture.user_id, date: row.date, kind: row.kind,
                activity: row.activity, durationMinutes: row.duration_min, source: row.source
            )
        }
        return HealthImport.buildRows(
            parsed: parsed, userID: fixture.user_id,
            dailyLogs: logs, metrics: metrics, activities: activities
        )
    }

    func testDailyLogsMatchTheWeb() {
        let rows = built().dailyLogs.sorted { $0.date < $1.date }
        let expected = Self.fixture.expected.daily_logs
        XCTAssertEqual(rows.map(\.date), expected.map(\.date))
        for (row, want) in zip(rows, expected) {
            XCTAssertEqual(row.kcal, want.kcal, want.date)
            XCTAssertEqual(row.proteinG, want.protein_g, want.date)
            XCTAssertEqual(row.fatG, want.fat_g, want.date)
            XCTAssertEqual(row.carbsG, want.carbs_g, want.date)
            XCTAssertEqual(row.waterL, want.water_l, accuracy: 0.0001, want.date)
        }
    }

    func testMetricsAndActivitiesMatchTheWeb() {
        let rows = built()
        let metrics = rows.metrics.sorted { $0.date < $1.date }
        XCTAssertEqual(metrics.map(\.date), Self.fixture.expected.metrics.map(\.date))
        for (row, want) in zip(metrics, Self.fixture.expected.metrics) {
            XCTAssertEqual(row.weightKG ?? .nan, want.weight_kg ?? .nan, accuracy: 0.0001, want.date)
            XCTAssertEqual(row.vo2Max == nil, want.vo2max == nil, want.date)
            XCTAssertEqual(row.restingHeartRate == nil, want.resting_hr == nil, want.date)
        }
        let activities = rows.activities.sorted {
            $0.date == $1.date ? $0.activity < $1.activity : $0.date < $1.date
        }
        XCTAssertEqual(activities.map(\.activity), Self.fixture.expected.activities.map(\.activity))
        XCTAssertEqual(activities.map(\.durationMinutes), Self.fixture.expected.activities.map(\.duration_min))
    }

    func testResultMatchesTheWeb() {
        let result = built().result
        let want = Self.fixture.expected.result
        XCTAssertEqual(result.dailyLogsTouched, want.dailyLogsTouched)
        XCTAssertEqual(result.metricsTouched, want.metricsTouched)
        XCTAssertEqual(result.workoutsAdded, want.workoutsAdded)
        XCTAssertEqual(result.latestWeight ?? .nan, want.latestWeight ?? .nan, accuracy: 0.0001)
        XCTAssertEqual(result.latestVO2Max ?? .nan, want.latestVo2max ?? .nan, accuracy: 0.0001)
        XCTAssertEqual(result.dateRange, want.dateRange)
    }

    /// The rules stated in prose, asserted directly rather than only through
    /// the fixture, so a future change has to break them explicitly.
    func testAManualEntryAlwaysWins() {
        let rows = built().dailyLogs
        XCTAssertNil(
            rows.first { $0.date == "2026-08-10" },
            "a day already logged by hand must not be rewritten by an import"
        )
        let partial = rows.first { $0.date == "2026-08-11" }
        XCTAssertEqual(partial?.proteinG, 99, "an existing macro must survive the import")
        XCTAssertEqual(partial?.kcal, 2400, "an empty macro should be filled")
    }

    func testWaterRisesButNeverFalls() {
        let rows = built().dailyLogs
        XCTAssertNil(rows.first { $0.date == "2026-08-10" }, "2.5 L logged by hand must not fall to 1.2")
        XCTAssertEqual(rows.first { $0.date == "2026-08-11" }?.waterL, 2.25, "rounded to the quarter litre")
    }

    func testReimportingAddsNothingTwice() {
        let first = built()
        XCTAssertEqual(first.activities.count, 2, "the already-recorded session must be skipped")
        /* Feed the freshly added activities back in: nothing should be new. */
        var parsed = HealthImport.Parsed()
        parsed.workouts = Self.fixture.parsed.workouts.map {
            .init(date: $0.date, activity: $0.activity, kind: $0.kind, durationMinutes: $0.durationMin, source: $0.source)
        }
        let again = HealthImport.buildRows(
            parsed: parsed, userID: Self.fixture.user_id,
            dailyLogs: [], metrics: [],
            activities: first.activities + Self.fixture.existing.activities.map {
                ImportedActivity(
                    id: UUID(), userID: Self.fixture.user_id, date: $0.date, kind: $0.kind,
                    activity: $0.activity, durationMinutes: $0.duration_min, source: $0.source
                )
            }
        )
        XCTAssertEqual(again.activities.count, 0, "a second import must add nothing")
    }

    func testShortAndUnmappedWorkoutsAreRejectedByTheSharedRules() {
        XCTAssertEqual(HealthImport.minimumWorkoutMinutes, 8)
        XCTAssertEqual(HealthImport.activityKind["Running"], "endurance")
        XCTAssertEqual(HealthImport.activityKind["Yoga"], "mobility")
        XCTAssertNil(HealthImport.activityKind["Curling"], "an unmapped type is skipped, not guessed")
    }
}

private enum HealthReadTestError: Error {
    case protectedDataUnavailable
}

private func makeHealthTodayPlan(
    weightKG: @escaping @Sendable () async throws -> Double? = { nil },
    vo2Max: @escaping @Sendable () async throws -> Double? = { nil },
    restingHeartRate: @escaping @Sendable () async throws -> Double? = { nil },
    dietaryWater: @escaping @Sendable () async throws -> HealthWaterTotals = { .unavailable },
    steps: @escaping @Sendable () async throws -> Double? = { nil },
    activeEnergyKcal: @escaping @Sendable () async throws -> Double? = { nil },
    exerciseMinutes: @escaping @Sendable () async throws -> Double? = { nil },
    sleepDurationHours: @escaping @Sendable () async throws -> Double? = { nil },
    heartRateVariabilityMS: @escaping @Sendable () async throws -> Double? = { nil },
    workouts: @escaping @Sendable () async throws -> [HealthWorkoutSnapshot] = { [] }
) -> HealthTodayQueryPlan {
    HealthTodayQueryPlan(
        weightKG: weightKG,
        vo2Max: vo2Max,
        restingHeartRate: restingHeartRate,
        dietaryWater: dietaryWater,
        steps: steps,
        activeEnergyKcal: activeEnergyKcal,
        exerciseMinutes: exerciseMinutes,
        sleepDurationHours: sleepDurationHours,
        heartRateVariabilityMS: heartRateVariabilityMS,
        workouts: workouts
    )
}

private func unavailableHealthTodayPlan() -> HealthTodayQueryPlan {
    makeHealthTodayPlan(
        weightKG: { throw HealthReadTestError.protectedDataUnavailable },
        vo2Max: { throw HealthReadTestError.protectedDataUnavailable },
        restingHeartRate: { throw HealthReadTestError.protectedDataUnavailable },
        dietaryWater: { throw HealthReadTestError.protectedDataUnavailable },
        steps: { throw HealthReadTestError.protectedDataUnavailable },
        activeEnergyKcal: { throw HealthReadTestError.protectedDataUnavailable },
        exerciseMinutes: { throw HealthReadTestError.protectedDataUnavailable },
        sleepDurationHours: { throw HealthReadTestError.protectedDataUnavailable },
        heartRateVariabilityMS: { throw HealthReadTestError.protectedDataUnavailable },
        workouts: { throw HealthReadTestError.protectedDataUnavailable }
    )
}

final class HealthTodayReadingsTests: XCTestCase {
    func testDeniedMetricDoesNotEraseReadableActivity() async throws {
        let snapshot = try await makeHealthTodayPlan(
            weightKG: { throw HealthReadTestError.protectedDataUnavailable },
            steps: { 8_432 },
            activeEnergyKcal: { 414 },
            exerciseMinutes: { 37 }
        ).snapshot(date: "2026-08-25")

        XCTAssertNil(snapshot.weightKG)
        XCTAssertEqual(snapshot.steps, 8_432)
        XCTAssertEqual(snapshot.activeEnergyKcal, 414)
        XCTAssertEqual(snapshot.exerciseMinutes, 37)
    }

    func testDeniedWaterDoesNotEraseReadableSleepOrWorkouts() async throws {
        let workout = HealthWorkoutSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000825")!,
            date: "2026-08-25",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: Date(timeIntervalSince1970: 1_777_003_600),
            kind: "endurance",
            activityName: "Running",
            durationMinutes: 60,
            distanceKM: 10,
            activeEnergyKcal: 620
        )
        let snapshot = try await makeHealthTodayPlan(
            dietaryWater: { throw HealthReadTestError.protectedDataUnavailable },
            sleepDurationHours: { 7.5 },
            workouts: { [workout] }
        ).snapshot(date: "2026-08-25")

        XCTAssertNil(snapshot.dietaryWaterL)
        XCTAssertNil(snapshot.importableDietaryWaterL)
        XCTAssertEqual(snapshot.sleepDurationHours, 7.5)
        XCTAssertEqual(snapshot.workouts, [workout])
        XCTAssertTrue(snapshot.hasImportableSignal)
    }

    func testEveryFailedQueryRejectsTheRefresh() async {
        do {
            _ = try await unavailableHealthTodayPlan().snapshot(date: "2026-08-25")
            XCTFail("A total HealthKit failure must not look like a successful empty day")
        } catch let error as HealthTodayReadError {
            XCTAssertEqual(error, .allQueriesUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulEmptyQueriesRemainAnHonestEmptySnapshot() async throws {
        let snapshot = try await makeHealthTodayPlan().snapshot(date: "2026-08-25")

        XCTAssertFalse(snapshot.hasImportableSignal)
        XCTAssertNil(snapshot.weightKG)
        XCTAssertNil(snapshot.vo2Max)
        XCTAssertNil(snapshot.restingHeartRate)
        XCTAssertNil(snapshot.dietaryWaterL)
        XCTAssertNil(snapshot.importableDietaryWaterL)
        XCTAssertNil(snapshot.steps)
        XCTAssertNil(snapshot.activeEnergyKcal)
        XCTAssertNil(snapshot.exerciseMinutes)
        XCTAssertNil(snapshot.sleepDurationHours)
        XCTAssertNil(snapshot.heartRateVariabilityMS)
        XCTAssertTrue(snapshot.workouts.isEmpty)
    }

    func testCancellationPropagatesInsteadOfPublishingAPartialSnapshot() async {
        let task = Task<HealthSnapshot, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await makeHealthTodayPlan(
                steps: { 8_432 },
                activeEnergyKcal: { 414 }
            ).snapshot(date: "2026-08-25")
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop the HealthKit refresh")
        } catch is CancellationError {
            // Expected: no partial snapshot escapes the cancelled lifecycle task.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
