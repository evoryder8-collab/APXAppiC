import Foundation
import XCTest
@testable import APEX

final class NutritionReportTests: XCTestCase {
    private let owner = UUID()
    private let range = "2026-03-01"..."2026-03-10"

    private func day(_ index: Int) -> String { String(format: "2026-03-%02d", index + 1) }

    private func profile(birthdate: String = "1990-01-01") -> Profile {
        Profile(
            id: owner, userID: owner, persona: .iulian, profileKind: .standard, bespokeProtocolID: nil,
            displayName: "Test User", sex: "male", weightKG: 70, bodyFatPercent: 20, bodyFatSource: .dexa,
            bodyFatMeasuredAt: nil, customBMR: nil, heightCM: 175, birthdate: birthdate,
            activityLevel: .sedentary, goal: .recomp, targetKcal: nil, targetProteinG: nil,
            targetFatG: nil, targetCarbsG: nil, trainingTime: "07:00", baselineDate: "2026-01-01",
            profileNote: "", seedVersion: 1, calibrationK: 1, calibrationHistory: [],
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func data(profile: Profile? = nil) -> DashboardData {
        var data = DashboardData()
        data.profile = profile ?? self.profile()
        return data
    }

    private var targets: NutritionTargets {
        EnergyEngine.targets(profile: profile(), logs: [], catalog: [])
    }

    private func meal(
        _ date: String, kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
        userID: UUID? = nil
    ) -> LoggedMeal {
        LoggedMeal(
            id: UUID(), userID: userID ?? owner, localDate: date, mealSlot: "lunch", displayName: "Meal",
            sourcePresetID: nil, sourcePlannedMealID: nil, loggedAt: "\(date)T12:00:00Z",
            clientIdempotencyKey: UUID().uuidString, loggedAs: "manual",
            totalKcal: kcal, totalProteinG: protein, totalCarbsG: carbs, totalFatG: fat
        )
    }

    private func dailyLog(
        _ date: String, kcal: Int? = nil, protein: Int? = nil, fat: Int? = nil, carbs: Int? = nil,
        water: Double = 0, userID: UUID? = nil
    ) -> DailyLog {
        DailyLog(
            id: UUID(), userID: userID ?? owner, date: date, kcal: kcal, proteinG: protein, fatG: fat,
            carbsG: carbs, waterL: water, estimatedTDEE: nil, computedPAL: nil, activityMode: "quick",
            weightKG: nil
        )
    }

    private func drink(
        _ date: String, ml: Int, kind: HydrationKind = .water, userID: UUID? = nil
    ) -> HydrationEvent {
        HydrationEvent(
            id: UUID(), userID: userID ?? owner, clientIdempotencyKey: UUID().uuidString, localDate: date,
            occurredAt: "\(date)T08:00:00Z", amountML: ml, kind: kind, paletteToken: "water",
            iconToken: "drop.fill", source: .iPhone, healthKitSampleID: nil,
            createdAt: "\(date)T08:00:00Z", updatedAt: "\(date)T08:00:00Z"
        )
    }

    /// One meal per day, each macro at the given share of today's target.
    private func mealsAtRatios(_ ratios: [(calories: Double, protein: Double, carbs: Double, fat: Double)]) -> [LoggedMeal] {
        let t = targets
        return ratios.enumerated().map { index, r in
            meal(
                day(index),
                kcal: Double(t.targetCalories) * r.calories,
                protein: Double(t.proteinG) * r.protein,
                carbs: Double(t.carbsG) * r.carbs,
                fat: Double(t.fatG) * r.fat
            )
        }
    }

    private func macro(_ report: NutritionReport, _ kind: NutritionReport.Kind) throws -> NutritionReport.Macro {
        try XCTUnwrap(report.macros.first { $0.kind == kind })
    }

    func testFixtureProfileHasPublishableTargets() {
        XCTAssertTrue(targets.isPublishable)
        XCTAssertGreaterThan(targets.proteinG, 0)
    }

    func testLoggedMealsOverrideDailyLogAndForeignMealsAreIgnored() throws {
        var data = data()
        data.dailyLogs = [dailyLog(day(0), kcal: 3_000, protein: 300, fat: 100, carbs: 400)]
        data.loggedMeals = [
            meal(day(0), kcal: 800, protein: 50, carbs: 90, fat: 20),
            meal(day(0), kcal: 1_200, protein: 70, carbs: 110, fat: 30),
            meal(day(0), kcal: 5_000, protein: 500, userID: UUID()),
        ]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: day(0)...day(0)))

        XCTAssertEqual(report.loggedDays, 1)
        XCTAssertEqual(try macro(report, .calories).average, 2_000, accuracy: 0.001)
        XCTAssertEqual(try macro(report, .protein).average, 120, accuracy: 0.001)
        XCTAssertEqual(try macro(report, .carbs).average, 200, accuracy: 0.001)
        XCTAssertEqual(try macro(report, .fat).average, 50, accuracy: 0.001)
    }

    func testDailyLogIsUsedWhenTheDayHasNoMeals() throws {
        var data = data()
        data.dailyLogs = [dailyLog(day(0), kcal: 2_100, protein: 150, fat: 60, carbs: 220)]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(try macro(report, .calories).average, 2_100, accuracy: 0.001)
        XCTAssertEqual(try macro(report, .protein).average, 150, accuracy: 0.001)
    }

    func testDayWithZeroCaloriesIsNotALoggedDay() throws {
        var data = data()
        data.dailyLogs = [dailyLog(day(0), kcal: 0, protein: 120), dailyLog(day(1), water: 1)]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.loggedDays, 0)
        XCTAssertEqual(report.periodDays, 10)
    }

    func testBandEdgesCountAsOnTargetAndJustOutsideDoesNot() throws {
        var data = data()
        data.loggedMeals = mealsAtRatios([
            (0.90, 0.95, 1, 1), (1.10, 1.25, 1, 1), (0.899, 0.949, 1, 1), (1.101, 1.251, 1, 1),
        ])

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        for kind in [NutritionReport.Kind.calories, .protein] {
            let m = try macro(report, kind)
            XCTAssertEqual(m.onTargetDays, 2, "\(kind)")
            XCTAssertEqual(m.underDays, 1, "\(kind)")
            XCTAssertEqual(m.overDays, 1, "\(kind)")
        }
        XCTAssertEqual(try macro(report, .carbs).onTargetDays, 4)
    }

    func testScoreStarsAndStrengthsMatchTheFormula() throws {
        var data = data()
        // Calories and fat always on target, protein on 8 of 10 days, carbs on 6 of 10.
        data.loggedMeals = mealsAtRatios((0..<10).map {
            (1.0, $0 < 8 ? 1.0 : 0.5, $0 < 6 ? 1.0 : 0.5, 1.0)
        })

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        // 100 * (0.40 * 0.8 + 0.30 * 1.0 + 0.15 * 0.6 + 0.15 * 1.0) = 86
        XCTAssertEqual(report.score, 86)
        XCTAssertEqual(report.stars, 4)
        XCTAssertEqual(report.strengths, [.calories, .protein, .fat])
        XCTAssertEqual(report.focus, [])
    }

    func testFewerThanSevenLoggedDaysHasNoScore() throws {
        var data = data()
        data.loggedMeals = mealsAtRatios(Array(repeating: (1.0, 1.0, 1.0, 1.0), count: 6))

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.loggedDays, 6)
        XCTAssertNil(report.score)
        XCTAssertEqual(report.stars, 0)
    }

    func testNoProfileOrUnpublishableTargetsStillAveragesButNeverScores() throws {
        var withoutProfile = data()
        withoutProfile.profile = nil
        var unpublishable = data(profile: profile(birthdate: "2015-01-01"))
        XCTAssertFalse(
            EnergyEngine.targets(profile: unpublishable.profile!, logs: [], catalog: []).isPublishable
        )
        let logs = (0..<8).map { dailyLog(day($0), kcal: 2_000, protein: 150, fat: 60, carbs: 200) }
        withoutProfile.dailyLogs = logs
        unpublishable.dailyLogs = logs

        for fixture in [withoutProfile, unpublishable] {
            let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: fixture, dates: range))
            XCTAssertNil(report.score)
            XCTAssertEqual(report.stars, 0)
            XCTAssertTrue(report.macros.allSatisfy { $0.target == nil })
            XCTAssertEqual(try macro(report, .protein).average, 150, accuracy: 0.001)
            XCTAssertEqual(report.focus, [])
        }
    }

    func testProteinHighWhenMostDaysExceedTheCeiling() throws {
        var data = data()
        data.loggedMeals = mealsAtRatios((0..<10).map { (1.0, $0 < 6 ? 1.3 : 1.0, 1.0, 1.0) })

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(try macro(report, .protein).overDays, 6)
        XCTAssertEqual(report.focus, [.proteinHigh])
    }

    func testSparseLoggingIsFlaggedAsAGap() throws {
        var data = data()
        data.loggedMeals = mealsAtRatios(Array(repeating: (1.0, 1.0, 1.0, 1.0), count: 5))

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.focus, [.loggingGaps])
    }

    func testWaterSumsDrinksFallsBackToLegacyAndIgnoresOtherOwnersAndDates() throws {
        var data = data()
        data.hydrationEvents = [
            drink(day(0), ml: 500),
            drink(day(0), ml: 250, kind: .coffee),
            drink(day(0), ml: 1_000, userID: UUID()),
            drink(day(2), ml: 300, kind: .food),
            drink("2026-04-01", ml: 900),
        ]
        data.dailyLogs = [
            dailyLog(day(0), water: 5),
            dailyLog(day(1), water: 1.5),
            dailyLog(day(3), water: 4, userID: UUID()),
        ]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.waterLitres, 2.25, accuracy: 0.0001)
        XCTAssertEqual(report.waterDays, 2)
    }

    func testEmptyRangeHasNoReport() {
        XCTAssertNil(NutritionReport.summarize(ownerID: owner, data: DashboardData(), dates: range))
        XCTAssertNil(NutritionReport.summarize(ownerID: owner, data: data(), dates: range))
    }
}
