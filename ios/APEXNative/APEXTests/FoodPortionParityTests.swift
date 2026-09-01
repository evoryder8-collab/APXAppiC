/*
 * The amount configurator must produce the same numbers as the web
 * composer. Cases mirror src/lib/food.ts (equivalentAmount,
 * calculatePortion, availableFoodUnits, beginFoodSelection).
 */
import XCTest
@testable import APEX

final class FoodPortionParityTests: XCTestCase {
    func testFoundFoodMacroPaletteMaintainsAAAContrast() {
        XCTAssertGreaterThanOrEqual(
            BarcodeFoundFoodPalette.statsContrastRatio,
            7.0,
            "Scanned-food macro facts must remain immediately readable over the camera surface"
        )
    }

    func testBarcodeCameraStopsAsSoonAsCaptureLeavesScanning() {
        let cases: [(BarcodeScannerPhase, Bool, Bool, Bool, Bool, Bool)] = [
            (.scanning, false, false, false, false, false),
            (.lookingUp, true, true, false, false, false),
            (.foodFound, true, false, true, false, false),
            (.message, true, false, false, true, false),
            (.choosingPortion, true, false, true, false, true),
        ]
        for (expected, codeCaptured, lookingUp, hasFood, hasMessage, choosingPortion) in cases {
            let phase = BarcodeScannerPhase.resolve(
                codeCaptured: codeCaptured,
                lookingUp: lookingUp,
                hasFood: hasFood,
                hasMessage: hasMessage,
                choosingPortion: choosingPortion
            )
            XCTAssertEqual(phase, expected)
            XCTAssertEqual(phase.shouldRunCamera, expected == .scanning)
        }
    }

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

    func testPortionUnitLabelsExposeTheirMeasuredEquivalent() {
        let portioned = food(serving: 30, piece: 55.5)
        XCTAssertEqual(
            FoodPortionMath.unitLabel(portioned, unit: .serving, localizedName: "Serving"),
            "Serving (30 g)"
        )
        XCTAssertEqual(
            FoodPortionMath.unitLabel(portioned, unit: .piece, localizedName: "Piece"),
            "Piece (55.5 g)"
        )
        XCTAssertEqual(
            FoodPortionMath.unitLabel(portioned, unit: .grams, localizedName: "g"),
            "g"
        )
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
        XCTAssertEqual(piece.quantity, 100)
        XCTAssertEqual(piece.unit, .grams)

        let declaredServing = FoodPortionMath.defaultSelection(
            food(serving: 30, servingUnit: "serving"), preference: nil)
        XCTAssertEqual(declaredServing.quantity, 100)
        XCTAssertEqual(declaredServing.unit, .grams)

        let rememberedServing = FoodPortionMath.defaultSelection(
            food(serving: 30, servingUnit: "serving"),
            preference: nil,
            remembered: MealMemory.Selection(foodID: "food", quantity: 2, unit: "serving")
        )
        XCTAssertEqual(rememberedServing.quantity, 2)
        XCTAssertEqual(rememberedServing.unit, .serving)

        let providerWeight = FoodPortionMath.defaultSelection(
            food(serving: 30, servingUnit: "g"), preference: nil)
        XCTAssertEqual(providerWeight.quantity, 100)
        XCTAssertEqual(providerWeight.unit, .grams)
    }

    func testProvenanceLabelsMatchWeb() {
        XCTAssertEqual(FoodPortionMath.provenanceLabel(food(source: "private")), "Your private food")
        XCTAssertEqual(
            FoodPortionMath.provenanceLabel(food(source: "open_food_facts")),
            "Check the package label.")
    }
}

final class NutrientEvidenceTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private func evidence(
        _ code: String,
        _ name: String,
        _ value: Double?,
        _ unit: String,
        _ status: NutrientObservationStatus = .measured
    ) -> NutrientEvidenceObservation {
        NutrientEvidenceObservation(
            nutrientCode: code,
            name: name,
            valuePer100: value,
            unit: unit,
            observationStatus: status,
            originalValueText: value.map { String($0) } ?? "tr",
            derivationMethod: nil,
            sourceKey: "fixture-source",
            sourceReference: "fixture-reference"
        )
    }

    func testMealComposerSnapshotsCoarseFactsBesideTraceEvidence() {
        let trace = evidence("VITA", "Vitamin A", nil, "µg", .trace)
        let food = Food(
            id: UUID().uuidString.lowercased(),
            ownerUserID: nil,
            name: "Evidence food",
            namesI18n: [:],
            brand: "Fixture",
            barcode: nil,
            source: "open_food_facts",
            providerProductID: "fixture:food",
            externalImageURL: nil,
            packageQuantity: nil,
            nutritionBasis: "per_100g",
            preparationState: "as_sold",
            kcal100: 120,
            protein100: 3,
            carbs100: 20,
            fat100: 2,
            fibre100: 4,
            sugar100: 6,
            saturatedFat100: 1,
            salt100: 0.4,
            waterML100: 60,
            servingAmount: nil,
            servingUnit: nil,
            servingGramsOrML: nil,
            pieceGramsOrML: nil,
            confidence: "provider_verified",
            nutrientEvidence: [trace]
        )

        let item = MealComposerItem(food: food, quantity: 100, unit: "g")
        XCTAssertEqual(item.nutrientEvidence.first { $0.nutrientCode == "SUGAR" }?.valuePer100, 6)
        XCTAssertEqual(item.nutrientEvidence.first { $0.nutrientCode == "FIBT" }?.valuePer100, 4)
        XCTAssertEqual(item.nutrientEvidence.first { $0.nutrientCode == "FASAT" }?.valuePer100, 1)
        XCTAssertEqual(item.nutrientEvidence.first { $0.nutrientCode == "VITA" }?.observationStatus, .trace)
    }

    func testObservedAveragesScalePortionsPreserveMissingAndIsolateOwners() {
        let other = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let mealA = UUID()
        let mealB = UUID()
        let emptyMeal = UUID()
        let foreignMeal = UUID()
        let summary = NutrientPatternEngine.summarize(
            meals: [
                .init(id: mealA, userID: owner, localDate: "2026-08-30"),
                .init(id: mealB, userID: owner, localDate: "2026-08-31"),
                .init(id: emptyMeal, userID: owner, localDate: "2026-08-31"),
                .init(id: foreignMeal, userID: other, localDate: "2026-08-31")
            ],
            entries: [
                .init(mealID: mealA, userID: owner, equivalentAmount: 200, evidence: [
                    evidence("VITC", "Vitamin C", 50, "mg"),
                    evidence("FE", "Iron", 2, "mg")
                ]),
                .init(mealID: mealB, userID: owner, equivalentAmount: 100, evidence: [
                    evidence("VITC", "Vitamin C", 50, "mg"),
                    evidence("VITA", "Vitamin A", nil, "µg", .trace)
                ]),
                .init(mealID: emptyMeal, userID: owner, equivalentAmount: 100, evidence: []),
                .init(mealID: foreignMeal, userID: other, equivalentAmount: 10_000, evidence: [
                    evidence("VITC", "Vitamin C", 500, "mg")
                ])
            ],
            ownerID: owner,
            anchorDate: "2026-08-31",
            period: .week
        )

        let vitaminC = summary.rows.first { $0.nutrientCode == "VITC" && $0.unit == "mg" }
        XCTAssertEqual(summary.calendarDays, 7)
        XCTAssertEqual(summary.observedDays, 2)
        XCTAssertEqual(summary.totalFoodEntries, 3)
        XCTAssertEqual(summary.evidenceFoodEntries, 2)
        XCTAssertEqual(summary.coverage, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(vitaminC?.total ?? -1, 150, accuracy: 0.000_001)
        XCTAssertEqual(vitaminC?.averagePerObservedDay ?? -1, 75, accuracy: 0.000_001)
        XCTAssertFalse(summary.rows.contains { $0.nutrientCode == "VITA" })
    }

    func testWindowUsesLocalDatesAndNeverMergesUnits() {
        XCTAssertEqual(
            NutrientPatternEngine.window(anchorDate: "2026-09-01", period: .week),
            .init(start: "2026-08-26", end: "2026-09-01", calendarDays: 7)
        )
        XCTAssertEqual(
            NutrientPatternEngine.window(anchorDate: "2026-09-15", period: .month),
            .init(start: "2026-09-01", end: "2026-09-15", calendarDays: 15)
        )

        let mealID = UUID()
        let result = NutrientPatternEngine.summarize(
            meals: [.init(id: mealID, userID: owner, localDate: "2026-09-01")],
            entries: [.init(mealID: mealID, userID: owner, equivalentAmount: 100, evidence: [
                evidence("VITD", "Vitamin D", 10, "µg"),
                evidence("VITD", "Vitamin D", 2, "IU")
            ])],
            ownerID: owner,
            anchorDate: "2026-09-01",
            period: .day
        )
        XCTAssertEqual(result.rows.filter { $0.nutrientCode == "VITD" }.count, 2)
    }
}
