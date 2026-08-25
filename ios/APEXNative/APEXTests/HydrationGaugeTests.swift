import XCTest
@testable import APEX

/*
 * The litre scale beside the hydration figure has to land on the body, not
 * on the frame. The SVG viewBox is "-150 -150 W 1015"; inside it the crown
 * of the head is y = 0 and the feet, where the fill rests at zero, are
 * y = 712. Rendered with xMidYMid meet into a frame of the same aspect
 * ratio, those become fixed fractions of the frame height.
 *
 * These pin the mapping so a future layout change cannot quietly detach the
 * ruler from the silhouette again.
 */
final class HydrationGaugeTests: XCTestCase {

    private let crownFraction = 150.0 / 1015.0
    private let feetFraction = 862.0 / 1015.0

    private func tickY(liters: Double, target: Double, height: Double) -> Double {
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        let fraction = target > 0 ? min(1, max(0, liters / target)) : 0
        return feetY - fraction * (feetY - crownY)
    }

    func testZeroLitresSitsAtTheFeet() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 0, target: 2.75, height: height), feetFraction * height, accuracy: 0.001)
    }

    func testTargetSitsAtTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 2.75, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testHalfTheTargetSitsHalfwayUpTheBody() {
        let height = 400.0
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        XCTAssertEqual(
            tickY(liters: 1.375, target: 2.75, height: height),
            (crownY + feetY) / 2,
            accuracy: 0.001
        )
    }

    func testScaleIsProportionalToFrameHeight() {
        /* Doubling the figure doubles every offset, so the ruler tracks it. */
        let small = tickY(liters: 1.0, target: 2.75, height: 200)
        let large = tickY(liters: 1.0, target: 2.75, height: 400)
        XCTAssertEqual(large, small * 2, accuracy: 0.001)
    }

    func testBodyOccupiesTheExpectedSliceOfTheFrame() {
        /* Guards against someone "fixing" the layout by stretching the web
           view to full height, which would silently break the alignment. */
        XCTAssertEqual(crownFraction, 0.1478, accuracy: 0.0005)
        XCTAssertEqual(feetFraction, 0.8493, accuracy: 0.0005)
    }

    func testOverdrinkingIsClampedToTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 5.0, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testFigureAspectMatchesTheViewBox() {
        /* Frame aspect must equal the viewBox aspect or xMidYMid meet
           letterboxes the drawing and the fractions above stop holding. */
        XCTAssertEqual(583.6 / 1015.0, 0.5750, accuracy: 0.0005, "male figure")
        XCTAssertEqual(568.0 / 1015.0, 0.5596, accuracy: 0.0005, "female figure")
    }
}

final class WatchHydrationFillStateTests: XCTestCase {
    func testProgressAndWaterlineClampAtEmptyAndTarget() {
        let empty = WatchHydrationFillState(liters: -0.5, targetLiters: 2.75)
        let full = WatchHydrationFillState(liters: 4.0, targetLiters: 2.75)

        XCTAssertEqual(empty.progress, 0)
        XCTAssertEqual(empty.baseWaterline, 1)
        XCTAssertEqual(full.progress, 1)
        XCTAssertEqual(full.baseWaterline, 0)
    }

    func testWaterlineRisesProportionallyThroughTheBody() {
        let quarter = WatchHydrationFillState(liters: 0.6875, targetLiters: 2.75)
        let half = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)
        let threeQuarters = WatchHydrationFillState(liters: 2.0625, targetLiters: 2.75)

        XCTAssertEqual(quarter.baseWaterline, 0.75, accuracy: 0.0001)
        XCTAssertEqual(half.baseWaterline, 0.5, accuracy: 0.0001)
        XCTAssertEqual(threeQuarters.baseWaterline, 0.25, accuracy: 0.0001)
    }

    func testWaveCannotCreateWaterWhenEmptyOrLeaveAirWhenFull() {
        for phase in stride(from: 0.0, through: Double.pi * 2, by: 0.4) {
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 0, normalizedX: 0.35, phase: phase),
                1,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 1, normalizedX: 0.65, phase: phase),
                0,
                accuracy: 0.0001
            )
        }
    }

    func testAnimatedWaveStaysInsideNormalizedGaugeBounds() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                let waterline = WatchHydrationFillState.waterline(
                    progress: progress,
                    normalizedX: x,
                    phase: 1.75
                )
                XCTAssertGreaterThanOrEqual(waterline, 0)
                XCTAssertLessThanOrEqual(waterline, 1)
            }
        }
    }

    func testComplicationModesDeriveFromLitersWithoutStoringConvertedValues() {
        let state = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)
        XCTAssertEqual(WatchHydrationDisplayMode.percent.shortValue(for: state), "50%")
        XCTAssertEqual(WatchHydrationDisplayMode.liters.shortValue(for: state), "1.38L")
        XCTAssertEqual(WatchHydrationDisplayMode.gallons.shortValue(for: state), "0.36gal")
    }

    func testPrimaryWatchAmountKeepsTheUnitBesideTheValueWithoutARedundantDayLabel() {
        let state = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)

        XCTAssertEqual(state.primaryAmount, "1.38 L")
        XCTAssertFalse(state.primaryAmount.localizedCaseInsensitiveContains("today"))
    }

    func testGaugeAnimationRunsOnlyWhileTheAppIsActivelyVisible() {
        XCTAssertTrue(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: false,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: false,
                luminanceIsReduced: false,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: false,
                reduceMotion: true
            )
        )
    }

    func testCompositionStopsPreserveExactBeverageProportions() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationCompositionLayout.stops(for: bands)
        let first = try XCTUnwrap(stops.first)
        let last = try XCTUnwrap(stops.last)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(coffeeStart.location - waterEnd.location, 0.005)
        XCTAssertEqual(first.location, 0)
        XCTAssertEqual(last.location, 1)
    }

    func testCompositionStopsMapExactProportionsIntoOnlyTheFilledSilhouette() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationCompositionLayout.stops(for: bands, mappedInto: 0.6 ... 1)
        let first = try XCTUnwrap(stops.first)
        let last = try XCTUnwrap(stops.last)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual(first.location, 0.6, accuracy: 0.000_001)
        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.96, accuracy: 0.000_001)
        XCTAssertEqual(last.location, 1, accuracy: 0.000_001)
    }

    func testFigureBridgeCarriesWeightedStopsAcrossTheVisibleFill() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationFigureWebPalette.stops(for: bands)
        let waterEnd = try XCTUnwrap(stops.last { $0.color == "#14CCE8" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.color == "#8C4A21" })

        XCTAssertEqual((waterEnd.offset + coffeeStart.offset) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(coffeeStart.offset - waterEnd.offset, 0.005)
        XCTAssertEqual(HydrationFigureWebPalette.fillHeight(progress: 0.49), 348.88, accuracy: 0.000_001)
    }
}

final class WatchHydrationPreferencesTests: XCTestCase {
    func testDefaultsAreQuietAndBatteryConscious() {
        let preferences = WatchHydrationPreferences.default

        XCTAssertEqual(preferences.targetLiters, 2.75)
        XCTAssertEqual(preferences.effectiveTargetMode, .automatic)
        XCTAssertEqual(preferences.unit, .liters)
        XCTAssertTrue(preferences.showsPresetNames)
        XCTAssertTrue(preferences.confirmationHaptics)
        XCTAssertEqual(preferences.motionIntensity, .subtle)
        XCTAssertFalse(preferences.remindersEnabled)
        XCTAssertEqual(preferences.reminderIntervalMinutes, 90)
        XCTAssertEqual(preferences.quietHoursStartMinutes, 21 * 60 + 30)
        XCTAssertEqual(preferences.quietHoursEndMinutes, 8 * 60)
    }

    func testExactTargetValidationRejectsUnsafeOrInvalidValues() throws {
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(3.8), 3.8)
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(1.0), 1.0)
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(6.0), 6.0)
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(0.9))
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(6.1))
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(.nan))
    }

    func testPreferencesRoundTripWithoutLosingExactGoal() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(3.83)
        preferences.targetMode = .custom
        preferences.unit = .gallons
        preferences.showsPresetNames = false
        preferences.remindersEnabled = true
        preferences.reminderIntervalMinutes = 120

        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(WatchHydrationPreferences.self, from: data)

        XCTAssertEqual(restored, preferences)
        XCTAssertEqual(restored.targetLiters, 3.83)
        XCTAssertEqual(restored.effectiveTargetMode, .custom)
    }

    func testEarlierWatchCacheWithoutTargetModeStillDecodesAsAutomatic() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchHydrationPreferences.default))
                as? [String: Any]
        )
        object.removeValue(forKey: "targetMode")
        let restored = try JSONDecoder().decode(
            WatchHydrationPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(restored.effectiveTargetMode, .automatic)
        XCTAssertEqual(restored.targetLiters, 2.75)
    }

    func testEarlierWatchCachePreservesANonDefaultCustomTarget() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.targetLiters = 3.8
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
        )
        object.removeValue(forKey: "targetMode")
        let restored = try JSONDecoder().decode(
            WatchHydrationPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(restored.effectiveTargetMode, .custom)
        XCTAssertEqual(restored.targetLiters, 3.8)
    }

    func testSelectedUnitsDeriveDisplayWithoutChangingStoredLiters() {
        var preferences = WatchHydrationPreferences.default
        XCTAssertEqual(preferences.formattedAmount(liters: 1), "1.00 L")

        preferences.unit = .gallons
        XCTAssertEqual(preferences.formattedAmount(liters: 1), "0.26 gal")
        XCTAssertEqual(preferences.formattedTarget, "0.73 gal")
        XCTAssertEqual(preferences.targetLiters, 2.75)
    }
}

final class AdaptiveHydrationTargetTests: XCTestCase {
    func testAutomaticTargetCombinesBodySizeWithBoundedExercise() {
        let target = HydrationTargetPolicy.resolve(
            sex: "male",
            weightKG: 80,
            mode: .automatic,
            customTargetML: 3_800,
            plannedExerciseMinutes: 60,
            recordedExerciseMinutes: 0,
            activeCalories: 0,
            dateRelation: .today,
            localHour: 10
        )

        XCTAssertEqual(target.mode, .automatic)
        XCTAssertEqual(target.targetML, 3_250)
        XCTAssertEqual(target.baselineML, 2_850)
        XCTAssertEqual(target.exerciseAdjustmentML, 400)
        XCTAssertEqual(target.wearableAdjustmentML, 0)
    }

    func testBaselineIsBoundedBySexSpecificPopulationReferences() {
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "female", weightKG: 60).baselineML, 2_150)
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "female", weightKG: 35).baselineML, 2_000)
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "male", weightKG: 200).baselineML, 3_700)
    }

    func testLateWearableCaloriesAreSmallAndCapped() {
        let before = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 1_600, dateRelation: .today, localHour: 14
        )
        let after = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 800, dateRelation: .today, localHour: 16
        )
        let muchHigherCalories = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 1_600, dateRelation: .today, localHour: 16
        )

        XCTAssertEqual(before.wearableAdjustmentML, 0)
        XCTAssertEqual(after.wearableAdjustmentML, 200)
        XCTAssertEqual(muchHigherCalories.wearableAdjustmentML, 200)
        XCTAssertEqual(after.exerciseAdjustmentML, 400)
        XCTAssertEqual(after.targetML, 3_450)
    }

    func testLateStepsCanCorroborateActivityWithoutACalorieSample() {
        let moderate = HydrationTargetPolicy.resolve(
            sex: "female", weightKG: 60,
            activeCalories: 0, steps: 12_000,
            dateRelation: .today, localHour: 16
        )
        let high = HydrationTargetPolicy.resolve(
            sex: "female", weightKG: 60,
            activeCalories: 0, steps: 18_000,
            dateRelation: .today, localHour: 16
        )

        XCTAssertEqual(moderate.wearableAdjustmentML, 100)
        XCTAssertEqual(high.wearableAdjustmentML, 200)
    }

    func testExactCustomTargetCannotDriftWithActivity() {
        let target = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 100,
            mode: .custom, customTargetML: 3_830,
            plannedExerciseMinutes: 120, recordedExerciseMinutes: 120,
            activeCalories: 2_000, dateRelation: .past, localHour: 23
        )

        XCTAssertEqual(target.targetML, 3_830)
        XCTAssertEqual(target.baselineML, 3_830)
        XCTAssertEqual(target.exerciseAdjustmentML, 0)
        XCTAssertEqual(target.wearableAdjustmentML, 0)
    }

    func testLegacyModeInferencePreservesCustomChoice() {
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: nil, targetML: 2_750), .automatic)
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: nil, targetML: 3_800), .custom)
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: "automatic", targetML: 3_800), .automatic)
    }
}

final class WatchHydrationReminderPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDisabledAndCompletedGoalsDoNotSchedule() {
        let now = date(hour: 12)
        var preferences = WatchHydrationPreferences.default

        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: now,
                liters: 0.5,
                lastDrinkAt: date(hour: 10),
                preferences: preferences,
                calendar: calendar
            )
        )

        preferences.remindersEnabled = true
        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: now,
                liters: preferences.targetLiters,
                lastDrinkAt: date(hour: 10),
                preferences: preferences,
                calendar: calendar
            )
        )
    }

    func testReminderRequiresBothInactivityAndQuarterLiterPaceDeficit() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.remindersEnabled = true
        preferences.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(3)
        let now = date(hour: 10)

        let behind = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 0,
            lastDrinkAt: date(hour: 8),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertEqual(behind, date(hour: 10, minute: 1))

        let recentlyDrank = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 0,
            lastDrinkAt: date(hour: 9, minute: 30),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertEqual(recentlyDrank, date(hour: 11))

        let ahead = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 1,
            lastDrinkAt: date(hour: 8),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertNotNil(ahead)
        XCTAssertGreaterThan(ahead ?? now, date(hour: 13))
    }

    func testQuietHoursNeverScheduleAStaleNextDayReminder() {
        var preferences = WatchHydrationPreferences.default
        preferences.remindersEnabled = true

        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: date(hour: 22),
                liters: 0,
                lastDrinkAt: date(hour: 18),
                preferences: preferences,
                calendar: calendar
            )
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: hour, minute: minute))!
    }
}
