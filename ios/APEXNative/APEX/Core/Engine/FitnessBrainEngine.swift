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

    /// Each list holds every answer for its day, oldest first.
    private struct CapacityCalibrationTimeline {
        var beforeBaseline: [FBCapacityCalibrationEvidence] = []
        var byDate: [String: [FBCapacityCalibrationEvidence]] = [:]
    }

    private static func capacityCalibrationTimeline(
        _ evidence: [FBCapacityCalibrationEvidence],
        ownerID: String,
        baselineDate: String,
        throughDate: String
    ) -> CapacityCalibrationTimeline {
        let owned = evidence.filter { $0.userID == ownerID }
        let supersededIDs = Set(owned.compactMap(\.supersedesID))
        var answers: [(order: String, item: FBCapacityCalibrationEvidence)] = []
        for var item in owned where !supersededIDs.contains(item.id) {
            guard item.value.isFinite,
                  (0...100).contains(item.value),
                  item.coverage.isFinite,
                  item.coverage > 0 else { continue }
            // Evidence that already exists cannot be from the future: an answer stamped with
            // tomorrow's UTC date on an evening west of Greenwich counts today.
            item.measuredOn = min(item.measuredOn, throughDate)
            answers.append(("\(item.measuredOn):\(item.importedAt):\(item.id)", item))
        }
        // Every answer counts, oldest first, so a repeat or a lower one later the same day
        // changes nothing.
        var timeline = CapacityCalibrationTimeline()
        for (_, item) in answers.sorted(by: { $0.order < $1.order }) {
            if item.measuredOn <= baselineDate {
                timeline.beforeBaseline.append(item)
            } else {
                timeline.byDate[item.measuredOn, default: []].append(item)
            }
        }
        return timeline
    }

    /// A self-check sets the first estimate of a domain that has no evidence yet. Once a domain
    /// has evidence, an answer only lifts a score that sits below the answered band, and the
    /// same or a lower answer given again lifts nothing. It never takes away what the log earned.
    /// The first answer of a day is that evidence for the ones that follow it.
    @discardableResult
    private static func applyCapacityCalibration(
        _ evidence: [FBCapacityCalibrationEvidence],
        to stats: inout StatBlock,
        observed: [String: String],
        credited: inout [FBCapacityCalibrationMetric: Double]
    ) -> Set<FBCapacityCalibrationMetric> {
        var applied = Set<FBCapacityCalibrationMetric>()
        for item in evidence {
            let metric = item.metric
            let key: String
            let stat: WritableKeyPath<StatBlock, Double>
            switch metric {
            case .cardiorespiratory: (key, stat) = ("endurance", \.endurance)
            case .upperStrength: (key, stat) = ("upper", \.strengthUpper)
            case .lowerStrength: (key, stat) = ("lower", \.strengthLower)
            case .flexibility: (key, stat) = ("flexibility", \.flexibility)
            }
            let anchor = clamp(item.value)
            let current = stats[keyPath: stat]
            let lifts = (observed[key] == nil && credited[metric] == nil)
                || (current < (item.lowerBound ?? anchor) && anchor > (credited[metric] ?? -.infinity))
            if lifts { stats[keyPath: stat] += (anchor - current) * min(0.55, max(0, item.coverage)) }
            credited[metric] = max(credited[metric] ?? anchor, anchor)
            applied.insert(metric)
        }
        return applied
    }

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
        var mealRhythmVerdict: FBMealRhythmVerdict?
        var streak = 0
    }

    static let upperTypes: Set<FBDayType> = [.push, .pull, .upper]
    static let lowerTypes: Set<FBDayType> = [.legsA, .legsB]
    static let flexTypes: Set<FBDayType> = [.mobility, .fix]

    private static func recordedQuality(_ session: FBWorkoutSession, logs: [FBWorkoutLog]) -> Double {
        guard session.completed else { return 0 }
        let notes = WorkoutReceipt.notesWithoutTimingMetadata(session.notes ?? "")
        let external = notes == "Completed externally from the APEX guided player"
            || notes == "Completed externally from the FITR MAX guided player"
        if !logs.isEmpty && !external && !logs.contains(where: \.hasRecordedWork) { return 0 }
        guard session.qualityScore.isFinite, session.qualityScore >= 0 else { return 0 }
        // Old receipts may have no set detail; absence is not proof of no work.
        if session.qualityScore == 0 && (logs.isEmpty || external) { return 1 }
        return min(1, session.qualityScore)
    }

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
        let authored = profile.authorizedProtocol != nil
        let allocated = authored ? nil : AvatarStartingPoints.stats(profile.avatarStartingPoints)

        var dayTypeByID: [String: FBDayType] = [:]
        for d in input.programDays { dayTypeByID[d.id] = d.dayType }
        let currentTargets = FitnessBrainTargets.computeTargets(
            profile,
            asOf: throughDate,
            trainingGoal: input.trainingGoal,
            planWeeks: input.planWeeks
        )

        var activity: [String: DayActivity] = [:]
        func day(_ date: String) -> DayActivity {
            if let a = activity[date] { return a }
            let a = DayActivity()
            activity[date] = a
            return a
        }

        var sessionByID: [String: FBWorkoutSession] = [:]
        for s in input.workoutSessions { sessionByID[s.id] = s }
        let logsBySession = Dictionary(grouping: input.workoutLogs, by: \.sessionID)
        var qualityBySession: [String: Double] = [:]
        for session in input.workoutSessions {
            qualityBySession[session.id] = recordedQuality(session, logs: logsBySession[session.id] ?? [])
        }

        var missedDomains: [String: Set<FBDayType>] = [:]
        var uncertainWorkoutDates = Set<String>()
        for s in input.workoutSessions where s.completed {
            let quality = qualityBySession[s.id] ?? 0
            if allocated != nil {
                let logs = logsBySession[s.id] ?? []
                let domain = dayTypeByID[s.programDayID]?.activityDomain
                if quality == 0, let domain, !s.isDeload, !s.isEventRecovery,
                   !logs.isEmpty, logs.allSatisfy(\.skipped) {
                    missedDomains[s.date, default: []].insert(domain)
                    _ = day(s.date)
                } else if quality > 0 && (s.isDeload || s.isEventRecovery
                            || (domain == nil && !logs.contains(where: { !($0.performedTypes ?? []).isEmpty }))) {
                    uncertainWorkoutDates.insert(s.date)
                }
            }
            guard quality > 0 else { continue }
            guard let type = dayTypeByID[s.programDayID], type != .custom else { continue }
            let activity = day(s.date)
            if s.isEventRecovery {
                activity.types.append(TypeEntry(type: type, quality: quality, deload: s.isDeload, recovery: true))
                continue
            }
            // A planned session credits the body areas its catalogue movements trained. A strength
            // or mobility label speaks only for work the receipt cannot identify, or when it
            // identifies nothing. A cardio label always stands: conditioning is often built from
            // strength movements.
            let logs = logsBySession[s.id] ?? []
            let proved = Set(logs.flatMap { $0.performedTypes ?? [] })
            let labelled = type.activityDomain == .cardio || proved.isEmpty
                || logs.contains { ($0.movementID ?? "").isEmpty && $0.hasPerformedWork }
            for domain in [FBDayType.upper, .legsA, .mobility, .cardio] {
                let own = domain == type.activityDomain
                guard proved.contains(domain) || (own && labelled) else { continue }
                activity.types.append(TypeEntry(
                    type: own ? type : domain, quality: quality, deload: s.isDeload, recovery: false))
            }
        }
        /* Focus T25 conditioning logged inside any completed session */
        for log in input.workoutLogs {
            guard let s = sessionByID[log.sessionID], s.completed, log.hasPerformedWork,
                  (qualityBySession[s.id] ?? 0) > 0,
                  dayTypeByID[s.programDayID] != .custom,
                  isConditioningFocusT25(log.exerciseName) else { continue }
            let d = day(s.date)
            if !d.types.contains(where: { $0.type == .t25 }) {
                d.types.append(TypeEntry(type: .t25, quality: 1, deload: s.isDeload, recovery: false))
            }
        }
        // Custom receipts use performed catalogue movements, once per domain
        // and day. Existing planned-session credit takes precedence.
        var customByDate: [String: [FBDayType: Double]] = [:]
        for log in input.workoutLogs {
            guard log.hasRecordedWork,
                  let session = sessionByID[log.sessionID], session.completed,
                  !session.isEventRecovery, dayTypeByID[session.programDayID] == .custom,
                  let quality = qualityBySession[session.id], quality > 0 else { continue }
            for type in log.performedTypes ?? [] {
                guard let domain = type.activityDomain else { continue }
                customByDate[session.date, default: [:]][domain] = max(
                    customByDate[session.date]?[domain] ?? 0, quality)
            }
        }
        for date in customByDate.keys.sorted() {
            let activity = day(date)
            for type in [FBDayType.upper, .legsA, .mobility, .cardio] {
                guard let quality = customByDate[date]?[type],
                      !activity.types.contains(where: { !$0.recovery && $0.type.activityDomain == type }) else { continue }
                activity.types.append(TypeEntry(type: type, quality: quality, deload: false, recovery: false))
            }
        }
        for log in input.workoutLogs {
            guard let s = sessionByID[log.sessionID], s.completed, log.hasPerformedWork,
                  (qualityBySession[s.id] ?? 0) > 0 else { continue }
            if log.overrideFlag { day(s.date).overrides += 1 }
        }

        /* Progressive overload: top weight rises vs the previous session */
        var byExercise: [String: [(date: String, w: Double)]] = [:]
        var exerciseOrder: [String] = []
        var exerciseDomains: [String: Set<FBDayType>] = [:]
        for log in input.workoutLogs {
            guard let exID = log.exerciseID, log.hasPerformedWork, let w = log.weightKG, w.isFinite,
                  let s = sessionByID[log.sessionID], s.completed,
                  (qualityBySession[s.id] ?? 0) > 0 else { continue }
            if byExercise[exID] == nil { exerciseOrder.append(exID) }
            byExercise[exID, default: []].append((s.date, w))
            exerciseDomains[exID, default: []].formUnion(log.performedTypes ?? [])
        }
        var exerciseDayByID: [String: String] = [:]
        for e in input.exercises { exerciseDayByID[e.id] = e.programDayID }
        for exID in exerciseOrder {
            var byDate: [String: Double] = [:]
            // Seeded with the first load, not zero: an assisted lift is logged below zero.
            for entry in byExercise[exID] ?? [] {
                byDate[entry.date] = max(byDate[entry.date] ?? entry.w, entry.w)
            }
            let dates = byDate.keys.sorted()
            for i in 1..<max(1, dates.count) where dates.count > 1 {
                if (byDate[dates[i]] ?? 0) > (byDate[dates[i - 1]] ?? 0) {
                    let type = exerciseDayByID[exID].flatMap { dayTypeByID[$0] }
                    let a = day(dates[i])
                    // The movement decides which half of the body progressed. The day's label
                    // speaks only for a lift the catalogue cannot identify.
                    let domains = exerciseDomains[exID] ?? []
                    let lower = domains.isEmpty ? type.map(lowerTypes.contains) == true : domains.contains(.legsA)
                    let upper = domains.isEmpty ? type.map(upperTypes.contains) == true : domains.contains(.upper)
                    if lower { a.overloadLower += 1 } else if upper { a.overloadUpper += 1 }
                }
            }
        }

        for date in input.hydrationByDay.keys { _ = day(date) }
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
            d.mealRhythmVerdict = rhythm.verdict
        }

        let earliestWork = allocated == nil ? nil : activity.keys.filter {
            $0 < profile.baselineDate && $0 <= throughDate && activity[$0]?.types.isEmpty == false
                && FBDate.validDate($0) != nil
        }.min()
        // A baseline the server stamped with tomorrow's UTC date still starts today.
        let start = min(earliestWork ?? profile.baselineDate, throughDate)
        let total = FBDate.daysBetween(start, throughDate)
        if total < 0 { return FBEngineResult(snapshots: [], synergies: []) }

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
        // A neutral numeric starting point is internal arithmetic. No standard domain
        // or historical composite is published until that domain actually has evidence.
        var s = allocated ?? (authored ? baseline(for: profile.persona) : StatBlock(
            health: 50, joint: 50, flexibility: 50, endurance: 50, strengthUpper: 50, strengthLower: 50))
        var firstObserved = authored || allocated != nil ? Dictionary(uniqueKeysWithValues:
            ["health", "joint", "flexibility", "endurance", "upper", "lower"].map { ($0, start) }) : [:]
        func observe(_ key: String, _ date: String) {
            if firstObserved[key] == nil { firstObserved[key] = date }
        }
        var lastLegsOffset = -99

        let calibrationTimeline = capacityCalibrationTimeline(
            input.capacityCalibrationEvidence,
            ownerID: profile.userID,
            baselineDate: start,
            throughDate: throughDate
        )
        var creditedSelfChecks: [FBCapacityCalibrationMetric: Double] = [:]
        let preCalibration = applyCapacityCalibration(
            calibrationTimeline.beforeBaseline, to: &s, observed: firstObserved, credited: &creditedSelfChecks)
        for (metric, key) in [(FBCapacityCalibrationMetric.cardiorespiratory, "endurance"),
                              (.upperStrength, "upper"), (.lowerStrength, "lower"), (.flexibility, "flexibility")]
            where preCalibration.contains(metric) { observe(key, start) }

        /* Pre-baseline wearable history informs the starting point */
        let preVo2 = input.healthMetrics
            .filter { $0.vo2max != nil && $0.date < start }
            .sorted { $0.date < $1.date }
            .last
        if allocated == nil, let vo2 = preVo2?.vo2max {
            observe("endurance", start)
            let anchor = vo2ToStat(vo2)
            s.endurance += (anchor - s.endurance) * 0.5
            synergies.append(FBSynergyEvent(
                date: start, kind: .vo2Anchor,
                label: "Baseline calibrated: VO2max \(fixed(vo2, 1)) from your watch pulled Endurance toward \(fixed(anchor, 0))"))
        }
        let preWindowStart = FBDate.addDays(start, -60)
        var preStrength = 0, preEndurance = 0, preMobility = 0
        for imp in input.importedActivities where allocated == nil && imp.date >= preWindowStart && imp.date < start {
            switch imp.kind {
            case .strength: if authored { preStrength += 1 }
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
        if authored && preStrength > 0 { observe("upper", start) }
        if preEndurance > 0 { observe("endurance", start) }
        if preMobility > 0 { observe("flexibility", start) }
        s = StatBlock(
            health: clamp(s.health), joint: clamp(s.joint), flexibility: clamp(s.flexibility),
            endurance: clamp(s.endurance), strengthUpper: clamp(s.strengthUpper),
            strengthLower: clamp(s.strengthLower))

        for i in 0...total {
            let date = FBDate.addDays(start, i)
            let a = activity[date]
            let streakMult = 1 + Double(min(a?.streak ?? 0, 30)) * 0.005

            if authored && i > 0 {
                s.endurance -= ageDragPerDay
                s.flexibility -= ageDragPerDay
                s.strengthUpper -= ageDragPerDay
                s.strengthLower -= ageDragPerDay
            }

            var fedEndurance = false, fedFlexibility = false, fedUpper = false
            var fedLower = false, fedJoint = false, fedHealth = false

            if let calibration = calibrationTimeline.byDate[date] {
                let calibrated = applyCapacityCalibration(
                    calibration, to: &s, observed: firstObserved, credited: &creditedSelfChecks)
                fedEndurance = calibrated.contains(.cardiorespiratory)
                fedFlexibility = calibrated.contains(.flexibility)
                fedUpper = calibrated.contains(.upperStrength)
                fedLower = calibrated.contains(.lowerStrength)
            }

            if let a {
                if let missed = missedDomains[date], !uncertainWorkoutDates.contains(date) {
                    let performed = Set(a.types.compactMap { $0.type.activityDomain })
                    for domain in missed.subtracting(performed) {
                        switch domain {
                        case .legsA where a.importStrengthMin <= 0: s.strengthLower -= 1
                        case .upper where a.importStrengthMin <= 0: s.strengthUpper -= 1
                        case .mobility where a.importMobilityMin <= 0: s.flexibility -= 1
                        case .cardio where a.importEnduranceMin <= 0: s.endurance -= 1
                        default: continue
                        }
                        synergies.append(FBSynergyEvent(date: date, kind: .skippedSession,
                                                       label: "Explicitly skipped workout: −1 training point"))
                    }
                }
                // A day is graded against the targets in force on it, not against today's.
                let targets = input.pastTargets.first { date < $0.until }?.targets ?? currentTargets
                let proteinHit = targets.isPublishable
                    && (a.protein ?? -1) >= targets.proteinG * 0.95
                let deepDeficit = targets.isPublishable
                    && date < throughDate
                    && (a.mealRhythmVerdict == .completeOnTime || a.mealRhythmVerdict == .completeIrregular)
                    && a.kcal != nil
                    && a.kcal! < targets.kcal * 0.85
                let hydration = input.hydrationByDay[date]
                let totalML = hydration.map { Double($0.totalML) } ?? (a.waterL ?? 0) * 1_000
                let hydrated = totalML >= Double(hydration?.targetML ?? HydrationTargetPolicy.resolve(sex: profile.sex, weightKG: profile.weightKG).targetML)
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

                var deloadBanked = false
                for t in a.types {
                    let q = max(0, min(1, t.quality)) * streakMult
                    if t.recovery {
                        s.joint += 1.8 * q * headroom(s.joint)
                        fedJoint = true
                        continue
                    }
                    if t.deload && !deloadBanked {
                        deloadBanked = true
                        s.joint += 2.5 * q * headroom(s.joint)
                        fedJoint = true
                        synergies.append(FBSynergyEvent(
                            date: date, kind: .deloadHonored,
                            label: "Deload honored. Joint Health banked the recovery"))
                    }
                    if t.type == .t25 || t.type == .cardio {
                        var m = 1.0
                        if hydrated && t.type == .t25 {
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
                        let boost = authored && s.strengthLower < s.strengthUpper - convergenceGap ? legXPBoost : 1
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
                if authored && a.importStrengthMin >= 8 && !fedUpper {
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
                s.strengthLower += Double(a.overloadLower) * 0.7 * (authored ? legXPBoost : 1) * headroom(s.strengthLower)
                s.joint -= Double(min(a.overrides, 2)) * 1.5

                var healthFed = false
                if hydrated {
                    s.health += 1.2 * streakMult * headroom(s.health)
                    healthFed = true
                }
                if targets.isPublishable,
                   let kcal = a.kcal, let protein = a.protein,
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
                    case .noMeals, .missedMeals, .open:
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

            for (key, observed) in [("health", fedHealth), ("joint", fedJoint),
                                    ("flexibility", fedFlexibility), ("endurance", fedEndurance),
                                    ("upper", fedUpper), ("lower", fedLower)] where observed {
                observe(key, date)
            }
            if authored && i > 0 {
                if !fedEndurance { s.endurance = decay(s.endurance, floor: floors.endurance, halfLife: halfLife.endurance) }
                if !fedFlexibility { s.flexibility = decay(s.flexibility, floor: floors.flexibility, halfLife: halfLife.flexibility) }
                if !fedUpper { s.strengthUpper = decay(s.strengthUpper, floor: floors.strengthUpper, halfLife: halfLife.strengthUpper) }
                if !fedLower { s.strengthLower = decay(s.strengthLower, floor: floors.strengthLower, halfLife: halfLife.strengthLower) }
                if !fedJoint { s.joint = decay(s.joint, floor: floors.joint, halfLife: halfLife.joint) }
                if !fedHealth { s.health = decay(s.health, floor: floors.health, halfLife: halfLife.health) }
            }

            if authored, let calibration = input.avatarCalibration, calibration.source == "manual",
               calibration.date == date, (0...100).contains(calibration.score) {
                s.health = calibration.score
                if let scores = calibration.scores {
                    for (value, key) in [(scores.joint, \StatBlock.joint), (scores.flexibility, \.flexibility),
                                         (scores.endurance, \.endurance)] {
                        if let value, (0...100).contains(value) { s[keyPath: key] = value }
                    }
                }
                synergies.append(FBSynergyEvent(date: date, kind: .manualHealthCalibration,
                    label: calibration.scores == nil ? "Health score manually calibrated" : "Avatar scores manually calibrated"))
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
        return FBEngineResult(snapshots: snapshots, synergies: synergies, firstObserved: firstObserved)
    }
}
