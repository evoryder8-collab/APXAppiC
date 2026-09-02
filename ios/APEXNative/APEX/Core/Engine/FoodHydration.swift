import Foundation

/*
 * Port of src/lib/hydration.ts.
 *
 * Every logged food may carry grams of water per 100 g. Only explicitly
 * measured values are presented as exact; provider, reference and derived
 * values remain visibly approximate.
 *
 * Reference values: Swiss Food Composition Database V7.1 (FSVO/BLV,
 * naehrwertdaten.ch) and USDA FoodData Central. Estimating by difference
 * (100 - protein - fat - carbohydrate - ash) is the standard composition-table
 * method, used only when nothing measured matches.
 */
enum FoodHydration {
    enum Basis: String, Sendable {
        case measured
        case providerReported = "provider_reported"
        case reference
        case name
        case difference
        case legacy
        case userEntered = "user_entered"
        case unknown
    }

    struct Disclosure: Equatable, Sendable {
        let isEstimated: Bool
        let prefix: String
        let label: String
    }

    struct Estimate: Hashable, Sendable {
        let waterML100: Double
        let basis: Basis
    }

    static func disclosure(for basis: String?) -> Disclosure {
        if basis == Basis.measured.rawValue {
            return Disclosure(isEstimated: false, prefix: "", label: "Measured water")
        }
        return Disclosure(isEstimated: true, prefix: "≈", label: "Estimated water")
    }

    struct Input: Sendable {
        var name: String?
        var nutritionBasis: String?
        var kcal100: Double?
        var protein100: Double?
        var carbs100: Double?
        var fat100: Double?
        var fibre100: Double?
        var salt100: Double?

        init(
            name: String? = nil,
            nutritionBasis: String? = nil,
            kcal100: Double? = nil,
            protein100: Double? = nil,
            carbs100: Double? = nil,
            fat100: Double? = nil,
            fibre100: Double? = nil,
            salt100: Double? = nil
        ) {
            self.name = name
            self.nutritionBasis = nutritionBasis
            self.kcal100 = kcal100
            self.protein100 = protein100
            self.carbs100 = carbs100
            self.fat100 = fat100
            self.fibre100 = fibre100
            self.salt100 = salt100
        }

        init(_ food: Food) {
            self.init(
                name: food.name,
                nutritionBasis: food.nutritionBasis,
                kcal100: food.kcal100,
                protein100: food.protein100,
                carbs100: food.carbs100,
                fat100: food.fat100,
                fibre100: food.fibre100,
                salt100: food.salt100
            )
        }
    }

    /* Whole foods whose water content is stable enough to key off the name, in
       every language the app ships. Swiss FSVO V7.1 unless noted. */
    private static let namedWater: [(water: Double, pattern: String)] = [
        (99.5, "water|wasser|eau|acqua|apă|apa|น้ำเปล่า"),
        (96.0, "cucumber|gurke|concombre|cetriolo|castravete|แตงกวา"),
        (95.3, "celery|sellerie|céleri|sedano|țelină|telina|คื่นช่าย"),
        (94.0, "tomato|tomatoes|tomate|tomaten|pomodoro|roșie|rosie|มะเขือเทศ"),
        (92.0, "courgette|zucchini|zucchine|dovlecel|บวบ"),
        (91.5, "watermelon|wassermelone|pastèque|anguria|pepene verde|แตงโม"),
        (90.9, "lettuce|salat|kopfsalat|laitue|lattuga|salată verde|ผักกาดหอม"),
        (90.4, "broccoli|brokkoli|brocoli|broccolo|บรอกโคลี"),
        (89.1, "strawberry|strawberries|erdbeere|fraise|fragola|căpșun|capsun|สตรอว์เบอร์รี"),
        (88.1, "orange|orangen|arancia|portocal|ส้ม"),
        (87.9, "papaya|papaye|มะละกอ"),
        (87.4, "milk|milch|lait|latte|lapte|นม"),
        (85.6, "apple|apfel|äpfel|pomme|mela|măr|mar|แอปเปิล"),
        (85.5, "yoghurt|yogurt|joghurt|iaurt|โยเกิร์ต"),
        (84.2, "carrot|karotte|möhre|carotte|carota|morcov|แครอท"),
        (75.0, "banana|banane|banană|กล้วย"),
    ]

    private static let dryProduct = "powder|pulver|poudre|polvere|pudră|dried|getrocknet|séché|essiccato|uscat|concentrate|konzentrat|oil|öl|huile|olio|ulei|freeze[- ]dried|instant|isolate|isolat"

    private static func matches(_ name: String, _ alternatives: String) -> Bool {
        let pattern = "(^|[^a-z])(\(alternatives))([^a-z]|$)"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /* Ash, the mineral residue, is not stored on a food row, so it comes from a
       small table keyed on macro shape. Conventional composition-table values;
       the error is under a gram per 100 g. */
    private static func estimateAsh(_ input: Input) -> Double {
        if let salt = input.salt100, salt > 0 {
            return min(20, max(0.5, salt * 1.1))
        }
        let protein = input.protein100 ?? 0
        let fat = input.fat100 ?? 0
        if protein >= 60 { return 3.5 }
        if protein >= 15 && fat <= 12 { return 1.2 }
        if fat >= 50 { return 1.8 }
        return 0.9
    }

    /// How much of 100 g is not already claimed by macros and minerals.
    private static func headroom(_ input: Input) -> Double {
        guard let protein = input.protein100,
              let carbs = input.carbs100,
              let fat = input.fat100 else { return 100 }
        return max(0, 100 - (protein + carbs + fat + estimateAsh(input)))
    }

    /// Water by difference, or nil when the composition cannot support the sum.
    static func waterByDifference(_ input: Input) -> Double? {
        guard let protein = input.protein100,
              let carbs = input.carbs100,
              let fat = input.fat100 else { return nil }
        /* A pressed or refined oil is fat all the way down; residual water sits
           below 0.1 g and is reported as none rather than left unknown. */
        let perML = input.nutritionBasis == "per_100ml"
        if fat >= (perML ? 80 : 90) && protein + carbs <= 2 { return 0 }
        /* Difference arithmetic assumes 100 g. A per-100 ml row only obeys it
           when the liquid is about as dense as water; a fatty liquid's missing
           grams are density, not water. */
        if perML && fat >= 20 { return nil }
        let ash = estimateAsh(input)
        let fibre = input.fibre100 ?? 0
        /* Europe reports available carbohydrate with fibre listed separately;
           the USDA reports carbohydrate by difference, fibre included. Both
           conventions appear in one catalogue, so the row's own energy decides
           which it uses: score it against Atwater under each and keep the
           closer reading. Without an energy figure, assume fibre is separate,
           which is both the commoner case here and the reading that never
           overstates hydration. */
        var carbsExcludeFibre = fibre > 0
        if fibre > 0, let kcal = input.kcal100, kcal > 0 {
            let asExcluded = 4 * protein + 4 * carbs + 9 * fat + 2 * fibre
            let asIncluded = 4 * protein + 4 * (carbs - fibre) + 9 * fat + 2 * fibre
            carbsExcludeFibre = abs(asExcluded - kcal) <= abs(asIncluded - kcal)
        }
        let solids = protein + carbs + fat + ash + (carbsExcludeFibre ? fibre : 0)
        let candidate = 100 - solids
        guard candidate.isFinite else { return nil }
        return min(100, max(0, (candidate * 10).rounded() / 10))
    }

    /// Best available water content for a food, with the basis it rests on.
    static func estimate(_ input: Input, measured: Double? = nil) -> Estimate? {
        if let measured, measured.isFinite, measured >= 0 {
            return Estimate(waterML100: min(100, measured), basis: .measured)
        }
        let name = (input.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, !matches(name, dryProduct) {
            let room = headroom(input)
            /* A name is only a hint. "Tuna in water" and "milk chocolate" both
               carry a water-dense word while being mostly something else, so
               the guess survives only if the macros leave room for it. */
            if let match = namedWater.first(where: { matches(name, $0.pattern) }), match.water <= room {
                return Estimate(waterML100: match.water, basis: .name)
            }
        }
        guard let derived = waterByDifference(input) else { return nil }
        return Estimate(waterML100: derived, basis: .difference)
    }

    /// Millilitres of water in a portion of a food.
    static func portionWater(_ waterPer100: Double?, equivalentAmount: Double) -> Double? {
        guard let waterPer100, waterPer100.isFinite else { return nil }
        guard equivalentAmount.isFinite, equivalentAmount > 0 else { return 0 }
        return (waterPer100 * equivalentAmount).rounded() / 100
    }

    /// A food with its water filled in, so a scanned or hand-entered product
    /// still contributes hydration.
    static func resolved(_ food: Food) -> Food {
        if food.waterML100 != nil {
            guard food.waterBasis == nil else { return food }
            var legacy = food
            legacy.waterBasis = Basis.legacy.rawValue
            return legacy
        }
        guard let estimate = estimate(Input(food)) else { return food }
        var updated = food
        updated.waterML100 = estimate.waterML100
        updated.waterBasis = estimate.basis.rawValue
        return updated
    }

    /*
     * Food water is real intake - EFSA puts it at roughly a fifth to a third of
     * the total - but it is not interchangeable with drinking. The drink target
     * stays the target; food water is reported beside it, never folded in.
     */
    struct Breakdown: Hashable, Sendable {
        let drinkL: Double
        let foodL: Double
        let totalL: Double
    }

    static func breakdown(drinkL: Double, foodML: Double) -> Breakdown {
        let drink = drinkL.isFinite && drinkL > 0 ? drinkL : 0
        let food = foodML.isFinite && foodML > 0 ? foodML / 1000 : 0
        return Breakdown(
            drinkL: (drink * 100).rounded() / 100,
            foodL: (food * 100).rounded() / 100,
            totalL: ((drink + food) * 100).rounded() / 100
        )
    }
}

/*
 * HealthKit is the exchange ledger, while APEX keeps drinks and food water as
 * separate facts. The classification and delta merge live outside HealthKit
 * so the no-double-count contract is deterministic and testable.
 */
enum HydrationReconciliation {
    enum Source: Hashable, Sendable {
        case apexPhone
        case apexWatch
        case apexFood
        case external
    }

    struct Sample: Hashable, Sendable {
        let liters: Double
        let source: Source
    }

    static let phoneBundleIdentifier = "ch.apexperformance.APEX"
    static let watchBundleIdentifier = "ch.apexperformance.APEX.watchkitapp"
    static let foodMetadataKey = HydrationMetadata.kind
    static let foodMetadataValue = "food"
    static let eventIDMetadataKey = HydrationMetadata.eventID
    static let paletteMetadataKey = HydrationMetadata.palette
    static let iconMetadataKey = HydrationMetadata.icon

    static func importableDrinkLiters(_ samples: [Sample]) -> Double {
        samples.reduce(0) { total, sample in
            guard sample.liters.isFinite, sample.liters > 0 else { return total }
            switch sample.source {
            case .apexWatch, .external:
                return total + sample.liters
            case .apexPhone, .apexFood:
                return total
            }
        }
    }

    static func mergedDrinkLiters(
        localDrinkLiters: Double,
        previousImportableLiters: Double,
        currentImportableLiters: Double
    ) -> Double {
        let local = localDrinkLiters.isFinite ? localDrinkLiters : 0
        let previous = previousImportableLiters.isFinite ? previousImportableLiters : 0
        let current = currentImportableLiters.isFinite ? currentImportableLiters : 0
        let merged = local + (current - previous)
        return min(6, max(0, (merged * 100).rounded() / 100))
    }

    static func foodSyncIdentifier(accountID: UUID, dateKey: String) -> String {
        "apex.hydration.food.\(accountID.uuidString.lowercased()).\(dateKey)"
    }

    static func canDeleteOnWatch(
        sourceBundleIdentifier: String,
        syncIdentifier: String? = nil
    ) -> Bool {
        WatchHydrationAuthorship.canDelete(
            sourceBundleIdentifier: sourceBundleIdentifier,
            syncIdentifier: syncIdentifier
        )
    }
}

enum NutrientCategory: String, CaseIterable, Hashable, Sendable {
    case vitamins
    case minerals
    case fats
    case carbohydrates
    case other
}

enum NutritionFactSectionKind: String, CaseIterable, Hashable, Sendable {
    case facts
    case vitamins
    case minerals
}

struct NutritionFactDisplayRow: Equatable, Hashable, Sendable {
    let observation: NutrientEvidenceObservation
    let label: String
    let depth: Int
}

struct NutritionFactDisplaySection: Equatable, Hashable, Sendable {
    let kind: NutritionFactSectionKind
    let rows: [NutritionFactDisplayRow]
}

enum FoodNutrientEvidence {
    private static let categoryOrder = NutrientCategory.allCases
    private static let maximumNaturalEvidenceRows = 96
    private static let maximumNaturalEvidenceBytes = 65_536
    private static let maximumNaturalEvidenceTargets = 256
    private static let maximumNaturalEvidenceResourceBytes = 4_194_304

    /// Canonicalizes only dimensionally explicit units. Vitamin-equivalent
    /// semantics remain attached because RE, RAE, alpha-TE and plain mass are
    /// not interchangeable values. Opaque publisher units fail closed.
    static func canonicalUnit(_ rawUnit: String) -> String? {
        let unit = rawUnit
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard unit.isEmpty == false else { return nil }
        let basis = #"(?:\s*(?:/|per)\s*100\s*(?:g|ml))?"#
        if unitMatches(unit, #"^(?:kcal|kilocalories?)"# + basis + "$") { return "kcal" }
        if unitMatches(unit, #"^(?:g|grams?)"# + basis + "$") { return "g" }
        if unitMatches(unit, #"^(?:mg|milligrams?)"# + basis + "$") { return "mg" }
        if unitMatches(unit, #"^(?:µg|ug|mcg|micrograms?)"# + basis + "$") { return "µg" }
        if unitMatches(unit, #"^(?:ml|millilit(?:er|re)s?)"# + basis + "$") { return "ml" }
        if unitMatches(unit, #"^i\.?\s*u\.?"# + basis + "$") { return "IU" }

        let micro = #"(?:µg|ug|mcg|micrograms?)"#
        if let match = unitCapture(unit, "^" + micro + #"\s+(re|rae)"# + basis + "$") {
            return "µg \(match.uppercased())"
        }
        if let match = unitCapture(
            unit,
            #"^(re|rae)\s*\(\s*"# + micro + basis + #"\s*\)$"#
        ) {
            return "µg \(match.uppercased())"
        }

        let alphaTE = #"(?:α|alpha|alfa)[\s-]*te"#
        if unitMatches(unit, #"^(?:mg|milligrams?)\s*"# + alphaTE + basis + "$")
            || unitMatches(unit, "^" + alphaTE + basis + "$") {
            return "mg α-TE"
        }
        return nil
    }

    static func canonicalized(
        _ observation: NutrientEvidenceObservation
    ) -> NutrientEvidenceObservation? {
        guard let unit = canonicalUnit(observation.unit) else { return nil }
        return NutrientEvidenceObservation(
            nutrientCode: observation.nutrientCode,
            name: observation.name,
            valuePer100: observation.valuePer100,
            unit: unit,
            observationStatus: observation.observationStatus,
            originalValueText: observation.originalValueText,
            derivationMethod: observation.derivationMethod,
            sourceKey: observation.sourceKey,
            sourceReference: observation.sourceReference
        )
    }

    private static func unitMatches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func unitCapture(_ value: String, _ pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private struct NaturalEvidenceEntry: Decodable {
        let aliases: [NaturalEvidenceAlias]
        let category: String
        let donor: NaturalEvidenceDonor
        let evidence: [NutrientEvidenceObservation]
        let target: NaturalEvidenceIdentity
    }

    private struct NaturalEvidenceDonor: Decodable {
        let id: String
        let name: String
        let sourceKey: String
        let sourceRecordID: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case sourceKey = "source_key"
            case sourceRecordID = "source_record_id"
        }
    }

    private struct NaturalEvidenceIdentity: Decodable {
        let id: String
        let name: String
        let providerProductID: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case providerProductID = "provider_product_id"
        }
    }

    private struct NaturalEvidenceAlias: Decodable {
        let kind: String
        let id: String
        let providerProductID: String
        let nutritionBasis: String
        let preparationState: String
        let fingerprint: NaturalEvidenceFingerprint

        enum CodingKeys: String, CodingKey {
            case kind, id, fingerprint
            case providerProductID = "provider_product_id"
            case nutritionBasis = "nutrition_basis"
            case preparationState = "preparation_state"
        }
    }

    private struct NaturalEvidenceFingerprint: Decodable {
        let kcal100: Double
        let protein100: Double
        let carbs100: Double
        let fat100: Double

        enum CodingKeys: String, CodingKey {
            case kcal100 = "kcal_100"
            case protein100 = "protein_100"
            case carbs100 = "carbs_100"
            case fat100 = "fat_100"
        }
    }

    private struct NaturalEvidenceCandidate {
        let alias: NaturalEvidenceAlias
        let evidence: [NutrientEvidenceObservation]
    }

    private static let bundledNaturalEvidenceIndex: [String: [NaturalEvidenceCandidate]]? = {
        guard let data = naturalFoodEvidenceResourceData() else { return nil }
        return naturalEvidenceIndex(from: data)
    }()

    private enum Code: String {
        case vitaminPrefix = "VIT"
        case energy = "ENERC_KCAL"
        case protein = "PROT"
        case carbohydrate = "CHOAVL"
        case fat = "FAT"
        case transFat = "FATRN"
        case monounsaturatedFat = "FAMS"
        case polyunsaturatedFat = "FAPU"
        case omegaPrefix = "OMEGA"
        case cholesterol = "CHOLE"
        case sodium = "NA"
        case fibre = "FIBT"
        case sugar = "SUGAR"
        case addedSugar = "SUGAR_ADDED"
        case starch = "STARCH"
        case saturatedFat = "FASAT"
        case salt = "NACL"
        case water = "WATER"
    }

    /// Stable localization keys for nutrient identifiers. Dataset-specific
    /// English descriptions remain evidence metadata, never interface copy.
    private static let displayKeys: [String: String] = [
        "BIOT": "Biotin (B7)",
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
        "FOL": "Folate (B9)",
        "I": "Iodine",
        "K": "Potassium",
        "MG": "Magnesium",
        "MN": "Manganese",
        "NA": "Sodium",
        "NACL": "Salt",
        "NIA": "Niacin (B3)",
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
        "PANTAC": "Pantothenic acid (B5)",
        "PROT": "Protein",
        "RIBF": "Riboflavin (B2)",
        "SALT": "Salt",
        "SE": "Selenium",
        "STARCH": "Starch",
        "SUGAR": "Total sugars",
        "SUGAR_ADDED": "Added sugars",
        "THIA": "Thiamin (B1)",
        "VITA": "Vitamin A",
        "VITB1": "Thiamin (B1)",
        "VITB12": "Vitamin B12",
        "VITB2": "Riboflavin (B2)",
        "VITB3": "Niacin (B3)",
        "VITB5": "Pantothenic acid (B5)",
        "VITB6": "Vitamin B6",
        "VITB6A": "Vitamin B6",
        "VITB7": "Biotin (B7)",
        "VITB9": "Folate (B9)",
        "VITC": "Vitamin C",
        "VITD": "Vitamin D",
        "VITE": "Vitamin E",
        "VITK": "Vitamin K",
        "WATER": "Water",
        "ZN": "Zinc"
    ]

    static func displayKey(for nutrientCode: String) -> String {
        displayKeys[nutrientCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
            ?? "Other nutrient"
    }

    static func category(_ observation: NutrientEvidenceObservation) -> NutrientCategory {
        let code = observation.nutrientCode.uppercased()
        let name = observation.name.lowercased()
        if code.hasPrefix(Code.vitaminPrefix.rawValue)
            || name.range(of: #"vitamin|retinol|carotene|thiam|riboflav|niacin|folate|folic|cobalamin|tocopher|biotin|pantothen"#, options: .regularExpression) != nil {
            return .vitamins
        }
        if code.range(of: #"^(CA|FE|MG|P|K|NA|ZN|CU|MN|SE|I|CL|F)$"#, options: .regularExpression) != nil
            || name.range(of: #"calcium|iron|magnesium|phosph|potassium|sodium|zinc|copper|manganese|selenium|iodine|chloride|fluoride|mineral"#, options: .regularExpression) != nil {
            return .minerals
        }
        if code.range(of: #"^(FASAT|FAMS|FAPU|FATRN|CHOLE|OMEGA)"#, options: .regularExpression) != nil
            || name.range(of: #"saturat|monounsaturat|polyunsaturat|trans fat|cholesterol|omega-|fatty acid"#, options: .regularExpression) != nil {
            return .fats
        }
        if code.range(of: #"^(SUGAR|SUGAR_ADDED|FIBT|STARCH)"#, options: .regularExpression) != nil
            || name.range(of: #"sugar|fibre|fiber|starch"#, options: .regularExpression) != nil {
            return .carbohydrates
        }
        return .other
    }

    static func nutritionFactSections(
        _ observations: [NutrientEvidenceObservation]
    ) -> [NutritionFactDisplaySection] {
        let canonical = observations.compactMap(canonicalized)
        let groups: [(NutritionFactSectionKind, [NutrientEvidenceObservation])] = [
            (.facts, canonical.filter {
                let category = category($0)
                return category != .vitamins && category != .minerals
            }),
            (.vitamins, canonical.filter { category($0) == .vitamins }),
            (.minerals, canonical.filter { category($0) == .minerals })
        ]
        return groups.compactMap { kind, observations in
            guard !observations.isEmpty else { return nil }
            let rows = observations.sorted { left, right in
                if kind == .facts {
                    let leftPriority = nutritionFactPriority(left)
                    let rightPriority = nutritionFactPriority(right)
                    if leftPriority != rightPriority { return leftPriority < rightPriority }
                }
                let labelOrder = nutritionFactLabel(left)
                    .localizedCaseInsensitiveCompare(nutritionFactLabel(right))
                if labelOrder != .orderedSame { return labelOrder == .orderedAscending }
                return left.unit < right.unit
            }.map { observation in
                NutritionFactDisplayRow(
                    observation: observation,
                    label: nutritionFactLabel(observation),
                    depth: kind == .facts ? nutritionFactDepth(observation) : 0
                )
            }
            return NutritionFactDisplaySection(kind: kind, rows: rows)
        }
    }

    private static func nutritionFactLabel(_ observation: NutrientEvidenceObservation) -> String {
        displayKey(for: observation.nutrientCode)
    }

    private static func nutritionFactDepth(_ observation: NutrientEvidenceObservation) -> Int {
        let code = observation.nutrientCode.uppercased()
        let detailCodes: Set<String> = [
            Code.saturatedFat.rawValue,
            Code.transFat.rawValue,
            Code.monounsaturatedFat.rawValue,
            Code.polyunsaturatedFat.rawValue,
            Code.fibre.rawValue,
            Code.sugar.rawValue,
            Code.addedSugar.rawValue,
            Code.starch.rawValue
        ]
        if detailCodes.contains(code) || code.hasPrefix(Code.omegaPrefix.rawValue) {
            return 1
        }
        return 0
    }

    private static func nutritionFactPriority(_ observation: NutrientEvidenceObservation) -> Int {
        let code = observation.nutrientCode.uppercased()
        switch code {
        case Code.energy.rawValue: return 0
        case Code.fat.rawValue: return 10
        case Code.saturatedFat.rawValue: return 11
        case Code.transFat.rawValue: return 12
        case Code.monounsaturatedFat.rawValue: return 13
        case Code.polyunsaturatedFat.rawValue: return 14
        case let value where value.hasPrefix(Code.omegaPrefix.rawValue): return 15
        case Code.cholesterol.rawValue: return 20
        case Code.sodium.rawValue: return 30
        case Code.salt.rawValue: return 31
        case Code.carbohydrate.rawValue: return 40
        case Code.fibre.rawValue: return 41
        case Code.sugar.rawValue: return 42
        case Code.addedSugar.rawValue: return 43
        case Code.starch.rawValue: return 44
        case Code.protein.rawValue: return 50
        case Code.water.rawValue: return 60
        default: return 100
        }
    }

    static func observations(for food: Food) -> [NutrientEvidenceObservation] {
        let status: NutrientObservationStatus = food.source == "open_food_facts"
            || food.confidence == "provider_verified" ? .reported : .estimated
        let facts: [(String, String, Double?, String)] = [
            (Code.energy.rawValue, "Energy", food.kcal100, "kcal"),
            (Code.protein.rawValue, "Protein", food.protein100, "g"),
            (Code.carbohydrate.rawValue, "Carbohydrate", food.carbs100, "g"),
            (Code.fat.rawValue, "Fat", food.fat100, "g"),
            (Code.fibre.rawValue, "Dietary fibre", food.fibre100, "g"),
            (Code.sugar.rawValue, "Total sugars", food.sugar100, "g"),
            (Code.saturatedFat.rawValue, "Saturated fat", food.saturatedFat100, "g"),
            (Code.salt.rawValue, "Salt", food.salt100, "g"),
            (Code.water.rawValue, "Water", food.waterML100, "ml")
        ]
        let canonicalFacts = facts.compactMap { code, name, value, unit -> NutrientEvidenceObservation? in
            guard let value, value.isFinite, value >= 0 else { return nil }
            return NutrientEvidenceObservation(
                nutrientCode: code,
                name: name,
                valuePer100: value,
                unit: unit,
                observationStatus: status,
                originalValueText: String(value),
                derivationMethod: nil,
                sourceKey: food.source,
                sourceReference: food.providerProductID
            )
        }
        /* The amount card and immutable log use the canonical Food totals.
           Exact donor evidence may add micronutrients and detail facts, but it
           must never surface a second calorie or macro truth. */
        let canonicalCodes = Set(canonicalFacts.map { $0.nutrientCode.uppercased() })
        var rows = (food.nutrientEvidence ?? []).filter {
            canonicalCodes.contains($0.nutrientCode.uppercased()) == false
        }.compactMap(canonicalized)
        rows.append(contentsOf: canonicalFacts)
        return rows.sorted { left, right in
            let leftCategory = categoryOrder.firstIndex(of: category(left)) ?? categoryOrder.count
            let rightCategory = categoryOrder.firstIndex(of: category(right)) ?? categoryOrder.count
            if leftCategory != rightCategory { return leftCategory < rightCategory }
            if left.name != right.name { return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending }
            return left.unit < right.unit
        }
    }

    static func naturalFoodEvidenceResourceData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: "natural-food-evidence", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Applies one generated whole official record to either exact reviewed
    /// alias. Display names never authorize a link, and existing target
    /// evidence remains whole without donor gap-filling.
    static func overlayBundledNaturalFoodEvidence(
        _ foods: [Food],
        resourceData: Data? = nil
    ) -> [Food] {
        let candidatesByIdentity: [String: [NaturalEvidenceCandidate]]?
        if let resourceData {
            candidatesByIdentity = naturalEvidenceIndex(from: resourceData)
        } else {
            candidatesByIdentity = bundledNaturalEvidenceIndex
        }
        guard let candidatesByIdentity else { return foods }

        return foods.map { food in
            guard (food.nutrientEvidence ?? []).isEmpty,
                  food.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let providerProductID = food.providerProductID,
                  providerProductID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  food.ownerUserID == nil,
                  food.brand == nil,
                  food.barcode == nil,
                  food.source == "apex_cache"
            else { return food }
            let key = naturalEvidenceAliasKey(id: food.id, providerProductID: providerProductID)
            guard let candidates = candidatesByIdentity[key], candidates.count == 1 else { return food }
            let candidate = candidates[0]
            guard candidate.alias.id == food.id,
                  candidate.alias.providerProductID == providerProductID,
                  candidate.alias.nutritionBasis == food.nutritionBasis,
                  candidate.alias.preparationState == food.preparationState,
                  naturalEvidenceFingerprintMatches(food, candidate.alias.fingerprint)
            else { return food }
            var enriched = food
            enriched.nutrientEvidence = candidate.evidence.map { $0 }
            return enriched
        }
    }

    private static func naturalEvidenceIndex(
        from data: Data
    ) -> [String: [NaturalEvidenceCandidate]]? {
        guard data.count <= maximumNaturalEvidenceResourceBytes,
              let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any],
              object["schema_version"] as? Int == 1,
              let rawTargets = object["targets"] as? [Any],
              rawTargets.count <= maximumNaturalEvidenceTargets
        else { return nil }

        let decoder = JSONDecoder()
        var candidatesByIdentity: [String: [NaturalEvidenceCandidate]] = [:]
        for rawValue in rawTargets {
            guard let rawTarget = rawValue as? [String: Any],
                  let rawEvidence = rawTarget["evidence"] as? [Any],
                  rawEvidence.isEmpty == false,
                  rawEvidence.count <= maximumNaturalEvidenceRows,
                  rawEvidence.allSatisfy({ rawObservation in
                      guard let rawObservation = rawObservation as? [String: Any] else { return false }
                      return rawObservation.keys.contains("value_per_100")
                  }),
                  let rawEvidenceData = try? JSONSerialization.data(withJSONObject: rawEvidence),
                  rawEvidenceData.count <= maximumNaturalEvidenceBytes,
                  let rawEntryData = try? JSONSerialization.data(withJSONObject: rawTarget),
                  let entry = try? decoder.decode(NaturalEvidenceEntry.self, from: rawEntryData)
            else { continue }
            let donorProviderID = [
                "corpus", entry.donor.sourceKey, entry.donor.sourceRecordID
            ].joined(separator: ":")
            guard entry.evidence.isEmpty == false,
                  entry.evidence.count <= maximumNaturalEvidenceRows,
                  entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.donor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.donor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.donor.sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.donor.sourceRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.target.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.target.providerProductID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  entry.evidence.allSatisfy({
                      guard $0.sourceKey == entry.donor.sourceKey,
                            let reference = $0.sourceReference
                      else { return false }
                      return $0.nutrientCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && canonicalUnit($0.unit) != nil
                          && ($0.valuePer100.map {
                              $0.isFinite && (0...1_000_000_000_000).contains($0)
                          } ?? true)
                          && reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                  }),
                  entry.aliases.count == 2,
                  Set(entry.aliases.map(\.kind)) == Set(["target", "donor"]),
                  entry.aliases.allSatisfy({
                      $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && $0.providerProductID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && $0.nutritionBasis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && $0.preparationState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                          && $0.fingerprint.kcal100.isFinite
                          && $0.fingerprint.protein100.isFinite
                          && $0.fingerprint.carbs100.isFinite
                          && $0.fingerprint.fat100.isFinite
                  }),
                  entry.aliases.contains(where: {
                      $0.kind == "target"
                          && $0.id == entry.target.id
                          && $0.providerProductID == entry.target.providerProductID
                  }),
                  entry.aliases.contains(where: {
                      $0.kind == "donor"
                          && $0.id == entry.donor.id
                          && $0.providerProductID == donorProviderID
                  })
            else { continue }
            for alias in entry.aliases {
                guard alias.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                      alias.providerProductID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                else { continue }
                let key = naturalEvidenceAliasKey(id: alias.id, providerProductID: alias.providerProductID)
                candidatesByIdentity[key, default: []].append(
                    NaturalEvidenceCandidate(alias: alias, evidence: entry.evidence)
                )
            }
        }
        return candidatesByIdentity
    }

    private static func naturalEvidenceAliasKey(id: String, providerProductID: String) -> String {
        "\(id)\u{0}\(providerProductID)"
    }

    private static func naturalEvidenceFingerprintMatches(
        _ food: Food,
        _ fingerprint: NaturalEvidenceFingerprint
    ) -> Bool {
        let fields = [
            (food.kcal100, fingerprint.kcal100, 1.0),
            (food.protein100, fingerprint.protein100, 0.05),
            (food.carbs100, fingerprint.carbs100, 0.05),
            (food.fat100, fingerprint.fat100, 0.05)
        ]
        return fields.allSatisfy { actual, reviewed, absoluteTolerance in
            guard let actual, actual.isFinite, reviewed.isFinite else { return false }
            return abs(actual - reviewed) <= max(absoluteTolerance, abs(reviewed) * 0.02)
        }
    }

    /// Coalesces evidence into the local curated row only for one exact,
    /// compatible public server copy. Search names are intentionally absent
    /// from this approval path, and explicit local evidence remains whole.
    static func enrichLocalFoods(_ localFoods: [Food], with serverFoods: [Food]) -> [Food] {
        localFoods.map { localFood in
            guard (localFood.nutrientEvidence ?? []).isEmpty else { return localFood }
            let donors = serverFoods.filter { serverFood in
                guard (serverFood.nutrientEvidence ?? []).isEmpty == false else { return false }
                return hasExactCompatibleIdentity(localFood, serverFood)
            }
            guard donors.count == 1, let evidence = donors[0].nutrientEvidence else { return localFood }
            var enriched = localFood
            enriched.nutrientEvidence = evidence.map { $0 }
            return enriched
        }
    }

    /// Keeps the local read model canonical while removing a matching server
    /// duplicate only after its compatible evidence has been coalesced.
    static func mergeLocalSearchFoods(_ localFoods: [Food], with serverFoods: [Food]) -> [Food] {
        let serverEnrichedLocalFoods = enrichLocalFoods(localFoods, with: serverFoods)
        let bundledLocalFoods = overlayBundledNaturalFoodEvidence(serverEnrichedLocalFoods)
        let bundledServerFoods = overlayBundledNaturalFoodEvidence(serverFoods)
        var seen = Set(bundledLocalFoods.map { $0.providerProductID ?? $0.barcode ?? $0.id.lowercased() })
        return bundledLocalFoods + bundledServerFoods.filter { food in
            seen.insert(food.providerProductID ?? food.barcode ?? food.id.lowercased()).inserted
        }
    }

    private static func hasExactCompatibleIdentity(_ localFood: Food, _ serverFood: Food) -> Bool {
        guard localFood.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let providerID = localFood.providerProductID,
              providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              localFood.id == serverFood.id,
              providerID == serverFood.providerProductID,
              localFood.ownerUserID == nil,
              localFood.brand == nil,
              localFood.barcode == nil,
              localFood.source == "apex_cache",
              serverFood.ownerUserID == nil,
              serverFood.brand == nil,
              serverFood.barcode == nil,
              serverFood.source == "apex_cache",
              localFood.nutritionBasis == serverFood.nutritionBasis,
              localFood.preparationState == serverFood.preparationState
        else { return false }
        let macroFingerprint = [
            (localFood.kcal100, serverFood.kcal100, 1.0),
            (localFood.protein100, serverFood.protein100, 0.05),
            (localFood.carbs100, serverFood.carbs100, 0.05),
            (localFood.fat100, serverFood.fat100, 0.05)
        ]
        return macroFingerprint.allSatisfy { localValue, serverValue, absoluteTolerance in
            guard let localValue,
                  let serverValue,
                  localValue.isFinite,
                  serverValue.isFinite
            else { return false }
            return abs(localValue - serverValue) <= max(absoluteTolerance, abs(localValue) * 0.02)
        }
    }
}

enum NutrientPatternPeriod: String, CaseIterable, Hashable, Sendable {
    case day
    case week
    case month
}

struct NutrientPatternWindow: Equatable, Hashable, Sendable {
    let start: String
    let end: String
    let calendarDays: Int
}

struct NutrientPatternMeal: Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let localDate: String
}

struct NutrientPatternEntry: Hashable, Sendable {
    let mealID: UUID
    let userID: UUID
    let equivalentAmount: Double
    let evidence: [NutrientEvidenceObservation]
}

struct NutrientPatternRow: Equatable, Hashable, Sendable {
    let nutrientCode: String
    let name: String
    let unit: String
    let category: NutrientCategory
    let total: Double
    let averagePerObservedDay: Double
    let observedFoodEntries: Int
}

struct NutrientPatternSummary: Equatable, Sendable {
    let window: NutrientPatternWindow
    let calendarDays: Int
    let observedDays: Int
    let totalFoodEntries: Int
    let evidenceFoodEntries: Int
    let coverage: Double
    let rows: [NutrientPatternRow]
}

enum NutrientPatternEngine {
    /// Coverage requires at least one valid immutable fact beyond calories
    /// and the three core macros. Fibre, sugars, fat detail, salt, water,
    /// vitamins, minerals and other secondary nutrients qualify. Trace and
    /// below-detection observations are evidence, but never numeric intake.
    private static let coreNutritionCodes: Set<String> = [
        "ENERC_KCAL", "PROT", "CHOAVL", "FAT"
    ]

    private struct MutableRow {
        var nutrientCode: String
        var name: String
        var unit: String
        var category: NutrientCategory
        var total: Double
        var observedFoodEntries: Int
        var observedDates: Set<String>
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func window(anchorDate: String, period: NutrientPatternPeriod) -> NutrientPatternWindow {
        guard let anchor = date(anchorDate) else {
            return NutrientPatternWindow(start: anchorDate, end: anchorDate, calendarDays: 1)
        }
        switch period {
        case .day:
            return NutrientPatternWindow(start: anchorDate, end: anchorDate, calendarDays: 1)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
            return NutrientPatternWindow(start: dateKey(start), end: anchorDate, calendarDays: 7)
        case .month:
            let components = calendar.dateComponents([.year, .month, .day], from: anchor)
            let start = String(format: "%04d-%02d-01", components.year ?? 0, components.month ?? 0)
            return NutrientPatternWindow(start: start, end: anchorDate, calendarDays: components.day ?? 1)
        }
    }

    static func summarize(
        meals: [NutrientPatternMeal],
        entries: [NutrientPatternEntry],
        ownerID: UUID,
        anchorDate: String,
        period: NutrientPatternPeriod
    ) -> NutrientPatternSummary {
        let window = window(anchorDate: anchorDate, period: period)
        let eligibleMeals = Dictionary(uniqueKeysWithValues: meals.compactMap { meal -> (UUID, String)? in
            guard meal.userID == ownerID,
                  meal.localDate >= window.start,
                  meal.localDate <= window.end else { return nil }
            return (meal.id, meal.localDate)
        })
        let eligibleEntries = entries.filter { entry in
            entry.userID == ownerID && eligibleMeals[entry.mealID] != nil
        }
        let observedDays = Set(eligibleEntries.compactMap { eligibleMeals[$0.mealID] }).count
        var evidenceFoodEntries = 0
        var groups: [String: MutableRow] = [:]
        for entry in eligibleEntries {
            let localDate = eligibleMeals[entry.mealID]!
            let usable = entry.evidence.compactMap { observation -> (NutrientEvidenceObservation, Double)? in
                guard let canonical = FoodNutrientEvidence.canonicalized(observation),
                      canonical.observationStatus == .measured
                        || canonical.observationStatus == .calculated
                        || canonical.observationStatus == .estimated
                        || canonical.observationStatus == .reported,
                      let value = canonical.valuePer100,
                      value.isFinite,
                      value >= 0 else { return nil }
                return (canonical, value * max(0, entry.equivalentAmount) / 100)
            }
            if entry.evidence.contains(where: isDetailedEvidence) { evidenceFoodEntries += 1 }
            var countedKeys = Set<String>()
            for (observation, amount) in usable {
                let key = "\(observation.nutrientCode.uppercased())|\(observation.unit)"
                var row = groups[key] ?? MutableRow(
                    nutrientCode: observation.nutrientCode,
                    name: FoodNutrientEvidence.displayKey(for: observation.nutrientCode),
                    unit: observation.unit,
                    category: FoodNutrientEvidence.category(observation),
                    total: 0,
                    observedFoodEntries: 0,
                    observedDates: []
                )
                row.total += amount
                if countedKeys.insert(key).inserted { row.observedFoodEntries += 1 }
                row.observedDates.insert(localDate)
                groups[key] = row
            }
        }
        let rows = groups.values.map { row in
            let divisor = Double(max(1, row.observedDates.count))
            return NutrientPatternRow(
                nutrientCode: row.nutrientCode,
                name: row.name,
                unit: row.unit,
                category: row.category,
                total: rounded(row.total),
                averagePerObservedDay: rounded(row.total / divisor),
                observedFoodEntries: row.observedFoodEntries
            )
        }.sorted { left, right in
            let leftCategory = NutrientCategory.allCases.firstIndex(of: left.category) ?? NutrientCategory.allCases.count
            let rightCategory = NutrientCategory.allCases.firstIndex(of: right.category) ?? NutrientCategory.allCases.count
            if leftCategory != rightCategory { return leftCategory < rightCategory }
            if left.averagePerObservedDay != right.averagePerObservedDay {
                return left.averagePerObservedDay > right.averagePerObservedDay
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
        return NutrientPatternSummary(
            window: window,
            calendarDays: window.calendarDays,
            observedDays: observedDays,
            totalFoodEntries: eligibleEntries.count,
            evidenceFoodEntries: evidenceFoodEntries,
            coverage: eligibleEntries.isEmpty ? 0 : Double(evidenceFoodEntries) / Double(eligibleEntries.count),
            rows: rows
        )
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    private static func isDetailedEvidence(_ observation: NutrientEvidenceObservation) -> Bool {
        guard FoodNutrientEvidence.canonicalUnit(observation.unit) != nil else { return false }
        let code = observation.nutrientCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard coreNutritionCodes.contains(code) == false else { return false }
        switch observation.observationStatus {
        case .measured, .calculated, .estimated, .reported:
            guard let value = observation.valuePer100 else { return false }
            return value.isFinite && value >= 0
        case .trace, .belowDetection:
            return observation.valuePer100 == nil
        case .notMeasured, .missing:
            return false
        }
    }
}
