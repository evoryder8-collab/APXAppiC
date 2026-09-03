import Foundation

enum RestingEnergyProvenance: String, Equatable, Sendable {
    case indirectCalorimetry = "indirect_calorimetry"
    case legacyUserEntered = "legacy_user_entered"
    case bodyCompositionEstimate = "body_composition_estimate"
    case mifflinEstimate = "mifflin_estimate"
}

enum NutritionTargetProvenance: String, Equatable, Sendable {
    case calculatedEstimate = "calculated_estimate"
    case authoredProtocol = "authored_protocol"
}

enum NutritionReviewReason: String, Hashable, Sendable {
    case underNineteen = "under_nineteen"
    case invalidBirthdate = "invalid_birthdate"
    case implausibleDemographics = "implausible_demographics"
    case implausibleBMR = "implausible_bmr"
    case macroEnergyConflict = "macro_energy_conflict"
    case lowCalorieTarget = "low_calorie_target"
    case dexaEstimatedBMRStored = "dexa_estimated_bmr_ignored"
    case legacyBMRNeedsReview = "legacy_bmr_needs_review"
}

struct NutritionTargets: Equatable, Sendable {
    let bmr: Int
    let tdee: Int
    let targetCalories: Int
    let proteinG: Int
    let fatG: Int
    let carbsG: Int
    let pal: Double
    let level: ActivityLevel
    let restingEnergyProvenance: RestingEnergyProvenance
    let targetProvenance: NutritionTargetProvenance
    let reviewReasons: Set<NutritionReviewReason>

    var requiresReview: Bool { reviewReasons.isEmpty == false }
    var isPublishable: Bool {
        let blockingReasons: Set<NutritionReviewReason> = targetProvenance == .authoredProtocol
            ? [.macroEnergyConflict]
            : [
            .underNineteen,
            .invalidBirthdate,
            .implausibleDemographics,
            .implausibleBMR,
            .macroEnergyConflict,
        ]
        return reviewReasons.isDisjoint(with: blockingReasons)
    }

    init(
        bmr: Int,
        tdee: Int,
        targetCalories: Int,
        proteinG: Int,
        fatG: Int,
        carbsG: Int,
        pal: Double,
        level: ActivityLevel,
        restingEnergyProvenance: RestingEnergyProvenance = .mifflinEstimate,
        targetProvenance: NutritionTargetProvenance = .calculatedEstimate,
        reviewReasons: Set<NutritionReviewReason> = []
    ) {
        self.bmr = bmr
        self.tdee = tdee
        self.targetCalories = targetCalories
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.pal = pal
        self.level = level
        self.restingEnergyProvenance = restingEnergyProvenance
        self.targetProvenance = targetProvenance
        self.reviewReasons = reviewReasons
    }
}

struct EnergyMacroTargets: Equatable, Sendable {
    let proteinG: Int
    let fatG: Int
    let carbsG: Int
    let requiresReview: Bool

    init(
        proteinG: Int,
        fatG: Int,
        carbsG: Int,
        requiresReview: Bool = false
    ) {
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.requiresReview = requiresReview
    }
}

struct NutritionPlanContext: Equatable, Sendable {
    let trainingGoal: String
    let planWeeks: Int
}

struct NutritionGoalPreset: Equatable, Sendable {
    let goal: Goal
    let label: String
    let factor: Double
    let explanation: String
    let caution: String
}

enum NutritionGoalPolicy {
    static let allowedPlanWeeks: Set<Int> = [4, 8, 12, 26]

    static func normalizedTrainingGoal(_ rawValue: String?) -> String {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "muscle", "fat_loss", "strength", "endurance", "rebuild":
            return normalized ?? "rebuild"
        case "hypertrophy":
            return "muscle"
        case "general":
            return "rebuild"
        default:
            return "rebuild"
        }
    }

    static func normalizedPlanWeeks(_ value: Int?) -> Int {
        guard let value, allowedPlanWeeks.contains(value) else { return 12 }
        return value
    }

    static func normalizedContext(_ context: NutritionPlanContext?) -> NutritionPlanContext? {
        guard let context else { return nil }
        return NutritionPlanContext(
            trainingGoal: normalizedTrainingGoal(context.trainingGoal),
            planWeeks: normalizedPlanWeeks(context.planWeeks)
        )
    }

    static func context(from settings: UserSettings?) -> NutritionPlanContext? {
        guard let addons = settings?.addons,
              let induction = addons["training_induction"]?.objectValue
                ?? addons[TrainingInduction.baselineMarkerKey]?.objectValue,
              let trainingGoal = induction["goal"]?.stringValue else { return nil }
        return NutritionPlanContext(
            trainingGoal: normalizedTrainingGoal(trainingGoal),
            planWeeks: normalizedPlanWeeks(Int(induction["plan_weeks"]?.numberValue ?? 12))
        )
    }

    static func presets(context: NutritionPlanContext?) -> [NutritionGoalPreset] {
        guard let context = normalizedContext(context) else {
            return [
                preset(.recomp, "Lean recomp", 0.90, "A moderate deficit with extra protein support.", "Review recovery, hunger, and weight trend after two weeks."),
                preset(.maintain, "Maintain", 1, "Match estimated daily expenditure without targeting weight change.", "Wearable estimates are a starting point, not a metabolic measurement."),
                preset(.bulk, "Lean bulk", 1.05, "A controlled surplus to support training progression.", "Reduce the surplus if weight rises faster than intended."),
            ]
        }

        switch context.trainingGoal {
        case "muscle":
            return [
                preset(.recomp, "Lean recomp", 0.95, "Build skill and preserve muscle while trimming slowly.", "Choose Maintain if training performance or recovery declines."),
                preset(.maintain, "Maintain", 1, "Hold body weight while progressive training drives recomposition.", "Progress is slower, so judge the trend over several weeks."),
                preset(.bulk, "Lean bulk", 1.07, "Use a small surplus to support muscle gain and harder sessions.", "Review the two-week weight trend and reduce if gain is too fast."),
            ]
        case "fat_loss":
            let accelerated: Double = switch context.planWeeks {
            case 4: 0.80
            case 8: 0.82
            case 26: 0.86
            default: 0.84
            }
            let steady: Double = switch context.planWeeks {
            case 4: 0.86
            case 8: 0.87
            case 26: 0.89
            default: 0.88
            }
            return [
                preset(.recomp, "Accelerated cut", accelerated, "The largest bounded deficit for this plan horizon.", "Not the default. Stop and reassess if recovery, sleep, or performance falls."),
                preset(.maintain, "Steady cut", steady, "A repeatable deficit balanced against training and lean-mass retention.", "Best default; use measured trends instead of cutting harder too soon."),
                preset(.bulk, "Gentle cut", 0.93, "A smaller deficit with more room for training and appetite control.", "Loss is intentionally slower and depends on consistent weeks."),
            ]
        case "strength":
            return [
                preset(.recomp, "Strength recomp", 0.95, "A small deficit while strength skill remains the priority.", "Move to Strength base if load or recovery trends down."),
                preset(.maintain, "Strength base", 1, "Maintenance energy for repeatable heavy practice and recovery.", "The recommended starting point for most strength plans."),
                preset(.bulk, "Power surplus", 1.05, "A small surplus for higher volume and progressive loading.", "Review body-weight trend after two weeks; more is not automatically better."),
            ]
        case "endurance":
            return [
                preset(.recomp, "Light fuel", 0.96, "A slight deficit while protecting useful training fuel.", "Avoid on high-volume weeks if pace, mood, or recovery deteriorates."),
                preset(.maintain, "Balanced fuel", 1, "Match daily expenditure for consistent endurance work.", "The recommended base before adding fuel for longer sessions."),
                preset(.bulk, "High-volume fuel", 1.06, "Extra energy for long or dense training weeks.", "Use for real workload, then return to Balanced fuel as volume falls."),
            ]
        default:
            return [
                preset(.recomp, "Light balance", 0.95, "A small deficit while rebuilding a consistent routine.", "Choose Balanced fitness if hunger or recovery disrupts consistency."),
                preset(.maintain, "Balanced fitness", 1, "Maintenance fuel for broad fitness and repeatable sessions.", "The recommended start when body-weight change is not the main goal."),
                preset(.bulk, "Fuel progress", 1.04, "A small surplus for higher volume and easier recovery.", "Review body-weight trend after two weeks and adjust deliberately."),
            ]
        }
    }

    static func preset(for goal: Goal, context: NutritionPlanContext?) -> NutritionGoalPreset {
        presets(context: context).first { $0.goal == goal }
            ?? presets(context: nil).first { $0.goal == goal }
            ?? preset(.maintain, "Maintain", 1, "Match estimated daily expenditure without targeting weight change.", "Review the estimate against your weight trend.")
    }

    static func recommendedGoal(for trainingGoal: String) -> Goal {
        normalizedTrainingGoal(trainingGoal) == "muscle" ? .bulk : .maintain
    }

    private static func preset(
        _ goal: Goal,
        _ label: String,
        _ factor: Double,
        _ explanation: String,
        _ caution: String
    ) -> NutritionGoalPreset {
        NutritionGoalPreset(
            goal: goal,
            label: label,
            factor: factor,
            explanation: explanation,
            caution: caution
        )
    }
}

enum RestingEnergyPolicy {
    static let validRange = 800.0...4_000.0
    static let dexaReportEstimateSource = "dexa_report_estimate"

    static func validated(_ value: Double?) -> Double? {
        guard let value, value.isFinite, validRange.contains(value) else { return nil }
        return value.rounded()
    }

    /* The settings JSON is the compatible persistence boundary for this
       field. An explicit null means the user cleared it; only a missing key
       falls back to an older profile/cache value. */
    static func resolved(profile: Profile, settings: UserSettings?) -> Double? {
        if let settings,
           settings.userID == profile.userID,
           settings.addons.keys.contains("custom_bmr") {
            if settings.addons["custom_bmr_source"]?.stringValue == dexaReportEstimateSource {
                return nil
            }
            return validated(settings.addons["custom_bmr"]?.numberValue)
        }
        return validated(profile.customBMR)
    }

    static func provenance(profile: Profile, settings: UserSettings?) -> RestingEnergyProvenance? {
        if let settings,
           settings.userID == profile.userID,
           settings.addons.keys.contains("custom_bmr") {
            guard validated(settings.addons["custom_bmr"]?.numberValue) != nil else {
                return nil
            }
            switch settings.addons["custom_bmr_source"]?.stringValue {
            case RestingEnergyProvenance.indirectCalorimetry.rawValue:
                return .indirectCalorimetry
            case dexaReportEstimateSource:
                return nil
            default:
                return .legacyUserEntered
            }
        }
        return validated(profile.customBMR) == nil ? nil : .legacyUserEntered
    }

    static func reviewReasons(profile: Profile, settings: UserSettings?) -> Set<NutritionReviewReason> {
        if let settings,
           settings.userID == profile.userID,
           settings.addons.keys.contains("custom_bmr") {
            guard validated(settings.addons["custom_bmr"]?.numberValue) != nil else {
                return []
            }
            switch settings.addons["custom_bmr_source"]?.stringValue {
            case RestingEnergyProvenance.indirectCalorimetry.rawValue:
                return []
            case dexaReportEstimateSource:
                return [.dexaEstimatedBMRStored]
            default:
                return [.legacyBMRNeedsReview]
            }
        }
        return validated(profile.customBMR) == nil ? [] : [.legacyBMRNeedsReview]
    }

    static func storeDEXAReportEstimate(
        _ value: Double?,
        in addons: inout [String: JSONValue]
    ) {
        guard let value = validated(value) else { return }
        let existingIsIndirectMeasurement =
            addons["custom_bmr_source"]?.stringValue
                == RestingEnergyProvenance.indirectCalorimetry.rawValue
            && validated(addons["custom_bmr"]?.numberValue) != nil
        guard existingIsIndirectMeasurement == false else { return }
        addons["custom_bmr"] = .number(value)
        addons["custom_bmr_source"] = .string(dexaReportEstimateSource)
    }

    static func applied(to profile: Profile, settings: UserSettings?) -> Profile {
        var resolvedProfile = profile
        resolvedProfile.customBMR = resolved(profile: profile, settings: settings)
        return resolvedProfile
    }

    @discardableResult
    static func migrateLegacyProfileValue(
        in dashboard: inout DashboardData,
        ownerID: UUID,
        fallbackProfile: Profile? = nil
    ) -> UserSettings? {
        guard let profile = dashboard.profile,
              profile.userID == ownerID,
              var settings = dashboard.settings,
              settings.userID == ownerID,
              settings.addons.keys.contains("custom_bmr") == false
        else { return nil }
        let fallbackValue = fallbackProfile?.userID == ownerID
            ? fallbackProfile?.customBMR
            : nil
        guard let measured = validated(profile.customBMR) ?? validated(fallbackValue)
        else { return nil }
        settings.addons["custom_bmr"] = .number(measured)
        settings.addons["custom_bmr_source"] = .string(RestingEnergyProvenance.legacyUserEntered.rawValue)
        dashboard.settings = settings
        return settings
    }
}

enum EnergyEngine {
    static let calibrationLowerBound = 0.85
    static let calibrationUpperBound = 1.15
    static let calibrationLearningRate = 0.2

    static func bmr(for profile: Profile) -> Double {
        if let measured = profile.customBMR,
           measured.isFinite,
           (800...4_000).contains(measured) {
            return measured.rounded()
        }
        if ProfileIntegrityPolicy.isBodyFatEnergyEligible(profile),
           let bodyFatPercent = profile.bodyFatPercent {
            let leanMass = profile.weightKG * (1 - bodyFatPercent / 100)
            let estimate = 370 + 21.6 * leanMass
            return estimate.isFinite ? estimate : 0
        }

        let sexConstant = profile.sex.lowercased() == "female" ? -161.0 : 5.0
        let estimate = 10 * profile.weightKG
            + 6.25 * profile.heightCM
            - 5 * Double(profile.age)
            + sexConstant
        return estimate.isFinite ? estimate : 0
    }

    static func restingEnergyProvenance(
        for profile: Profile,
        settings: UserSettings?
    ) -> RestingEnergyProvenance {
        if let provenance = RestingEnergyPolicy.provenance(profile: profile, settings: settings) {
            return provenance
        }
        return ProfileIntegrityPolicy.isBodyFatEnergyEligible(profile)
            ? .bodyCompositionEstimate
            : .mifflinEstimate
    }

    static func blockCalories(
        type: ActivityType,
        quantity: Double,
        durationMinutes: Int?,
        distanceKM: Double?,
        watchKcal: Double?,
        weightKG: Double
    ) -> Double {
        let discountedWatch = max(0, watchKcal ?? 0) * 0.8
        let primary: Double

        switch type.inputStyle {
        case .distance:
            primary = max(0, distanceKM ?? 0) * weightKG * (type.distanceFactor ?? 1)
        case .steps:
            primary = max(0, quantity) * 0.00055 * weightKG
        case .watchKcal:
            primary = discountedWatch
        case .count, .duration:
            let minutes = Double(durationMinutes ?? type.defaultDurationMinutes ?? 0)
            let totalMinutes = type.inputStyle == .count ? minutes * max(quantity, 0) : minutes
            primary = max(0, type.met - 1.2) * weightKG * totalMinutes / 60
        }

        if type.supportsWatch, discountedWatch > 0 {
            return max(primary, discountedWatch)
        }
        return primary
    }

    static func resolvedActiveCalories(
        wearableActiveCalories: Int?,
        logs: [ActivityLog]
    ) -> Int {
        if let wearableActiveCalories, wearableActiveCalories > 0 {
            return wearableActiveCalories
        }
        let estimate = logs.reduce(0.0) { total, log in
            total + (log.computedKcal.isFinite ? max(0, log.computedKcal) : 0)
        }
        guard estimate < Double(Int.max) else { return Int.max }
        return Int(estimate.rounded())
    }

    static func hasMeaningfulActivity(
        wearableActiveCalories: Int?,
        logs: [ActivityLog]
    ) -> Bool {
        if let wearableActiveCalories, wearableActiveCalories > 0 { return true }
        return logs.contains { $0.computedKcal.isFinite && $0.computedKcal > 0 }
    }

    static func targets(
        profile: Profile,
        logs: [ActivityLog],
        catalog: [ActivityType],
        planContext: NutritionPlanContext? = nil,
        settings: UserSettings? = nil,
        wearableActiveCalories: Int? = nil
    ) -> NutritionTargets {
        let resolvedProfile = RestingEnergyPolicy.applied(to: profile, settings: settings)
        let bmr = bmr(for: resolvedProfile)
        let restingEnergyProvenance = restingEnergyProvenance(for: profile, settings: settings)
        let restingEnergyReviewReasons = RestingEnergyPolicy.reviewReasons(
            profile: profile,
            settings: settings
        )
        var reviewReasons = profileAgeReviewReasons(resolvedProfile)
        reviewReasons.formUnion(restingEnergyReviewReasons)
        reviewReasons.formUnion(standardInputReviewReasons(resolvedProfile))
        if restingEnergyInputIsInvalid(profile: profile, settings: settings) {
            reviewReasons.insert(.implausibleBMR)
        }
        if RestingEnergyPolicy.validRange.contains(bmr) == false {
            reviewReasons.insert(.implausibleBMR)
        }
        if let personal = personalTargets(
            profile: resolvedProfile,
            bmr: bmr,
            restingEnergyProvenance: restingEnergyProvenance,
            reviewReasons: reviewReasons
        ) {
            return personal
        }
        if reviewReasons.isDisjoint(with: [
            .underNineteen,
            .invalidBirthdate,
            .implausibleDemographics,
            .implausibleBMR,
        ]) == false {
            return blockedTargets(
                bmr: bmr,
                restingEnergyProvenance: restingEnergyProvenance,
                reviewReasons: reviewReasons
            )
        }

        let precise = hasMeaningfulActivity(
            wearableActiveCalories: wearableActiveCalories,
            logs: logs
        )
        let tdee: Double
        if precise {
            /* Whole-day wearable active energy already contains the effort
               represented by APEX activity blocks. It replaces their sum;
               adding both would count the same workout twice. */
            let activityEnergy: Double
            if let wearableActiveCalories, wearableActiveCalories > 0 {
                activityEnergy = Double(wearableActiveCalories)
            } else {
                activityEnergy = logs.reduce(0) { total, log in
                    total + (log.computedKcal.isFinite ? max(0, log.computedKcal) : 0)
                }
            }
            tdee = bmr * 1.2
                + min(max(resolvedProfile.calibrationK, 0.85), 1.15) * activityEnergy
        } else {
            tdee = bmr * resolvedProfile.activityLevel.multiplier
        }

        let baselineTDEE = bmr * resolvedProfile.activityLevel.multiplier
        guard bmr.isFinite,
              tdee.isFinite,
              RestingEnergyPolicy.validRange.contains(bmr) else {
            reviewReasons.insert(.implausibleBMR)
            return blockedTargets(
                bmr: bmr,
                restingEnergyProvenance: restingEnergyProvenance,
                reviewReasons: reviewReasons
            )
        }
        let pal = tdee / bmr
        let level = level(forPAL: pal)
        let factor = NutritionGoalPolicy.preset(
            for: resolvedProfile.goal,
            context: planContext
        ).factor
        let rawTarget = baselineTDEE * factor
        guard rawTarget.isFinite,
              rawTarget > 0,
              rawTarget <= Double(Int.max) else {
            reviewReasons.insert(.implausibleDemographics)
            return blockedTargets(
                bmr: bmr,
                restingEnergyProvenance: restingEnergyProvenance,
                reviewReasons: reviewReasons
            )
        }
        let roundedTarget = Int(rawTarget.rounded())
        let macros = macroTargets(
            weightKG: resolvedProfile.weightKG,
            level: resolvedProfile.activityLevel,
            goal: resolvedProfile.goal,
            targetCalories: roundedTarget
        )
        if macros.requiresReview {
            reviewReasons.insert(.macroEnergyConflict)
            return blockedTargets(
                bmr: bmr,
                tdee: tdee,
                targetCalories: roundedTarget,
                pal: pal,
                level: level,
                restingEnergyProvenance: restingEnergyProvenance,
                reviewReasons: reviewReasons
            )
        }
        let clinicalFloor = resolvedProfile.sex.lowercased() == "female" ? 1_200 : 1_500
        if roundedTarget < clinicalFloor {
            reviewReasons.insert(.lowCalorieTarget)
        }

        return NutritionTargets(
            bmr: Int(bmr.rounded()),
            tdee: Int(tdee.rounded()),
            targetCalories: roundedTarget,
            proteinG: macros.proteinG,
            fatG: macros.fatG,
            carbsG: macros.carbsG,
            pal: (pal * 100).rounded() / 100,
            level: level,
            restingEnergyProvenance: restingEnergyProvenance,
            targetProvenance: .calculatedEstimate,
            reviewReasons: reviewReasons
        )
    }

    static func targetCalories(
        bmr: Double,
        tdee: Double,
        goal: Goal,
        planContext: NutritionPlanContext? = nil
    ) -> Int {
        let factor = NutritionGoalPolicy.preset(for: goal, context: planContext).factor
        let target = tdee * factor
        guard bmr.isFinite,
              tdee.isFinite,
              target.isFinite,
              RestingEnergyPolicy.validRange.contains(bmr),
              tdee > 0,
              target > 0,
              target <= Double(Int.max) else { return 0 }
        return Int(target.rounded())
    }

    static func usesPersonalProtocol(_ profile: Profile) -> Bool {
        guard let protocolID = ProfileIntegrityPolicy.authorizedProtocol(for: profile),
              let persona = personalPersona(for: protocolID)
        else { return false }
        return FitnessBrainTargets.personalProtocols[persona] != nil
    }

    private static func personalTargets(
        profile: Profile,
        bmr: Double,
        restingEnergyProvenance: RestingEnergyProvenance,
        reviewReasons: Set<NutritionReviewReason>
    ) -> NutritionTargets? {
        guard let protocolID = ProfileIntegrityPolicy.authorizedProtocol(for: profile),
              let persona = personalPersona(for: protocolID),
              let level = FBActivityLevel(rawValue: profile.activityLevel.rawValue),
              let goal = FBGoal(rawValue: profile.goal.rawValue),
              let personal = FitnessBrainTargets.personalProtocols[persona],
              let target = personal.calories[goal]?[level],
              let tdee = personal.calories[.maintain]?[level],
              let protein = personal.protein[goal],
              let fat = personal.fat[goal],
              [target, tdee, protein, fat].allSatisfy(\.isFinite),
              target > 0,
              tdee > 0,
              protein > 0,
              fat > 0
        else { return nil }
        let carbs = FitnessBrainTargets.carbohydrateGrams(
            kcal: target,
            proteinG: protein,
            fatG: fat
        )
        let targetSafeBMR = RestingEnergyPolicy.validated(bmr) ?? 0
        guard carbs.isFinite,
              carbs >= 0,
              protein * 4 + fat * 9 + carbs * 4 <= target else { return nil }
        return NutritionTargets(
            bmr: Int(targetSafeBMR),
            tdee: Int(tdee.rounded()),
            targetCalories: Int(target.rounded()),
            proteinG: Int(protein.rounded()),
            fatG: Int(fat.rounded()),
            carbsG: Int(carbs.rounded()),
            pal: targetSafeBMR > 0
                ? ((tdee / targetSafeBMR) * 100).rounded() / 100
                : 0,
            /* Bespoke tables are explicit whole-day modes. Their selected
               mode remains the label even when its quotient crosses a
               generic PAL threshold. */
            level: profile.activityLevel,
            restingEnergyProvenance: restingEnergyProvenance,
            targetProvenance: .authoredProtocol,
            reviewReasons: reviewReasons
        )
    }

    private static func personalPersona(
        for protocolID: ProfileIntegrityPolicy.ProtocolID
    ) -> FBPersona? {
        switch protocolID {
        case .constantineV85: .constantine
        case .juneV84: .june
        case .matthewV1, .iulianV2: nil
        }
    }

    static func macroTargets(
        weightKG: Double,
        level: ActivityLevel,
        goal: Goal,
        targetCalories: Int
    ) -> EnergyMacroTargets {
        guard weightKG.isFinite,
              (30...300).contains(weightKG),
              targetCalories > 0 else {
            return EnergyMacroTargets(
                proteinG: 0,
                fatG: 0,
                carbsG: 0,
                requiresReview: true
            )
        }
        let baseProtein: Double = switch level {
        case .sedentary: 1.6
        case .light: 1.75
        case .moderate: 1.9
        case .very: 2.0
        case .extra: 2.1
        }
        let goalProteinAdjustment: Double = switch goal {
        case .recomp: 0.2
        case .maintain: 0
        case .bulk: -0.1
        }
        let proteinPerKG = min(2.4, max(1.6, baseProtein + goalProteinAdjustment))
        let protein = max(1, Int((weightKG * proteinPerKG).rounded()))

        let fatEnergyShare: Double = switch goal {
        case .recomp: 0.25
        case .maintain: 0.275
        case .bulk: 0.28
        }
        let fatFloorPerKG: Double = switch goal {
        case .recomp: 0.7
        case .maintain, .bulk: 0.8
        }
        let fatFromEnergy = Double(targetCalories) * fatEnergyShare / 9
        let fatFloor = weightKG * fatFloorPerKG
        let fat = max(1, Int(max(fatFloor, fatFromEnergy).rounded()))
        let resolvedProtein = protein
        let requestedEnergy = resolvedProtein * 4 + fat * 9
        let requiresReview = requestedEnergy > targetCalories
        if requiresReview {
            return EnergyMacroTargets(
                proteinG: 0,
                fatG: 0,
                carbsG: 0,
                requiresReview: true
            )
        }
        let carbohydrateEnergy = max(0, targetCalories - resolvedProtein * 4 - fat * 9)
        let carbs = Int((Double(carbohydrateEnergy) / 4).rounded(.down))
        return EnergyMacroTargets(
            proteinG: resolvedProtein,
            fatG: fat,
            carbsG: carbs,
            requiresReview: requiresReview
        )
    }

    private static func profileAgeReviewReasons(_ profile: Profile) -> Set<NutritionReviewReason> {
        guard let age = FitnessBrainTargets.validAgeFrom(
            birthdate: profile.birthdate,
            asOf: Date().apexDateKey
        ) else {
            return [.invalidBirthdate]
        }
        if age < 19 { return [.underNineteen] }
        if age > 100 { return [.implausibleDemographics] }
        return []
    }

    private static func standardInputReviewReasons(
        _ profile: Profile
    ) -> Set<NutritionReviewReason> {
        guard profile.weightKG.isFinite,
              (30...300).contains(profile.weightKG),
              profile.heightCM.isFinite,
              (120...230).contains(profile.heightCM),
              ["male", "female"].contains(profile.sex.lowercased()) else {
            return [.implausibleDemographics]
        }
        return []
    }

    private static func restingEnergyInputIsInvalid(
        profile: Profile,
        settings: UserSettings?
    ) -> Bool {
        if let settings,
           settings.userID == profile.userID,
           let stored = settings.addons["custom_bmr"] {
            switch stored {
            case .null:
                return false
            case .number(let value):
                return RestingEnergyPolicy.validated(value) == nil
            default:
                return true
            }
        }
        guard let value = profile.customBMR else { return false }
        return RestingEnergyPolicy.validated(value) == nil
    }

    private static func blockedTargets(
        bmr: Double,
        tdee: Double = 0,
        targetCalories: Int = 0,
        pal: Double = 0,
        level: ActivityLevel = .sedentary,
        restingEnergyProvenance: RestingEnergyProvenance,
        reviewReasons: Set<NutritionReviewReason>
    ) -> NutritionTargets {
        func safeInt(_ value: Double) -> Int {
            guard value.isFinite,
                  value >= 0,
                  value <= Double(Int.max) else { return 0 }
            return Int(value.rounded())
        }
        return NutritionTargets(
            bmr: safeInt(bmr),
            tdee: safeInt(tdee),
            targetCalories: max(0, targetCalories),
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            pal: pal.isFinite ? max(0, pal) : 0,
            level: level,
            restingEnergyProvenance: restingEnergyProvenance,
            targetProvenance: .calculatedEstimate,
            reviewReasons: reviewReasons
        )
    }

    static func level(forPAL pal: Double) -> ActivityLevel {
        if pal < 1.40 { return .sedentary }
        if pal < 1.55 { return .light }
        if pal < 1.75 { return .moderate }
        if pal < 2.00 { return .very }
        return .extra
    }

    /// Returns a seven-sample exponential moving average. Missing days should
    /// be removed before calling this function rather than represented as zero.
    static func weightEMA(_ weights: [Double], period: Int = 7) -> [Double] {
        guard let first = weights.first else { return [] }
        let alpha = 2 / (Double(max(period, 1)) + 1)
        return weights.dropFirst().reduce(into: [first]) { values, weight in
            let previous = values.last ?? weight
            values.append(alpha * weight + (1 - alpha) * previous)
        }
    }

    /// Learns only a conservative correction to activity-block expenditure.
    /// Weight change is converted to a daily energy balance after smoothing.
    static func calibratedK(
        currentK: Double,
        meanDailyIntake: Double,
        predictedDailyTDEE: Double,
        startingEMAWeight: Double,
        endingEMAWeight: Double,
        elapsedDays: Int
    ) -> Double {
        guard predictedDailyTDEE > 0, elapsedDays > 0 else {
            return min(max(currentK, calibrationLowerBound), calibrationUpperBound)
        }
        let dailyStoredEnergy = (endingEMAWeight - startingEMAWeight) * 7_700 / Double(elapsedDays)
        let observedDailyTDEE = meanDailyIntake - dailyStoredEnergy
        let correction = calibrationLearningRate * (observedDailyTDEE - predictedDailyTDEE) / predictedDailyTDEE
        return min(max(currentK + correction, calibrationLowerBound), calibrationUpperBound)
    }
}
