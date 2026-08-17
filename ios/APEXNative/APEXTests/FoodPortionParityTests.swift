/*
 * The amount configurator must produce the same numbers as the web
 * composer. Cases mirror src/lib/food.ts (equivalentAmount,
 * calculatePortion, availableFoodUnits, beginFoodSelection).
 */
import XCTest
@testable import APEX

final class FoodPortionParityTests: XCTestCase {
    private func food(
        basis: String = "per_100g",
        kcal: Double? = 364,
        protein: Double? = 86,
        carbs: Double? = 1.2,
        fat: Double? = 1.2,
        serving: Double? = nil,
        servingUnit: String? = nil,
        piece: Double? = nil,
        source: String = "private"
    ) -> Food {
        Food(
            id: UUID().uuidString.lowercased(),
            ownerUserID: nil,
            name: "Whey protein isolate, unflavoured",
            namesI18n: [:],
            brand: "Lee-Sport",
            barcode: nil,
            source: source,
            providerProductID: nil,
            externalImageURL: nil,
            packageQuantity: nil,
            nutritionBasis: basis,
            preparationState: "as_sold",
            kcal100: kcal,
            protein100: protein,
            carbs100: carbs,
            fat100: fat,
            fibre100: nil,
            sugar100: nil,
            saturatedFat100: nil,
            salt100: nil,
            servingAmount: nil,
            servingUnit: servingUnit,
            servingGramsOrML: serving,
            pieceGramsOrML: piece,
            confidence: "curated"
        )
    }

    /* The screenshot case: 20 g of 364 kcal/100 g whey = 73 kcal, P 17.2 */
    func testMatchesWebComposerScreenshotNumbers() throws {
        let portion = try XCTUnwrap(
            FoodPortionMath.portion(food(), quantity: 20, unit: .grams))
        XCTAssertEqual(portion.kcal, 73)
        XCTAssertEqual(portion.proteinG, 17.2, accuracy: 1e-9)
        XCTAssertEqual(portion.carbsG, 0.2, accuracy: 1e-9)
        XCTAssertEqual(portion.fatG, 0.2, accuracy: 1e-9)
        XCTAssertEqual(portion.equivalentAmount, 20, accuracy: 1e-9)
    }

    func testUnitAvailabilityMirrorsWeb() {
        XCTAssertEqual(FoodPortionMath.availableUnits(food()), [.grams])
        XCTAssertEqual(
            FoodPortionMath.availableUnits(food(serving: 30, piece: 50)),
            [.grams, .serving, .piece])
        XCTAssertEqual(
            FoodPortionMath.availableUnits(food(basis: "per_100ml")),
            [.millilitres])
        /* zero or negative equivalents never become selectable units */
        XCTAssertEqual(FoodPortionMath.availableUnits(food(serving: 0)), [.grams])
    }

    func testEquivalentAmountRespectsBasisAndMultipliers() {
        let grams = food()
        XCTAssertNil(FoodPortionMath.equivalentAmount(grams, quantity: 100, unit: .millilitres))
        XCTAssertNil(FoodPortionMath.equivalentAmount(grams, quantity: 0, unit: .grams))
        let withServings = food(serving: 30, piece: 55)
        XCTAssertEqual(
            FoodPortionMath.equivalentAmount(withServings, quantity: 2, unit: .serving), 60)
        XCTAssertEqual(
            FoodPortionMath.equivalentAmount(withServings, quantity: 3, unit: .piece), 165)
    }

    func testIncompleteNutritionYieldsNoPortion() {
        XCTAssertNil(FoodPortionMath.portion(food(protein: nil), quantity: 100, unit: .grams))
    }

    /* Parity: beginFoodSelection. A real piece opens as one piece; provider
       "serving_quantity" weights stay on the basis unit. */
    func testDefaultSelectionRules() {
        let plain = FoodPortionMath.defaultSelection(food(), preference: nil)
        XCTAssertEqual(plain.quantity, 100)
        XCTAssertEqual(plain.unit, .grams)

        let piece = FoodPortionMath.defaultSelection(food(piece: 55), preference: nil)
        XCTAssertEqual(piece.quantity, 1)
        XCTAssertEqual(piece.unit, .piece)

        let declaredServing = FoodPortionMath.defaultSelection(
            food(serving: 30, servingUnit: "serving"), preference: nil)
        XCTAssertEqual(declaredServing.quantity, 1)
        XCTAssertEqual(declaredServing.unit, .serving)

        let providerWeight = FoodPortionMath.defaultSelection(
            food(serving: 30, servingUnit: "g"), preference: nil)
        XCTAssertEqual(providerWeight.quantity, 100)
        XCTAssertEqual(providerWeight.unit, .grams)
    }

    func testProvenanceLabelsMatchWeb() {
        XCTAssertEqual(FoodPortionMath.provenanceLabel(food(source: "private")), "Your private food")
        XCTAssertEqual(
            FoodPortionMath.provenanceLabel(food(source: "open_food_facts")),
            "Open Food Facts community record. Check the package label.")
    }
}
