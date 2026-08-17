import Foundation

enum Persona: String, Codable, CaseIterable, Identifiable, Sendable {
    case iulian
    case june
    case matthew
    case constantine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iulian: "Iulian-Andrei"
        case .june: "June"
        case .matthew: "Matthew Hua"
        case .constantine: "Constantine"
        }
    }

    var subtitle: String {
        switch self {
        case .iulian: "Natural strength · Precision · Durability"
        case .june: "Strength · Grace · Growth"
        case .matthew: "Endurance · Clarity · Mastery"
        case .constantine: "Performance · Vision · Evolution"
        }
    }

    var portraitName: String { rawValue }
}

enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary
    case light
    case moderate
    case very
    case extra

    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .very: "Very active"
        case .extra: "Extra active"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .very: 1.725
        case .extra: 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Sendable {
    case recomp
    case maintain
    case bulk

    var title: String {
        switch self {
        case .recomp: "Lean recomp"
        case .maintain: "Maintain"
        case .bulk: "Lean bulk"
        }
    }

    var factor: Double {
        switch self {
        case .recomp: 0.89
        case .maintain: 1
        case .bulk: 1.07
        }
    }
}

struct CalibrationHistoryEntry: Codable, Hashable, Sendable {
    let appliedAt: String
    let previousK: Double
    let nextK: Double
    let observedTDEE: Double
    let predictedTDEE: Double
    let sampleDays: Int

    enum CodingKeys: String, CodingKey {
        case appliedAt = "applied_at"
        case previousK = "previous_k"
        case nextK = "next_k"
        case observedTDEE = "observed_tdee"
        case predictedTDEE = "predicted_tdee"
        case sampleDays = "sample_days"
    }
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var persona: Persona
    var displayName: String
    var sex: String
    var weightKG: Double
    var bodyFatPercent: Double
    var heightCM: Double
    var birthdate: String
    var activityLevel: ActivityLevel
    var goal: Goal
    var targetKcal: Int?
    var targetProteinG: Int?
    var targetFatG: Int?
    var targetCarbsG: Int?
    var trainingTime: String
    var baselineDate: String
    var profileNote: String
    var seedVersion: Int
    var calibrationK: Double
    var calibrationHistory: [CalibrationHistoryEntry]
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case persona
        case displayName = "display_name"
        case sex
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_pct"
        case heightCM = "height_cm"
        case birthdate
        case activityLevel = "activity_level"
        case goal
        case targetKcal = "target_kcal"
        case targetProteinG = "target_protein_g"
        case targetFatG = "target_fat_g"
        case targetCarbsG = "target_carbs_g"
        case trainingTime = "training_time"
        case baselineDate = "baseline_date"
        case profileNote = "profile_note"
        case seedVersion = "seed_version"
        case calibrationK = "calibration_k"
        case calibrationHistory = "calibration_history"
        case updatedAt = "updated_at"
    }

    var age: Int {
        let formatter = ISO8601DateFormatter.apexDateOnly
        guard let date = formatter.date(from: birthdate) else { return 0 }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
    }
}

struct UserSettings: Codable, Hashable, Sendable {
    let userID: UUID
    var voiceOn: Bool
    var ticksOn: Bool
    var notificationsOn: Bool
    var guardianFactor: Double
    var addons: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case voiceOn = "voice_on"
        case ticksOn = "ticks_on"
        case notificationsOn = "notifications_on"
        case guardianFactor = "guardian_factor"
        case addons
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let object = try? value.decode([String: JSONValue].self) { self = .object(object) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }
}

extension JSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

struct Meal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var time: String
    var name: String
    var foods: String
    var kcal: Int
    var proteinG: Int
    var fatG: Int
    var carbsG: Int
    var fullDaysOnly: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case time, name, foods, kcal
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case fullDaysOnly = "full_days_only"
        case sortOrder = "sort_order"
    }
}

struct MealLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    let mealID: UUID
    let checkedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date
        case userID = "user_id"
        case mealID = "meal_id"
        case checkedAt = "checked_at"
    }
}

struct Supplement: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var dose: String
    var timing: String
    var clockTime: String?
    var offsetMinutes: Int?
    var groupLabel: String
    var trainingDaysOnly: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, dose, timing
        case userID = "user_id"
        case clockTime = "clock_time"
        case offsetMinutes = "offset_min"
        case groupLabel = "group_label"
        case trainingDaysOnly = "training_days_only"
        case sortOrder = "sort_order"
    }
}

struct SupplementLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    let supplementID: UUID
    let checkedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date
        case userID = "user_id"
        case supplementID = "supplement_id"
        case checkedAt = "checked_at"
    }
}

struct Program: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var slug: String
    var name: String
    var description: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description
        case userID = "user_id"
    }
}

struct ProgramDay: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let programID: UUID
    var weekday: Int
    var name: String
    var dayType: String
    var estimatedMinutes: Int
    var warmupNote: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, weekday, name
        case userID = "user_id"
        case programID = "program_id"
        case dayType = "day_type"
        case estimatedMinutes = "est_minutes"
        case warmupNote = "warmup_note"
        case sortOrder = "sort_order"
    }
}

struct Exercise: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let programDayID: UUID
    var name: String
    var sets: Int
    var repMin: Int
    var repMax: Int
    var repUnit: String
    var perSide: Bool
    var restSeconds: Int
    var tempoUp: Double
    var tempoDown: Double
    var tempoPause: Double
    var tempoNote: String
    var notes: String
    var incrementKG: Double
    var isLite: Bool
    var optional: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sets, notes, optional
        case userID = "user_id"
        case programDayID = "program_day_id"
        case repMin = "rep_min"
        case repMax = "rep_max"
        case repUnit = "rep_unit"
        case perSide = "per_side"
        case restSeconds = "rest_sec"
        case tempoUp = "tempo_up_s"
        case tempoDown = "tempo_down_s"
        case tempoPause = "tempo_pause_s"
        case tempoNote = "tempo_note"
        case incrementKG = "increment_kg"
        case isLite = "is_lite"
        case sortOrder = "sort_order"
    }
}

struct WorkoutSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    let programDayID: UUID
    var isLite: Bool
    var isDeload: Bool
    var isEventRecovery: Bool
    var completed: Bool
    var qualityScore: Double
    var startedAt: String?
    var completedAt: String?
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, date, completed, notes
        case userID = "user_id"
        case programDayID = "program_day_id"
        case isLite = "is_lite"
        case isDeload = "is_deload"
        case isEventRecovery = "is_event_recovery"
        case qualityScore = "quality_score"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct DeloadMark: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String

    enum CodingKeys: String, CodingKey {
        case id, date
        case userID = "user_id"
    }
}

struct WorkoutLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let sessionID: UUID
    let exerciseID: UUID?
    var exerciseName: String
    var setNumber: Int
    var weightKG: Double?
    var reps: Int?
    var rir: Int?
    var skipped: Bool
    var overrideFlag: Bool
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, reps, rir, skipped
        case userID = "user_id"
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case setNumber = "set_no"
        case weightKG = "weight_kg"
        case overrideFlag = "override_flag"
        case createdAt = "created_at"
    }
}

struct WorkoutSetInput: Codable, Hashable, Sendable {
    let exerciseID: UUID?
    var exerciseName: String
    var setNumber: Int
    var weightKG: Double?
    var reps: Int?
    var rir: Int?
    var skipped: Bool
}

struct DailyLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    var kcal: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var waterL: Double
    var estimatedTDEE: Int?
    var computedPAL: Double?
    var activityMode: String
    var weightKG: Double?
    var nutritionSource: String = "manual"
    var manualKcal: Int? = nil
    var manualProteinG: Int? = nil
    var manualFatG: Int? = nil
    var manualCarbsG: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, kcal
        case userID = "user_id"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case waterL = "water_l"
        case estimatedTDEE = "estimated_tdee"
        case computedPAL = "computed_pal"
        case activityMode = "activity_mode"
        case weightKG = "weight_kg"
        case nutritionSource = "nutrition_source"
        case manualKcal = "manual_kcal"
        case manualProteinG = "manual_protein_g"
        case manualFatG = "manual_fat_g"
        case manualCarbsG = "manual_carbs_g"
    }
}

struct EventRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var type: String
    var startDate: String
    var endDate: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, name, type, notes
        case userID = "user_id"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct Food: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let ownerUserID: UUID?
    var name: String
    var namesI18n: [String: String]
    var brand: String?
    var barcode: String?
    var source: String
    var providerProductID: String?
    var externalImageURL: String?
    var packageQuantity: String?
    var nutritionBasis: String
    var preparationState: String
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
    var fibre100: Double?
    var sugar100: Double?
    var saturatedFat100: Double?
    var salt100: Double?
    var servingAmount: Double?
    var servingUnit: String?
    var servingGramsOrML: Double?
    var pieceGramsOrML: Double?
    var confidence: String

    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, confidence
        case ownerUserID = "owner_user_id"
        case namesI18n = "names_i18n"
        case providerProductID = "provider_product_id"
        case externalImageURL = "external_image_url"
        case packageQuantity = "package_quantity"
        case nutritionBasis = "nutrition_basis"
        case preparationState = "preparation_state"
        case kcal100 = "kcal_100"
        case protein100 = "protein_100"
        case carbs100 = "carbs_100"
        case fat100 = "fat_100"
        case fibre100 = "fibre_100"
        case sugar100 = "sugar_100"
        case saturatedFat100 = "saturated_fat_100"
        case salt100 = "salt_100"
        case servingAmount = "serving_amount"
        case servingUnit = "serving_unit"
        case servingGramsOrML = "serving_grams_or_ml"
        case pieceGramsOrML = "piece_grams_or_ml"
    }

    func nutrients(forEquivalentAmount amount: Double) -> FoodNutrients {
        let scale = max(0, amount) / 100
        return FoodNutrients(
            kcal: (kcal100 ?? 0) * scale,
            proteinG: (protein100 ?? 0) * scale,
            carbsG: (carbs100 ?? 0) * scale,
            fatG: (fat100 ?? 0) * scale
        )
    }
}

struct FoodNutrients: Codable, Hashable, Sendable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct FoodPreference: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let foodID: UUID
    var personalName: String?
    var aliases: [String]
    var favourite: Bool
    var usualAmount: Double?
    var usualUnit: String?
    var usageCount: Int
    var lastUsedAt: String?
    var hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id, aliases, favourite, hidden
        case userID = "user_id"
        case foodID = "food_id"
        case personalName = "personal_name"
        case usualAmount = "usual_amount"
        case usualUnit = "usual_unit"
        case usageCount = "usage_count"
        case lastUsedAt = "last_used_at"
    }
}

struct MealPreset: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var mealSlot: String
    var sourcePlannedMealID: UUID?
    var archived: Bool
    var version: Int

    enum CodingKeys: String, CodingKey {
        case id, name, archived, version
        case userID = "user_id"
        case mealSlot = "meal_slot"
        case sourcePlannedMealID = "source_planned_meal_id"
    }
}

struct MealPresetItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let presetID: UUID
    let userID: UUID
    let foodID: UUID
    var sortOrder: Int
    var quantity: Double
    var unit: String
    var optional: Bool
    var locked: Bool
    var adjustable: Bool
    var minimumAmount: Double?
    var maximumAmount: Double?
    var stepAmount: Double?
    var adjustmentRole: String

    enum CodingKeys: String, CodingKey {
        case id, quantity, unit, optional, locked, adjustable
        case presetID = "preset_id"
        case userID = "user_id"
        case foodID = "food_id"
        case sortOrder = "sort_order"
        case minimumAmount = "minimum_amount"
        case maximumAmount = "maximum_amount"
        case stepAmount = "step_amount"
        case adjustmentRole = "adjustment_role"
    }
}

struct LoggedMeal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let localDate: String
    let mealSlot: String
    let displayName: String
    let sourcePresetID: UUID?
    let sourcePlannedMealID: UUID?
    var loggedAt: String
    let clientIdempotencyKey: String
    let loggedAs: String
    let totalKcal: Double
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case localDate = "local_date"
        case mealSlot = "meal_slot"
        case displayName = "display_name"
        case sourcePresetID = "source_preset_id"
        case sourcePlannedMealID = "source_planned_meal_id"
        case loggedAt = "logged_at"
        case clientIdempotencyKey = "client_idempotency_key"
        case loggedAs = "logged_as"
        case totalKcal = "total_kcal"
        case totalProteinG = "total_protein_g"
        case totalCarbsG = "total_carbs_g"
        case totalFatG = "total_fat_g"
    }
}

struct LoggedFoodEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let mealID: UUID
    let userID: UUID
    let foodID: UUID?
    let sortOrder: Int
    let snapshotName: String
    let snapshotBrand: String?
    let snapshotPreparationState: String
    let snapshotNutritionBasis: String
    let snapshotKcal100: Double
    let snapshotProtein100: Double
    let snapshotCarbs100: Double
    let snapshotFat100: Double
    let quantity: Double
    let unit: String
    let equivalentAmount: Double
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    var snapshotFibre100: Double? = nil
    var snapshotSugar100: Double? = nil
    var snapshotSaturatedFat100: Double? = nil
    var snapshotSalt100: Double? = nil
    var fibreG: Double? = nil
    var sugarG: Double? = nil
    var saturatedFatG: Double? = nil
    var saltG: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, quantity, unit, kcal
        case mealID = "meal_id"
        case userID = "user_id"
        case foodID = "food_id"
        case sortOrder = "sort_order"
        case snapshotName = "snapshot_name"
        case snapshotBrand = "snapshot_brand"
        case snapshotPreparationState = "snapshot_preparation_state"
        case snapshotNutritionBasis = "snapshot_nutrition_basis"
        case snapshotKcal100 = "snapshot_kcal_100"
        case snapshotProtein100 = "snapshot_protein_100"
        case snapshotCarbs100 = "snapshot_carbs_100"
        case snapshotFat100 = "snapshot_fat_100"
        case snapshotFibre100 = "snapshot_fibre_100"
        case snapshotSugar100 = "snapshot_sugar_100"
        case snapshotSaturatedFat100 = "snapshot_saturated_fat_100"
        case snapshotSalt100 = "snapshot_salt_100"
        case equivalentAmount = "equivalent_amount"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fibreG = "fibre_g"
        case sugarG = "sugar_g"
        case saturatedFatG = "saturated_fat_g"
        case saltG = "salt_g"
    }
}

struct FoodLookupEnvelope: Codable, Sendable {
    let state: String
    let source: String?
    let food: Food?
    let results: [Food]?
    let message: String?
}

struct StructuredMealRequest: Codable, Sendable {
    let id: UUID
    let localDate: String
    let mealSlot: String
    let displayName: String
    let sourcePresetID: UUID?
    let sourcePlannedMealID: UUID?
    let loggedAt: String
    let clientIdempotencyKey: String
    let loggedAs: String
    let replaceMealID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case localDate = "local_date"
        case mealSlot = "meal_slot"
        case displayName = "display_name"
        case sourcePresetID = "source_preset_id"
        case sourcePlannedMealID = "source_planned_meal_id"
        case loggedAt = "logged_at"
        case clientIdempotencyKey = "client_idempotency_key"
        case loggedAs = "logged_as"
        case replaceMealID = "replace_meal_id"
    }
}

struct StructuredFoodEntryRequest: Codable, Sendable {
    let id: UUID
    let foodID: UUID?
    let sortOrder: Int
    let snapshotName: String
    let snapshotBrand: String?
    let snapshotPreparationState: String
    let snapshotNutritionBasis: String
    let snapshotKcal100: Double
    let snapshotProtein100: Double
    let snapshotCarbs100: Double
    let snapshotFat100: Double
    let snapshotFibre100: Double?
    let snapshotSugar100: Double?
    let snapshotSaturatedFat100: Double?
    let snapshotSalt100: Double?
    let quantity: Double
    let unit: String
    let equivalentAmount: Double

    enum CodingKeys: String, CodingKey {
        case id, quantity, unit
        case foodID = "food_id"
        case sortOrder = "sort_order"
        case snapshotName = "snapshot_name"
        case snapshotBrand = "snapshot_brand"
        case snapshotPreparationState = "snapshot_preparation_state"
        case snapshotNutritionBasis = "snapshot_nutrition_basis"
        case snapshotKcal100 = "snapshot_kcal_100"
        case snapshotProtein100 = "snapshot_protein_100"
        case snapshotCarbs100 = "snapshot_carbs_100"
        case snapshotFat100 = "snapshot_fat_100"
        case snapshotFibre100 = "snapshot_fibre_100"
        case snapshotSugar100 = "snapshot_sugar_100"
        case snapshotSaturatedFat100 = "snapshot_saturated_fat_100"
        case snapshotSalt100 = "snapshot_salt_100"
        case equivalentAmount = "equivalent_amount"
    }
}

struct StructuredMealRPCPayload: Codable, Sendable {
    let pMeal: StructuredMealRequest
    let pEntries: [StructuredFoodEntryRequest]

    enum CodingKeys: String, CodingKey {
        case pMeal = "p_meal"
        case pEntries = "p_entries"
    }
}

/// The native meal composer uses the same immutable food snapshots as the web
/// client. A draft is intentionally local-only; committing it always goes
/// through `log_structured_meal`, which atomically replaces the meal and
/// recalculates the shared daily nutrition row.
struct MealComposerItem: Identifiable, Hashable, Sendable {
    var id: UUID
    var foodID: UUID?
    var name: String
    var brand: String?
    var preparationState: String
    var nutritionBasis: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var fibre100: Double?
    var sugar100: Double?
    var saturatedFat100: Double?
    var salt100: Double?
    var quantity: Double
    var unit: String
    var equivalentAmount: Double
    var optional: Bool = false
    var locked: Bool = false
    var adjustable: Bool = true
    var minimumAmount: Double?
    var maximumAmount: Double?
    var stepAmount: Double?
    var adjustmentRole: String = "none"
    var personalLabel: String = ""

    var nutrients: FoodNutrients {
        let scale = max(0, equivalentAmount) / 100
        return FoodNutrients(
            kcal: kcal100 * scale,
            proteinG: protein100 * scale,
            carbsG: carbs100 * scale,
            fatG: fat100 * scale
        )
    }

    mutating func setQuantity(_ value: Double, food: Food? = nil) {
        quantity = max(0, value)
        switch unit {
        case "piece": equivalentAmount = quantity * (food?.pieceGramsOrML ?? equivalentAmountPerUnit)
        case "serving": equivalentAmount = quantity * (food?.servingGramsOrML ?? equivalentAmountPerUnit)
        default: equivalentAmount = quantity
        }
    }

    mutating func setUnit(_ value: String, food: Food? = nil) {
        unit = value
        setQuantity(quantity, food: food)
    }

    private var equivalentAmountPerUnit: Double {
        guard quantity > 0 else { return 0 }
        return equivalentAmount / quantity
    }

    init(food: Food, quantity: Double, unit: String) {
        let equivalent: Double
        switch unit {
        case "piece": equivalent = quantity * (food.pieceGramsOrML ?? 0)
        case "serving": equivalent = quantity * (food.servingGramsOrML ?? 0)
        default: equivalent = quantity
        }
        id = UUID()
        foodID = UUID(uuidString: food.id)
        name = food.name
        brand = food.brand
        preparationState = food.preparationState
        nutritionBasis = food.nutritionBasis
        kcal100 = food.kcal100 ?? 0
        protein100 = food.protein100 ?? 0
        carbs100 = food.carbs100 ?? 0
        fat100 = food.fat100 ?? 0
        fibre100 = food.fibre100
        sugar100 = food.sugar100
        saturatedFat100 = food.saturatedFat100
        salt100 = food.salt100
        self.quantity = quantity
        self.unit = unit
        equivalentAmount = equivalent
    }

    init(entry: LoggedFoodEntry) {
        id = entry.id
        foodID = entry.foodID
        name = entry.snapshotName
        brand = entry.snapshotBrand
        preparationState = entry.snapshotPreparationState
        nutritionBasis = entry.snapshotNutritionBasis
        kcal100 = entry.snapshotKcal100
        protein100 = entry.snapshotProtein100
        carbs100 = entry.snapshotCarbs100
        fat100 = entry.snapshotFat100
        fibre100 = entry.snapshotFibre100
        sugar100 = entry.snapshotSugar100
        saturatedFat100 = entry.snapshotSaturatedFat100
        salt100 = entry.snapshotSalt100
        quantity = entry.quantity
        unit = entry.unit
        equivalentAmount = entry.equivalentAmount
    }

    init(food: Food, preset: MealPresetItem) {
        self.init(food: food, quantity: preset.quantity, unit: preset.unit)
        id = preset.id
        optional = preset.optional
        locked = preset.locked
        adjustable = preset.adjustable
        minimumAmount = preset.minimumAmount
        maximumAmount = preset.maximumAmount
        stepAmount = preset.stepAmount
        adjustmentRole = preset.adjustmentRole
    }
}

struct MealComposerDraft: Identifiable, Hashable, Sendable {
    var id: UUID
    var localDate: String
    var mealSlot: String
    var displayName: String
    var finishedAt: Date
    var sourcePresetID: UUID?
    var sourcePlannedMealID: UUID?
    var replaceMealID: UUID?
    var loggedAs: String
    var items: [MealComposerItem]

    var totals: FoodNutrients {
        items.reduce(FoodNutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)) { partial, item in
            let value = item.nutrients
            return FoodNutrients(
                kcal: partial.kcal + value.kcal,
                proteinG: partial.proteinG + value.proteinG,
                carbsG: partial.carbsG + value.carbsG,
                fatG: partial.fatG + value.fatG
            )
        }
    }
}

struct MealPresetRequest: Codable, Sendable {
    let id: UUID
    let name: String
    let mealSlot: String
    let sourcePlannedMealID: UUID?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, archived
        case mealSlot = "meal_slot"
        case sourcePlannedMealID = "source_planned_meal_id"
    }
}

struct MealPresetItemRequest: Codable, Sendable {
    let id: UUID
    let foodID: UUID
    let sortOrder: Int
    let quantity: Double
    let unit: String
    let optional: Bool
    let locked: Bool
    let adjustable: Bool
    let minimumAmount: Double?
    let maximumAmount: Double?
    let stepAmount: Double?
    let adjustmentRole: String

    enum CodingKeys: String, CodingKey {
        case id, quantity, unit, optional, locked, adjustable
        case foodID = "food_id"
        case sortOrder = "sort_order"
        case minimumAmount = "minimum_amount"
        case maximumAmount = "maximum_amount"
        case stepAmount = "step_amount"
        case adjustmentRole = "adjustment_role"
    }
}

struct MealPresetRPCPayload: Codable, Sendable {
    let pPreset: MealPresetRequest
    let pItems: [MealPresetItemRequest]
    let pExpectedVersion: Int

    enum CodingKeys: String, CodingKey {
        case pPreset = "p_preset"
        case pItems = "p_items"
        case pExpectedVersion = "p_expected_version"
    }
}

enum ActivityInputStyle: String, Codable, Sendable {
    case count
    case duration
    case distance
    case steps
    case watchKcal = "watch_kcal"
}

struct ActivityType: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var category: String
    var name: String
    var icon: String
    var met: Double
    var inputStyle: ActivityInputStyle
    var defaultDurationMinutes: Int?
    var isTrainingLinked: Bool
    var notes: String
    var distanceFactor: Double?
    var supportsWatch: Bool

    enum CodingKeys: String, CodingKey {
        case id, category, name, icon, met, notes
        case inputStyle = "input_style"
        case defaultDurationMinutes = "default_duration_min"
        case isTrainingLinked = "is_training_linked"
        case distanceFactor = "distance_factor"
        case supportsWatch = "supports_watch"
    }
}

struct ActivityLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var date: String
    var typeID: String
    var quantity: Double
    var durationMinutes: Int?
    var distanceKM: Double?
    var watchKcal: Double?
    var computedKcal: Double
    var source: String
    var reconciled: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, quantity, source, reconciled
        case userID = "user_id"
        case typeID = "type_id"
        case durationMinutes = "duration_min"
        case distanceKM = "distance_km"
        case watchKcal = "watch_kcal"
        case computedKcal = "computed_kcal"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RPGSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    var overall: Double
    var health: Double
    var joint: Double
    var flexibility: Double
    var endurance: Double
    var strength: Double
    var strengthUpper: Double
    var strengthLower: Double

    enum CodingKeys: String, CodingKey {
        case id, date, overall, health, joint, flexibility, endurance, strength
        case userID = "user_id"
        case strengthUpper = "strength_upper"
        case strengthLower = "strength_lower"
    }
}

struct HealthMetric: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    var weightKG: Double?
    var vo2Max: Double?
    var restingHeartRate: Double?

    enum CodingKeys: String, CodingKey {
        case id, date
        case userID = "user_id"
        case weightKG = "weight_kg"
        case vo2Max = "vo2max"
        case restingHeartRate = "resting_hr"
    }
}

struct ImportedActivity: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let date: String
    let kind: String
    let activity: String
    let durationMinutes: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, date, kind, activity, source
        case userID = "user_id"
        case durationMinutes = "duration_min"
    }
}

struct ProgressPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let localDate: String
    let capturedAt: String
    let pose: String
    let storagePath: String
    let thumbnailPath: String
    let width: Int
    let height: Int
    let aspectRatio: Double
    let cropX: Double
    let cropY: Double
    let cropScale: Double
    let referencePhotoID: UUID?
    let weightKG: Double?
    let note: String
    let clientIdempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case id, pose, width, height, note
        case userID = "user_id"
        case localDate = "local_date"
        case capturedAt = "captured_at"
        case storagePath = "storage_path"
        case thumbnailPath = "thumbnail_path"
        case aspectRatio = "aspect_ratio"
        case cropX = "crop_x"
        case cropY = "crop_y"
        case cropScale = "crop_scale"
        case referencePhotoID = "reference_photo_id"
        case weightKG = "weight_kg"
        case clientIdempotencyKey = "client_idempotency_key"
    }
}

struct OrbitRouteRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var clientIdempotencyKey: String
    var name: String
    var note: String
    var points: [JSONValue]
    var distanceM: Int
    var elevationGainM: Int?
    var surface: String
    var terrain: String
    var shape: String
    var navigationComplexity: String
    var familiarityPercent: Double?
    var favourite: Bool
    var rating: Int?
    var missionTags: [String]
    var preferredSections: [String]
    var avoidedSections: [String]
    var provider: String
    var attribution: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, note, points, surface, terrain, shape, favourite, rating
        case userID = "user_id"
        case clientIdempotencyKey = "client_idempotency_key"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
        case navigationComplexity = "navigation_complexity"
        case familiarityPercent = "familiarity_pct"
        case missionTags = "mission_tags"
        case preferredSections = "preferred_sections"
        case avoidedSections = "avoided_sections"
        case provider, attribution
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitRunRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let clientIdempotencyKey: String
    let localDate: String
    let startedAt: String
    let endedAt: String
    let mission: String
    let routeID: UUID?
    let campaignSessionID: UUID?
    let shoeID: UUID?
    let samples: [JSONValue]
    let pauses: [JSONValue]
    let manualLapsM: [JSONValue]
    let metrics: [String: JSONValue]
    let checkIn: [String: JSONValue]
    let nutritionAdjustmentAppliedAt: String?
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, mission, samples, metrics, status
        case userID = "user_id"
        case clientIdempotencyKey = "client_idempotency_key"
        case localDate = "local_date"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case routeID = "route_id"
        case campaignSessionID = "campaign_session_id"
        case shoeID = "shoe_id"
        case pauses
        case manualLapsM = "manual_laps_m"
        case checkIn = "check_in"
        case nutritionAdjustmentAppliedAt = "nutrition_adjustment_applied_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitShoe: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var brand: String
    var firstUseDate: String
    var preferredSurfaces: [String]
    var notes: String
    var archived: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, brand, notes, archived
        case userID = "user_id"
        case firstUseDate = "first_use_date"
        case preferredSurfaces = "preferred_surfaces"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitSegment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let routeID: UUID
    var name: String
    var startDistanceM: Int
    var endDistanceM: Int
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case routeID = "route_id"
        case startDistanceM = "start_distance_m"
        case endDistanceM = "end_distance_m"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitPoster: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let runID: UUID
    var style: String
    var privacyTrimM: Int
    var includeHeartRate: Bool
    var note: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, style, note
        case userID = "user_id"
        case runID = "run_id"
        case privacyTrimM = "privacy_trim_m"
        case includeHeartRate = "include_heart_rate"
        case createdAt = "created_at"
    }
}

struct OrbitInduction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var answers: [String: JSONValue]
    var currentStep: Int
    var completed: Bool
    var outcome: String?
    var outcomeReason: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, answers, completed, outcome
        case userID = "user_id"
        case currentStep = "current_step"
        case outcomeReason = "outcome_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitCampaign: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let clientIdempotencyKey: String
    let inductionID: UUID
    var family: String
    var phase: String
    var outcome: String
    var status: String
    var raceName: String
    var raceDate: String
    var raceGoal: String
    var startedAt: String
    var planVersion: String
    var assignmentReason: String
    var timelineWarning: String
    var readiness: [JSONValue]
    var adaptations: [JSONValue]
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, family, phase, outcome, status, readiness, adaptations
        case userID = "user_id"
        case clientIdempotencyKey = "client_idempotency_key"
        case inductionID = "induction_id"
        case raceName = "race_name"
        case raceDate = "race_date"
        case raceGoal = "race_goal"
        case startedAt = "started_at"
        case planVersion = "plan_version"
        case assignmentReason = "assignment_reason"
        case timelineWarning = "timeline_warning"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrbitCampaignSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let campaignID: UUID
    var date: String
    var prescribedDate: String
    var phase: String
    var original: [String: JSONValue]
    var adapted: [String: JSONValue]
    var status: String
    var completionRunID: UUID?
    var adaptationReason: String
    var userOverride: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, phase, original, adapted, status
        case userID = "user_id"
        case campaignID = "campaign_id"
        case prescribedDate = "prescribed_date"
        case completionRunID = "completion_run_id"
        case adaptationReason = "adaptation_reason"
        case userOverride = "user_override"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DashboardData: Codable, Sendable {
    var profile: Profile?
    var settings: UserSettings?
    var meals: [Meal] = []
    var mealLogs: [MealLog] = []
    var supplements: [Supplement] = []
    var supplementLogs: [SupplementLog] = []
    var programs: [Program] = []
    var programDays: [ProgramDay] = []
    var exercises: [Exercise] = []
    var workoutSessions: [WorkoutSession] = []
    var workoutLogs: [WorkoutLog] = []
    // Optional keeps dashboards cached by older native builds decodable.
    var deloadMarks: [DeloadMark]? = []
    var activityTypes: [ActivityType] = []
    var activityLogs: [ActivityLog] = []
    var dailyLogs: [DailyLog] = []
    var events: [EventRecord] = []
    var foods: [Food] = []
    var foodPreferences: [FoodPreference] = []
    var mealPresets: [MealPreset] = []
    var mealPresetItems: [MealPresetItem] = []
    var loggedMeals: [LoggedMeal] = []
    var loggedFoodEntries: [LoggedFoodEntry] = []
    var snapshots: [RPGSnapshot] = []
    var healthMetrics: [HealthMetric] = []
    var importedActivities: [ImportedActivity] = []
    var progressPhotos: [ProgressPhoto] = []
    var orbitRoutes: [OrbitRouteRecord] = []
    var orbitRuns: [OrbitRunRecord] = []
    var orbitShoes: [OrbitShoe] = []
    var orbitSegments: [OrbitSegment] = []
    var orbitPosters: [OrbitPoster] = []
    var orbitInductions: [OrbitInduction] = []
    var orbitCampaigns: [OrbitCampaign] = []
    var orbitCampaignSessions: [OrbitCampaignSession] = []

    static let empty = DashboardData()
}

extension ISO8601DateFormatter {
    static let apexDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Date {
    var apexDateKey: String { ISO8601DateFormatter.apexDateOnly.string(from: self) }
}
