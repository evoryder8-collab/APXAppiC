import XCTest
@testable import APEX

final class MealComposerTests: XCTestCase {
    func testDraftTotalsFollowEditedQuantities() {
        let oats = food(
            name: "Oats",
            kcal100: 370,
            protein100: 13,
            carbs100: 60,
            fat100: 7
        )
        let whey = food(
            name: "Whey isolate",
            kcal100: 360,
            protein100: 86,
            carbs100: 2,
            fat100: 1
        )
        var oatItem = MealComposerItem(food: oats, quantity: 60, unit: "g")
        let wheyItem = MealComposerItem(food: whey, quantity: 30, unit: "g")

        oatItem.setQuantity(80, food: oats)
        let draft = MealComposerDraft(
            id: UUID(),
            localDate: "2026-08-17",
            mealSlot: "breakfast",
            displayName: "Breakfast",
            finishedAt: Date(timeIntervalSince1970: 0),
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            replaceMealID: nil,
            loggedAs: "actual",
            items: [oatItem, wheyItem]
        )

        XCTAssertEqual(draft.totals.kcal, 404, accuracy: 0.001)
        XCTAssertEqual(draft.totals.proteinG, 36.2, accuracy: 0.001)
        XCTAssertEqual(draft.totals.carbsG, 48.6, accuracy: 0.001)
        XCTAssertEqual(draft.totals.fatG, 5.9, accuracy: 0.001)
    }

    func testPieceAndServingUnitsUseFoodEquivalents() {
        var egg = food(name: "Egg", kcal100: 143, protein100: 13, carbs100: 1, fat100: 10)
        egg.pieceGramsOrML = 50
        egg.servingGramsOrML = 100

        var item = MealComposerItem(food: egg, quantity: 2, unit: "piece")
        XCTAssertEqual(item.equivalentAmount, 100)
        XCTAssertEqual(item.nutrients.kcal, 143, accuracy: 0.001)

        item.setUnit("serving", food: egg)
        XCTAssertEqual(item.equivalentAmount, 200)
        XCTAssertEqual(item.nutrients.proteinG, 26, accuracy: 0.001)
    }

    func testPresetPayloadKeepsSupabaseRPCContract() throws {
        let foodID = UUID()
        let payload = MealPresetRPCPayload(
            pPreset: MealPresetRequest(
                id: UUID(),
                name: "Fast breakfast",
                mealSlot: "breakfast",
                sourcePlannedMealID: nil,
                archived: false
            ),
            pItems: [
                MealPresetItemRequest(
                    id: UUID(),
                    foodID: foodID,
                    sortOrder: 0,
                    quantity: 60,
                    unit: "g",
                    optional: false,
                    locked: true,
                    adjustable: false,
                    minimumAmount: nil,
                    maximumAmount: nil,
                    stepAmount: nil,
                    adjustmentRole: "fixed"
                )
            ],
            pExpectedVersion: 3
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertNotNil(object["p_preset"])
        XCTAssertNotNil(object["p_items"])
        XCTAssertEqual(object["p_expected_version"] as? Int, 3)

        let items = try XCTUnwrap(object["p_items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["food_id"] as? String, foodID.uuidString)
        XCTAssertEqual(items.first?["adjustment_role"] as? String, "fixed")
    }

    private func food(
        name: String,
        kcal100: Double,
        protein100: Double,
        carbs100: Double,
        fat100: Double
    ) -> Food {
        Food(
            id: UUID().uuidString,
            ownerUserID: nil,
            name: name,
            namesI18n: [:],
            brand: nil,
            barcode: nil,
            source: "test",
            providerProductID: nil,
            externalImageURL: nil,
            packageQuantity: nil,
            nutritionBasis: "per_100g",
            preparationState: "as_sold",
            kcal100: kcal100,
            protein100: protein100,
            carbs100: carbs100,
            fat100: fat100,
            fibre100: nil,
            sugar100: nil,
            saturatedFat100: nil,
            salt100: nil,
            servingAmount: nil,
            servingUnit: nil,
            servingGramsOrML: nil,
            pieceGramsOrML: nil,
            confidence: "verified"
        )
    }
}
