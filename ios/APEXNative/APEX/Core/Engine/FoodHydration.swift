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
        let groups: [(NutritionFactSectionKind, [NutrientEvidenceObservation])] = [
            (.facts, observations.filter {
                let category = category($0)
                return category != .vitamins && category != .minerals
            }),
            (.vitamins, observations.filter { category($0) == .vitamins }),
            (.minerals, observations.filter { category($0) == .minerals })
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
        switch observation.nutrientCode.uppercased() {
        case Code.energy.rawValue: "Calories"
        case Code.fat.rawValue: "Total fat"
        case Code.carbohydrate.rawValue: "Total carbs"
        default: observation.name
        }
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
        var rows = food.nutrientEvidence ?? []
        var existing = Set(rows.map { $0.nutrientCode.uppercased() })
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
        for (code, name, value, unit) in facts {
            guard let value, value.isFinite, value >= 0, existing.insert(code).inserted else { continue }
            rows.append(NutrientEvidenceObservation(
                nutrientCode: code,
                name: name,
                valuePer100: value,
                unit: unit,
                observationStatus: status,
                originalValueText: String(value),
                derivationMethod: nil,
                sourceKey: food.source,
                sourceReference: food.providerProductID
            ))
        }
        return rows.sorted { left, right in
            let leftCategory = categoryOrder.firstIndex(of: category(left)) ?? categoryOrder.count
            let rightCategory = categoryOrder.firstIndex(of: category(right)) ?? categoryOrder.count
            if leftCategory != rightCategory { return leftCategory < rightCategory }
            if left.name != right.name { return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending }
            return left.unit < right.unit
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
    private struct MutableRow {
        var nutrientCode: String
        var name: String
        var unit: String
        var category: NutrientCategory
        var total: Double
        var observedFoodEntries: Int
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
            let usable = entry.evidence.compactMap { observation -> (NutrientEvidenceObservation, Double)? in
                guard observation.observationStatus == .measured
                        || observation.observationStatus == .calculated
                        || observation.observationStatus == .estimated
                        || observation.observationStatus == .reported,
                      let value = observation.valuePer100,
                      value.isFinite,
                      value >= 0 else { return nil }
                return (observation, value * max(0, entry.equivalentAmount) / 100)
            }
            if usable.isEmpty == false { evidenceFoodEntries += 1 }
            var countedKeys = Set<String>()
            for (observation, amount) in usable {
                let key = "\(observation.nutrientCode.uppercased())|\(observation.unit)"
                var row = groups[key] ?? MutableRow(
                    nutrientCode: observation.nutrientCode,
                    name: observation.name,
                    unit: observation.unit,
                    category: FoodNutrientEvidence.category(observation),
                    total: 0,
                    observedFoodEntries: 0
                )
                row.total += amount
                if countedKeys.insert(key).inserted { row.observedFoodEntries += 1 }
                groups[key] = row
            }
        }
        let divisor = Double(max(1, observedDays))
        let rows = groups.values.map { row in
            NutrientPatternRow(
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
}
