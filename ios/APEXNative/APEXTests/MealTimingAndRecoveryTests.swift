import XCTest
@testable import APEX

/*
 * Two questions this engine answers, and both change what a person does:
 * whether enough time has passed since eating to train comfortably, and what
 * last night means for today.
 */
final class MealTimingEngineTests: XCTestCase {
    private let user = UUID()

    private func meal(
        id: UUID = UUID(),
        slot: String = "lunch",
        date: String = "2026-01-05",
        at: String,
        kcal: Double = 500,
        fat: Double = 15
    ) -> LoggedMeal {
        LoggedMeal(
            id: id, userID: user, localDate: date, mealSlot: slot, displayName: slot.capitalized,
            sourcePresetID: nil, sourcePlannedMealID: nil, loggedAt: at,
            clientIdempotencyKey: id.uuidString, loggedAs: "manual",
            totalKcal: kcal, totalProteinG: 30, totalCarbsG: 50, totalFatG: fat
        )
    }

    private func session(
        date: String = "2026-01-05",
        started: String?,
        completed: String? = nil
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID(), userID: user, date: date, programDayID: UUID(),
            isLite: false, isDeload: false, isEventRecovery: false,
            completed: completed != nil, qualityScore: 1,
            startedAt: started, completedAt: completed, notes: ""
        )
    }

    func testComfortWindowGrowsWithTheSizeOfTheMeal() {
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 150, fatG: 4).load, "light")
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 400, fatG: 12).load, "standard")
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 700, fatG: 25).load, "substantial")
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 1_000, fatG: 40).load, "large")
    }

    func testFatAndFibreExtendTheWindowOnTheirOwn() {
        /* A modest calorie count with heavy fat still settles slowly. */
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 300, fatG: 36).load, "large")
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 200, fatG: 2, fibreG: 20).load, "large")
        XCTAssertEqual(MealTimingEngine.comfortWindow(kcal: 200, fatG: 2, fibreG: 8).load, "standard")
    }

    func testTheZoneMovesAsTimePasses() {
        let window = MealTimingEngine.comfortWindow(kcal: 700, fatG: 25)
        XCTAssertEqual(MealTimingEngine.zone(minutesSinceMeal: 30, window: window), .settling)
        XCTAssertEqual(MealTimingEngine.zone(minutesSinceMeal: 120, window: window), .transition)
        XCTAssertEqual(MealTimingEngine.zone(minutesSinceMeal: 200, window: window), .ready)
    }

    func testAWorkoutIsMeasuredAgainstTheLastMealBeforeIt() {
        let lunch = meal(at: "2026-01-05T12:00:00Z", kcal: 700, fat: 25)
        let analysis = MealTimingEngine.analyze(
            meals: [lunch],
            entries: [],
            sessions: [session(started: "2026-01-05T14:30:00Z")],
            timeZone: "UTC"
        )
        let relation = analysis.workoutRelations.first
        XCTAssertEqual(relation?.waitedMinutes, 150)
        XCTAssertEqual(relation?.zone, .transition)
        XCTAssertEqual(analysis.workoutsWithContext, 1)
        XCTAssertEqual(analysis.transitionStarts, 1)
    }

    func testAMealEatenAfterTheWorkoutIsNotItsContext() {
        let analysis = MealTimingEngine.analyze(
            meals: [meal(at: "2026-01-05T18:00:00Z")],
            entries: [],
            sessions: [session(started: "2026-01-05T14:00:00Z")],
            timeZone: "UTC"
        )
        XCTAssertNil(analysis.workoutRelations.first?.mealID)
        XCTAssertEqual(analysis.workoutsWithContext, 0)
    }

    func testEatingSoonAfterTrainingScoresFull() {
        XCTAssertEqual(MealTimingEngine.recoveryTimingScore(gapMinutes: 0), 100)
        XCTAssertEqual(MealTimingEngine.recoveryTimingScore(gapMinutes: 120), 100)
        XCTAssertEqual(MealTimingEngine.recoveryTimingScore(gapMinutes: 180), 85)
        XCTAssertEqual(MealTimingEngine.recoveryTimingScore(gapMinutes: 240), 70)
        XCTAssertEqual(MealTimingEngine.recoveryTimingScore(gapMinutes: 600), 0)
        XCTAssertNil(MealTimingEngine.recoveryTimingScore(gapMinutes: nil))
    }

    func testThePostWorkoutMealIsTheNextOneWithinSixHours() {
        let dinner = meal(slot: "dinner", at: "2026-01-05T19:30:00Z")
        let relations = MealTimingEngine.postWorkoutNutrition(
            sessions: [session(started: "2026-01-05T17:00:00Z", completed: "2026-01-05T18:00:00Z")],
            meals: [dinner],
            timeZone: "UTC"
        )
        XCTAssertEqual(relations.first?.gapMinutes, 90)
        XCTAssertEqual(relations.first?.timingScore, 100)
        XCTAssertEqual(relations.first?.source, "recorded_finish")
    }

    func testAMealTheNextMorningIsNotRecovery() {
        let breakfast = meal(slot: "breakfast", date: "2026-01-06", at: "2026-01-06T07:00:00Z")
        let relations = MealTimingEngine.postWorkoutNutrition(
            sessions: [session(started: "2026-01-05T17:00:00Z", completed: "2026-01-05T18:00:00Z")],
            meals: [breakfast],
            timeZone: "UTC"
        )
        XCTAssertEqual(relations.first?.source, "missing")
        XCTAssertNil(relations.first?.gapMinutes)
    }

    func testRhythmRewardsEatingAtTheSameTime() {
        let steady = (5...9).map { day in
            meal(slot: "lunch", date: "2026-01-0\(day)", at: "2026-01-0\(day)T12:00:00Z")
        }
        let scattered = [
            meal(slot: "lunch", date: "2026-01-05", at: "2026-01-05T11:00:00Z"),
            meal(slot: "lunch", date: "2026-01-06", at: "2026-01-06T14:00:00Z"),
            meal(slot: "lunch", date: "2026-01-07", at: "2026-01-07T12:30:00Z"),
            meal(slot: "lunch", date: "2026-01-08", at: "2026-01-08T16:00:00Z"),
        ]
        let steadyScore = MealTimingEngine.analyze(
            meals: steady, entries: [], sessions: [], timeZone: "UTC"
        ).rhythmScore
        let scatteredScore = MealTimingEngine.analyze(
            meals: scattered, entries: [], sessions: [], timeZone: "UTC"
        ).rhythmScore
        XCTAssertEqual(steadyScore, 100)
        XCTAssertNotNil(scatteredScore)
        XCTAssertLessThan(scatteredScore!, steadyScore!)
    }
}

final class RecoveryAssessmentTests: XCTestCase {
    private func apple(_ score: Int) -> RecoveryAssessment.Checkin {
        RecoveryAssessment.Checkin(
            date: "2026-01-05", source: "apple", sleepScore: score,
            sleepPercent: nil, recoveryPercent: nil, updatedAt: "2026-01-05T07:00:00Z"
        )
    }

    private func wearableScore(recovery: Int, sleep: Int) -> RecoveryAssessment.Checkin {
        RecoveryAssessment.Checkin(
            date: "2026-01-05", source: "other", sleepScore: nil,
            sleepPercent: sleep, recoveryPercent: recovery, updatedAt: "2026-01-05T07:00:00Z"
        )
    }

    func testAppleBandsFollowWatchOSClassifications() {
        XCTAssertEqual(RecoveryAssessment.assess(apple(30)).state, .veryLow)
        XCTAssertEqual(RecoveryAssessment.assess(apple(55)).state, .low)
        XCTAssertEqual(RecoveryAssessment.assess(apple(75)).state, .normal)
        XCTAssertEqual(RecoveryAssessment.assess(apple(90)).state, .strong)
    }

    func testAthlyticUsesItsOwnBands() {
        /* 55 is a normal day on Athlytic and a low one on Apple. */
        XCTAssertEqual(RecoveryAssessment.assess(wearableScore(recovery: 55, sleep: 80)).state, .normal)
        XCTAssertEqual(RecoveryAssessment.assess(apple(55)).state, .low)
    }

    func testAShortNightHoldsBackAStrongReadiness() {
        XCTAssertEqual(RecoveryAssessment.assess(wearableScore(recovery: 80, sleep: 90)).state, .strong)
        XCTAssertEqual(RecoveryAssessment.assess(wearableScore(recovery: 80, sleep: 35)).state, .normal)
    }

    func testEnoughWarningSignsPushABorderlineDayDown() {
        var context = RecoveryAssessment.Context()
        XCTAssertEqual(RecoveryAssessment.assess(apple(55), context: context).state, .low)
        context.consecutiveLowMornings = 2
        context.highSoreness = true
        XCTAssertEqual(RecoveryAssessment.assess(apple(55), context: context).state, .veryLow)
    }

    func testAGoodDayNeedsThreeSignsBeforeItIsDowngraded() {
        var context = RecoveryAssessment.Context()
        context.decliningPerformance = true
        context.highSoreness = true
        XCTAssertEqual(RecoveryAssessment.assess(apple(75), context: context).state, .normal)
        context.increasedJointDiscomfort = true
        XCTAssertEqual(RecoveryAssessment.assess(apple(75), context: context).state, .low)
    }

    func testEachStateSaysWhatToDo() {
        XCTAssertEqual(RecoveryAssessment.assess(apple(90)).title, "Ready for the planned session")
        XCTAssertTrue(RecoveryAssessment.assess(apple(55)).guidance.contains("priority strength work"))
        XCTAssertTrue(RecoveryAssessment.assess(apple(20)).guidance.contains("Avoid adding extra training"))
    }

    func testStoredHistoryDropsRowsMissingTheirOwnScore() {
        let addons: [String: JSONValue] = [
            "recovery_history": .array([
                .object([
                    "date": .string("2026-01-05"), "source": .string("apple"),
                    "sleep_score": .number(72), "updated_at": .string("2026-01-05T07:00:00Z"),
                ]),
                /* Apple without a sleep score cannot be scored, so it is dropped
                   rather than counted as zero. */
                .object([
                    "date": .string("2026-01-06"), "source": .string("apple"),
                    "updated_at": .string("2026-01-06T07:00:00Z"),
                ]),
            ])
        ]
        let history = RecoveryAssessment.history(from: addons)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.sleepScore, 72)
    }

    func testSleepDurationNeverMasqueradesAsAppleSleepScore() {
        var data = DashboardData()
        data.settings = UserSettings(
            userID: UUID(), voiceOn: false, ticksOn: false, notificationsOn: false,
            guardianFactor: 1,
            addons: [
                "apple_recovery_context": .object([
                    "date": .string("2026-01-05"),
                    "sleep_duration_hours": .number(7.2),
                    "updated_at": .string("2026-01-05T07:00:00Z"),
                ])
            ]
        )
        XCTAssertEqual(RecoveryAssessment.sleepDurationHours(data, date: "2026-01-05"), 7.2)
        XCTAssertNil(RecoveryAssessment.todaysCheckin(data, date: "2026-01-05"))
        XCTAssertNil(RecoveryAssessment.todaysCheckin(data, date: "2026-01-06"))
    }

    func testRecordedAppleSleepScoreIsNeverRecomputedFromDuration() {
        var data = DashboardData()
        data.settings = UserSettings(
            userID: UUID(), voiceOn: false, ticksOn: false, notificationsOn: false,
            guardianFactor: 1,
            addons: [
                "recovery_history": .array([
                    .object([
                        "date": .string("2026-01-05"), "source": .string("apple"),
                        "sleep_score": .number(57), "updated_at": .string("2026-01-05T07:00:00Z"),
                    ])
                ]),
                "apple_recovery_context": .object([
                    "date": .string("2026-01-05"),
                    "sleep_duration_hours": .number(4.16),
                    "updated_at": .string("2026-01-05T07:00:00Z"),
                ]),
            ]
        )
        XCTAssertEqual(
            RecoveryAssessment.todaysCheckin(data, date: "2026-01-05")?.sleepScore,
            57
        )
    }
}
