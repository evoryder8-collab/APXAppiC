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

    static let goalFactor: [FBGoal: Double] = [.recomp: 0.89, .maintain: 1, .bulk: 1.07]

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
        let b = FBDate.parse(birthdate)
        let a = FBDate.parse(asOf)
        var years = a.year - b.year
        if (a.month, a.day) < (b.month, b.day) { years -= 1 }
        return years
    }

    public static func bmrMifflin(_ p: FBProfile, asOf: String) -> Double {
        let age = Double(ageFrom(birthdate: p.birthdate, asOf: asOf))
        let base = 10 * p.weightKG + 6.25 * p.heightCM - 5 * age
        return jsRound(base + (p.sex == "male" ? 5 : -161))
    }

    public static func bmrKatch(_ p: FBProfile) -> Double? {
        guard ProfileIntegrityPolicy.isBodyFatEnergyEligible(
            value: p.bodyFatPct,
            source: p.bodyFatSource.flatMap(ProfileIntegrityPolicy.BodyFatSource.init(rawValue:))
        ), let bodyFatPct = p.bodyFatPct else { return nil }
        let lean = p.weightKG * (1 - bodyFatPct / 100)
        return jsRound(370 + 21.6 * lean)
    }

    static func carbohydrateGrams(kcal: Double, proteinG: Double, fatG: Double) -> Double {
        max(0, jsRound((kcal - proteinG * 4 - fatG * 9) / 4))
    }

    public static func computeTargets(_ p: FBProfile, asOf: String) -> FBTargets {
        let katch = bmrKatch(p)
        let mifflin = bmrMifflin(p, asOf: asOf)
        let hasCustomBMR = p.customBMR.map { $0 >= 800 && $0 <= 4000 } ?? false
        let activeBMR = hasCustomBMR ? jsRound(p.customBMR!) : katch ?? mifflin

        if let persona = authorizedPersonalPersona(p),
           let proto = personalProtocols[persona] {
            let kcal = proto.calories[p.goal]![p.activityLevel]!
            let proteinG = proto.protein[p.goal]!
            let fatG = proto.fat[p.goal]!
            return FBTargets(
                bmrMifflin: mifflin,
                bmrKatch: katch,
                tdee: proto.calories[.maintain]![p.activityLevel]!,
                kcal: kcal,
                proteinG: proteinG,
                fatG: fatG,
                carbsG: carbohydrateGrams(kcal: kcal, proteinG: proteinG, fatG: fatG),
                waterL: persona == .june ? 2.2 : 2.75
            )
        }

        let tdee = jsRound(activeBMR * activityFactor[p.activityLevel]!)
        let kcal = jsRound(max(activeBMR * 1.05, tdee * goalFactor[p.goal]!))
        let proteinPerKG = min(2.4, max(1.6, proteinGPerKG[p.activityLevel]! + goalProteinAdjustment[p.goal]!))
        let proteinG = jsRound(p.weightKG * proteinPerKG)
        let fatFromEnergy = kcal * fatEnergyShare[p.goal]! / 9
        let fatFloor = p.weightKG * fatFloorGPerKG[p.goal]!
        let fatG = jsRound(max(fatFloor, fatFromEnergy))
        let carbsG = max(0, jsRound((kcal - proteinG * 4 - fatG * 9) / 4))
        return FBTargets(
            bmrMifflin: mifflin, bmrKatch: katch, tdee: tdee, kcal: kcal,
            proteinG: proteinG, fatG: fatG, carbsG: carbsG, waterL: 2.75
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
