/*
 * FitnessBrainEngine input/output models. Pure, Sendable, Codable with
 * snake_case keys matching the web app's Supabase rows and the parity
 * fixtures. The engine layer never imports UI or networking.
 */
import Foundation

public enum FBPersona: String, Codable, Sendable {
    case constantine, june, matthew, iulian
}

public enum FBActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, moderate, very, extra
}

public enum FBGoal: String, Codable, Sendable {
    case recomp, maintain, bulk
}

public enum FBDayType: String, Codable, Sendable {
    case legsA = "legs_a"
    case legsB = "legs_b"
    case push, pull, upper, mobility, fix, t25
}

public struct FBProfile: Codable, Sendable {
    public var userID: String
    public var persona: FBPersona
    public var sex: String
    public var weightKG: Double
    public var bodyFatPct: Double?
    public var customBMR: Double?
    public var profileKind: String?
    public var bespokeProtocolID: String?
    public var bodyFatSource: String?
    public var heightCM: Double
    public var birthdate: String
    public var activityLevel: FBActivityLevel
    public var goal: FBGoal
    public var baselineDate: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case persona, sex
        case weightKG = "weight_kg"
        case bodyFatPct = "body_fat_pct"
        case customBMR = "custom_bmr"
        case profileKind = "profile_kind"
        case bespokeProtocolID = "bespoke_protocol_id"
        case bodyFatSource = "body_fat_source"
        case heightCM = "height_cm"
        case birthdate
        case activityLevel = "activity_level"
        case goal
        case baselineDate = "baseline_date"
    }

    public init(
        userID: String, persona: FBPersona, sex: String, weightKG: Double,
        bodyFatPct: Double?, customBMR: Double?, heightCM: Double, birthdate: String,
        activityLevel: FBActivityLevel, goal: FBGoal, baselineDate: String,
        profileKind: String? = nil, bespokeProtocolID: String? = nil,
        bodyFatSource: String? = nil
    ) {
        self.userID = userID
        self.persona = persona
        self.sex = sex
        self.weightKG = weightKG
        self.bodyFatPct = bodyFatPct
        self.customBMR = customBMR
        self.profileKind = profileKind
        self.bespokeProtocolID = bespokeProtocolID
        self.bodyFatSource = bodyFatSource
        self.heightCM = heightCM
        self.birthdate = birthdate
        self.activityLevel = activityLevel
        self.goal = goal
        self.baselineDate = baselineDate
    }
}

public struct FBProgramDayRef: Codable, Sendable {
    public var id: String
    public var dayType: FBDayType

    enum CodingKeys: String, CodingKey {
        case id
        case dayType = "day_type"
    }

    public init(id: String, dayType: FBDayType) {
        self.id = id
        self.dayType = dayType
    }
}

public struct FBExerciseRef: Codable, Sendable {
    public var id: String
    public var programDayID: String

    enum CodingKeys: String, CodingKey {
        case id
        case programDayID = "program_day_id"
    }

    public init(id: String, programDayID: String) {
        self.id = id
        self.programDayID = programDayID
    }
}

public struct FBWorkoutSession: Codable, Sendable {
    public var id: String
    public var date: String
    public var programDayID: String
    public var isDeload: Bool
    public var isEventRecovery: Bool
    public var completed: Bool
    public var qualityScore: Double

    enum CodingKeys: String, CodingKey {
        case id, date, completed
        case programDayID = "program_day_id"
        case isDeload = "is_deload"
        case isEventRecovery = "is_event_recovery"
        case qualityScore = "quality_score"
    }

    public init(
        id: String, date: String, programDayID: String, isDeload: Bool,
        isEventRecovery: Bool, completed: Bool, qualityScore: Double
    ) {
        self.id = id
        self.date = date
        self.programDayID = programDayID
        self.isDeload = isDeload
        self.isEventRecovery = isEventRecovery
        self.completed = completed
        self.qualityScore = qualityScore
    }
}

public struct FBWorkoutLog: Codable, Sendable {
    public var id: String
    public var sessionID: String
    public var exerciseID: String?
    public var exerciseName: String
    public var weightKG: Double?
    public var skipped: Bool
    public var overrideFlag: Bool

    enum CodingKeys: String, CodingKey {
        case id, skipped
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case weightKG = "weight_kg"
        case overrideFlag = "override_flag"
    }

    public init(
        id: String, sessionID: String, exerciseID: String?, exerciseName: String,
        weightKG: Double?, skipped: Bool, overrideFlag: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKG = weightKG
        self.skipped = skipped
        self.overrideFlag = overrideFlag
    }
}

public struct FBDailyLog: Codable, Sendable {
    public var date: String
    public var kcal: Double?
    public var proteinG: Double?
    public var waterL: Double

    enum CodingKeys: String, CodingKey {
        case date, kcal
        case proteinG = "protein_g"
        case waterL = "water_l"
    }

    public init(date: String, kcal: Double?, proteinG: Double?, waterL: Double) {
        self.date = date
        self.kcal = kcal
        self.proteinG = proteinG
        self.waterL = waterL
    }
}

public struct FBHealthMetric: Codable, Sendable {
    public var date: String
    public var vo2max: Double?
    public var restingHR: Double?

    enum CodingKeys: String, CodingKey {
        case date, vo2max
        case restingHR = "resting_hr"
    }

    public init(date: String, vo2max: Double?, restingHR: Double?) {
        self.date = date
        self.vo2max = vo2max
        self.restingHR = restingHR
    }
}

public enum FBImportKind: String, Codable, Sendable {
    case strength, endurance, mobility
}

public struct FBImportedActivity: Codable, Sendable {
    public var date: String
    public var kind: FBImportKind
    public var durationMin: Double

    enum CodingKeys: String, CodingKey {
        case date, kind
        case durationMin = "duration_min"
    }

    public init(date: String, kind: FBImportKind, durationMin: Double) {
        self.date = date
        self.kind = kind
        self.durationMin = durationMin
    }
}

public enum FBRecoverySource: String, Codable, Sendable {
    case apple, other
}

public struct FBRecoveryCheckin: Codable, Sendable {
    public var date: String
    public var source: FBRecoverySource
    public var sleepScore: Double?
    public var recoveryPct: Double?

    enum CodingKeys: String, CodingKey {
        case date, source
        case sleepScore = "sleep_score"
        case recoveryPct = "recovery_pct"
    }

    public init(date: String, source: FBRecoverySource, sleepScore: Double?, recoveryPct: Double?) {
        self.date = date
        self.source = source
        self.sleepScore = sleepScore
        self.recoveryPct = recoveryPct
    }
}

public enum FBMealRhythmVerdict: String, Codable, Sendable {
    case open
    case completeOnTime = "complete_on_time"
    case completeIrregular = "complete_irregular"
    case missedMeals = "missed_meals"
    case noMeals = "no_meals"
}

/* Raw meal-rhythm day as stored in settings JSON; normalized by the engine
   exactly like the web's normalizeMealRhythmHistory. */
public struct FBMealRhythmDayRaw: Codable, Sendable {
    public var finalized: Bool?
    public var expectedMeals: Double?
    public var loggedMeals: Double?
    public var completionScore: Double?
    public var rhythmScore: Double?
    public var verdict: String?

    enum CodingKeys: String, CodingKey {
        case finalized, verdict
        case expectedMeals = "expected_meals"
        case loggedMeals = "logged_meals"
        case completionScore = "completion_score"
        case rhythmScore = "rhythm_score"
    }

    public init(
        finalized: Bool?, expectedMeals: Double?, loggedMeals: Double?,
        completionScore: Double?, rhythmScore: Double?, verdict: String?
    ) {
        self.finalized = finalized
        self.expectedMeals = expectedMeals
        self.loggedMeals = loggedMeals
        self.completionScore = completionScore
        self.rhythmScore = rhythmScore
        self.verdict = verdict
    }
}

public struct FBEngineInput: Sendable {
    public var profile: FBProfile
    public var programDays: [FBProgramDayRef]
    public var exercises: [FBExerciseRef]
    public var workoutSessions: [FBWorkoutSession]
    public var workoutLogs: [FBWorkoutLog]
    public var dailyLogs: [FBDailyLog]
    public var healthMetrics: [FBHealthMetric]
    public var importedActivities: [FBImportedActivity]
    public var recoveryHistory: [FBRecoveryCheckin]
    /* keys are yyyy-MM-dd dates; order preserved from storage where relevant */
    public var mealRhythmHistory: [String: FBMealRhythmDayRaw]

    public init(
        profile: FBProfile,
        programDays: [FBProgramDayRef] = [],
        exercises: [FBExerciseRef] = [],
        workoutSessions: [FBWorkoutSession] = [],
        workoutLogs: [FBWorkoutLog] = [],
        dailyLogs: [FBDailyLog] = [],
        healthMetrics: [FBHealthMetric] = [],
        importedActivities: [FBImportedActivity] = [],
        recoveryHistory: [FBRecoveryCheckin] = [],
        mealRhythmHistory: [String: FBMealRhythmDayRaw] = [:]
    ) {
        self.profile = profile
        self.programDays = programDays
        self.exercises = exercises
        self.workoutSessions = workoutSessions
        self.workoutLogs = workoutLogs
        self.dailyLogs = dailyLogs
        self.healthMetrics = healthMetrics
        self.importedActivities = importedActivities
        self.recoveryHistory = recoveryHistory
        self.mealRhythmHistory = mealRhythmHistory
    }
}

public struct FBSnapshot: Codable, Sendable, Equatable {
    public var date: String
    public var overall: Double
    public var health: Double
    public var joint: Double
    public var flexibility: Double
    public var endurance: Double
    public var strength: Double
    public var strengthUpper: Double
    public var strengthLower: Double

    enum CodingKeys: String, CodingKey {
        case date, overall, health, joint, flexibility, endurance, strength
        case strengthUpper = "strength_upper"
        case strengthLower = "strength_lower"
    }

    public init(
        date: String, overall: Double, health: Double, joint: Double, flexibility: Double,
        endurance: Double, strength: Double, strengthUpper: Double, strengthLower: Double
    ) {
        self.date = date
        self.overall = overall
        self.health = health
        self.joint = joint
        self.flexibility = flexibility
        self.endurance = endurance
        self.strength = strength
        self.strengthUpper = strengthUpper
        self.strengthLower = strengthLower
    }
}

public enum FBSynergyKind: String, Codable, Sendable {
    case proteinStrength = "protein_strength"
    case deficitStrength = "deficit_strength"
    case hydrationEndurance = "hydration_endurance"
    case mobilityAfterLegs = "mobility_after_legs"
    case recoverySignal = "recovery_signal"
    case mealRhythm = "meal_rhythm"
    case vo2Anchor = "vo2_anchor"
    case importFeed = "import_feed"
    case deloadHonored = "deload_honored"
}

public struct FBSynergyEvent: Codable, Sendable, Equatable {
    public var date: String
    public var kind: FBSynergyKind
    public var label: String

    public init(date: String, kind: FBSynergyKind, label: String) {
        self.date = date
        self.kind = kind
        self.label = label
    }
}

public struct FBEngineResult: Sendable {
    public var snapshots: [FBSnapshot]
    public var synergies: [FBSynergyEvent]

    public init(snapshots: [FBSnapshot], synergies: [FBSynergyEvent]) {
        self.snapshots = snapshots
        self.synergies = synergies
    }
}

public struct FBTargets: Codable, Sendable, Equatable {
    public var bmrMifflin: Double
    public var bmrKatch: Double?
    public var tdee: Double
    public var kcal: Double
    public var proteinG: Double
    public var fatG: Double
    public var carbsG: Double
    public var waterL: Double

    enum CodingKeys: String, CodingKey {
        case bmrMifflin, bmrKatch, tdee, kcal
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case waterL = "water_l"
    }

    public init(
        bmrMifflin: Double, bmrKatch: Double?, tdee: Double, kcal: Double,
        proteinG: Double, fatG: Double, carbsG: Double, waterL: Double
    ) {
        self.bmrMifflin = bmrMifflin
        self.bmrKatch = bmrKatch
        self.tdee = tdee
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.waterL = waterL
    }
}
