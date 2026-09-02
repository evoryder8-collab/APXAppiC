/*
 * Golden parity: the Swift MealMemory ranking must reproduce the web's
 * rankMealHistoryRecommendations exactly — same food order, and the same
 * remembered amount per food. Fixtures come from running the REAL
 * TypeScript engine (Tools/generate-meal-memory-fixtures.mts).
 */
import XCTest
@testable import APEX

private struct MemoryFixture: Decodable, Sendable {
    let foods: [Food]
    let meals: [LoggedMeal]
    let entries: [LoggedFoodEntry]
    let cases: [MemoryCase]
}

private struct MemoryCase: Decodable, Sendable {
    let name: String
    let context: MemoryContext
    let expected: MemoryExpectation
}

private struct MemoryContext: Decodable, Sendable {
    let date: String
    let slot: String
    let memoryMode: String
    let blockId: String?
    let targetTime: String?
}

private struct MemoryExpectation: Decodable, Sendable {
    let meals: [String]
    let foods: [String]
    let selections: [MemorySelection]
}

private struct MemorySelection: Decodable, Sendable {
    let foodId: String
    let quantity: Double
    let unit: String
}

private enum DeferredFoodSearchFailure: Error {
    case offline
}

private actor DeferredFoodSearchProvider {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var response: CheckedContinuation<FoodLookupEnvelope, Error>?

    func search(_ query: String) async throws -> FoodLookupEnvelope {
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            response = continuation
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func succeed(with envelope: FoodLookupEnvelope) {
        response?.resume(returning: envelope)
        response = nil
    }

    func fail() {
        response?.resume(throwing: DeferredFoodSearchFailure.offline)
        response = nil
    }
}

final class MealMemoryParityTests: XCTestCase {
    private static let fixture: MemoryFixture = {
        guard let url = Bundle(for: MealMemoryParityTests.self)
            .url(forResource: "meal-memory-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("meal-memory-parity.json missing from test bundle")
        }
        return try! JSONDecoder().decode(MemoryFixture.self, from: data)
    }()

    func testRankingMatchesTheWebEngine() {
        for scenario in Self.fixture.cases {
            let result = MealMemory.rank(
                context: MealMemory.Context(
                    date: scenario.context.date,
                    slot: scenario.context.slot,
                    mode: MealMemory.normalizeMode(.string(scenario.context.memoryMode)),
                    blockID: scenario.context.blockId,
                    targetTime: scenario.context.targetTime
                ),
                meals: Self.fixture.meals,
                entries: Self.fixture.entries,
                foods: Self.fixture.foods,
                foodLimit: 12
            )
            XCTAssertEqual(
                result.meals.map { $0.id.uuidString.lowercased() },
                scenario.expected.meals.map { $0.lowercased() },
                "meal order drifted in \(scenario.name)"
            )
            XCTAssertEqual(
                result.foods.map { $0.id.lowercased() },
                scenario.expected.foods.map { $0.lowercased() },
                "food order drifted in \(scenario.name)"
            )
            XCTAssertEqual(
                result.selections.map { "\($0.foodID.lowercased())|\($0.quantity)|\($0.unit)" },
                scenario.expected.selections.map { "\($0.foodId.lowercased())|\($0.quantity)|\($0.unit)" },
                "remembered amounts drifted in \(scenario.name)"
            )
        }
    }

    /// The whole point of the request: a food reopens at the grams last logged.
    func testRememberedAmountBeatsTheHundredGramDefault() {
        guard let scenario = Self.fixture.cases.first(where: { $0.name == "daily-breakfast" }),
              let oats = Self.fixture.foods.first(where: { $0.name == "Rolled oats" }) else {
            return XCTFail("fixture missing the daily breakfast scenario")
        }
        let result = MealMemory.rank(
            context: MealMemory.Context(
                date: scenario.context.date,
                slot: scenario.context.slot,
                mode: .daily,
                blockID: scenario.context.blockId,
                targetTime: scenario.context.targetTime
            ),
            meals: Self.fixture.meals,
            entries: Self.fixture.entries,
            foods: Self.fixture.foods
        )
        let remembered = result.selection(for: oats.id)
        XCTAssertEqual(remembered?.quantity, 120)
        let start = FoodPortionMath.defaultSelection(oats, preference: nil, remembered: remembered)
        XCTAssertEqual(start.quantity, 120, "the composer must open at the last confirmed amount")
        XCTAssertEqual(start.unit, .grams)
        /* Without history it falls back to the catalogue default, as before. */
        XCTAssertEqual(FoodPortionMath.defaultSelection(oats, preference: nil).quantity, 100)
    }

    /// Weekly memory prioritises the same weekday; daily prioritises recency.
    func testWeeklyModePrefersTheSameWeekday() {
        guard let oats = Self.fixture.foods.first(where: { $0.name == "Rolled oats" }) else {
            return XCTFail("fixture missing oats")
        }
        func amount(on date: String, mode: MealMemory.Mode) -> Double? {
            MealMemory.rank(
                context: MealMemory.Context(date: date, slot: "breakfast", mode: mode, blockID: "breakfast", targetTime: "07:00"),
                meals: Self.fixture.meals,
                entries: Self.fixture.entries,
                foods: Self.fixture.foods
            ).selection(for: oats.id)?.quantity
        }
        // 2026-06-07 is a Sunday, and Sunday breakfasts were 120 g.
        XCTAssertEqual(amount(on: "2026-06-07", mode: .weekly), 120)
        // 2026-06-01 is a Monday, whose only breakfast was 80 g.
        XCTAssertEqual(amount(on: "2026-06-01", mode: .weekly), 80)
        // Daily ignores the weekday and takes the most recent confirmation.
        XCTAssertEqual(amount(on: "2026-06-01", mode: .daily), 120)
    }

    func testModeNormalizationMatchesTheWeb() {
        XCTAssertEqual(MealMemory.normalizeMode(.string("weekly")), .weekly)
        XCTAssertEqual(MealMemory.normalizeMode(.string("daily")), .daily)
        XCTAssertEqual(MealMemory.normalizeMode(.string("nonsense")), .daily)
        XCTAssertEqual(MealMemory.normalizeMode(nil), .daily)
        XCTAssertEqual(MealMemory.normalizeMode(.null), .daily)
    }

    func testStandaloneRecentsReconstructYesterdayScannedFoodMissingFromCatalogue() throws {
        let meal = try XCTUnwrap(Self.fixture.meals.max { $0.loggedAt < $1.loggedAt })
        let entry = try XCTUnwrap(Self.fixture.entries.first { $0.mealID == meal.id && $0.foodID != nil })
        let scannedID = try XCTUnwrap(entry.foodID)
        let catalogueWithoutScan = Self.fixture.foods.filter {
            $0.id.lowercased() != scannedID.uuidString.lowercased()
        }

        let recents = MealMemory.recentFoods(
            foods: catalogueWithoutScan,
            preferences: [],
            meals: [meal],
            entries: [entry],
            userID: meal.userID
        )

        XCTAssertEqual(recents.first?.id.lowercased(), scannedID.uuidString.lowercased())
        XCTAssertEqual(recents.first?.name, entry.snapshotName)

        let foreignAccountRecents = MealMemory.recentFoods(
            foods: catalogueWithoutScan,
            preferences: [],
            meals: [meal],
            entries: [entry],
            userID: UUID()
        )
        XCTAssertFalse(
            foreignAccountRecents.contains { $0.id.lowercased() == scannedID.uuidString.lowercased() },
            "another account's scanned history must never leak into Food Memory"
        )
    }

    func testConfirmedScannedAmountCreatesAccountScopedRecentPreference() throws {
        let food = try XCTUnwrap(Self.fixture.foods.first { UUID(uuidString: $0.id) != nil })
        let userID = UUID()
        let usedAt = "2026-08-24T12:03:09.000Z"
        let item = MealComposerItem(food: food, quantity: 27, unit: "g")

        let updates = MealMemory.usagePreferenceUpdates(
            current: [],
            items: [item],
            userID: userID,
            usedAt: usedAt
        )

        let preference = try XCTUnwrap(updates.first)
        XCTAssertEqual(preference.userID, userID)
        XCTAssertEqual(preference.foodID.uuidString.lowercased(), food.id.lowercased())
        XCTAssertEqual(preference.usageCount, 1)
        XCTAssertEqual(preference.usualAmount, 27)
        XCTAssertEqual(preference.usualUnit, "g")
        XCTAssertEqual(preference.lastUsedAt, usedAt)
    }

    func testFoodMemorySearchMatchesLocalizedNamesAndPrivateAliasesOffline() throws {
        let food = try XCTUnwrap(Self.fixture.foods.first { UUID(uuidString: $0.id) != nil })
        var localizedFood = food
        localizedFood.namesI18n["de"] = "Haus-Burger"
        localizedFood.namesI18n["de-CH"] = "Haus-Burger Schweiz"
        let userID = try XCTUnwrap(localizedFood.ownerUserID)
        let preference = FoodPreference(
            id: UUID(),
            userID: userID,
            foodID: try XCTUnwrap(UUID(uuidString: food.id)),
            personalName: "Mein Abendessen",
            aliases: ["cheeseburger royal", "after gym burger"],
            favourite: false,
            usualAmount: nil,
            usualUnit: nil,
            usageCount: 1,
            lastUsedAt: nil,
            hidden: false
        )

        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "haus burger",
                foods: [localizedFood],
                preferences: [preference],
                userID: userID
            ).map(\.id),
            [localizedFood.id],
            "localized names must remain searchable without the provider"
        )
        XCTAssertEqual(localizedFood.localizedName(.german), "Haus-Burger")
        XCTAssertEqual(localizedFood.localizedName(.swissGerman), "Haus-Burger Schweiz")
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "Royal",
                foods: [localizedFood],
                preferences: [preference],
                userID: userID
            ).map(\.id),
            [localizedFood.id],
            "a user's private aliases must remain searchable without the provider"
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "abendessen mein",
                foods: [localizedFood],
                preferences: [preference],
                userID: userID
            ).map(\.id),
            [localizedFood.id],
            "token order and the personal name should not make a saved food disappear"
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "hausburger",
                foods: [localizedFood],
                preferences: [preference],
                userID: userID
            ).map(\.id),
            [localizedFood.id],
            "joined words must still find a saved food"
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "cheeseburgerrroyal",
                foods: [localizedFood],
                preferences: [preference],
                userID: userID
            ).map(\.id),
            [localizedFood.id],
            "a small typo in a joined alias must still find a saved food"
        )
    }

    func testFoodMemorySearchRanksPureOilAndRepairsSplitMisspellings() throws {
        var vegetableOil = try XCTUnwrap(Self.fixture.foods.first)
        vegetableOil.name = "Vegetable oil"
        vegetableOil.namesI18n = ["en": "Vegetable oil"]
        vegetableOil.brand = nil
        vegetableOil.protein100 = 0
        vegetableOil.carbs100 = 0
        vegetableOil.fat100 = 100

        var oilMargarine = try XCTUnwrap(Self.fixture.foods.dropFirst().first)
        oilMargarine.name = "Oil margarine"
        oilMargarine.namesI18n = ["en": "Oil margarine"]
        oilMargarine.brand = nil
        oilMargarine.protein100 = 0.2
        oilMargarine.carbs100 = 0.5
        oilMargarine.fat100 = 70

        var extraVirgin = try XCTUnwrap(Self.fixture.foods.dropFirst(2).first)
        extraVirgin.name = "Extra virgin olive oil"
        extraVirgin.namesI18n = ["en": "Extra virgin olive oil"]
        extraVirgin.brand = nil
        extraVirgin.protein100 = 0
        extraVirgin.carbs100 = 0
        extraVirgin.fat100 = 100

        var beefExtract = vegetableOil
        beefExtract.name = "Beef extract"
        beefExtract.namesI18n = ["en": "Beef extract"]
        beefExtract.brand = nil

        var extraLeanBeef = oilMargarine
        extraLeanBeef.name = "Beef, mince, raw, extra lean"
        extraLeanBeef.namesI18n = ["en": "Beef, mince, raw, extra lean"]
        extraLeanBeef.brand = nil

        let userID = try XCTUnwrap(extraVirgin.ownerUserID)

        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "oil",
                foods: [oilMargarine, vegetableOil, extraVirgin],
                preferences: [],
                userID: userID
            ).first?.id,
            extraVirgin.id,
            "extra-virgin olive oil should lead a broad oil query"
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "ext;ra vlrgn",
                foods: [beefExtract, extraLeanBeef, extraVirgin],
                preferences: [],
                userID: userID
            ).map(\.id),
            [extraVirgin.id],
            "split punctuation and two-edit misspellings must resolve without weak matches"
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "extra virgin",
                foods: [extraVirgin, beefExtract, extraLeanBeef],
                preferences: [],
                userID: userID
            ).map(\.id),
            [extraVirgin.id],
            "every meaningful query token must match"
        )
    }

    func testFoodMemorySearchHonoursHiddenPreference() throws {
        let food = try XCTUnwrap(Self.fixture.foods.first { UUID(uuidString: $0.id) != nil })
        let userID = try XCTUnwrap(food.ownerUserID)
        let preference = FoodPreference(
            id: UUID(), userID: userID,
            foodID: try XCTUnwrap(UUID(uuidString: food.id)),
            personalName: nil, aliases: ["burger"], favourite: false,
            usualAmount: nil, usualUnit: nil, usageCount: 0,
            lastUsedAt: nil, hidden: true
        )

        XCTAssertTrue(
            MealMemory.searchFoods(
                query: "burger",
                foods: [food],
                preferences: [preference],
                userID: userID
            ).isEmpty
        )
    }

    func testFoodMemorySearchNeverReturnsAnotherAccountsPrivateFood() throws {
        let ownerA = UUID()
        let ownerB = UUID()
        func ownedCopy(_ food: Food, ownerID: UUID?, name: String) -> Food {
            Food(
                id: UUID().uuidString, ownerUserID: ownerID, name: name,
                namesI18n: [:], brand: food.brand, barcode: food.barcode,
                source: food.source, providerProductID: food.providerProductID,
                externalImageURL: food.externalImageURL, packageQuantity: food.packageQuantity,
                nutritionBasis: food.nutritionBasis, preparationState: food.preparationState,
                kcal100: food.kcal100, protein100: food.protein100,
                carbs100: food.carbs100, fat100: food.fat100,
                fibre100: food.fibre100, sugar100: food.sugar100,
                saturatedFat100: food.saturatedFat100, salt100: food.salt100,
                waterML100: food.waterML100, waterBasis: food.waterBasis,
                waterSourceID: food.waterSourceID, servingAmount: food.servingAmount,
                servingUnit: food.servingUnit, servingGramsOrML: food.servingGramsOrML,
                pieceGramsOrML: food.pieceGramsOrML, confidence: food.confidence,
                nutrientEvidence: food.nutrientEvidence
            )
        }
        let privateA = ownedCopy(
            try XCTUnwrap(Self.fixture.foods.first),
            ownerID: ownerA,
            name: "Boundary berry private A"
        )
        let privateB = ownedCopy(
            try XCTUnwrap(Self.fixture.foods.dropFirst().first),
            ownerID: ownerB,
            name: "Boundary berry private B"
        )
        let global = ownedCopy(
            try XCTUnwrap(Self.fixture.foods.dropFirst(2).first),
            ownerID: nil,
            name: "Boundary berry global"
        )

        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "boundary berry",
                foods: [privateA, privateB, global],
                preferences: [],
                userID: ownerB
            ).map(\.id).sorted(),
            [privateB.id, global.id].sorted()
        )
        XCTAssertEqual(
            MealMemory.searchFoods(
                query: "boundary berry",
                foods: [privateA, privateB, global],
                preferences: [],
                userID: nil
            ).map(\.id),
            [global.id],
            "an unauthenticated search may only expose global catalogue rows"
        )
    }

    @MainActor
    func testAppSessionFoodSearchPrefersExactServerEvidenceOverBundledFallback() async throws {
        let ownerID = UUID()
        let dashboard = APEXDebugFixture.dashboard(userID: ownerID)
        let localIndex = try XCTUnwrap(dashboard.foods.firstIndex {
            $0.providerProductID == "apex-curated:swiss-retail-strawberries-fresh-reference"
        })
        let serverEvidence = NutrientEvidenceObservation(
            nutrientCode: "VITC",
            name: "Server vitamin C",
            valuePer100: 61,
            unit: "mg",
            observationStatus: .reported,
            originalValueText: "61",
            derivationMethod: nil,
            sourceKey: "server-official",
            sourceReference: "server:strawberry"
        )
        var serverFoodDraft = dashboard.foods[localIndex]
        serverFoodDraft.name = "Exact server strawberry"
        serverFoodDraft.nutrientEvidence = [serverEvidence]
        let serverFood = serverFoodDraft
        let session = AppSession(foodSearchProvider: { _ in
            FoodLookupEnvelope(
                state: "available",
                source: "test",
                food: nil,
                results: [serverFood],
                message: nil
            )
        })
        session.data = dashboard

        let results = try await session.searchFoods(query: "strawberries")
        let result = try XCTUnwrap(results.first {
            $0.id == dashboard.foods[localIndex].id
        })

        XCTAssertEqual(
            result.nutrientEvidence,
            [serverEvidence],
            "an exact compatible server correction must outrank the bundled fallback"
        )
    }

    @MainActor
    func testAppSessionFoodSearchPreservesExplicitLocalEvidenceAheadOfServerAndBundle() async throws {
        let ownerID = UUID()
        var dashboard = APEXDebugFixture.dashboard(userID: ownerID)
        let localIndex = try XCTUnwrap(dashboard.foods.firstIndex {
            $0.providerProductID == "apex-curated:swiss-retail-strawberries-fresh-reference"
        })
        let explicitEvidence = NutrientEvidenceObservation(
            nutrientCode: "VITC",
            name: "Explicit vitamin C",
            valuePer100: 60,
            unit: "mg",
            observationStatus: .reported,
            originalValueText: "60",
            derivationMethod: nil,
            sourceKey: "apex-curation",
            sourceReference: "explicit:strawberry"
        )
        let serverEvidence = NutrientEvidenceObservation(
            nutrientCode: "VITC",
            name: "Server vitamin C",
            valuePer100: 61,
            unit: "mg",
            observationStatus: .reported,
            originalValueText: "61",
            derivationMethod: nil,
            sourceKey: "server-official",
            sourceReference: "server:strawberry"
        )
        dashboard.foods[localIndex].nutrientEvidence = [explicitEvidence]
        var serverFoodDraft = dashboard.foods[localIndex]
        serverFoodDraft.name = "Exact server strawberry"
        serverFoodDraft.nutrientEvidence = [serverEvidence]
        let serverFood = serverFoodDraft
        let session = AppSession(foodSearchProvider: { _ in
            FoodLookupEnvelope(
                state: "available",
                source: "test",
                food: nil,
                results: [serverFood],
                message: nil
            )
        })
        session.data = dashboard

        let results = try await session.searchFoods(query: "strawberries")
        let result = try XCTUnwrap(results.first {
            $0.id == dashboard.foods[localIndex].id
        })

        XCTAssertEqual(
            result.nutrientEvidence,
            [explicitEvidence],
            "authored local evidence must remain ahead of exact server and bundled evidence"
        )
    }

    @MainActor
    func testInFlightRemoteFoodSearchRejectsSuccessAfterTheAccountChanges() async throws {
        let provider = DeferredFoodSearchProvider()
        let ownerA = UUID()
        let ownerB = UUID()
        let session = AppSession(foodSearchProvider: { query in
            try await provider.search(query)
        })
        session.data = APEXDebugFixture.dashboard(userID: ownerA)

        let search = Task { try await session.searchFoods(query: "strawberries") }
        await provider.waitUntilStarted()
        session.data = APEXDebugFixture.dashboard(userID: ownerB)
        await provider.succeed(with: FoodLookupEnvelope(
            state: "available",
            source: "test",
            food: nil,
            results: [],
            message: nil
        ))

        do {
            _ = try await search.value
            XCTFail("a completion captured for account A must never render in account B")
        } catch is CancellationError {
            // Expected: the caller quietly discards a stale search result.
        }
    }

    @MainActor
    func testInFlightRemoteFoodSearchRejectsOfflineFallbackAfterTheAccountChanges() async throws {
        let provider = DeferredFoodSearchProvider()
        let ownerA = UUID()
        let ownerB = UUID()
        let session = AppSession(foodSearchProvider: { query in
            try await provider.search(query)
        })
        session.data = APEXDebugFixture.dashboard(userID: ownerA)

        let search = Task { try await session.searchFoods(query: "strawberries") }
        await provider.waitUntilStarted()
        session.data = APEXDebugFixture.dashboard(userID: ownerB)
        await provider.fail()

        do {
            _ = try await search.value
            XCTFail("account A's cached fallback must never render in account B")
        } catch is CancellationError {
            // Expected: even an offline fallback is scoped to the captured owner.
        }
    }
}
