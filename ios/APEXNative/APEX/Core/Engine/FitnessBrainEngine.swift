/*
 * The interconnection brain, ported 1:1 from src/lib/rpg.ts.
 *
 * Deterministic daily replay from the baseline date: nutrition modulates
 * training XP, mobility pays joint bonuses after leg days, wearable imports
 * feed stats at reduced credit, VO2max anchors Endurance, recovery
 * check-ins and meal rhythm verdicts adjust Health, and every stat decays
 * toward its floor on its own physiological half-life when it starves.
 * Every rule that fires emits a synergy event with the exact label the web
 * app produces; the parity test suite holds both engines to the decimal.
 */
import Foundation

public struct StatBlock: Sendable {
    public var health: Double
    public var joint: Double
    public var flexibility: Double
    public var endurance: Double
    public var strengthUpper: Double
    public var strengthLower: Double
}

public enum FitnessBrainEngine {
    // MARK: - Calibration (mirrors rpg.ts constants)

    static let baselineConstantine = StatBlock(
        health: 60, joint: 55, flexibility: 40, endurance: 45, strengthUpper: 60, strengthLower: 42)
    static let baselineJune = StatBlock(
        health: 68, joint: 58, flexibility: 65, endurance: 70, strengthUpper: 70, strengthLower: 78)
    static let baselineMatthew = StatBlock(
        health: 72, joint: 65, flexibility: 60, endurance: 82, strengthUpper: 72, strengthLower: 68)

    static let floors = StatBlock(
        health: 40, joint: 35, flexibility: 28, endurance: 30, strengthUpper: 45, strengthLower: 32)
    static let halfLife = StatBlock(
        health: 10, joint: 40, flexibility: 8.5, endurance: 12, strengthUpper: 31, strengthLower: 31)

    static let weightStrength = 0.25
    static let weightEndurance = 0.2
    static let weightFlexibility = 0.15
    static let weightJoint = 0.2
    static let weightHealth = 0.2

    public static let legXPBoost = 1.25
    static let ageDragPerDay = 0.45 / 365
    static let convergenceGap = 3.0
    static let importCredit = 0.6

    public static func baseline(for persona: FBPersona) -> StatBlock {
        switch persona {
        case .june: return baselineJune
        case .matthew: return baselineMatthew
        default: return baselineConstantine
        }
    }

    public static func overall(of s: StatBlock) -> Double {
        let strength = (s.strengthUpper + s.strengthLower) / 2
        return weightStrength * strength + weightEndurance * s.endurance
            + weightFlexibility * s.flexibility + weightJoint * s.joint + weightHealth * s.health
    }

    static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    static func decay(_ value: Double, floor: Double, halfLife: Double) -> Double {
        floor + (value - floor) * pow(2, -1 / halfLife)
    }

    static func headroom(_ stat: Double) -> Double { max(0.1, 1 - stat / 110) }

    public static func vo2ToStat(_ vo2: Double) -> Double { min(95, max(20, vo2 * 1.35)) }

    static func round1(_ v: Double) -> Double { (v * 10).rounded(.toNearestOrAwayFromZero) / 10 }

    /* JS number.toFixed for the label strings */
    static func fixed(_ v: Double, _ digits: Int) -> String {
        let p = pow(10.0, Double(digits))
        let r = (v * p).rounded(.toNearestOrAwayFromZero) / p
        return String(format: "%.\(digits)f", r)
    }

    // MARK: - Per-day activity index

    struct TypeEntry {
        let type: FBDayType
        let quality: Double
        let deload: Bool
        let recovery: Bool
    }

    final class DayActivity {
        var types: [TypeEntry] = []
        var overrides = 0
        var overloadUpper = 0
        var overloadLower = 0
        var waterL: Double?
        var kcal: Double?
        var protein: Double?
        var importStrengthMin = 0.0
        var importEnduranceMin = 0.0
        var importMobilityMin = 0.0
        var vo2: Double?
        var recoveryScore: Double?
        var recoverySource: FBRecoverySource?
        var mealRhythmScore: Double?
        var mealCompletionScore: Double?
        var mealRhythmVerdict: FBMealRhythmVerdict?
        var streak = 0
    }

    static let upperTypes: Set<FBDayType> = [.push, .pull, .upper]
    static let lowerTypes: Set<FBDayType> = [.legsA, .legsB]
    static let flexTypes: Set<FBDayType> = [.mobility, .fix]

    /* Mirrors focusT25.isConditioningFocusT25: a Focus T25 log name that is
       not a pure stretch session counts as conditioning. */
    static func isConditioningFocusT25(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasPrefix("focus t25") else { return false }
        return !lower.contains("stretch")
    }

    /* Mirrors mealRhythm.normalizeMealRhythmHistory for the fields the
       engine consumes. */
    struct RhythmDay {
        let date: String
        let finalized: Bool
        let completionScore: Double
        let rhythmScore: Double
        let verdict: FBMealRhythmVerdict
    }

    static func normalizeRhythm(_ history: [String: FBMealRhythmDayRaw]) -> [RhythmDay] {
        var out: [RhythmDay] = []
        for (key, raw) in history {
            guard key.count == 10, key[key.index(key.startIndex, offsetBy: 4)] == "-" else { continue }
            let expected = max(0, min(20, FitnessBrainTargets.jsRound(raw.expectedMeals ?? 0)))
            let logged = max(0, min(30, FitnessBrainTargets.jsRound(raw.loggedMeals ?? 0)))
            let completion = max(0, min(100, FitnessBrainTargets.jsRound(raw.completionScore ?? 0)))
            let rhythm = max(0, min(100, FitnessBrainTargets.jsRound(raw.rhythmScore ?? 0)))
            let finalized = raw.finalized ?? false
            let verdict: FBMealRhythmVerdict
            if let v = raw.verdict, let parsed = FBMealRhythmVerdict(rawValue: v) {
                verdict = parsed
            } else if finalized {
                verdict = logged == 0 ? .noMeals : logged < expected ? .missedMeals : .completeIrregular
            } else {
                verdict = .open
            }
            out.append(RhythmDay(
                date: key, finalized: finalized, completionScore: completion,
                rhythmScore: rhythm, verdict: verdict))
        }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: - The replay

    public static func compute(_ input: FBEngineInput, throughDate: String) -> FBEngineResult {
        let profile = input.profile
        let start = profile.baselineDate
        let total = FBDate.daysBetween(start, throughDate)
        if total < 0 { return FBEngineResult(snapshots: [], synergies: []) }

        var dayTypeByID: [String: FBDayType] = [:]
        for d in input.programDays { dayTypeByID[d.id] = d.dayType }
        let targets = FitnessBrainTargets.computeTargets(profile, asOf: throughDate)

        var activity: [String: DayActivity] = [:]
        func day(_ date: String) -> DayActivity {
            if let a = activity[date] { return a }
            let a = DayActivity()
            activity[date] = a
            return a
        }

        var sessionByID: [String: FBWorkoutSession] = [:]
        for s in input.workoutSessions { sessionByID[s.id] = s }

        for s in input.workoutSessions where s.completed {
            guard let type = dayTypeByID[s.programDayID] else { continue }
            day(s.date).types.append(TypeEntry(
                type: type,
                quality: s.qualityScore == 0 ? 1 : s.qualityScore,
                deload: s.isDeload,
                recovery: s.isEventRecovery))
        }
        /* Focus T25 conditioning logged inside any completed session */
        for log in input.workoutLogs {
            guard let s = sessionByID[log.sessionID], s.completed, !log.skipped,
                  isConditioningFocusT25(log.exerciseName) else { continue }
            let d = day(s.date)
            if !d.types.contains(where: { $0.type == .t25 }) {
                d.types.append(TypeEntry(type: .t25, quality: 1, deload: s.isDeload, recovery: false))
            }
        }
        for log in input.workoutLogs {
            guard let s = sessionByID[log.sessionID] else { continue }
            if log.overrideFlag { day(s.date).overrides += 1 }
        }

        /* Progressive overload: top weight rises vs the previous session */
        var byExercise: [String: [(date: String, w: Double)]] = [:]
        var exerciseOrder: [String] = []
        for log in input.workoutLogs {
            guard let exID = log.exerciseID, !log.skipped, let w = log.weightKG,
                  let s = sessionByID[log.sessionID] else { continue }
            if byExercise[exID] == nil { exerciseOrder.append(exID) }
            byExercise[exID, default: []].append((s.date, w))
        }
        var exerciseDayByID: [String: String] = [:]
        for e in input.exercises { exerciseDayByID[e.id] = e.programDayID }
        for exID in exerciseOrder {
            var byDate: [String: Double] = [:]
            for entry in byExercise[exID] ?? [] {
                byDate[entry.date] = max(byDate[entry.date] ?? 0, entry.w)
            }
            let dates = byDate.keys.sorted()
            for i in 1..<max(1, dates.count) where dates.count > 1 {
                if (byDate[dates[i]] ?? 0) > (byDate[dates[i - 1]] ?? 0) {
                    let type = exerciseDayByID[exID].flatMap { dayTypeByID[$0] }
                    let a = day(dates[i])
                    if let type, lowerTypes.contains(type) { a.overloadLower += 1 }
                    else { a.overloadUpper += 1 }
                }
            }
        }

        for d in input.dailyLogs {
            let a = day(d.date)
            a.waterL = d.waterL
            a.kcal = d.kcal
            a.protein = d.proteinG
        }
        for imp in input.importedActivities {
            let a = day(imp.date)
            switch imp.kind {
            case .strength: a.importStrengthMin += imp.durationMin
            case .endurance: a.importEnduranceMin += imp.durationMin
            case .mobility: a.importMobilityMin += imp.durationMin
            }
        }
        for m in input.healthMetrics {
            if let vo2 = m.vo2max { day(m.date).vo2 = vo2 }
        }
        for checkin in input.recoveryHistory {
            let score = checkin.source == .apple ? checkin.sleepScore : checkin.recoveryPct
            guard let score, score.isFinite else { continue }
            let d = day(checkin.date)
            d.recoveryScore = max(0, min(100, score))
            d.recoverySource = checkin.source
        }
        for rhythm in normalizeRhythm(input.mealRhythmHistory) {
            guard rhythm.finalized, rhythm.date <= throughDate else { continue }
            let d = day(rhythm.date)
            d.mealRhythmScore = rhythm.rhythmScore
            d.mealCompletionScore = rhythm.completionScore
            d.mealRhythmVerdict = rhythm.verdict
        }

        /* Streaks */
        var streak = 0
        for i in 0...total {
            let date = FBDate.addDays(start, i)
            if let a = activity[date], !a.types.isEmpty {
                streak += 1
                a.streak = streak
            } else {
                streak = 0
                activity[date]?.streak = 0
            }
        }

        var snapshots: [FBSnapshot] = []
        var synergies: [FBSynergyEvent] = []
        var s = baseline(for: profile.persona)
        var lastLegsOffset = -99

        /* Pre-baseline wearable history informs the starting point */
        let preVo2 = input.healthMetrics
            .filter { $0.vo2max != nil && $0.date < start }
            .sorted { $0.date < $1.date }
            .last
        if let vo2 = preVo2?.vo2max {
            let anchor = vo2ToStat(vo2)
            s.endurance += (anchor - s.endurance) * 0.5
            synergies.append(FBSynergyEvent(
                date: start, kind: .vo2Anchor,
                label: "Baseline calibrated: VO2max \(fixed(vo2, 1)) from your watch pulled Endurance toward \(fixed(anchor, 0))"))
        }
        let preWindowStart = FBDate.addDays(start, -60)
        var preStrength = 0, preEndurance = 0, preMobility = 0
        for imp in input.importedActivities where imp.date >= preWindowStart && imp.date < start {
            switch imp.kind {
            case .strength: preStrength += 1
            case .endurance: preEndurance += 1
            case .mobility: preMobility += 1
            }
        }
        if preStrength + preEndurance + preMobility > 0 {
            s.strengthUpper += min(6, Double(preStrength) * 0.5)
            s.endurance += min(6, Double(preEndurance) * 0.5)
            s.flexibility += min(6, Double(preMobility) * 0.5)
            synergies.append(FBSynergyEvent(
                date: start, kind: .importFeed,
                label: "Baseline credit: \(preStrength + preEndurance + preMobility) Apple Health workouts in the 60 days before APEX"))
        }
        s = StatBlock(
            health: clamp(s.health), joint: clamp(s.joint), flexibility: clamp(s.flexibility),
            endurance: clamp(s.endurance), strengthUpper: clamp(s.strengthUpper),
            strengthLower: clamp(s.strengthLower))

        for i in 0...total {
            let date = FBDate.addDays(start, i)
            let a = activity[date]
            let streakMult = 1 + Double(min(a?.streak ?? 0, 30)) * 0.005

            if i > 0 {
                s.endurance -= ageDragPerDay
                s.flexibility -= ageDragPerDay
                s.strengthUpper -= ageDragPerDay
                s.strengthLower -= ageDragPerDay
            }

            var fedEndurance = false, fedFlexibility = false, fedUpper = false
            var fedLower = false, fedJoint = false, fedHealth = false

            if let a {
                let proteinHit = (a.protein ?? -1) >= targets.proteinG * 0.95
                let deepDeficit = a.kcal != nil && a.kcal! < targets.kcal * 0.85
                let hydrated = (a.waterL ?? -1) >= 2.5
                let hasStrengthSession = a.types.contains {
                    !$0.recovery && (upperTypes.contains($0.type) || lowerTypes.contains($0.type))
                }
                var strengthMult = 1.0
                if hasStrengthSession && proteinHit {
                    strengthMult *= 1.15
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .proteinStrength,
                        label: "Protein target hit on a strength day. Strength XP +15%"))
                }
                if hasStrengthSession && deepDeficit {
                    strengthMult *= 0.85
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .deficitStrength,
                        label: "Deep calorie deficit under a strength session. XP tempered -15%, recovery costs energy"))
                }
                if hasStrengthSession, let completion = a.mealCompletionScore, completion < 60 {
                    strengthMult *= 0.94
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .mealRhythm,
                        label: "Closed-day meal completion was \(Int(completion))%. Training adaptation credit was tempered until the missing intake is corrected"))
                }

                for t in a.types {
                    let q = max(0, min(1, t.quality)) * streakMult
                    if t.recovery {
                        s.joint += 1.8 * q * headroom(s.joint)
                        fedJoint = true
                        continue
                    }
                    if t.deload {
                        s.joint += 2.5 * q * headroom(s.joint)
                        fedJoint = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .deloadHonored,
                            label: "Deload honored. Joint Health banked the recovery"))
                    }
                    if t.type == .t25 {
                        var m = 1.0
                        if hydrated {
                            m = 1.1
                            synergies.append(FBSynergyEvent(
                                date: date, kind: .hydrationEndurance,
                                label: "Hydration at target fueled the T25 engine. Endurance XP +10%"))
                        }
                        s.endurance += 3.2 * m * q * headroom(s.endurance)
                        fedEndurance = true
                    } else if flexTypes.contains(t.type) {
                        var jm = 1.0
                        if i - lastLegsOffset <= 2 {
                            jm = 1.25
                            synergies.append(FBSynergyEvent(
                                date: date, kind: .mobilityAfterLegs,
                                label: "Mobility within 48 h of a leg day. Joint synergy bonus +25%"))
                        }
                        s.flexibility += 2.8 * q * headroom(s.flexibility)
                        s.joint += 1.4 * jm * q * headroom(s.joint)
                        fedFlexibility = true
                        fedJoint = true
                    } else if lowerTypes.contains(t.type) {
                        let boost = s.strengthLower < s.strengthUpper - convergenceGap ? legXPBoost : 1
                        s.strengthLower += 2.6 * boost * strengthMult * q * headroom(s.strengthLower)
                        fedLower = true
                        lastLegsOffset = i
                    } else if upperTypes.contains(t.type) {
                        s.strengthUpper += 2.0 * strengthMult * q * headroom(s.strengthUpper)
                        fedUpper = true
                    }
                }

                /* Wearable imports feed stats at reduced credit */
                if a.importEnduranceMin >= 8 && !fedEndurance {
                    let scale = min(1.3, a.importEnduranceMin / 30)
                    s.endurance += 3.2 * importCredit * scale * headroom(s.endurance)
                    fedEndurance = true
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .importFeed,
                        label: "Wearable cardio (\(Int(a.importEnduranceMin)) min) fed Endurance"))
                }
                if a.importStrengthMin >= 8 && !fedUpper {
                    let scale = min(1.3, a.importStrengthMin / 35)
                    s.strengthUpper += 2.0 * importCredit * scale * headroom(s.strengthUpper)
                    fedUpper = true
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .importFeed,
                        label: "Wearable strength work (\(Int(a.importStrengthMin)) min) fed Strength"))
                }
                if a.importMobilityMin >= 8 && !fedFlexibility {
                    s.flexibility += 2.8 * importCredit * headroom(s.flexibility)
                    fedFlexibility = true
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .importFeed,
                        label: "Imported mobility session (\(Int(a.importMobilityMin)) min) fed Flexibility"))
                }

                s.strengthUpper += Double(a.overloadUpper) * 0.7 * headroom(s.strengthUpper)
                s.strengthLower += Double(a.overloadLower) * 0.7 * legXPBoost * headroom(s.strengthLower)
                s.joint -= Double(min(a.overrides, 2)) * 1.5

                var healthFed = false
                if hydrated {
                    s.health += 1.2 * streakMult * headroom(s.health)
                    healthFed = true
                }
                if let kcal = a.kcal, let protein = a.protein,
                   abs(kcal - targets.kcal) <= targets.kcal * 0.1,
                   protein >= targets.proteinG * 0.95 {
                    s.health += 1.4 * streakMult * headroom(s.health)
                    healthFed = true
                }
                if let score = a.recoveryScore, let source = a.recoverySource {
                    let strongThreshold: Double = source == .apple ? 81 : 67
                    let normalThreshold: Double = source == .apple ? 61 : 34
                    if score >= strongThreshold {
                        s.health += 0.8 * headroom(s.health)
                        healthFed = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .recoverySignal,
                            label: "\(source == .apple ? "Apple Sleep Score" : "Recovery score") \(Int(FitnessBrainTargets.jsRound(score))) supported the planned training day"))
                    } else if score >= normalThreshold {
                        s.health += 0.35 * headroom(s.health)
                        healthFed = true
                    }
                }
                if let rhythmScore = a.mealRhythmScore, let verdict = a.mealRhythmVerdict {
                    switch verdict {
                    case .completeOnTime:
                        s.health += 0.7 * headroom(s.health)
                        healthFed = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .mealRhythm,
                            label: "Meal schedule completed with a \(Int(rhythmScore))/100 rhythm signal. Health consistency gained context"))
                    case .completeIrregular:
                        s.health -= 0.15
                        healthFed = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .mealRhythm,
                            label: "All planned meals were logged, but their timing rhythm was \(Int(rhythmScore))/100"))
                    case .missedMeals:
                        s.health -= 0.35
                        healthFed = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .mealRhythm,
                            label: "The closed day recorded \(Int(a.mealCompletionScore ?? 0))% of configured meals. A later correction will replay this verdict"))
                    case .noMeals:
                        s.health -= 0.55
                        healthFed = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .mealRhythm,
                            label: "The day closed with no configured meal recorded. This can still be corrected from the calendar"))
                    case .open:
                        break
                    }
                }
                fedHealth = healthFed

                if let vo2 = a.vo2 {
                    let anchor = vo2ToStat(vo2)
                    s.endurance += (anchor - s.endurance) * 0.5
                    fedEndurance = true
                    synergies.append(FBSynergyEvent(
                        date: date, kind: .vo2Anchor,
                        label: "VO2max measured at \(fixed(vo2, 1)). Endurance anchored toward \(fixed(anchor, 0))"))
                }
            }

            if i > 0 {
                if !fedEndurance { s.endurance = decay(s.endurance, floor: floors.endurance, halfLife: halfLife.endurance) }
                if !fedFlexibility { s.flexibility = decay(s.flexibility, floor: floors.flexibility, halfLife: halfLife.flexibility) }
                if !fedUpper { s.strengthUpper = decay(s.strengthUpper, floor: floors.strengthUpper, halfLife: halfLife.strengthUpper) }
                if !fedLower { s.strengthLower = decay(s.strengthLower, floor: floors.strengthLower, halfLife: halfLife.strengthLower) }
                if !fedJoint { s.joint = decay(s.joint, floor: floors.joint, halfLife: halfLife.joint) }
                if !fedHealth { s.health = decay(s.health, floor: floors.health, halfLife: halfLife.health) }
            }

            s = StatBlock(
                health: clamp(s.health), joint: clamp(s.joint), flexibility: clamp(s.flexibility),
                endurance: clamp(s.endurance), strengthUpper: clamp(s.strengthUpper),
                strengthLower: clamp(s.strengthLower))

            snapshots.append(FBSnapshot(
                date: date,
                overall: round1(overall(of: s)),
                health: round1(s.health),
                joint: round1(s.joint),
                flexibility: round1(s.flexibility),
                endurance: round1(s.endurance),
                strength: round1((s.strengthUpper + s.strengthLower) / 2),
                strengthUpper: round1(s.strengthUpper),
                strengthLower: round1(s.strengthLower)))
        }
        return FBEngineResult(snapshots: snapshots, synergies: synergies)
    }
}
