import XCTest
@testable import APEX

final class FoodEvidenceEnrichmentTests: XCTestCase {
    private let foodID = "10000000-0000-4000-8000-000000000046"
    private let providerID = "apex-curated:usda-fdc-167762"

    private var vitaminC: NutrientEvidenceObservation {
        NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Vitamin C", valuePer100: 58.8,
            unit: "mg", observationStatus: .measured,
            originalValueText: "58.8 mg/100 g", derivationMethod: nil,
            sourceKey: "usda-fdc", sourceReference: "167762"
        )
    }

    private func strawberry(
        id: String = "10000000-0000-4000-8000-000000000046",
        ownerID: UUID? = nil,
        brand: String? = nil,
        barcode: String? = nil,
        source: String = "apex_cache",
        providerID: String? = "apex-curated:usda-fdc-167762",
        basis: String = "per_100g",
        preparation: String = "as_sold",
        carbs: Double? = 7.68,
        evidence: [NutrientEvidenceObservation] = []
    ) -> Food {
        Food(
            id: id, ownerUserID: ownerID, name: "Strawberries, raw",
            namesI18n: ["en": "Strawberries, raw", "de": "Erdbeeren, roh"],
            brand: brand, barcode: barcode, source: source, providerProductID: providerID,
            externalImageURL: "https://images.example.test/local-strawberries.jpg",
            packageQuantity: "250 g", nutritionBasis: basis, preparationState: preparation,
            kcal100: 32, protein100: 0.67, carbs100: carbs, fat100: 0.3,
            fibre100: 2, sugar100: 4.89, saturatedFat100: 0.015, salt100: 0.0025,
            waterML100: 90.95, waterBasis: "provider_reported",
            waterSourceID: "local-curation:strawberry-water",
            servingAmount: 1, servingUnit: "serving", servingGramsOrML: 150,
            pieceGramsOrML: 12, confidence: "provider_verified", nutrientEvidence: evidence
        )
    }

    func testExactCompatibleServerCopyTransfersWholeEvidenceWithoutChangingLocalFood() {
        let local = strawberry()
        let enriched = FoodNutrientEvidence.enrichLocalFoods([local], with: [strawberry(evidence: [vitaminC])])[0]

        XCTAssertEqual(enriched.id, foodID)
        XCTAssertEqual(enriched.providerProductID, providerID)
        XCTAssertEqual(enriched.name, local.name)
        XCTAssertEqual(enriched.namesI18n, local.namesI18n)
        XCTAssertEqual(enriched.kcal100, 32)
        XCTAssertEqual(enriched.packageQuantity, "250 g")
        XCTAssertEqual(enriched.waterML100, 90.95)
        XCTAssertEqual(enriched.nutrientEvidence, [vitaminC])
    }

    func testExistingEvidenceWinsWholeWithoutDonorGapFilling() {
        let localVitaminC = NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Vitamin C", valuePer100: 60,
            unit: "mg", observationStatus: .reported, originalValueText: "60 mg/100 g",
            derivationMethod: nil, sourceKey: "apex-curation", sourceReference: "strawberry-review-2026"
        )
        let iron = NutrientEvidenceObservation(
            nutrientCode: "FE", name: "Iron", valuePer100: 0.41,
            unit: "mg", observationStatus: .measured, originalValueText: "0.41 mg/100 g",
            derivationMethod: nil, sourceKey: "usda-fdc", sourceReference: "167762"
        )

        let enriched = FoodNutrientEvidence.enrichLocalFoods(
            [strawberry(evidence: [localVitaminC])],
            with: [strawberry(evidence: [vitaminC, iron])]
        )

        XCTAssertEqual(enriched[0].nutrientEvidence, [localVitaminC])
    }

    func testIdentityAndEligibilityMismatchesCannotTransferEvidence() {
        let cases: [(String, Food, Food)] = [
            ("different public id", strawberry(), strawberry(id: "20000000-0000-4000-8000-000000000046", evidence: [vitaminC])),
            ("different provider id", strawberry(), strawberry(providerID: "apex-curated:other-strawberry", evidence: [vitaminC])),
            ("empty provider id", strawberry(providerID: nil), strawberry(providerID: nil, evidence: [vitaminC])),
            ("private local", strawberry(ownerID: UUID(), source: "private"), strawberry(evidence: [vitaminC])),
            ("non-curated local", strawberry(source: "open_food_facts"), strawberry(evidence: [vitaminC])),
            ("branded local", strawberry(brand: "Example Berry Farm"), strawberry(evidence: [vitaminC])),
            ("barcode local", strawberry(barcode: "7612345678901"), strawberry(evidence: [vitaminC]))
        ]

        for (label, local, server) in cases {
            XCTAssertEqual(FoodNutrientEvidence.enrichLocalFoods([local], with: [server])[0].nutrientEvidence, [], label)
        }
    }

    func testBasisPreparationBrandAndMacroMismatchesCannotTransferEvidence() {
        let cases: [(String, Food, Food)] = [
            ("different basis", strawberry(), strawberry(basis: "per_100ml", evidence: [vitaminC])),
            ("different preparation", strawberry(), strawberry(preparation: "cooked", evidence: [vitaminC])),
            ("branded server", strawberry(), strawberry(brand: "Example Berry Farm", evidence: [vitaminC])),
            ("macro mismatch", strawberry(), strawberry(carbs: 27.7, evidence: [vitaminC]))
        ]

        for (label, local, server) in cases {
            XCTAssertEqual(FoodNutrientEvidence.enrichLocalFoods([local], with: [server])[0].nutrientEvidence, [], label)
        }
    }
}
