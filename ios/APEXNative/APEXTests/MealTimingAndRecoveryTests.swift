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
        slot: String = "lunch", marker: String? = nil,
        date: String = "2026-01-05",
        at: String,
        kcal: Double = 500,
        fat: Double = 15
    ) -> LoggedMeal {
        LoggedMeal(
            id: id, userID: user, localDate: date, mealSlot: slot, displayName: slot.capitalized,
            sourcePresetID: nil, sourcePlannedMealID: nil, loggedAt: at,
            clientIdempotencyKey: id.uuidString + (marker.map { "|apex-meal-block=" + $0 } ?? ""), loggedAs: "manual",
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

    func testALaterLightSnackCannotEraseAnActiveLongerLunchComfortWindow() {
        let lunch = MealTimingEngine.ComfortAnchor(
            startMinute: 12 * 60,
            window: MealTimingEngine.comfortWindow(kcal: 700, fatG: 26, fibreG: 10)
        )
        let snack = MealTimingEngine.ComfortAnchor(
            startMinute: 12 * 60 + 5,
            window: MealTimingEngine.comfortWindow(kcal: 180, fatG: 4, fibreG: 3)
        )

        XCTAssertEqual(MealTimingEngine.mergedComfortBands([lunch, snack]), [
            MealTimingEngine.ComfortBand(zone: .settling, startMinute: 12 * 60, endMinute: 13 * 60 + 30),
            MealTimingEngine.ComfortBand(zone: .transition, startMinute: 13 * 60 + 30, endMinute: 15 * 60),
        ])
    }

    func testDaylineUsesTheRecordedFinishOnlyWhenItBelongsToTheSelectedDay() {
        let recorded = MealTimingEngine.daylineMealTiming(
            loggedAt: "2026-01-05T12:37:00Z",
            localDate: "2026-01-05",
            scheduledMinute: 13 * 60,
            timeZone: "Europe/Zurich"
        )
        XCTAssertTrue(recorded.recorded)
        XCTAssertEqual(recorded.minute, 13 * 60 + 37)

        let stale = MealTimingEngine.daylineMealTiming(
            loggedAt: "2026-01-04T12:37:00Z",
            localDate: "2026-01-05",
            scheduledMinute: 13 * 60,
            timeZone: "Europe/Zurich"
        )
        XCTAssertFalse(stale.recorded)
        XCTAssertEqual(stale.minute, 13 * 60)
    }

    func testDaylineBuildsAnExactZonedInstantAcrossItsThreeAMBoundary() throws {
        let instant = try XCTUnwrap(MealTimingEngine.daylineInstant(
            localDate: "2026-01-05",
            lineMinute: 25 * 60 + 15,
            timeZone: "Europe/Zurich"
        ))
        XCTAssertEqual(instant.ISO8601Format(), "2026-01-06T00:15:00Z")

        let recorded = MealTimingEngine.daylineMealTiming(
            loggedAt: "2026-01-06T00:15:00Z",
            localDate: "2026-01-05",
            scheduledMinute: 21 * 60,
            timeZone: "Europe/Zurich"
        )
        XCTAssertTrue(recorded.recorded)
        XCTAssertEqual(recorded.lineMinute, 25 * 60 + 15)
    }

    func testDaylineSnapsToTheConfiguredIncrement() {
        XCTAssertEqual(MealTimingEngine.snapDaylineMinute(12 * 60 + 7, increment: 5), 12 * 60 + 5)
        XCTAssertEqual(MealTimingEngine.snapDaylineMinute(12 * 60 + 7, increment: 15), 12 * 60)
        XCTAssertEqual(MealTimingEngine.snapDaylineMinute(12 * 60 + 47, increment: 30), 13 * 60)
        XCTAssertEqual(MealTimingEngine.snapDaylineMinute(12 * 60 + 31, increment: 60), 13 * 60)
    }

    func testHistoricalQuickLogsKeepTheirReceiptsWithoutUsingSaveTimeAsAWorkoutFinish() {
        for (assignedDate, savedAt) in [
            ("2026-11-01", "2026-11-02T18:38:00Z"),
            ("2026-10-14", "2026-11-02T18:55:00Z")
        ] {
            var workout = session(date: assignedDate, started: savedAt, completed: savedAt)
            workout.notes = ManualWorkout.notes(title: "Quick Log")

            for visibleDate in [assignedDate, "2026-11-02"] {
                XCTAssertNil(MealTimingEngine.daylineWorkoutTiming(
                    workout, localDate: visibleDate, timeZone: "Europe/Zurich"
                ))
            }
            XCTAssertTrue(MealTimingEngine.postWorkoutNutrition(
                sessions: [workout], meals: [], timeZone: "Europe/Zurich"
            ).isEmpty)
            XCTAssertEqual(WorkoutReceipt.history(
                sessions: [workout], days: [], date: assignedDate, ownerID: user
            ).map(\.session.id), [workout.id])
            XCTAssertTrue(WorkoutReceipt.history(
                sessions: [workout], days: [], date: "2026-11-02", ownerID: user
            ).isEmpty)
        }
    }

    func testQuickLogWithARecordedFinishOnItsAssignedDayRemainsOnTheDayline() throws {
        var workout = session(
            date: "2026-11-01", started: nil, completed: "2026-11-02T01:40:00Z"
        )
        workout.notes = ManualWorkout.notes(title: "Late workout")
        let timing = try XCTUnwrap(MealTimingEngine.daylineWorkoutTiming(
            workout, localDate: "2026-11-01", timeZone: "Europe/Zurich"
        ))
        XCTAssertEqual(timing.lineMinute, 26 * 60 + 40)
        XCTAssertNil(workout.startedAt)
        XCTAssertEqual(MealTimingEngine.postWorkoutNutrition(
            sessions: [workout], meals: [], timeZone: "Europe/Zurich"
        ).count, 1)
    }

    func testTrackedWorkoutKeepsItsActualCompletionDayWhenDifferentFromItsAssignedDate() throws {
        let workout = session(
            date: "2026-11-01", started: "2026-11-02T17:00:00Z", completed: "2026-11-02T18:38:00Z"
        )
        let timing = try XCTUnwrap(MealTimingEngine.daylineWorkoutTiming(
            workout, localDate: "2026-11-02", timeZone: "Europe/Zurich"
        ))
        XCTAssertEqual(timing.minute, 19 * 60 + 38)
        XCTAssertNil(MealTimingEngine.daylineWorkoutTiming(
            workout, localDate: "2026-11-01", timeZone: "Europe/Zurich"
        ))
    }

    func testCompletedWorkoutAppearsAtItsFinishTimeInTheConfiguredZone() throws {
        let workout = session(
            started: "2026-01-05T17:00:00Z",
            completed: "2026-01-05T18:23:00Z"
        )
        let timing = try XCTUnwrap(MealTimingEngine.daylineWorkoutTiming(
            workout,
            localDate: "2026-01-05",
            timeZone: "Europe/Zurich"
        ))
        XCTAssertEqual(timing.minute, 19 * 60 + 23)
        XCTAssertEqual(timing.lineMinute, 19 * 60 + 23)

        let afterMidnight = try XCTUnwrap(MealTimingEngine.daylineWorkoutTiming(
            session(
                started: "2026-01-05T22:30:00Z",
                completed: "2026-01-06T00:15:00Z"
            ),
            localDate: "2026-01-05",
            timeZone: "Europe/Zurich"
        ))
        XCTAssertEqual(afterMidnight.lineMinute, 25 * 60 + 15)
    }

    func testDaylineSourceKeepsScheduledMealsLiveAndRefreshesItsClock() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dayline = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Nutrition/NutritionParityViews.swift")
        )

        XCTAssertTrue(dayline.contains("plannedMeal: planned"))
        XCTAssertTrue(dayline.contains("TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30))"))
        XCTAssertTrue(dayline.contains("session.data.workoutSessions"))
        XCTAssertTrue(dayline.contains("updateMealBlockTime"))
        XCTAssertTrue(dayline.contains("updateWorkoutCompletedAt"))
    }

    func testNativeDaylineRendersMergedBandsInsteadOfOnlyTheLatestMeal() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dayline = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Nutrition/NutritionParityViews.swift")
        )

        XCTAssertTrue(dayline.contains("MealTimingEngine.mergedComfortBands(comfortContexts.map(\\.anchor))"))
        XCTAssertFalse(dayline.contains("private var latestLoggedMeal"))
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

    func testMealTimingSeparatesSnackFromRecoveryAndClosesItsDateWindow() throws {
        let cutoff = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-07T22:00:00Z"))
        var data = APEXDebugFixture.dashboard(userID: user)
        data.settings?.addons["time_zone"] = .string("UTC")
        let early = meal(slot: "snack", marker: "snack", date: "2026-01-05", at: "2026-01-05T15:00:00Z")
        let late = meal(slot: "snack", marker: "post_workout", date: "2026-01-06", at: "2026-01-06T21:00:00Z")
        data.loggedMeals = [early, late, meal(slot: "snack", date: "2026-01-08", at: "2026-01-08T15:00:00Z")]
        let partial = MetabolicRhythm(data: data, days: 3, now: cutoff)
        XCTAssertEqual(partial.mealCount, 2)
        XCTAssertNil(partial.score)
        data.loggedMeals.append(meal(slot: "snack", date: "2026-01-07", at: "2026-01-07T15:00:00Z"))
        let complete = MetabolicRhythm(data: data, days: 3, now: cutoff)
        XCTAssertEqual(complete.mealCount, 3)
        XCTAssertEqual(complete.timingVariation ?? -1, 0, accuracy: 0.01)
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
    func testNightSleepReadsTheSameAllDayAndLeavesNapsOut() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        // Asleep 23:00 to 07:00: the Watch writes hourly stages, the iPhone one overlapping block.
        let night = (0..<8).map { DateInterval(start: at(9, 23).addingTimeInterval(Double($0) * 3_600), duration: 3_600) }
            + [DateInterval(start: at(9, 23, 30), end: at(10, 6, 30))]
        let naps = [
            DateInterval(start: at(9, 14, 30), end: at(9, 15, 30)),
            DateInterval(start: at(10, 14), end: at(10, 15)),
        ]
        func hours(_ asleep: [DateInterval], readAt: Date) throws -> Double? {
            let window = try XCTUnwrap(RecoveryAssessment.nightSleepWindow(endingOn: readAt, calendar: calendar))
            return RecoveryAssessment.nightSleepHours(asleep: asleep, window: window)
        }

        XCTAssertEqual(try XCTUnwrap(hours(night + naps, readAt: at(10, 8))), 8, accuracy: 0.001,
                       "yesterday afternoon's nap is not last night")
        XCTAssertEqual(try XCTUnwrap(hours(night + naps, readAt: at(10, 22))), 8, accuracy: 0.001,
                       "an evening read must not shrink the night or add today's nap")
        XCTAssertNil(try hours(naps, readAt: at(10, 9)), "no sleep in the night is no reading, never zero")
        let earlyNight = [DateInterval(start: at(9, 17), end: at(9, 19)), DateInterval(start: at(10, 11), end: at(10, 13))]
        XCTAssertEqual(try XCTUnwrap(hours(earlyNight, readAt: at(10, 13))), 2, accuracy: 0.001,
                       "sleep that crosses the window counts only inside it")
    }

    func testLaterReadOfTheSameNightNeverTakesHoursAway() {
        func stored(_ addons: [String: JSONValue]) -> Double? {
            addons["apple_recovery_context"]?.objectValue?["sleep_duration_hours"]?.numberValue
        }
        func read(_ addons: [String: JSONValue], _ date: String, _ hours: Double?) -> [String: JSONValue] {
            RecoveryAssessment.addons(
                addons, storingHealthRead: date, sleepHours: hours,
                heartRateVariabilityMS: 41, restingHeartRate: 52, updatedAt: "2026-11-10T08:00:00Z"
            )
        }
        var addons = read([:], "2026-11-10", 7.5)
        XCTAssertEqual(stored(addons), 7.5)
        addons = read(addons, "2026-11-10", nil)
        XCTAssertEqual(stored(addons), 7.5, "a sleep read that failed must not erase the night")
        addons = read(addons, "2026-11-10", 3.7)
        XCTAssertEqual(stored(addons), 7.5)
        addons = read(addons, "2026-11-10", 8.25)
        XCTAssertEqual(stored(addons), 8.25, "a lie-in adds to the night")
        addons = read(addons, "2026-11-11", 5)
        XCTAssertEqual(stored(addons), 5, "a new day starts from its own night")
        XCTAssertEqual(addons["apple_recovery_context"]?.objectValue?["date"]?.stringValue, "2026-11-11")
    }

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
