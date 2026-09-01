import Foundation
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

    private var iron: NutrientEvidenceObservation {
        NutrientEvidenceObservation(
            nutrientCode: "FE", name: "Iron", valuePer100: 0.41,
            unit: "mg", observationStatus: .measured,
            originalValueText: "0.41 mg/100 g", derivationMethod: nil,
            sourceKey: "usda-fdc", sourceReference: "167762"
        )
    }

    private struct NaturalEvidenceEnvelope: Decodable {
        let schemaVersion: Int
        let targets: [NaturalEvidenceTarget]

        enum CodingKeys: String, CodingKey {
            case targets
            case schemaVersion = "schema_version"
        }
    }

    private struct NaturalEvidenceTarget: Decodable {
        let category: String
        let donor: NaturalEvidenceDonor
        let target: NaturalEvidenceIdentity
        let evidence: [NutrientEvidenceObservation]
    }

    private struct NaturalEvidenceDonor: Decodable {
        let sourceKey: String
        let sourceRecordID: String

        enum CodingKeys: String, CodingKey {
            case sourceKey = "source_key"
            case sourceRecordID = "source_record_id"
        }
    }

    private struct NaturalEvidenceIdentity: Decodable {
        let id: String
    }

    private func mutatedNaturalEvidenceResource(
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let data = try XCTUnwrap(FoodNutrientEvidence.naturalFoodEvidenceResourceData())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutation(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func strawberry(
        id: String = "10000000-0000-4000-8000-000000000046",
        ownerID: UUID? = nil,
        name: String = "Strawberries, raw",
        brand: String? = nil,
        barcode: String? = nil,
        source: String = "apex_cache",
        providerID: String? = "apex-curated:usda-fdc-167762",
        basis: String = "per_100g",
        preparation: String = "as_sold",
        kcal: Double? = 32,
        protein: Double? = 0.67,
        carbs: Double? = 7.68,
        fat: Double? = 0.3,
        evidence: [NutrientEvidenceObservation] = []
    ) -> Food {
        Food(
            id: id, ownerUserID: ownerID, name: name,
            namesI18n: ["en": name, "de": "Erdbeeren, roh"],
            brand: brand, barcode: barcode, source: source, providerProductID: providerID,
            externalImageURL: "https://images.example.test/local-strawberries.jpg",
            packageQuantity: "250 g", nutritionBasis: basis, preparationState: preparation,
            kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat,
            fibre100: 2, sugar100: 4.89, saturatedFat100: 0.015, salt100: 0.0025,
            waterML100: 90.95, waterBasis: "provider_reported",
            waterSourceID: "local-curation:strawberry-water",
            servingAmount: 1, servingUnit: "serving", servingGramsOrML: 150,
            pieceGramsOrML: 12, confidence: "provider_verified", nutrientEvidence: evidence
        )
    }

    private func bundledStrawberry(
        id: String = "10000000-0000-4000-8000-000000000046",
        ownerID: UUID? = nil,
        name: String = "Strawberries, fresh",
        brand: String? = nil,
        barcode: String? = nil,
        source: String = "apex_cache",
        providerID: String? = "apex-curated:swiss-retail-strawberries-fresh-reference",
        basis: String = "per_100g",
        preparation: String = "as_sold",
        kcal: Double? = 32,
        protein: Double? = 0.67,
        carbs: Double? = 7.68,
        fat: Double? = 0.3,
        evidence: [NutrientEvidenceObservation] = []
    ) -> Food {
        strawberry(
            id: id, ownerID: ownerID, name: name, brand: brand, barcode: barcode,
            source: source, providerID: providerID, basis: basis, preparation: preparation,
            kcal: kcal, protein: protein, carbs: carbs, fat: fat, evidence: evidence
        )
    }

    private func assertNoTransfer(
        _ label: String,
        local: Food,
        server: Food,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            FoodNutrientEvidence.enrichLocalFoods([local], with: [server])[0].nutrientEvidence,
            [], label, file: file, line: line
        )
    }

    func testExactCompatibleServerCopyClonesEveryObservationDespiteDifferentDisplayName() {
        let local = strawberry()
        let donorEvidence = [vitaminC, iron]
        let donor = strawberry(name: "USDA composition entry 167762", evidence: donorEvidence)
        let enriched = FoodNutrientEvidence.enrichLocalFoods([local], with: [donor])[0]

        XCTAssertEqual(enriched.id, foodID)
        XCTAssertEqual(enriched.providerProductID, providerID)
        XCTAssertEqual(enriched.name, local.name)
        XCTAssertEqual(enriched.namesI18n, local.namesI18n)
        XCTAssertEqual(enriched.kcal100, local.kcal100)
        XCTAssertEqual(enriched.packageQuantity, local.packageQuantity)
        XCTAssertEqual(enriched.nutrientEvidence, donor.nutrientEvidence)
        XCTAssertEqual(donor.nutrientEvidence, donorEvidence)
    }

    func testExistingEvidenceWinsWholeWithoutDonorGapFilling() {
        let localVitaminC = NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Vitamin C", valuePer100: 60,
            unit: "mg", observationStatus: .reported, originalValueText: "60 mg/100 g",
            derivationMethod: nil, sourceKey: "apex-curation", sourceReference: "strawberry-review-2026"
        )
        let enriched = FoodNutrientEvidence.enrichLocalFoods(
            [strawberry(evidence: [localVitaminC])],
            with: [strawberry(name: "Official donor", evidence: [vitaminC, iron])]
        )

        XCTAssertEqual(enriched[0].nutrientEvidence, [localVitaminC])
    }

    func testWhitespaceAndEmptyPublicAndProviderIdentifiersRejectTransfer() {
        let cases: [(String, Food, Food)] = [
            ("empty matching ids", strawberry(id: ""), strawberry(id: "", evidence: [vitaminC, iron])),
            ("whitespace matching ids", strawberry(id: "   "), strawberry(id: "   ", evidence: [vitaminC, iron])),
            ("missing matching providers", strawberry(providerID: nil), strawberry(providerID: nil, evidence: [vitaminC, iron])),
            ("empty matching providers", strawberry(providerID: ""), strawberry(providerID: "", evidence: [vitaminC, iron])),
            ("whitespace matching providers", strawberry(providerID: "   "), strawberry(providerID: "   ", evidence: [vitaminC, iron])),
            ("empty remote id", strawberry(), strawberry(id: "", evidence: [vitaminC, iron])),
            ("empty remote provider", strawberry(), strawberry(providerID: "", evidence: [vitaminC, iron]))
        ]
        for (label, local, server) in cases { assertNoTransfer(label, local: local, server: server) }
    }

    func testIdentityAndPublicCuratedEligibilityRejectTransferOnEitherSide() {
        let donor = strawberry(evidence: [vitaminC, iron])
        let cases: [(String, Food, Food)] = [
            ("different public id", strawberry(), strawberry(id: "20000000-0000-4000-8000-000000000046", evidence: [vitaminC, iron])),
            ("different provider id", strawberry(), strawberry(providerID: "apex-curated:other", evidence: [vitaminC, iron])),
            ("target ownership", strawberry(ownerID: UUID()), donor),
            ("remote ownership", strawberry(), strawberry(ownerID: UUID(), evidence: [vitaminC, iron])),
            ("target barcode", strawberry(barcode: "7612345678901"), donor),
            ("remote barcode", strawberry(), strawberry(barcode: "7612345678901", evidence: [vitaminC, iron])),
            ("target source", strawberry(source: "open_food_facts"), donor),
            ("remote source", strawberry(), strawberry(source: "open_food_facts", evidence: [vitaminC, iron])),
            ("target brand", strawberry(brand: "Example Berry Farm"), donor),
            ("remote brand", strawberry(), strawberry(brand: "Example Berry Farm", evidence: [vitaminC, iron]))
        ]
        for (label, local, server) in cases { assertNoTransfer(label, local: local, server: server) }
    }

    func testBasisAndPreparationMatrixRejectsRawCookedDryCookedAndOilNoOilLinks() {
        let donor = [vitaminC, iron]
        let cases: [(String, Food, Food)] = [
            ("basis", strawberry(), strawberry(basis: "per_100ml", evidence: donor)),
            ("raw cooked", strawberry(preparation: "as_sold"), strawberry(preparation: "cooked", evidence: donor)),
            ("dry cooked", strawberry(preparation: "dry"), strawberry(preparation: "cooked", evidence: donor)),
            ("oil no-oil", strawberry(name: "Potatoes, cooked without oil", preparation: "cooked"), strawberry(name: "Potatoes, cooked in oil", preparation: "prepared", evidence: donor))
        ]
        for (label, local, server) in cases { assertNoTransfer(label, local: local, server: server) }
    }

    func testEveryFingerprintFieldRejectsMissingAndNonFiniteValuesIndependently() {
        let evidence = [vitaminC, iron]
        let cases: [(String, Food, Food)] = [
            ("missing target kcal", strawberry(kcal: nil), strawberry(evidence: evidence)),
            ("missing remote protein", strawberry(), strawberry(protein: nil, evidence: evidence)),
            ("missing target carbs", strawberry(carbs: nil), strawberry(evidence: evidence)),
            ("missing remote fat", strawberry(), strawberry(fat: nil, evidence: evidence)),
            ("nonfinite target kcal", strawberry(kcal: .nan), strawberry(evidence: evidence)),
            ("nonfinite remote protein", strawberry(), strawberry(protein: .infinity, evidence: evidence)),
            ("nonfinite target carbs", strawberry(carbs: -.infinity), strawberry(evidence: evidence)),
            ("nonfinite remote fat", strawberry(), strawberry(fat: .nan, evidence: evidence)),
            ("kcal mismatch", strawberry(), strawberry(kcal: 35, evidence: evidence)),
            ("protein mismatch", strawberry(), strawberry(protein: 1, evidence: evidence)),
            ("carbs mismatch", strawberry(), strawberry(carbs: 9, evidence: evidence)),
            ("fat mismatch", strawberry(), strawberry(fat: 0.6, evidence: evidence))
        ]
        for (label, local, server) in cases { assertNoTransfer(label, local: local, server: server) }
    }

    func testExactInclusiveFingerprintToleranceBoundariesTransfer() {
        let evidence = [vitaminC, iron]
        let cases: [(String, Food, Food)] = [
            ("kcal two percent", strawberry(kcal: 100), strawberry(kcal: 102, evidence: evidence)),
            ("protein two percent", strawberry(protein: 10), strawberry(protein: 10.2, evidence: evidence)),
            ("carbs two percent", strawberry(carbs: 10), strawberry(carbs: 10.2, evidence: evidence)),
            ("fat two percent", strawberry(fat: 10), strawberry(fat: 10.2, evidence: evidence))
        ]
        for (label, local, server) in cases {
            XCTAssertEqual(FoodNutrientEvidence.enrichLocalFoods([local], with: [server])[0].nutrientEvidence, evidence, label)
        }
    }

    func testExactInclusiveAbsoluteFingerprintFloorsTransfer() {
        let evidence = [vitaminC, iron]
        let cases: [(String, Food, Food)] = [
            ("kcal", strawberry(), strawberry(kcal: 33, evidence: evidence)),
            ("protein", strawberry(), strawberry(protein: 0.72, evidence: evidence)),
            ("carbs", strawberry(), strawberry(carbs: 7.73, evidence: evidence)),
            ("fat", strawberry(), strawberry(fat: 0.35, evidence: evidence))
        ]
        for (label, local, server) in cases {
            XCTAssertEqual(FoodNutrientEvidence.enrichLocalFoods([local], with: [server])[0].nutrientEvidence, evidence, label)
        }
    }

    func testAmbiguousCompatibleDonorsRejectTransfer() {
        let local = strawberry()
        let donor = strawberry(name: "Official donor", evidence: [vitaminC, iron])
        XCTAssertEqual(FoodNutrientEvidence.enrichLocalFoods([local], with: [donor, donor])[0].nutrientEvidence, [])
    }

    func testSearchMergeEnrichesLocalBeforeDuplicateRemoval() {
        let local = strawberry()
        let donorEvidence = [vitaminC, iron]
        let donor = strawberry(name: "Official donor", evidence: donorEvidence)
        let merged = FoodNutrientEvidence.mergeLocalSearchFoods([local], with: [donor])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, local.id)
        XCTAssertEqual(merged[0].name, local.name)
        XCTAssertEqual(merged[0].nutrientEvidence, donorEvidence)
    }

    func testBundledResourceHas111UniqueReviewedTargetsAcrossNineCategories() throws {
        let data = try XCTUnwrap(FoodNutrientEvidence.naturalFoodEvidenceResourceData())
        let resource = try JSONDecoder().decode(NaturalEvidenceEnvelope.self, from: data)

        XCTAssertEqual(resource.schemaVersion, 1)
        XCTAssertEqual(resource.targets.count, 111)
        XCTAssertEqual(Set(resource.targets.map(\.target.id)).count, 111)
        XCTAssertEqual(Set(resource.targets.map(\.category)), Set([
            "egg", "fish_shellfish", "fruit", "grain_starch", "legume",
            "meat_poultry", "nut_seed", "plain_dairy", "vegetable_leaf"
        ]))
        XCTAssertTrue(resource.targets.allSatisfy {
            !$0.evidence.isEmpty
                && $0.evidence.count <= 96
                && (try? JSONEncoder().encode($0.evidence).count).map({ $0 <= 65_536 }) == true
        })
    }

    func testBundledResourceRetainsOatsBiotinIodineAndFoundationChickenEnergy() throws {
        let data = try XCTUnwrap(FoodNutrientEvidence.naturalFoodEvidenceResourceData())
        let resource = try JSONDecoder().decode(NaturalEvidenceEnvelope.self, from: data)
        let oats = try XCTUnwrap(resource.targets.first {
            $0.target.id == "10000000-0000-4000-8000-000000000001"
        })
        XCTAssertEqual(oats.donor.sourceKey, "dk-frida")
        XCTAssertEqual(oats.donor.sourceRecordID, "59")
        XCTAssertEqual(oats.evidence.first { $0.nutrientCode == "VITB7" }?.valuePer100, 19)
        XCTAssertEqual(oats.evidence.first { $0.nutrientCode == "I" }?.valuePer100, 0.5)

        let chicken = try XCTUnwrap(resource.targets.first {
            $0.target.id == "10000000-0000-4000-8000-000000000013"
        })
        let energy = try XCTUnwrap(chicken.evidence.first { $0.nutrientCode == "ENERC_KCAL" })
        XCTAssertEqual(energy.name, "Energy (Atwater General Factors)")
        XCTAssertEqual(energy.valuePer100, 106.034)
        XCTAssertEqual(energy.sourceReference, "food_nutrient:33295327")
    }

    func testBundledStrawberryExposesSourceBackedVitaminCAndIron() {
        let enriched = FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([bundledStrawberry()])[0]
        let vitaminC = enriched.nutrientEvidence?.first { $0.nutrientCode == "VITC" }
        let iron = enriched.nutrientEvidence?.first { $0.nutrientCode == "FE" }

        XCTAssertEqual(vitaminC?.name, "Vitamin C, total ascorbic acid")
        XCTAssertEqual(vitaminC?.valuePer100, 58.8)
        XCTAssertEqual(vitaminC?.sourceKey, "usda-sr-legacy")
        XCTAssertEqual(vitaminC?.sourceReference, "food_nutrient:1303228")
        XCTAssertEqual(iron?.valuePer100, 0.41)
        XCTAssertEqual(
            FoodNutrientEvidence.nutritionFactSections(enriched.nutrientEvidence ?? []).map(\.kind),
            [.facts, .vitamins, .minerals]
        )
    }

    func testBundledTargetAndDonorAliasesBothApplyBeforeSearchDeduplication() {
        let target = bundledStrawberry(name: "Localized target display name")
        let donor = bundledStrawberry(
            id: "d52f7d80-8039-5b78-bb11-57bf3a75e9fa",
            name: "Publisher donor display name",
            providerID: "corpus:usda-sr-legacy:167762",
            preparation: "unknown"
        )
        let overlaid = FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([target, donor])

        XCTAssertEqual(overlaid[0].nutrientEvidence, overlaid[1].nutrientEvidence)
        XCTAssertEqual(overlaid[0].nutrientEvidence?.first { $0.nutrientCode == "VITC" }?.valuePer100, 58.8)
        let merged = FoodNutrientEvidence.mergeLocalSearchFoods(
            [target], with: [bundledStrawberry(name: "Server target copy")]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, target.name)
        XCTAssertEqual(merged[0].nutrientEvidence?.first { $0.nutrientCode == "VITC" }?.valuePer100, 58.8)
    }

    func testExistingTargetEvidenceWinsWholeOverBundledEvidence() {
        let explicit = NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Explicit vitamin C", valuePer100: 60,
            unit: "mg", observationStatus: .reported, originalValueText: "60",
            derivationMethod: nil, sourceKey: "apex-curation", sourceReference: "explicit:strawberry"
        )
        let enriched = FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([
            bundledStrawberry(evidence: [explicit])
        ])
        XCTAssertEqual(enriched[0].nutrientEvidence, [explicit])
    }

    func testBundledOverlayRejectsPrivacyBrandBarcodeIdentityPreparationBasisAndMacroDrift() {
        let cases: [(String, Food)] = [
            ("owner", bundledStrawberry(ownerID: UUID())),
            ("brand", bundledStrawberry(brand: "Nearby berry brand")),
            ("barcode", bundledStrawberry(barcode: "7612345678901")),
            ("source", bundledStrawberry(source: "private")),
            ("basis", bundledStrawberry(basis: "per_100ml")),
            ("preparation", bundledStrawberry(preparation: "cooked")),
            ("id", bundledStrawberry(id: "20000000-0000-4000-8000-000000000046")),
            ("provider", bundledStrawberry(providerID: "apex-curated:near-neighbour")),
            ("missing provider", bundledStrawberry(providerID: nil)),
            ("kcal", bundledStrawberry(kcal: 35)),
            ("protein", bundledStrawberry(protein: 1)),
            ("carbs", bundledStrawberry(carbs: 9)),
            ("fat", bundledStrawberry(fat: 0.6)),
            ("nonfinite", bundledStrawberry(kcal: .nan))
        ]
        for (label, food) in cases {
            XCTAssertEqual(
                FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([food])[0].nutrientEvidence,
                [], label
            )
        }
    }

    func testBundledOverlayNeverAuthorizesByMatchingNameAlone() {
        let nearNeighbour = bundledStrawberry(
            id: "99999999-9999-4999-8999-999999999999",
            providerID: "apex-curated:not-reviewed"
        )
        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([nearNeighbour])[0].nutrientEvidence,
            []
        )
    }

    func testBundledOverlayFailsClosedForMalformedOrOversizedEvidence() throws {
        let malformed = try mutatedNaturalEvidenceResource { root in
            var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
            let index = try XCTUnwrap(targets.firstIndex(where: {
                guard let target = $0["target"] as? [String: Any],
                      let id = target["id"] as? String
                else { return false }
                return id == self.foodID
            }))
            var evidence = try XCTUnwrap(targets[index]["evidence"] as? [[String: Any]])
            evidence[0]["source_reference"] = NSNull()
            targets[index]["evidence"] = evidence
            root["targets"] = targets
        }
        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                [bundledStrawberry()], resourceData: malformed
            )[0].nutrientEvidence,
            []
        )

        let oversized = try mutatedNaturalEvidenceResource { root in
            var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
            let index = try XCTUnwrap(targets.firstIndex(where: {
                guard let target = $0["target"] as? [String: Any],
                      let id = target["id"] as? String
                else { return false }
                return id == self.foodID
            }))
            var evidence = try XCTUnwrap(targets[index]["evidence"] as? [[String: Any]])
            evidence[0]["original_value_text"] = String(repeating: "x", count: 66_000)
            targets[index]["evidence"] = evidence
            root["targets"] = targets
        }
        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                [bundledStrawberry()], resourceData: oversized
            )[0].nutrientEvidence,
            []
        )
    }
}
