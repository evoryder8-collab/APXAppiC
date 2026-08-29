import XCTest
@testable import APEX

final class OrbitIntegrationsTests: XCTestCase {
    func testShortRunDoesNotAddFoodAutomatically() {
        let adjustment = OrbitIntegrations.nutritionAdjustment(run: run(minutes: 42), weightKG: 70)

        XCTAssertEqual(adjustment.kcal, 0)
        XCTAssertEqual(adjustment.timing, "normal_meals")
    }

    func testLongRunCreatesReviewableFuelingAdjustment() {
        let adjustment = OrbitIntegrations.nutritionAdjustment(run: run(minutes: 120), weightKG: 70)

        XCTAssertEqual(adjustment.carbsG, 65)
        XCTAssertEqual(adjustment.proteinG, 21)
        XCTAssertEqual(adjustment.kcal, 344)
        XCTAssertEqual(adjustment.timing, "during_and_recovery")
    }

    func testFoodMemoryPrefersFavouriteCompleteCarbohydrateFood() {
        let userID = UUID()
        let favouriteID = UUID()
        let otherID = UUID()
        let foods = [food(id: otherID, name: "Rice", carbs: 28), food(id: favouriteID, name: "Oats", carbs: 60)]
        let preferences = [
            preference(userID: userID, foodID: otherID, favourite: false, useCount: 12),
            preference(userID: userID, foodID: favouriteID, favourite: true, useCount: 2)
        ]
        let adjustment = OrbitNutritionAdjustment(kcal: 180, carbsG: 45, proteinG: 0, fatG: 0, timing: "pre_and_post", explanation: "")

        let suggestion = OrbitIntegrations.foodMemorySuggestion(
            adjustment: adjustment,
            foods: foods,
            preferences: preferences
        )

        XCTAssertEqual(suggestion?.food.name, "Oats")
        XCTAssertEqual(suggestion?.amount, 75)
        XCTAssertEqual(suggestion?.nutrients.carbsG ?? 0, 45, accuracy: 0.001)
    }

    func testNutritionAdjustmentCreatesAnAuditableStructuredMeal() throws {
        let orbitRun = run(minutes: 120)
        let oats = food(id: UUID(), name: "Oats", carbs: 60)
        let suggestion = OrbitFoodMemorySuggestion(
            food: oats, amount: 75, unit: "g",
            nutrients: oats.nutrients(forEquivalentAmount: 75)
        )

        let draft = try XCTUnwrap(OrbitIntegrations.nutritionMealDraft(run: orbitRun, suggestion: suggestion))

        XCTAssertEqual(draft.localDate, orbitRun.localDate)
        XCTAssertEqual(draft.mealSlot, "post-workout")
        XCTAssertEqual(draft.loggedAs, "custom")
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.foodID?.uuidString.lowercased(), oats.id.lowercased())
        XCTAssertEqual(draft.totals.kcal, suggestion.nutrients.kcal, accuracy: 0.001)
    }

    func testNutritionAdjustmentCannotBeAppliedWithoutAConcreteFoodRecord() {
        XCTAssertNil(OrbitIntegrations.nutritionMealDraft(run: run(minutes: 120), suggestion: nil))
    }

    func testOrbitReconciliationPreservesOtherSameDayActivities() {
        let orbitRun = run(minutes: 75)
        let generated = activity(id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate, typeID: "jog-run", source: "orbit")
        let manualRun = activity(id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate, typeID: "jog-run", source: "manual")
        let watchCalories = activity(id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate, typeID: "watch-kcal", source: "manual")
        let previousGenerated = activity(id: generated.id, userID: orbitRun.userID, date: orbitRun.localDate, typeID: "jog-run", source: "orbit")

        let result = OrbitIntegrations.reconciledActivityLogs(existing: [manualRun, watchCalories, previousGenerated], generated: generated)

        XCTAssertEqual(result.filter { $0.id == generated.id }.count, 1)
        XCTAssertTrue(result.contains { $0.id == manualRun.id })
        XCTAssertTrue(result.contains { $0.id == watchCalories.id })
    }

    func testOrbitRecognizesAnOwnedVisibleHealthKitRunWithoutDependingOnDisplaySource() {
        let orbitRun = run(minutes: 75)
        let matching = ImportedActivity(
            id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate,
            kind: "endurance", activity: "Outdoor Run", durationMinutes: 75,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-16T08:04:59Z",
            sourceBundleIdentifier: "com.apple.health.123456"
        )
        let foreign = ImportedActivity(
            id: UUID(), userID: UUID(), date: orbitRun.localDate,
            kind: "endurance", activity: "Outdoor Run", durationMinutes: 75,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-16T08:04:59Z",
            sourceBundleIdentifier: "com.apple.health.123456"
        )
        let hidden = ImportedActivity(
            id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate,
            kind: "endurance", activity: "Outdoor Run", durationMinutes: 75,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-16T08:04:59Z",
            sourceBundleIdentifier: "com.apple.health.123456",
            hiddenAt: "2026-08-16T12:00:00Z"
        )
        let unrelated = ImportedActivity(
            id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate,
            kind: "endurance", activity: "Outdoor Run", durationMinutes: 75,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-16T12:00:00Z",
            sourceBundleIdentifier: "com.apple.health.123456"
        )
        let atFiveMinuteBoundary = ImportedActivity(
            id: UUID(), userID: orbitRun.userID, date: orbitRun.localDate,
            kind: "endurance", activity: "Outdoor Run", durationMinutes: 75,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: "2026-08-16T08:05:00Z",
            sourceBundleIdentifier: "com.apple.health.123456"
        )

        XCTAssertTrue(OrbitIntegrations.healthWorkoutRepresentsRun(
            [matching, foreign, hidden],
            ownerID: orbitRun.userID,
            localDate: orbitRun.localDate,
            durationMinutes: 75,
            startedAt: orbitRun.startedAt
        ))
        XCTAssertFalse(OrbitIntegrations.healthWorkoutRepresentsRun(
            [foreign, hidden, unrelated, atFiveMinuteBoundary],
            ownerID: orbitRun.userID,
            localDate: orbitRun.localDate,
            durationMinutes: 75,
            startedAt: orbitRun.startedAt
        ))
    }

    func testAvatarContributionUsesOneRunAndReportsPacingDiscipline() {
        let contribution = OrbitIntegrations.avatarContribution(run: run(minutes: 75))

        XCTAssertEqual(contribution.enduranceMinutes, 75)
        XCTAssertEqual(contribution.lowerBodySignal, 1, accuracy: 0.001)
        XCTAssertGreaterThan(contribution.pacingDisciplineSignal, 0.9)
        XCTAssertTrue(contribution.explanation.contains("one authoritative endurance record"))
    }

    func testStableIDMatchesBrowserClientAlgorithm() {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let result = APEXStableID.scopedUUID(
            namespace: "daily-log",
            date: "2026-08-16",
            userID: userID
        )

        XCTAssertEqual(result.uuidString.lowercased(), "9ff06421-9493-466d-a0ea-2048b31d7814")
    }

    private func run(minutes: Double) -> OrbitRunRecord {
        let userID = UUID()
        return OrbitRunRecord(
            id: UUID(), userID: userID, clientIdempotencyKey: UUID().uuidString,
            localDate: "2026-08-16", startedAt: "2026-08-16T08:00:00Z", endedAt: "2026-08-16T10:00:00Z",
            mission: "aerobic_base", routeID: nil, campaignSessionID: nil, shoeID: nil,
            samples: [], pauses: [], manualLapsM: [],
            metrics: [
                "moving_s": .number(minutes * 60),
                "distance_m": .number(minutes * 125),
                "splits": .array([
                    .object(["distance_m": .number(1_000), "pace_sec_km": .number(480)]),
                    .object(["distance_m": .number(1_000), "pace_sec_km": .number(485)]),
                    .object(["distance_m": .number(1_000), "pace_sec_km": .number(478)])
                ])
            ],
            checkIn: ["discomfort": .string("none")], nutritionAdjustmentAppliedAt: nil,
            status: "completed", createdAt: "2026-08-16T08:00:00Z", updatedAt: "2026-08-16T10:00:00Z"
        )
    }

    private func food(id: UUID, name: String, carbs: Double) -> Food {
        Food(
            id: id.uuidString.lowercased(), ownerUserID: nil, name: name, namesI18n: [:],
            brand: nil, barcode: nil, source: "test", providerProductID: nil,
            externalImageURL: nil, packageQuantity: nil, nutritionBasis: "per_100g",
            preparationState: "ready", kcal100: 380, protein100: 12, carbs100: carbs,
            fat100: 7, fibre100: nil, sugar100: nil, saturatedFat100: nil, salt100: nil,
            servingAmount: nil, servingUnit: nil, servingGramsOrML: nil,
            pieceGramsOrML: nil, confidence: "verified"
        )
    }

    private func preference(userID: UUID, foodID: UUID, favourite: Bool, useCount: Int) -> FoodPreference {
        FoodPreference(
            id: UUID(), userID: userID, foodID: foodID, personalName: nil,
            aliases: [], favourite: favourite, usualAmount: nil, usualUnit: nil,
            usageCount: useCount, lastUsedAt: nil, hidden: false
        )
    }

    private func activity(id: UUID, userID: UUID, date: String, typeID: String, source: String) -> ActivityLog {
        ActivityLog(
            id: id, userID: userID, date: date, typeID: typeID, quantity: 1,
            durationMinutes: 60, distanceKM: typeID == "jog-run" ? 8 : nil,
            watchKcal: typeID == "watch-kcal" ? 500 : nil, computedKcal: 400,
            source: source, reconciled: false,
            createdAt: "2026-08-16T08:00:00Z", updatedAt: "2026-08-16T09:00:00Z"
        )
    }
}
