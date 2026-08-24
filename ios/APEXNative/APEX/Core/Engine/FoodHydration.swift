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
    static let foodMetadataKey = "ch.apexperformance.APEX.hydration.kind"
    static let foodMetadataValue = "food"

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

    static func canDeleteOnWatch(sourceBundleIdentifier: String) -> Bool {
        sourceBundleIdentifier == watchBundleIdentifier
    }
}
