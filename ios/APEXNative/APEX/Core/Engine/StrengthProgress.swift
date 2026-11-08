import Foundation

/*
 * Port of src/lib/strengthProgress.ts.
 *
 * Turns completed sets into a strength history: an estimated one-rep max per
 * exercise per session, what changed since last time, and what the weekly
 * joint check-in says about whether to keep pushing.
 */
enum StrengthProgress {
    enum JointRegion: String, Sendable, CaseIterable {
        case arms, core, legs
    }

    enum DeloadState: String, Sendable {
        case clear
        case watch
        case regionalDeload = "regional_deload"
        case wholeDeload = "whole_deload"
        case stopAndReview = "stop_and_review"
    }

    struct Point: Hashable, Sendable {
        let sessionID: UUID
        let date: String
        let topWeight: Double
        let estimated1RM: Double
        let volume: Double
        let setWeights: [Int: Double]
        var topReps: Int? = nil
    }

    struct Series: Hashable, Sendable {
        let key: String
        let exerciseID: UUID?
        let name: String
        let points: [Point]
    }

    enum BodyRegion: String, CaseIterable, Sendable {
        case lower = "Lower body"
        case upper = "Upper body"
        case core = "Core"
        case other = "Other"

        init(primaryMuscle: String?) {
            switch primaryMuscle {
            case "adductors", "ankle_stabilisers", "calves", "foot_intrinsics", "glute_medius",
                 "glutes", "hamstrings", "hip_flexors", "hips", "quadriceps", "soleus", "tibialis":
                self = .lower
            case "biceps", "chest", "deep_neck_flexors", "forearms", "front_delts", "lats",
                 "lower_traps", "mid_traps", "neck", "rear_delts", "rotator_cuff", "side_delts",
                 "traps", "triceps", "upper_back":
                self = .upper
            case "core", "erectors", "obliques", "spinal_erectors":
                self = .core
            default:
                self = .other
            }
        }
    }

    struct LifetimeTotals: Sendable {
        private(set) var sets = 0
        private(set) var reps = 0
        private(set) var loadedReps = 0
        private(set) var volumeKG = 0.0
        private(set) var missingReps = false
        private(set) var missingVolume = false

        var recordedReps: Int? { reps > 0 ? reps : nil }
        var liftedVolumeKG: Double? { loadedReps > 0 ? volumeKG : nil }
        var averageLoadKG: Double? { liftedVolumeKG.map { $0 / Double(loadedReps) } }

        mutating func record(_ log: WorkoutLog, measuresReps: Bool, measuresLoad: Bool) {
            sets += 1
            guard measuresReps else { return }
            guard let count = log.reps, count > 0 else {
                missingReps = true
                if measuresLoad { missingVolume = true }
                return
            }
            reps += count
            guard measuresLoad else { return }
            guard let load = log.weightKG, load.isFinite, load > 0 else {
                missingVolume = true
                return
            }
            loadedReps += count
            volumeKG += load * Double(count)
        }

        mutating func add(_ other: Self) {
            sets += other.sets
            reps += other.reps
            loadedReps += other.loadedReps
            volumeKG += other.volumeKG
            missingReps = missingReps || other.missingReps
            missingVolume = missingVolume || other.missingVolume
        }
    }

    struct SessionTotals: Sendable {
        let sessionID: UUID
        let date: String
        let time: Date?
        var totals = LifetimeTotals()
        var heaviestSet: (kg: Double, reps: Int)?
        var bestSingleKG: Double?

        init(_ session: WorkoutSession) {
            sessionID = session.id
            date = session.date
            time = ExternalWorkoutImport.parseTimestamp(session.startedAt) ?? ExternalWorkoutImport.parseTimestamp(session.completedAt)
        }

        static func chronological(_ lhs: Self, _ rhs: Self) -> Bool {
            (lhs.date, lhs.time ?? .distantPast, lhs.sessionID.uuidString)
                < (rhs.date, rhs.time ?? .distantPast, rhs.sessionID.uuidString)
        }
    }

    struct ExerciseHistory: Sendable {
        let key: String
        let name: String
        let region: BodyRegion
        let sessions: [SessionTotals]
        let familyKey: String
        let familyName: String?
        let familyRegion: BodyRegion
        let totals: LifetimeTotals
        var sessionCount: Int { sessions.count }
        let lastPerformed: String
        let points: [Point]

        var loadGain: Double? {
            guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
            return round1(last.topWeight - first.topWeight)
        }

        @MainActor
        func titleParts(_ language: LanguageState) -> (main: String, variation: String?) {
            let full = language.text(name)
            guard let familyName else { return (full, nil) }
            let main = language.text(familyName)
            guard main.localizedCaseInsensitiveCompare(full) != .orderedSame else { return (full, nil) }
            for suffix in [" " + main, " " + main + "s"] {
                if let match = full.range(of: suffix, options: [.backwards, .anchored, .caseInsensitive]),
                   match.lowerBound != full.startIndex {
                    return (main, String(full[..<match.lowerBound]))
                }
            }
            return (main, full)
        }
    }

    struct RankedFamily {
        let key: String
        let name: String
        let sessions: [SessionTotals]
        var sessionCount: Int { sessions.count }
        let lastPerformed: String
        let region: BodyRegion
        let totals: LifetimeTotals
        let variants: [ExerciseHistory]

        var showsVariants: Bool {
            variants.count > 1 || variants.first?.name.caseInsensitiveCompare(name) != .orderedSame
        }
    }

    private struct FamilyDefinition: Decodable {
        let id: String
        let name: String
        let movementIDs: [String]
        let aliases: [String]
        let equivalentLabels: [String: [String]]?
        let region: String

        var bodyRegion: BodyRegion {
            switch region {
            case "lower": .lower
            case "upper": .upper
            case "core": .core
            default: .other
            }
        }

        static func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        static let index: (movement: [String: Self], alias: [String: Self], equivalentMovement: [String: String]) = {
            guard let url = Bundle.main.url(forResource: "exercise-frequency-families", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let families = try? JSONDecoder().decode([Self].self, from: data) else { return ([:], [:], [:]) }
            var movements: [String: Self] = [:], aliases: [String: Self] = [:]
            var equivalentMovement: [String: String] = [:]
            for family in families {
                for (id, labels) in family.equivalentLabels ?? [:] {
                    for label in labels { equivalentMovement[label.lowercased()] = id }
                }
                for id in family.movementIDs { movements[id] = family }
                for label in family.aliases { aliases[normalized(label)] = family }
            }
            return (movements, aliases, equivalentMovement)
        }()

    }

    static func isKnownFamilyAlias(_ name: String) -> Bool {
        FamilyDefinition.index.alias[FamilyDefinition.normalized(name)] != nil
    }

    static func rankedFamilies(_ history: [ExerciseHistory]) -> [RankedFamily] {
        Dictionary(grouping: history, by: \.familyKey).compactMap { key, variants -> RankedFamily? in
            guard let first = variants.first else { return nil }
            var bySession = [UUID: SessionTotals]()
            for variant in variants {
                for point in variant.sessions {
                    if bySession[point.sessionID] == nil { bySession[point.sessionID] = point }
                    else { bySession[point.sessionID]?.totals.add(point.totals) }
                }
            }
            let sessions = bySession.values.sorted(by: SessionTotals.chronological)
            return RankedFamily(key: key, name: first.familyName ?? first.name,
                                sessions: sessions, lastPerformed: variants.map(\.lastPerformed).max() ?? "",
                                region: first.familyRegion, totals: variants.reduce(into: LifetimeTotals()) { $0.add($1.totals) },
                                variants: variants)
        }.sorted {
            if $0.sessionCount != $1.sessionCount { return $0.sessionCount > $1.sessionCount }
            if $0.lastPerformed != $1.lastPerformed { return $0.lastPerformed > $1.lastPerformed }
            if $0.name.lowercased() != $1.name.lowercased() { return $0.name.lowercased() < $1.name.lowercased() }
            return $0.key < $1.key
        }
    }

    struct SessionInsight: Hashable, Sendable {
        let key: String
        let name: String
        let current: Point
        let previous: Point?
        /// The point the comparison is made against, preferring 30-90 days back.
        let reference: Point?
        let daysCompared: Int?
        let loadDelta: Double?
        let estimated1RMDelta: Double?
    }

    struct JointCheckin: Hashable, Sendable {
        let date: String
        let arms: Int
        let core: Int
        let legs: Int

        subscript(region: JointRegion) -> Int {
            switch region {
            case .arms: arms
            case .core: core
            case .legs: legs
            }
        }
    }

    struct JointAssessment: Hashable, Sendable {
        let state: DeloadState
        let affected: [JointRegion]
        let average: Double
        let highest: Int
        let rising: [JointRegion]
    }

    // MARK: - Helpers

    /// JavaScript's Math.round rounds half up; Swift rounds half away from
    /// zero. Deltas here can be negative, so the JS rule is kept exactly.
    private static func roundJS(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    private static func round1(_ value: Double) -> Double {
        roundJS(value * 10) / 10
    }

    private static func exerciseKey(_ log: WorkoutLog) -> String {
        if let movement = MovementTiming.movement(
            named: log.exerciseName,
            movementID: log.movementID
        ) {
            return "movement:\(movement.id.lowercased())"
        }
        return "name:\(log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func daysBetween(_ earlier: String, _ later: String) -> Int {
        guard let start = APEXDateMath.date(from: earlier), let end = APEXDateMath.date(from: later) else { return 0 }
        return max(0, Int(roundJS(end.timeIntervalSince(start) / 86_400)))
    }

    // MARK: - Estimated one-rep max

    static func estimatedOneRepMax(weight: Double, reps: Int?) -> Double {
        guard weight.isFinite, weight > 0 else { return 0 }
        guard let reps, reps > 1 else { return roundJS(weight * 10) / 10 }
        /* Epley is capped at 15 reps on purpose: higher-rep sets estimate a
           maximum poorly and would manufacture spectacular fake gains. */
        let bounded = Double(min(15, reps))
        return roundJS(weight * (1 + bounded / 30) * 10) / 10
    }

    // MARK: - Series

    static func buildSeries(sessions allSessions: [WorkoutSession], logs: [WorkoutLog]) -> [Series] {
        var sessions: [UUID: WorkoutSession] = [:]
        for session in allSessions where session.completed { sessions[session.id] = session }

        struct Group {
            var exerciseID: UUID?
            var name: String
            var sessions: [UUID: [WorkoutLog]] = [:]
            var order: [UUID] = []
        }
        var grouped: [String: Group] = [:]
        var groupOrder: [String] = []

        for log in logs {
            let descriptor = ExerciseLogging.descriptor(
                movementNamed: log.exerciseName,
                movementID: log.movementID
            )
            guard descriptor.kind == .strength,
                  !log.skipped,
                  let weight = log.weightKG,
                  weight > 0,
                  sessions[log.sessionID] != nil else { continue }
            let key = exerciseKey(log)
            if grouped[key] == nil {
                grouped[key] = Group(exerciseID: log.exerciseID, name: log.exerciseName)
                groupOrder.append(key)
            }
            if grouped[key]?.sessions[log.sessionID] == nil { grouped[key]?.order.append(log.sessionID) }
            grouped[key]?.sessions[log.sessionID, default: []].append(log)
        }

        return groupOrder.compactMap { key -> Series? in
            guard let group = grouped[key] else { return nil }
            let points = group.order.compactMap { sessionID -> Point? in
                guard let session = sessions[sessionID], let logs = group.sessions[sessionID] else { return nil }
                return loadPoint(session: session, logs: logs)
            }.sorted {
                $0.date == $1.date
                    ? $0.sessionID.uuidString.lowercased() < $1.sessionID.uuidString.lowercased()
                    : $0.date < $1.date
            }
            guard !points.isEmpty else { return nil }
            return Series(key: key, exerciseID: group.exerciseID, name: group.name, points: points)
        }.sorted { $0.name < $1.name }
    }

    private static func loadPoint(session: WorkoutSession, logs: [WorkoutLog]) -> Point? {
        guard let top = logs.compactMap(\.weightKG).max() else { return nil }
        let best = logs.map { estimatedOneRepMax(weight: $0.weightKG ?? 0, reps: $0.reps) }.max() ?? top
        let volume = logs.reduce(0.0) { $0 + ($1.weightKG ?? 0) * Double(max(0, $1.reps ?? 0)) }
        var setWeights: [Int: Double] = [:]
        for log in logs { setWeights[log.setNumber] = log.weightKG }
        return Point(
            sessionID: session.id, date: session.date, topWeight: top, estimated1RM: best,
            volume: volume, setWeights: setWeights,
            topReps: logs.filter { $0.weightKG == top }.compactMap(\.reps).filter { $0 > 0 }.max()
        )
    }

    private static func equipment(in label: String) -> Set<String> {
        Set(label.lowercased().split(whereSeparator: { !$0.isLetter }).compactMap { word in
            switch word {
            case "barbell", "barbells", "bb", "bbs": "barbell"
            case "dumbbell", "dumbbells", "db", "dbs": "dumbbell"
            case "kettlebell", "kettlebells", "kb", "kbs": "kettlebell"
            case "cable", "cables": "cable"
            case "machine", "machines": "machine"
            case "backpack", "backpacks": "backpack"
            case "smith": "smith"
            case "band", "bands", "banded": "band"
            default: nil
            }
        })
    }

    private static let legacyVideoNames = Set([
        "FocusT25 session (Shaun T), Alpha or Beta cycle", "Any 10-min HIIT video", "Functional stretch flow (saved YouTube favorite)"
    ].map { $0.lowercased() })

    private static let catalogRepUnits = Dictionary(
        ExerciseCatalog.all.map { ($0.movementID, $0.unit) }, uniquingKeysWith: { first, _ in first }
    )

    static func exerciseHistory(
        ownerID: UUID, sessions: [WorkoutSession], logs: [WorkoutLog], exercises: [Exercise] = []
    ) -> [ExerciseHistory] {
        let ownedExercises = exercises.filter { $0.userID == ownerID }
        let units = Dictionary(ownedExercises.map { ($0.id, $0.repUnit) }, uniquingKeysWith: { first, _ in first })
        let unitsByName = Dictionary(ownedExercises.map {
            ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.repUnit)
        }, uniquingKeysWith: { first, next in first == next ? first : "ambiguous" })

        let completed = sessions.filter { $0.completed && $0.userID == ownerID }
        let sessionByID = Dictionary(completed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        struct Group {
            var name: String
            let region: BodyRegion
            let family: FamilyDefinition?
            var sessions = [UUID: SessionTotals]()
            var lastPerformed = ""
            var loads: [UUID: [WorkoutLog]] = [:]
        }
        var groups: [String: Group] = [:]
        var seen = Set<UUID>()
        for log in logs where log.userID == ownerID && !log.skipped {
            guard let session = sessionByID[log.sessionID], seen.insert(log.id).inserted else { continue }
            let treadmill = log.exerciseName.contains(" · ") ? ManualWorkout.parseTreadmill(log.exerciseName) : nil
            let name = (treadmill?.name ?? log.exerciseName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let normalized = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let equivalentID = FamilyDefinition.index.equivalentMovement[normalized]
            let movement = MovementTiming.movement(named: name, movementID: log.movementID ?? equivalentID)
                ?? ExerciseCatalog.movementID(matchingName: name).flatMap { MovementTiming.movement(named: name, movementID: $0) }
            let displayName = movement.flatMap { $0.id == equivalentID ? $0.name : nil } ?? name
            let descriptor = ExerciseLogging.descriptor(for: movement)
            let isComposite = normalized.contains("+") || normalized.contains("/")
                || normalized.split(whereSeparator: { !$0.isLetter }).contains("or")
            let loggedEquipment = equipment(in: name)
            let canonicalEquipment = movement.map { equipment(in: $0.name + " " + $0.id) } ?? []
            let aliasFamily = FamilyDefinition.index.alias[FamilyDefinition.normalized(name)]
            let movementFamily = movement.flatMap { FamilyDefinition.index.movement[$0.id] }
            let family = aliasFamily ?? (isComposite ? nil : movementFamily)
            let substitute = aliasFamily != nil && movementFamily != nil && aliasFamily?.id != movementFamily?.id
            let explicitLoad = log.weightKG?.isFinite == true && (log.weightKG ?? 0) > 0
            let usesBodyweight = descriptor.kind == .bodyweight || (family?.id == "push_up" && movement == nil)
            let exactName = name.lowercased()
            let storedUnit = log.exerciseID.flatMap { units[$0] } ?? unitsByName[exactName]
            // Programme revisions used both checkmarks and minutes for Focus T25 episodes.
            let episode = exactName.hasPrefix("Focus T25".lowercased() + " · ") || Self.legacyVideoNames.contains(exactName)
            let catalogUnit = movement.flatMap { catalogRepUnits[$0.id] }
            let measuresReps = !episode && descriptor.fields.contains(.reps) && treadmill == nil
                && [storedUnit, catalogUnit].compactMap { $0 }.allSatisfy { $0 == "reps" || $0 == "max" }
            // A recorded mass still measures a same-implement set when the log leaves its stance unspecified.
            let loadedPushUp = log.movementID == "weighted_push_up" && aliasFamily?.id == "push_up"
            let comparableMass = !isComposite || loadedPushUp || ["hip_thrust", "biceps_curl", "calf_raise"].contains(aliasFamily?.id ?? "")
            let assisted = (normalized + " " + (movement?.id ?? "")).split(whereSeparator: { !$0.isLetter })
                .contains { ["assisted", "counterweight", "counterweighted"].contains($0) }
            let recordsExternalWeight = measuresReps && comparableMass && !substitute && !assisted
                && !loggedEquipment.contains("band") && !canonicalEquipment.contains("band")
                && (descriptor.kind == .strength || descriptor.kind == .bodyweight)
            let measuresExternalLoad = recordsExternalWeight
                && (usesBodyweight ? explicitLoad : log.weightKG != 0 && (log.weightKG ?? 0) >= 0)
            let hasLoad = measuresExternalLoad && !usesBodyweight && explicitLoad
            var facts = WorkoutReceipt.editInput(log)
            if let treadmill {
                facts.distanceMeters = facts.distanceMeters ?? treadmill.metrics.distanceKM * 1_000
                facts.durationSeconds = facts.durationSeconds ?? treadmill.metrics.durationMinutes * 60
            }
            let timed = storedUnit == "seconds" || storedUnit == "minutes"
                || ((storedUnit == nil || storedUnit == "max") && descriptor.kind == .isometric && catalogUnit == "seconds")
            // Early players stored the completed quantity in reps, including seconds and checkmarks.
            let historicalQuantity = episode || storedUnit == "check"
                || (timed && [.strength, .bodyweight, .isometric].contains(descriptor.kind))
            let performed = historicalQuantity ? (log.durationSeconds ?? log.reps ?? 0) > 0
                : ExerciseLogging.isValid(facts, descriptor: descriptor)
            guard performed || (hasLoad && log.reps == nil) else { continue }
            // Historical aliases sometimes point different implements at the same movement ID.
            let key = movement.flatMap { !isComposite && !substitute && loggedEquipment.isSubset(of: canonicalEquipment) ? "movement:" + $0.id : nil }
                ?? "name:" + normalized
            if groups[key] == nil {
                let region = BodyRegion(primaryMuscle: movement?.primaryMuscles?.first)
                groups[key] = Group(name: displayName, region: region == .other ? family?.bodyRegion ?? region : region,
                                    family: family)
            }
            groups[key]?.sessions[session.id, default: SessionTotals(session)].totals.record(
                log, measuresReps: measuresReps, measuresLoad: measuresExternalLoad
            )
            if recordsExternalWeight,
               let kg = log.weightKG, kg.isFinite, kg >= 0, let reps = log.reps, reps > 0 {
                if let previous = groups[key]?.sessions[session.id]?.heaviestSet {
                    if (kg, reps) > (previous.kg, previous.reps) {
                        groups[key]?.sessions[session.id]?.heaviestSet = (kg, reps)
                    }
                } else {
                    groups[key]?.sessions[session.id]?.heaviestSet = (kg, reps)
                }
                if reps == 1, kg > 0 {
                    let previous = groups[key]?.sessions[session.id]?.bestSingleKG ?? 0
                    groups[key]?.sessions[session.id]?.bestSingleKG = max(kg, previous)
                }
            }
            if let current = groups[key], session.date > current.lastPerformed
                || (session.date == current.lastPerformed && displayName < current.name) {
                groups[key]?.lastPerformed = session.date
                groups[key]?.name = displayName
            }
            if hasLoad {
                groups[key]?.loads[session.id, default: []].append(log)
            }
        }

        return groups.map { key, group in
            let sessions = group.sessions.values.sorted(by: SessionTotals.chronological)
            let points = sessions.compactMap { point -> Point? in
                guard let rows = group.loads[point.sessionID], let session = sessionByID[point.sessionID] else { return nil }
                return loadPoint(session: session, logs: rows)
            }
            return ExerciseHistory(key: key, name: group.name, region: group.region,
                                   sessions: sessions, familyKey: group.family.map { "family:" + $0.id } ?? key,
                                   familyName: group.family?.name, familyRegion: group.family?.bodyRegion ?? group.region,
                                   totals: sessions.reduce(into: LifetimeTotals()) { $0.add($1.totals) },
                                   lastPerformed: group.lastPerformed, points: points)
        }.sorted {
            if $0.sessionCount != $1.sessionCount { return $0.sessionCount > $1.sessionCount }
            if $0.lastPerformed != $1.lastPerformed { return $0.lastPerformed > $1.lastPerformed }
            if $0.name.lowercased() != $1.name.lowercased() { return $0.name.lowercased() < $1.name.lowercased() }
            return $0.key < $1.key
        }
    }

    // MARK: - Session insights

    static func sessionInsights(
        sessions: [WorkoutSession],
        logs: [WorkoutLog],
        sessionID: UUID
    ) -> [SessionInsight] {
        guard let current = sessions.first(where: { $0.id == sessionID }) else { return [] }

        return buildSeries(sessions: sessions, logs: logs).compactMap { series -> SessionInsight? in
            guard let point = series.points.first(where: { $0.sessionID == sessionID }) else { return nil }
            let prior = series.points.filter { $0.date < current.date }
            let previous = prior.last
            /* Prefer a meaningful 30-90 day comparison. When history is newer,
               the earliest prior point is still more honest than inventing a
               horizon that does not exist. */
            let withinNinety = prior.filter { daysBetween($0.date, current.date) <= 90 }
            let reference = withinNinety.first ?? previous
            return SessionInsight(
                key: series.key,
                name: series.name,
                current: point,
                previous: previous,
                reference: reference,
                daysCompared: reference.map { daysBetween($0.date, current.date) },
                loadDelta: reference.map { round1(point.topWeight - $0.topWeight) },
                estimated1RMDelta: reference.map { round1(point.estimated1RM - $0.estimated1RM) }
            )
        }.sorted { ($0.loadDelta ?? -.infinity) > ($1.loadDelta ?? -.infinity) }
    }

    // MARK: - Joint check-ins

    static func assess(_ current: JointCheckin, previous: JointCheckin? = nil) -> JointAssessment {
        let regions = JointRegion.allCases
        let scores = regions.map { current[$0] }
        let affected = regions.filter { current[$0] >= 5 }
        let rising = previous.map { prior in regions.filter { current[$0] - prior[$0] >= 2 } } ?? []
        let highest = scores.max() ?? 0
        let average = roundJS(Double(scores.reduce(0, +)) / Double(scores.count) * 10) / 10
        let severe = regions.filter { current[$0] >= 9 }
        let high = regions.filter { current[$0] >= 7 }
        let elevated = regions.filter { current[$0] >= 6 }

        var state: DeloadState = .clear
        if !severe.isEmpty { state = .stopAndReview }
        else if high.count >= 2 || elevated.count >= 2 || average >= 7 { state = .wholeDeload }
        else if high.count == 1 { state = .regionalDeload }
        else if !affected.isEmpty || !rising.isEmpty { state = .watch }

        return JointAssessment(
            state: state,
            affected: severe.isEmpty ? affected : severe,
            average: average,
            highest: highest,
            rising: rising
        )
    }

    static func checkinDue(_ checkins: [JointCheckin], today: String, intervalDays: Int = 7) -> Bool {
        guard let latest = checkins.max(by: { $0.date < $1.date }) else { return true }
        return daysBetween(latest.date, today) >= intervalDays
    }

    /// Check-ins live in settings addons, the same place the web keeps them.
    static func checkins(from addons: [String: JSONValue]?) -> [JointCheckin] {
        guard case .array(let rows)? = addons?["joint_checkins"] else { return [] }
        return rows.compactMap { row in
            guard case .object(let fields) = row,
                  case .string(let date)? = fields["date"] else { return nil }
            func score(_ key: String) -> Int {
                guard case .number(let value)? = fields[key] else { return 0 }
                return max(0, min(10, Int(value)))
            }
            return JointCheckin(date: date, arms: score("arms"), core: score("core"), legs: score("legs"))
        }
    }
}

// Session IDs preserve separate workouts; the performed date controls horizontal distance.
struct WorkoutChartCalendar {
    let first: Date
    let last: Date
    let ticks: [Date]

    init?(from start: String, to end: String, intervals: Int = 4) {
        guard let first = APEXDateMath.date(from: start), let last = APEXDateMath.date(from: end),
              first <= last else { return nil }
        self.init(first: first, last: last, intervals: intervals)
    }

    init(first: Date, last: Date, intervals: Int = 4) {
        self.first = first
        self.last = last
        let calendar = APEXDateMath.calendar
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        let count = min(days, max(1, intervals))
        if count == 0 { ticks = [first]; return }
        ticks = (0...count).compactMap { i in
            let offset = Int((Double(days * i) / Double(count)).rounded())
            return calendar.date(byAdding: .day, value: offset, to: first)
        }
    }

    func position(_ date: Date) -> Double {
        let span = last.timeIntervalSince(first)
        return span > 0 ? date.timeIntervalSince(first) / span : 0.5
    }

    /// Keep separate workouts on a shared date visible within their nearest date ticks.
    func positions(for dates: [Date]) -> [Double] {
        var result = dates.map(position)
        var start = 0
        while start < dates.count {
            var end = start + 1
            while end < dates.count && dates[end] == dates[start] { end += 1 }
            if end - start > 1 {
                let center = position(dates[start])
                let left = start == 0 ? 0 : (position(dates[start - 1]) + center) / 2
                let right = end == dates.count ? 1 : (center + position(dates[end])) / 2
                let spread = min(0.08, Double(end - start - 1) * 0.015)
                let low = max(left, center - spread), high = min(right, center + spread)
                for i in start..<end {
                    result[i] = low + (high - low) * Double(i - start) / Double(end - start - 1)
                }
            }
            start = end
        }
        return result
    }

    func label(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: APEXDateMath.calendar, timeZone: .gmt)
            .month(.abbreviated).day()
        if APEXDateMath.calendar.component(.year, from: first) != APEXDateMath.calendar.component(.year, from: last) {
            style = style.year(.twoDigits)
        }
        return date.formatted(style)
    }
}
