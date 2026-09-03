/*
 * Nutrition targets, ported 1:1 from src/lib/nutrition.ts and
 * src/lib/personalProtocol.ts. Constantine and June run on the personal
 * calorie protocols only when the immutable account policy authorizes them;
 * everyone else uses the BMR formula path.
 */
import Foundation

public enum FitnessBrainTargets {
    static let activityFactor: [FBActivityLevel: Double] = [
        .sedentary: 1.2, .light: 1.375, .moderate: 1.55, .very: 1.725, .extra: 1.9,
    ]

    static let goalFactor: [FBGoal: Double] = [.recomp: 0.90, .maintain: 1, .bulk: 1.05]

    static let proteinGPerKG: [FBActivityLevel: Double] = [
        .sedentary: 1.6, .light: 1.75, .moderate: 1.9, .very: 2, .extra: 2.1,
    ]
    static let goalProteinAdjustment: [FBGoal: Double] = [.recomp: 0.2, .maintain: 0, .bulk: -0.1]
    static let fatEnergyShare: [FBGoal: Double] = [.recomp: 0.25, .maintain: 0.275, .bulk: 0.28]
    static let fatFloorGPerKG: [FBGoal: Double] = [.recomp: 0.7, .maintain: 0.8, .bulk: 0.8]

    struct PersonalProtocol {
        let calories: [FBGoal: [FBActivityLevel: Double]]
        let protein: [FBGoal: Double]
        let fat: [FBGoal: Double]
    }

    static func levelTable(_ values: [Double]) -> [FBActivityLevel: Double] {
        let levels: [FBActivityLevel] = [.sedentary, .light, .moderate, .very, .extra]
        return Dictionary(uniqueKeysWithValues: zip(levels, values))
    }

    static let personalProtocols: [FBPersona: PersonalProtocol] = [
        .constantine: PersonalProtocol(
            calories: [
                .recomp: levelTable([2300, 2400, 2450, 2650, 2900]),
                .maintain: levelTable([2400, 2500, 2550, 2750, 3000]),
                .bulk: levelTable([2550, 2650, 2700, 2900, 3150]),
            ],
            protein: [.recomp: 150, .maintain: 150, .bulk: 150],
            fat: [.recomp: 75, .maintain: 80, .bulk: 85]
        ),
        .june: PersonalProtocol(
            calories: [
                .recomp: levelTable([2200, 2200, 2200, 2350, 2550]),
                .maintain: levelTable([2200, 2250, 2300, 2450, 2650]),
                .bulk: levelTable([2300, 2350, 2400, 2550, 2750]),
            ],
            protein: [.recomp: 85, .maintain: 85, .bulk: 85],
            fat: [.recomp: 90, .maintain: 92, .bulk: 95]
        ),
    ]

    /* JS Math.round: half rounds toward positive infinity. All inputs here
       are positive, where that equals half-away-from-zero. */
    static func jsRound(_ v: Double) -> Double {
        (v).rounded(.toNearestOrAwayFromZero)
    }

    public static func ageFrom(birthdate: String, asOf: String) -> Int {
        guard let age = validAgeFrom(birthdate: birthdate, asOf: asOf) else { return 0 }
        return age
    }

    public static func validAgeFrom(birthdate: String, asOf: String) -> Int? {
        guard let b = FBDate.validDate(birthdate),
              let a = FBDate.validDate(asOf),
              b <= a else { return nil }
        var years = a.year - b.year
        if (a.month, a.day) < (b.month, b.day) { years -= 1 }
        return years
    }

    public static func bmrMifflin(_ p: FBProfile, asOf: String) -> Double {
        guard let resolvedAge = validAgeFrom(birthdate: p.birthdate, asOf: asOf),
              p.weightKG.isFinite,
              p.heightCM.isFinite,
              ["male", "female"].contains(p.sex) else { return 0 }
        let age = Double(resolvedAge)
        let base = 10 * p.weightKG + 6.25 * p.heightCM - 5 * age
        let estimate = base + (p.sex == "male" ? 5 : -161)
        return estimate.isFinite ? jsRound(estimate) : 0
    }

    public static func bmrKatch(_ p: FBProfile) -> Double? {
        guard ProfileIntegrityPolicy.isBodyFatEnergyEligible(
            value: p.bodyFatPct,
            source: p.bodyFatSource.flatMap(ProfileIntegrityPolicy.BodyFatSource.init(rawValue:))
        ), let bodyFatPct = p.bodyFatPct,
           p.weightKG.isFinite else { return nil }
        let lean = p.weightKG * (1 - bodyFatPct / 100)
        let estimate = 370 + 21.6 * lean
        return estimate.isFinite ? jsRound(estimate) : nil
    }

    static func carbohydrateGrams(kcal: Double, proteinG: Double, fatG: Double) -> Double {
        max(0, ((kcal - proteinG * 4 - fatG * 9) / 4).rounded(.down))
    }

    public static func computeTargets(
        _ p: FBProfile,
        asOf: String,
        trainingGoal: String? = nil,
        planWeeks: Int? = nil
    ) -> FBTargets {
        let katch = bmrKatch(p)
        let mifflin = bmrMifflin(p, asOf: asOf)
        let hasCustomBMR = p.customBMR.map {
            $0.isFinite && $0 >= 800 && $0 <= 4_000
        } ?? false
        let activeBMR = hasCustomBMR ? jsRound(p.customBMR ?? 0) : katch ?? mifflin

        if let persona = authorizedPersonalPersona(p),
           let proto = personalProtocols[persona],
           let kcal = proto.calories[p.goal]?[p.activityLevel],
           let proteinG = proto.protein[p.goal],
           let fatG = proto.fat[p.goal],
           let tdee = proto.calories[.maintain]?[p.activityLevel] {
            return FBTargets(
                bmrMifflin: mifflin,
                bmrKatch: katch,
                tdee: tdee,
                kcal: kcal,
                proteinG: proteinG,
                fatG: fatG,
                carbsG: carbohydrateGrams(kcal: kcal, proteinG: proteinG, fatG: fatG),
                waterL: persona == .june ? 2.2 : 2.75
            )
        }

        guard standardProfileIsValid(p, asOf: asOf),
              p.customBMR == nil || hasCustomBMR,
              activeBMR.isFinite,
              (800...4_000).contains(activeBMR) else {
            return blockedTargets(mifflin: mifflin, katch: katch)
        }

        let activityFactorValue = activityFactor[p.activityLevel] ?? 1.2
        let tdee = jsRound(activeBMR * activityFactorValue)
        let planContext = trainingGoal.map {
            NutritionPlanContext(
                trainingGoal: NutritionGoalPolicy.normalizedTrainingGoal($0),
                planWeeks: NutritionGoalPolicy.normalizedPlanWeeks(planWeeks)
            )
        }
        let goal = Goal(rawValue: p.goal.rawValue) ?? .maintain
        let factor = NutritionGoalPolicy.preset(for: goal, context: planContext).factor
        let kcal = jsRound(tdee * factor)
        let proteinPerKG = min(
            2.4,
            max(
                1.6,
                (proteinGPerKG[p.activityLevel] ?? 1.6)
                    + (goalProteinAdjustment[p.goal] ?? 0)
            )
        )
        let proteinG = jsRound(p.weightKG * proteinPerKG)
        let fatFromEnergy = kcal * (fatEnergyShare[p.goal] ?? 0.275) / 9
        let fatFloor = p.weightKG * (fatFloorGPerKG[p.goal] ?? 0.8)
        let fatG = jsRound(max(fatFloor, fatFromEnergy))
        let requestedMacroEnergy = proteinG * 4 + fatG * 9
        if requestedMacroEnergy > kcal {
            return blockedTargets(mifflin: mifflin, katch: katch)
        }
        let carbsG = max(0, ((kcal - proteinG * 4 - fatG * 9) / 4).rounded(.down))
        return FBTargets(
            bmrMifflin: mifflin, bmrKatch: katch, tdee: tdee, kcal: kcal,
            proteinG: proteinG, fatG: fatG, carbsG: carbsG, waterL: 2.75
        )
    }

    private static func standardProfileIsValid(_ profile: FBProfile, asOf: String) -> Bool {
        guard let age = validAgeFrom(birthdate: profile.birthdate, asOf: asOf) else {
            return false
        }
        return (19...100).contains(age)
            && profile.weightKG.isFinite
            && (30...300).contains(profile.weightKG)
            && profile.heightCM.isFinite
            && (120...230).contains(profile.heightCM)
            && ["male", "female"].contains(profile.sex)
    }

    private static func blockedTargets(mifflin: Double, katch: Double?) -> FBTargets {
        FBTargets(
            bmrMifflin: mifflin.isFinite ? max(0, mifflin) : 0,
            bmrKatch: katch?.isFinite == true ? katch : nil,
            tdee: 0,
            kcal: 0,
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            waterL: 2.75
        )
    }

    private static func authorizedPersonalPersona(_ profile: FBProfile) -> FBPersona? {
        guard let userID = UUID(uuidString: profile.userID),
              let persona = Persona(rawValue: profile.persona.rawValue),
              let kind = profile.profileKind.flatMap(ProfileIntegrityPolicy.Kind.init(rawValue:)),
              let protocolID = profile.bespokeProtocolID.flatMap(ProfileIntegrityPolicy.ProtocolID.init(rawValue:)),
              let authorized = ProfileIntegrityPolicy.authorizedProtocol(
                userID: userID,
                persona: persona,
                kind: kind,
                protocolID: protocolID
              )
        else { return nil }
        switch authorized {
        case .constantineV85: return .constantine
        case .juneV84: return .june
        case .matthewV1, .iulianV2: return nil
        }
    }
}

/* Pure yyyy-MM-dd arithmetic. No Calendar, no time zones, fully
   deterministic: the same math the web engine does with local-noon Dates. */
public enum FBDate {
    public struct YMD: Comparable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int

        public static func < (l: YMD, r: YMD) -> Bool {
            (l.year, l.month, l.day) < (r.year, r.month, r.day)
        }
    }

    public static func parse(_ iso: String) -> YMD {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return YMD(year: 1970, month: 1, day: 1) }
        return YMD(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func validDate(_ iso: String) -> YMD? {
        let components = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month) else { return nil }
        let leap = year.isMultiple(of: 400)
            || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { return nil }
        return YMD(year: year, month: month, day: day)
    }

    /* Howard Hinnant's days-from-civil algorithm */
    public static func dayNumber(_ iso: String) -> Int {
        let d = parse(iso)
        var y = d.year
        let m = d.month
        if m <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public static func daysBetween(_ from: String, _ to: String) -> Int {
        dayNumber(to) - dayNumber(from)
    }

    public static func addDays(_ iso: String, _ days: Int) -> String {
        var z = dayNumber(iso) + days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        z -= era * 146097
        let yoe = (z - z / 1460 + z / 36524 - z / 146096) / 365
        let y = yoe + era * 400
        let doy = z - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        let year = m <= 2 ? y + 1 : y
        return String(format: "%04d-%02d-%02d", year, m, d)
    }
}
