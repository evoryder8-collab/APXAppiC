import Foundation
import XCTest
@testable import APEX

final class FoodEvidenceEnrichmentTests: XCTestCase {
    private let foodID = "10000000-0000-4000-8000-000000000046"
    private let providerID = "apex-curated:usda-fdc-167762"

    private let shippedNaturalFoodDisplayKeys: [String: String] = [
        "CA": "Calcium",
        "CARTB": "Beta-carotene",
        "CHOAVL": "Total carbs",
        "CHOLE": "Cholesterol",
        "CU": "Copper",
        "ENERC_KCAL": "Calories",
        "FAMS": "Monounsaturated fat",
        "FAPU": "Polyunsaturated fat",
        "FASAT": "Saturated fat",
        "FAT": "Total fat",
        "FATRN": "Trans fat",
        "FE": "Iron",
        "FIBT": "Dietary fibre",
        "I": "Iodine",
        "K": "Potassium",
        "MG": "Magnesium",
        "MN": "Manganese",
        "NA": "Sodium",
        "NACL": "Salt",
        "OMEGA3": "Omega-3 fat",
        "OMEGA3_ALA": "Alpha-linolenic acid (ALA)",
        "OMEGA3_DHA": "Docosahexaenoic acid (DHA)",
        "OMEGA3_DPA": "Docosapentaenoic acid (DPA)",
        "OMEGA3_EPA": "Eicosapentaenoic acid (EPA)",
        "OMEGA6": "Omega-6 fat",
        "OMEGA6_AA": "Arachidonic acid (AA)",
        "OMEGA6_GLA": "Gamma-linolenic acid (GLA)",
        "OMEGA6_LA": "Linoleic acid (LA)",
        "P": "Phosphorus",
        "PROT": "Protein",
        "SE": "Selenium",
        "STARCH": "Starch",
        "SUGAR": "Total sugars",
        "VITA": "Vitamin A",
        "VITB1": "Thiamin (B1)",
        "VITB12": "Vitamin B12",
        "VITB2": "Riboflavin (B2)",
        "VITB3": "Niacin (B3)",
        "VITB5": "Pantothenic acid (B5)",
        "VITB6": "Vitamin B6",
        "VITB7": "Biotin (B7)",
        "VITB9": "Folate (B9)",
        "VITC": "Vitamin C",
        "VITD": "Vitamin D",
        "VITE": "Vitamin E",
        "VITK": "Vitamin K",
        "WATER": "Water",
        "ZN": "Zinc"
    ]

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

    func testDetailedNutritionUsesTheSameCanonicalTotalsAsTheAmountCard() {
        let donorFacts = [
            NutrientEvidenceObservation(
                nutrientCode: "ENERC_KCAL", name: "Energy from donor", valuePer100: 33,
                unit: "kcal", observationStatus: .measured, originalValueText: "33",
                derivationMethod: nil, sourceKey: "fixture", sourceReference: "fixture"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "PROT", name: "Protein from donor", valuePer100: 0.72,
                unit: "g", observationStatus: .measured, originalValueText: "0.72",
                derivationMethod: nil, sourceKey: "fixture", sourceReference: "fixture"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "CHOAVL", name: "Carbohydrate from donor", valuePer100: 7.9,
                unit: "g", observationStatus: .measured, originalValueText: "7.9",
                derivationMethod: nil, sourceKey: "fixture", sourceReference: "fixture"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "FAT", name: "Fat from donor", valuePer100: 0.32,
                unit: "g", observationStatus: .measured, originalValueText: "0.32",
                derivationMethod: nil, sourceKey: "fixture", sourceReference: "fixture"
            ),
            vitaminC
        ]
        let food = strawberry(evidence: donorFacts)
        let rows = FoodNutrientEvidence.observations(for: food)

        XCTAssertEqual(rows.first { $0.nutrientCode == "ENERC_KCAL" }?.valuePer100, food.kcal100)
        XCTAssertEqual(rows.first { $0.nutrientCode == "PROT" }?.valuePer100, food.protein100)
        XCTAssertEqual(rows.first { $0.nutrientCode == "CHOAVL" }?.valuePer100, food.carbs100)
        XCTAssertEqual(rows.first { $0.nutrientCode == "FAT" }?.valuePer100, food.fat100)
        XCTAssertEqual(rows.first { $0.nutrientCode == "VITC" }, vitaminC)
        for code in ["ENERC_KCAL", "PROT", "CHOAVL", "FAT"] {
            XCTAssertEqual(rows.filter { $0.nutrientCode == code }.count, 1)
        }
    }

    func testLegacyServerUnitsCanonicalizeAndOpaqueUnitsFailClosed() {
        let rows = [
            NutrientEvidenceObservation(
                nutrientCode: "VITC", name: "Vitamin C", valuePer100: 50,
                unit: "MG / 100g", observationStatus: .measured,
                originalValueText: "50", derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "1"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "VITA", name: "Vitamin A", valuePer100: 700,
                unit: "RE (ug/100 g)", observationStatus: .measured,
                originalValueText: "700", derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "2"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "VITE", name: "Vitamin E", valuePer100: 2,
                unit: "alfa-TE", observationStatus: .measured,
                originalValueText: "2", derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "3"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "VITD", name: "Vitamin D", valuePer100: 20,
                unit: "i.u.", observationStatus: .measured,
                originalValueText: "20", derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "4"
            ),
            NutrientEvidenceObservation(
                nutrientCode: "FE", name: "Iron", valuePer100: 9,
                unit: "publisher score", observationStatus: .measured,
                originalValueText: "9", derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "5"
            )
        ]
        let projected = FoodNutrientEvidence.observations(for: strawberry(evidence: rows))
        let units = Dictionary(uniqueKeysWithValues: projected.compactMap { observation in
            ["VITC", "VITA", "VITE", "VITD", "FE"].contains(observation.nutrientCode)
                ? (observation.nutrientCode, observation.unit) : nil
        })

        XCTAssertEqual(units, [
            "VITC": "mg", "VITA": "µg RE", "VITE": "mg α-TE", "VITD": "IU"
        ])
        XCTAssertEqual(FoodNutrientEvidence.canonicalUnit("KCAL/100 g"), "kcal")
        XCTAssertEqual(FoodNutrientEvidence.canonicalUnit("μg per 100g"), "µg")
        XCTAssertEqual(FoodNutrientEvidence.canonicalUnit("ug RAE"), "µg RAE")
        XCTAssertNil(FoodNutrientEvidence.canonicalUnit("publisher score"))
    }

    func testLegacyEquivalentUnitsMergeInPatternsWhileOpaqueUnitsAreOmitted() {
        let ownerID = UUID()
        let firstMeal = UUID()
        let secondMeal = UUID()
        func row(_ code: String, _ value: Double, _ unit: String) -> NutrientEvidenceObservation {
            NutrientEvidenceObservation(
                nutrientCode: code, name: code, valuePer100: value,
                unit: unit, observationStatus: .measured,
                originalValueText: String(value), derivationMethod: nil,
                sourceKey: "legacy-server", sourceReference: "fixture"
            )
        }
        let summary = NutrientPatternEngine.summarize(
            meals: [
                NutrientPatternMeal(id: firstMeal, userID: ownerID, localDate: "2026-09-01"),
                NutrientPatternMeal(id: secondMeal, userID: ownerID, localDate: "2026-09-02")
            ],
            entries: [
                NutrientPatternEntry(
                    mealID: firstMeal, userID: ownerID, equivalentAmount: 100,
                    evidence: [row("VITC", 40, "MG"), row("VITA", 10, "UG RAE")]
                ),
                NutrientPatternEntry(
                    mealID: secondMeal, userID: ownerID, equivalentAmount: 100,
                    evidence: [
                        row("VITC", 60, "mg per 100g"),
                        row("VITA", 20, "µg RAE"),
                        row("FE", 99, "publisher score")
                    ]
                )
            ],
            ownerID: ownerID,
            anchorDate: "2026-09-02",
            period: .week
        )

        let vitaminC = summary.rows.filter { $0.nutrientCode == "VITC" }
        XCTAssertEqual(vitaminC.count, 1)
        XCTAssertEqual(vitaminC.first?.unit, "mg")
        XCTAssertEqual(vitaminC.first?.total, 100)
        XCTAssertEqual(vitaminC.first?.averagePerObservedDay, 50)
        XCTAssertEqual(summary.rows.first { $0.nutrientCode == "VITA" }?.unit, "µg RAE")
        XCTAssertEqual(summary.rows.first { $0.nutrientCode == "VITA" }?.total, 30)
        XCTAssertFalse(summary.rows.contains { $0.nutrientCode == "FE" })
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

    func testSearchMergePrefersExactServerEvidenceOverBundledFallbackEvidence() {
        let local = bundledStrawberry()
        let serverEvidence = NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Server vitamin C", valuePer100: 61,
            unit: "mg", observationStatus: .reported, originalValueText: "61",
            derivationMethod: nil, sourceKey: "server-official",
            sourceReference: "server:strawberry"
        )
        let server = bundledStrawberry(name: "Exact server strawberry", evidence: [serverEvidence])

        let merged = FoodNutrientEvidence.mergeLocalSearchFoods([local], with: [server])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].nutrientEvidence, [serverEvidence])
    }

    func testSearchMergePreservesExplicitLocalEvidenceAheadOfServerAndBundle() {
        let explicit = NutrientEvidenceObservation(
            nutrientCode: "VITC", name: "Explicit vitamin C", valuePer100: 60,
            unit: "mg", observationStatus: .reported, originalValueText: "60",
            derivationMethod: nil, sourceKey: "apex-curation",
            sourceReference: "explicit:strawberry"
        )
        let local = bundledStrawberry(evidence: [explicit])
        let server = bundledStrawberry(name: "Exact server strawberry", evidence: [vitaminC, iron])

        XCTAssertEqual(
            FoodNutrientEvidence.mergeLocalSearchFoods([local], with: [server])[0].nutrientEvidence,
            [explicit]
        )
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

    func testDebugFoodMemoryStrawberryUsesTheRealBundledEvidencePath() throws {
        let strawberry = try XCTUnwrap(
            APEXDebugFixture.dashboard().foods.first {
                $0.id == "10000000-0000-4000-8000-000000000046"
            }
        )
        let enriched = FoodNutrientEvidence.overlayBundledNaturalFoodEvidence([strawberry])[0]

        XCTAssertEqual(
            enriched.nutrientEvidence?.first { $0.nutrientCode == "VITC" }?.valuePer100,
            58.8
        )
        XCTAssertEqual(
            enriched.nutrientEvidence?.first { $0.nutrientCode == "FE" }?.valuePer100,
            0.41
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

    func testBundledEvidenceValueUsesInclusiveZeroToOneTrillionDomain() throws {
        for invalidValue in [-1.0, 1_000_000_000_001.0] {
            let malformed = try mutatedNaturalEvidenceResource { root in
                var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
                let index = try XCTUnwrap(targets.firstIndex(where: {
                    guard let target = $0["target"] as? [String: Any],
                          let id = target["id"] as? String
                    else { return false }
                    return id == self.foodID
                }))
                var evidence = try XCTUnwrap(targets[index]["evidence"] as? [[String: Any]])
                evidence[0]["value_per_100"] = invalidValue
                targets[index]["evidence"] = evidence
                root["targets"] = targets
            }
            XCTAssertEqual(
                FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                    [bundledStrawberry()], resourceData: malformed
                )[0].nutrientEvidence,
                [], "invalid value \(invalidValue)"
            )
        }

        for boundaryValue in [0.0, 1_000_000_000_000.0] {
            let valid = try mutatedNaturalEvidenceResource { root in
                var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
                let index = try XCTUnwrap(targets.firstIndex(where: {
                    guard let target = $0["target"] as? [String: Any],
                          let id = target["id"] as? String
                    else { return false }
                    return id == self.foodID
                }))
                var evidence = try XCTUnwrap(targets[index]["evidence"] as? [[String: Any]])
                evidence[0]["value_per_100"] = boundaryValue
                targets[index]["evidence"] = evidence
                root["targets"] = targets
            }
            XCTAssertEqual(
                FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                    [bundledStrawberry()], resourceData: valid
                )[0].nutrientEvidence?.first?.valuePer100,
                boundaryValue
            )
        }
    }

    func testMalformedEntryDoesNotDisableOtherValidBundledEntries() throws {
        let malformed = try mutatedNaturalEvidenceResource { root in
            var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
            let index = try XCTUnwrap(targets.firstIndex(where: {
                guard let target = $0["target"] as? [String: Any],
                      let id = target["id"] as? String
                else { return false }
                return id != self.foodID
            }))
            targets[index]["aliases"] = "malformed entry"
            root["targets"] = targets
        }

        let enriched = FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
            [bundledStrawberry()], resourceData: malformed
        )[0]

        XCTAssertEqual(
            enriched.nutrientEvidence?.first { $0.nutrientCode == "VITC" }?.valuePer100,
            58.8
        )
    }

    func testEveryShippedNutrientUsesCanonicalLabelsInDetailsAndPatterns() throws {
        let resourceData = try XCTUnwrap(FoodNutrientEvidence.naturalFoodEvidenceResourceData())
        let resource = try JSONDecoder().decode(NaturalEvidenceEnvelope.self, from: resourceData)
        let shippedCodes = Set(resource.targets.flatMap { target in
            target.evidence.map { $0.nutrientCode.uppercased() }
        })
        XCTAssertEqual(shippedCodes, Set(shippedNaturalFoodDisplayKeys.keys))

        let hostilePublisherRows = shippedCodes.sorted().enumerated().map { index, code in
            NutrientEvidenceObservation(
                nutrientCode: code,
                name: "Untranslated publisher label \(index)",
                valuePer100: 1,
                unit: "mg",
                observationStatus: .measured,
                originalValueText: "1",
                derivationMethod: nil,
                sourceKey: "fixture-source",
                sourceReference: "fixture-reference"
            )
        }
        let detailLabels = Dictionary(uniqueKeysWithValues:
            FoodNutrientEvidence.nutritionFactSections(hostilePublisherRows)
                .flatMap(\.rows)
                .map { ($0.observation.nutrientCode, $0.label) }
        )
        XCTAssertEqual(detailLabels, shippedNaturalFoodDisplayKeys)

        let ownerID = UUID()
        let mealID = UUID()
        let summary = NutrientPatternEngine.summarize(
            meals: [NutrientPatternMeal(id: mealID, userID: ownerID, localDate: "2026-09-01")],
            entries: [NutrientPatternEntry(
                mealID: mealID,
                userID: ownerID,
                equivalentAmount: 100,
                evidence: hostilePublisherRows
            )],
            ownerID: ownerID,
            anchorDate: "2026-09-01",
            period: .month
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.nutrientCode, $0.name) }),
            shippedNaturalFoodDisplayKeys
        )
    }

    func testMalformedEntryMetadataFailsClosedAtNativeRuntimeBoundary() throws {
        let cases: [(String, (inout [String: Any]) throws -> Void)] = [
            ("category", { $0["category"] = "   " }),
            ("donor name", { target in
                var donor = try XCTUnwrap(target["donor"] as? [String: Any])
                donor["name"] = ""
                target["donor"] = donor
            }),
            ("target name", { target in
                var identity = try XCTUnwrap(target["target"] as? [String: Any])
                identity["name"] = "\n"
                target["target"] = identity
            })
        ]

        for (label, mutation) in cases {
            let malformed = try mutatedNaturalEvidenceResource { root in
                var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
                let index = try XCTUnwrap(targets.firstIndex(where: {
                    guard let target = $0["target"] as? [String: Any],
                          let id = target["id"] as? String
                    else { return false }
                    return id == self.foodID
                }))
                try mutation(&targets[index])
                root["targets"] = targets
            }
            XCTAssertEqual(
                FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                    [bundledStrawberry()], resourceData: malformed
                )[0].nutrientEvidence,
                [], label
            )
        }
    }

    func testMissingNullableEvidenceValueFailsClosedAtNativeRuntimeBoundary() throws {
        let malformed = try mutatedNaturalEvidenceResource { root in
            var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
            let index = try XCTUnwrap(targets.firstIndex(where: {
                guard let target = $0["target"] as? [String: Any],
                      let id = target["id"] as? String
                else { return false }
                return id == self.foodID
            }))
            var evidence = try XCTUnwrap(targets[index]["evidence"] as? [[String: Any]])
            evidence[0].removeValue(forKey: "value_per_100")
            targets[index]["evidence"] = evidence
            root["targets"] = targets
        }

        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                [bundledStrawberry()], resourceData: malformed
            )[0].nutrientEvidence,
            []
        )
    }

    func testResourceWithMoreThan256TargetsIsRejectedBeforeEntryDecoding() throws {
        let excessive = try mutatedNaturalEvidenceResource { root in
            var targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
            let filler = try XCTUnwrap(targets.first(where: {
                guard let target = $0["target"] as? [String: Any],
                      let id = target["id"] as? String
                else { return false }
                return id != self.foodID
            }))
            while targets.count <= 256 { targets.append(filler) }
            root["targets"] = targets
        }

        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                [bundledStrawberry()], resourceData: excessive
            )[0].nutrientEvidence,
            []
        )
    }

    func testResourceLargerThanFourMiBIsRejectedBeforeJSONParsing() throws {
        let oversized = try mutatedNaturalEvidenceResource { root in
            root["oversized_padding"] = String(repeating: "x", count: 4_194_305)
        }

        XCTAssertGreaterThan(oversized.count, 4_194_304)
        XCTAssertEqual(
            FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(
                [bundledStrawberry()], resourceData: oversized
            )[0].nutrientEvidence,
            []
        )
    }
}
