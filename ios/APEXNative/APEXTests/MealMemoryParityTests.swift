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
}
