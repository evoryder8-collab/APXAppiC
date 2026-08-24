import Foundation

struct NutritionTargets: Equatable, Sendable {
    let bmr: Int
    let tdee: Int
    let targetCalories: Int
    let proteinG: Int
    let fatG: Int
    let carbsG: Int
    let pal: Double
    let level: ActivityLevel
    let safetyFloorApplied: Bool
}

struct EnergyMacroTargets: Equatable, Sendable {
    let proteinG: Int
    let fatG: Int
    let carbsG: Int
}

enum EnergyEngine {
    static let calibrationLowerBound = 0.85
    static let calibrationUpperBound = 1.15
    static let calibrationLearningRate = 0.2

    static func bmr(for profile: Profile) -> Double {
        if profile.bodyFatPercent > 0, profile.bodyFatPercent < 70 {
            let leanMass = profile.weightKG * (1 - profile.bodyFatPercent / 100)
            return 370 + 21.6 * leanMass
        }

        let sexConstant = profile.sex.lowercased() == "female" ? -161.0 : 5.0
        return 10 * profile.weightKG + 6.25 * profile.heightCM - 5 * Double(profile.age) + sexConstant
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

    static func targets(profile: Profile, logs: [ActivityLog], catalog: [ActivityType]) -> NutritionTargets {
        let bmr = bmr(for: profile)
        let precise = !logs.isEmpty
        let tdee: Double
        if precise {
            let blockSum = logs.reduce(0) { $0 + max(0, $1.computedKcal) }
            tdee = bmr * 1.2 + min(max(profile.calibrationK, 0.85), 1.15) * blockSum
        } else {
            tdee = bmr * profile.activityLevel.multiplier
        }

        let pal = tdee / max(bmr, 1)
        let level = level(forPAL: pal)
        let rawTarget = tdee * profile.goal.factor
        let floor = bmr * 1.05
        let target = max(rawTarget, floor)
        let roundedTarget = Int(target.rounded())
        let macros = macroTargets(
            weightKG: profile.weightKG,
            level: level,
            goal: profile.goal,
            targetCalories: roundedTarget
        )

        return NutritionTargets(
            bmr: Int(bmr.rounded()),
            tdee: Int(tdee.rounded()),
            targetCalories: roundedTarget,
            proteinG: macros.proteinG,
            fatG: macros.fatG,
            carbsG: macros.carbsG,
            pal: (pal * 100).rounded() / 100,
            level: level,
            safetyFloorApplied: rawTarget < floor
        )
    }

    static func macroTargets(
        weightKG: Double,
        level: ActivityLevel,
        goal: Goal,
        targetCalories: Int
    ) -> EnergyMacroTargets {
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
        let carbohydrateEnergy = max(0, targetCalories - protein * 4 - fat * 9)
        let carbs = Int((Double(carbohydrateEnergy) / 4).rounded())
        return EnergyMacroTargets(proteinG: protein, fatG: fat, carbsG: carbs)
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
