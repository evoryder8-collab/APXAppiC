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

    /// Three equal meals per day (a full day), together at the given share of today's target.
    private func mealsAtRatios(_ ratios: [(calories: Double, protein: Double, carbs: Double, fat: Double)]) -> [LoggedMeal] {
        let t = targets
        return ratios.enumerated().flatMap { index, r in
            (0..<3).map { _ in
                meal(
                    day(index),
                    kcal: Double(t.targetCalories) * r.calories / 3,
                    protein: Double(t.proteinG) * r.protein / 3,
                    carbs: Double(t.carbsG) * r.carbs / 3,
                    fat: Double(t.fatG) * r.fat / 3
                )
            }
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
            meal(day(0), kcal: 700, protein: 40, carbs: 60, fat: 20),
            meal(day(0), kcal: 500, protein: 30, carbs: 50, fat: 10),
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
        XCTAssertEqual(report.periodDays, 9, "The period starts at the first entry: the water on the second day")
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
        XCTAssertEqual(try macro(report, .calories).metDays, 2)
        XCTAssertEqual(try macro(report, .protein).metDays, 3)
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

    func testEatingMoreProteinThanTheTargetIsAWinNotAMiss() throws {
        var data = data()
        data.loggedMeals = mealsAtRatios((0..<10).map { (1.0, $0 < 6 ? 1.6 : 1.0, 1.0, 1.0) })

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(try macro(report, .protein).overDays, 6)
        XCTAssertEqual(try macro(report, .protein).metDays, 10)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.strengths.contains(.protein))
        XCTAssertEqual(report.focus, [])
        XCTAssertEqual(report.verdict, .dialedIn)
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

    // MARK: Verdict

    func testEachVerdictIsReachableAndWinsOverTheRulesAfterIt() {
        typealias Input = NutritionReport.VerdictInput
        let cases: [(NutritionReport.Verdict, Input)] = [
            (.baseline, Input(score: nil, proteinRate: 1, trend: 30, weekendGap: 40)),
            (.dialedIn, Input(score: 92, proteinRate: 1, trend: 30, weekendGap: 40)),
            (.onTarget, Input(score: 84, proteinRate: 1, trend: 30, weekendGap: 40)),
            (.proteinPro, Input(score: 70, proteinRate: 0.9, trend: 30, weekendGap: 40)),
            (.onTheRise, Input(score: 70, proteinRate: 0.5, trend: 15, weekendGap: 40)),
            (.slippingLately, Input(score: 70, proteinRate: 0.5, trend: -15, weekendGap: 40)),
            (.weekendDrift, Input(score: 70, proteinRate: 0.5, trend: 5, weekendGap: 25)),
            (.solidBase, Input(score: 65, proteinRate: 0.5)),
            (.gettingThere, Input(score: 50, proteinRate: 0.5)),
            (.findingRhythm, Input(score: 35)),
            (.needsAttention, Input(score: 34)),
        ]
        XCTAssertEqual(cases.map(\.0), NutritionReport.Verdict.allCases)
        for (expected, input) in cases {
            XCTAssertEqual(NutritionReport.verdict(input), expected)
        }
    }

    func testTheLastTwoWeeksAgainstEarlierDaysDecideRiseAndSlip() throws {
        // 7 early days with only calories and fat on target (45), then 14 fully on-target days (100).
        var rising = data()
        rising.loggedMeals = mealsAtRatios((0..<21).map { $0 < 7 ? (1.0, 0.5, 0.5, 1.0) : (1.0, 1.0, 1.0, 1.0) })
        var slipping = data()
        slipping.loggedMeals = mealsAtRatios((0..<21).map { $0 < 7 ? (1.0, 1.0, 1.0, 1.0) : (1.0, 0.5, 1.0, 1.0) })
        let month = "2026-03-01"..."2026-03-31"

        XCTAssertEqual(try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: rising, dates: month)).score, 82)
        let rise = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: rising, dates: month))
        // 82 is already on target, which outranks the trend.
        XCTAssertEqual(rise.verdict, .onTarget)

        rising.loggedMeals = mealsAtRatios((0..<21).map { $0 < 7 ? (0.5, 0.5, 0.5, 0.5) : (1.0, 0.5, 1.0, 1.0) })
        let lateRise = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: rising, dates: month))
        XCTAssertEqual(lateRise.score, 40)
        XCTAssertEqual(lateRise.verdict, .onTheRise)

        let slip = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: slipping, dates: month))
        XCTAssertEqual(slip.score, 73)
        XCTAssertEqual(slip.verdict, .slippingLately)
    }

    func testWeekendDriftComparesSaturdayAndSundayWithWeekdays() throws {
        // 2026-03-01 is a Sunday: indexes 0, 6, 7, 13 are weekend days.
        var data = data()
        data.loggedMeals = mealsAtRatios((0..<14).map { [0, 6, 7, 13].contains($0) ? (0.5, 0.5, 1.0, 1.0) : (1.0, 1.0, 0.5, 1.0) })

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: "2026-03-01"..."2026-03-14"))

        XCTAssertEqual(report.verdict, .weekendDrift)
    }

    // MARK: Creatine

    private func creatineData(
        taken: [Int], name: String = "Creatine", trainingDaysOnly: Bool = false, extra: [SupplementLog] = []
    ) -> (DashboardData, UUID) {
        var data = data()
        let id = UUID()
        data.supplements = [
            Supplement(id: id, userID: owner, name: name, dose: "5 g", timing: "morning", clockTime: nil,
                       offsetMinutes: nil, groupLabel: "", trainingDaysOnly: trainingDaysOnly, sortOrder: 0),
            Supplement(id: UUID(), userID: owner, name: "Magnesium", dose: "", timing: "evening", clockTime: nil,
                       offsetMinutes: nil, groupLabel: "", trainingDaysOnly: false, sortOrder: 1),
        ]
        data.supplementLogs = taken.map { creatineLog(id, day: $0) } + extra
        return (data, id)
    }

    private func creatineLog(_ supplement: UUID, day index: Int, checkedAt: String? = nil, userID: UUID? = nil) -> SupplementLog {
        SupplementLog(id: UUID(), userID: userID ?? owner, date: day(index), supplementID: supplement,
                      checkedAt: checkedAt ?? "\(day(index))T08:00:00Z")
    }

    /// Read on the range's last day, unless a later `today` says the range has closed.
    private func creatine(taken: [Int], days: Int, today: Int? = nil) throws -> NutritionReport.Creatine {
        let (data, _) = creatineData(taken: taken)
        let report = try XCTUnwrap(NutritionReport.summarize(
            ownerID: owner, data: data, dates: day(0)...day(days - 1), today: day(today ?? days - 1)))
        return try XCTUnwrap(report.creatine)
    }

    func testEachCreatineBadgeIsReachableAndWinsOverTheRulesAfterIt() throws {
        // Day 0 is a Sunday; Saturdays are 6, 13, 20, 27.
        let weekends: Set<Int> = [0, 6, 7, 13, 14, 20, 21, 27]
        let cases: [(NutritionReport.Creatine.Badge, [Int], Int)] = [
            (.freshStart, Array(0..<10), 10),
            (.champ, Array(0..<30), 30),
            (.lockedIn, (0..<30).filter { $0 != 10 && $0 != 20 }, 30),
            (.onARoll, (0..<30).filter { ![3, 6, 9, 12, 15, 18, 21].contains($0) }, 30),
            (.comeback, Array(0..<3) + (16..<30).filter { $0 != 25 && $0 != 27 }, 30),
            (.lapsed, Array(0..<14), 30),
            (.weekendGaps, (0..<28).filter { !weekends.contains($0) }, 28),
            (.almostDaily, (0..<28).filter { ![3, 8, 12, 17, 22, 25].contains($0) }, 28),
            (.stopStart, Array(stride(from: 0, to: 28, by: 2)), 28),
            (.buildTheStreak, Array(0..<5) + Array(15..<20), 28),
        ]
        XCTAssertEqual(cases.map(\.0), NutritionReport.Creatine.Badge.allCases)
        for (expected, taken, days) in cases {
            XCTAssertEqual(try creatine(taken: taken, days: days).badge, expected, "\(expected)")
        }
    }

    func testCreatineStreaksAndScoreCountDistinctDaysFromTheFirstCheckOff() throws {
        let result = try creatine(taken: [2, 3, 4, 6, 7, 8, 9], days: 10)

        XCTAssertEqual(result.takenDays, 7)
        XCTAssertEqual(result.trackedDays, 8)
        XCTAssertEqual(result.longestStreak, 4)
        XCTAssertEqual(result.currentStreak, 4)
        XCTAssertEqual(result.score, 88)
        // The range's last day still open: the streak ending the day before it is current.
        XCTAssertEqual(try creatine(taken: [5, 6, 7, 8], days: 10).currentStreak, 4)
        XCTAssertEqual(try creatine(taken: [5, 6, 7], days: 10).currentStreak, 0)
    }

    func testAnUntickedLastDayIsStillOpenForTheScoreAsItIsForTheStreak() throws {
        // Nine days ticked; the report ends today, which is not ticked yet.
        let open = try creatine(taken: Array(0..<9), days: 10)
        XCTAssertEqual(open.currentStreak, 9)
        XCTAssertEqual(open.takenDays, 9)
        XCTAssertEqual(open.trackedDays, 9)
        XCTAssertEqual(open.score, 100)

        // Ticking it later counts it like any other day.
        let ticked = try creatine(taken: Array(0..<10), days: 10)
        XCTAssertEqual(ticked.trackedDays, 10)
        XCTAssertEqual(ticked.score, 100)

        // A day missed before the last one is still a miss.
        let missed = try creatine(taken: [0, 1, 2, 3, 4, 5, 6, 8], days: 10)
        XCTAssertEqual(missed.trackedDays, 9)
        XCTAssertEqual(missed.score, 89)
        XCTAssertEqual(missed.currentStreak, 1)
    }

    func testARangeThatEndedInThePastCountsItsUntickedLastDayAsAMiss() throws {
        // Nine days ticked, the tenth never was, and the report is read a week after the range closed.
        let closed = try creatine(taken: Array(0..<9), days: 10, today: 16)
        XCTAssertEqual(closed.takenDays, 9)
        XCTAssertEqual(closed.trackedDays, 10)
        XCTAssertEqual(closed.score, 90)
        XCTAssertEqual(closed.longestStreak, 9)
        XCTAssertEqual(closed.currentStreak, 0)
    }

    func testABackfilledCheckOffCountsOnTheDayItBelongsTo() throws {
        let (before, id) = creatineData(taken: (0..<10).filter { $0 != 5 })
        var after = before
        after.supplementLogs.append(creatineLog(id, day: 5, checkedAt: "2026-11-09T21:30:00Z"))

        let gap = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: before, dates: range)?.creatine)
        let filled = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: after, dates: range)?.creatine)

        XCTAssertEqual(gap.longestStreak, 5)
        XCTAssertEqual(filled.longestStreak, 10)
        XCTAssertEqual(filled.currentStreak, 10)
        XCTAssertEqual(filled.score, 100)
    }

    func testCreatineIgnoresOtherOwnersOutOfRangeDaysDuplicatesAndTrainingDayOnlyStacks() throws {
        let (base, id) = creatineData(taken: [0, 1])
        var data = base
        let second = Supplement(id: UUID(), userID: owner, name: "Creatine Monohydrate", dose: "", timing: "", clockTime: nil,
                                offsetMinutes: nil, groupLabel: "", trainingDaysOnly: false, sortOrder: 2)
        data.supplements.append(second)
        data.supplementLogs += [
            creatineLog(second.id, day: 1),
            creatineLog(id, day: 2, userID: UUID()),
            SupplementLog(id: UUID(), userID: owner, date: "2026-04-01", supplementID: id, checkedAt: "2026-04-01T08:00:00Z"),
            creatineLog(try XCTUnwrap(data.supplements.first { $0.name == "Magnesium" }).id, day: 3),
        ]

        let result = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range, today: range.upperBound)?.creatine)
        XCTAssertEqual(result.takenDays, 2)
        // Ten days in range; the last is unticked and still open, so nine are judged.
        XCTAssertEqual(result.trackedDays, 9)

        let (trainingOnly, _) = creatineData(taken: [0, 1], trainingDaysOnly: true)
        XCTAssertNil(NutritionReport.summarize(ownerID: owner, data: trainingOnly, dates: range)?.creatine)
        let (japanese, _) = creatineData(taken: [0, 1], name: "クレアチン")
        XCTAssertEqual(NutritionReport.summarize(ownerID: owner, data: japanese, dates: range)?.creatine?.takenDays, 2)
    }

    func testEmptyRangeHasNoReport() {
        XCTAssertNil(NutritionReport.summarize(ownerID: owner, data: DashboardData(), dates: range))
        XCTAssertNil(NutritionReport.summarize(ownerID: owner, data: data(), dates: range))
    }

    // MARK: Full days and the period

    func testADayWithFewerMealsThanAFullDayIsPartialNotUnderTarget() throws {
        var data = data()
        let t = targets
        data.loggedMeals = mealsAtRatios(Array(repeating: (1, 1, 1, 1), count: 7))
            + [meal(day(7), kcal: Double(t.targetCalories) * 0.3, protein: 20), meal(day(8), kcal: 400), meal(day(8), kcal: 500)]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.loggedDays, 7)
        XCTAssertEqual(report.partialDays, 2)
        XCTAssertEqual(try macro(report, .calories).underDays, 0, "A partly logged day is not a day of under-eating")
        XCTAssertEqual(report.score, 100)
    }

    func testAMealPlanWithTwoMealsMakesTwoMealsAFullDay() throws {
        var data = data()
        data.loggedMeals = [meal(day(0), kcal: 900), meal(day(0), kcal: 1_000)]
        XCTAssertEqual(try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range)).partialDays, 1)

        data.settings = UserSettings(userID: owner, voiceOn: false, ticksOn: false, notificationsOn: false, guardianFactor: 1,
                                     addons: ["meal_rhythm_history": .object([day(0): .object(["expected_meals": .number(2)])])])
        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))
        XCTAssertEqual(report.loggedDays, 1)
        XCTAssertEqual(report.partialDays, 0)
    }

    func testThePeriodStartsAtTheFirstEntryNotTheStartOfTheRange() throws {
        var data = data()
        data.dailyLogs = [dailyLog(day(4), kcal: 2_000, protein: 120, fat: 60, carbs: 220)]

        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range))

        XCTAssertEqual(report.from, day(4))
        XCTAssertEqual(report.periodDays, 6)
    }

    func testProteinIsOnlyAFocusWhenTheAverageIsShortToo() throws {
        var data = data()
        // Four days far over target and six just under: under on most days, yet the average is above target.
        data.loggedMeals = mealsAtRatios(Array(repeating: (1, 2.0, 1, 1), count: 4) + Array(repeating: (1, 0.9, 1, 1), count: 6))
        XCTAssertFalse(try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range)).focus.contains(.proteinLow))

        data.loggedMeals = mealsAtRatios(Array(repeating: (1, 0.6, 1, 1), count: 10))
        XCTAssertTrue(try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range)).focus.contains(.proteinLow))
    }

    func testStarsStepWithTheVerdictTiers() throws {
        func stars(onTarget: Int) throws -> Int {
            var data = data()
            data.loggedMeals = mealsAtRatios(Array(repeating: (1, 1, 1, 1), count: onTarget) + Array(repeating: (0.5, 0.5, 0.5, 0.5), count: 10 - onTarget))
            return try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: data, dates: range)).stars
        }
        XCTAssertEqual(try stars(onTarget: 10), 5)
        XCTAssertEqual(try stars(onTarget: 8), 4)
        XCTAssertEqual(try stars(onTarget: 7), 3, "70 is a solid base, not a four-star score")
        XCTAssertEqual(try stars(onTarget: 4), 2)
        XCTAssertEqual(try stars(onTarget: 0), 0)
    }
}
