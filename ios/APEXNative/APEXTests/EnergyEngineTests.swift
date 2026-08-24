import XCTest
@testable import APEX

final class EnergyEngineTests: XCTestCase {
    func testQuickSedentaryRecompUsesProfileAndSafetyFloor() {
        let result = EnergyEngine.targets(profile: profile(weight: 70, level: .sedentary, goal: .recomp), logs: [], catalog: [])

        XCTAssertEqual(result.bmr, 1_580)
        XCTAssertEqual(result.tdee, 1_896)
        XCTAssertEqual(result.pal, 1.20, accuracy: 0.001)
        XCTAssertEqual(result.level, .sedentary)
        XCTAssertGreaterThanOrEqual(result.targetCalories, Int((Double(result.bmr) * 1.05).rounded(.down)))
    }

    func testNetBlocksAvoidRestingEnergyDoubleCount() {
        let profile = profile(weight: 70)
        let massage = activity(id: "massage-session", met: 4, input: .count, minutes: 60)
        let market = activity(id: "supermarket-trip", met: 3, input: .count, minutes: 25)
        let steps = activity(id: "incidental-steps", met: 1.2, input: .steps)

        let massageKcal = EnergyEngine.blockCalories(type: massage, quantity: 2, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let marketKcal = EnergyEngine.blockCalories(type: market, quantity: 1, durationMinutes: 25, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let stepsKcal = EnergyEngine.blockCalories(type: steps, quantity: 8_000, durationMinutes: nil, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let logs = [
            log(typeID: massage.id, kcal: massageKcal),
            log(typeID: market.id, kcal: marketKcal),
            log(typeID: steps.id, kcal: stepsKcal)
        ]
        let result = EnergyEngine.targets(profile: profile, logs: logs, catalog: [massage, market, steps])

        XCTAssertEqual(massageKcal, 392, accuracy: 0.01)
        XCTAssertEqual(marketKcal, 52.5, accuracy: 0.01)
        XCTAssertEqual(stepsKcal, 308, accuracy: 0.01)
        XCTAssertEqual(result.tdee, 2_648)
        XCTAssertEqual(result.level, .moderate)
    }

    func testDistanceAndDiscountedWatchUseMaximumNotSum() {
        let run = activity(id: "jog-run", met: 7, input: .distance, distanceFactor: 1, supportsWatch: true)
        let result = EnergyEngine.blockCalories(
            type: run,
            quantity: 1,
            durationMinutes: nil,
            distanceKM: 5,
            watchKcal: 420,
            weightKG: 70
        )

        XCTAssertEqual(result, 350, accuracy: 0.001)
    }

    func testChampionshipWorkloadMapsToExtraActive() {
        let profile = profile(weight: 70)
        let filming = activity(id: "gimbal-filming", met: 3.2, input: .duration)
        let travel = activity(id: "travel-day", met: 2.5, input: .duration)
        let filmingKcal = EnergyEngine.blockCalories(type: filming, quantity: 1, durationMinutes: 480, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let travelKcal = EnergyEngine.blockCalories(type: travel, quantity: 1, durationMinutes: 120, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let result = EnergyEngine.targets(
            profile: profile,
            logs: [log(typeID: filming.id, kcal: filmingKcal), log(typeID: travel.id, kcal: travelKcal)],
            catalog: [filming, travel]
        )

        XCTAssertEqual(result.level, .extra)
        XCTAssertGreaterThanOrEqual(result.pal, 2)
    }

    func testGoalChangeRecalculatesEveryMacroAndEnergyStillBalances() {
        let recomp = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .recomp), logs: [], catalog: [])
        let maintain = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .maintain), logs: [], catalog: [])
        let bulk = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .bulk), logs: [], catalog: [])

        XCTAssertGreaterThan(recomp.proteinG, maintain.proteinG)
        XCTAssertGreaterThan(maintain.proteinG, bulk.proteinG)
        XCTAssertLessThan(recomp.fatG, maintain.fatG)
        XCTAssertLessThan(maintain.fatG, bulk.fatG)
        XCTAssertLessThan(recomp.carbsG, maintain.carbsG)
        XCTAssertLessThan(maintain.carbsG, bulk.carbsG)

        for target in [recomp, maintain, bulk] {
            let macroCalories = target.proteinG * 4 + target.fatG * 9 + target.carbsG * 4
            XCTAssertLessThanOrEqual(abs(macroCalories - target.targetCalories), 2)
        }
    }

    func testMacroPolicyMatchesCrossClientLiteralFixtures() {
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .recomp, targetCalories: 2_200
            ),
            .init(proteinG: 147, fatG: 61, carbsG: 266)
        )
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .maintain, targetCalories: 2_400
            ),
            .init(proteinG: 133, fatG: 73, carbsG: 303)
        )
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .bulk, targetCalories: 2_600
            ),
            .init(proteinG: 126, fatG: 81, carbsG: 342)
        )
    }

    func testCalibrationNudgesUpwardAndClamps() {
        let next = EnergyEngine.calibratedK(
            currentK: 1,
            meanDailyIntake: 2_300,
            predictedDailyTDEE: 2_100,
            startingEMAWeight: 70,
            endingEMAWeight: 70,
            elapsedDays: 13
        )
        XCTAssertEqual(next, 1.0190476, accuracy: 0.00001)

        let clamped = EnergyEngine.calibratedK(
            currentK: 1.14,
            meanDailyIntake: 4_000,
            predictedDailyTDEE: 1_800,
            startingEMAWeight: 70,
            endingEMAWeight: 70,
            elapsedDays: 13
        )
        XCTAssertEqual(clamped, 1.15, accuracy: 0.00001)
    }

    func testSameCatalogBlockUsesViewingUsersWeight() {
        let massage = activity(id: "massage-session", met: 4, input: .count, minutes: 60)
        let at70 = EnergyEngine.blockCalories(type: massage, quantity: 1, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let at58 = EnergyEngine.blockCalories(type: massage, quantity: 1, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 58)

        XCTAssertEqual(at70, 196, accuracy: 0.001)
        XCTAssertEqual(at58, 162.4, accuracy: 0.001)
        XCTAssertNotEqual(at70, at58)
    }

    private func profile(
        weight: Double,
        level: ActivityLevel = .sedentary,
        goal: Goal = .recomp
    ) -> Profile {
        let id = UUID()
        return Profile(
            id: id,
            userID: id,
            persona: .constantine,
            displayName: "Test User",
            sex: "male",
            weightKG: weight,
            bodyFatPercent: 20,
            heightCM: 175,
            birthdate: "1990-01-01",
            activityLevel: level,
            goal: goal,
            targetKcal: nil,
            targetProteinG: nil,
            targetFatG: nil,
            targetCarbsG: nil,
            trainingTime: "07:00",
            baselineDate: "2026-01-01",
            profileNote: "",
            seedVersion: 1,
            calibrationK: 1,
            calibrationHistory: [],
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func activity(
        id: String,
        met: Double,
        input: ActivityInputStyle,
        minutes: Int? = nil,
        distanceFactor: Double? = nil,
        supportsWatch: Bool = false
    ) -> ActivityType {
        ActivityType(
            id: id,
            category: "test",
            name: id,
            icon: "figure.walk",
            met: met,
            inputStyle: input,
            defaultDurationMinutes: minutes,
            isTrainingLinked: false,
            notes: "",
            distanceFactor: distanceFactor,
            supportsWatch: supportsWatch
        )
    }

    private func log(typeID: String, kcal: Double) -> ActivityLog {
        let id = UUID()
        return ActivityLog(
            id: id,
            userID: id,
            date: "2026-08-16",
            typeID: typeID,
            quantity: 1,
            durationMinutes: nil,
            distanceKM: nil,
            watchKcal: nil,
            computedKcal: kcal,
            source: "manual",
            reconciled: false,
            createdAt: "2026-08-16T00:00:00Z",
            updatedAt: "2026-08-16T00:00:00Z"
        )
    }
}
