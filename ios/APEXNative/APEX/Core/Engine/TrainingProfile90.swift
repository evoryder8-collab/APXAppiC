import Foundation

struct TrainingProfile90: Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case resistance = "Resistance"
        case cardio = "Cardio"
        case mobility = "Mobility"
    }

    struct MatchedLoad: Sendable {
        let exercise: String
        let reps: Int
        let earlierKG: Double
        let recentKG: Double
    }

    let from: String
    let to: String
    let classifiedWorkouts: Int
    let counts: [Mode: Int]
    let runs: Int
    let recentMedianReps: Double?
    let matchedLoad: MatchedLoad?
    var muscleGrowthGoal = false

    var athleteTitle: String {
        switch category {
        case "Resistance-focused": muscleGrowthGoal ? "Bodybuilder" : "Strength athlete"
        case "Running-focused": "Runner"
        case "Cardio-focused": "Endurance athlete"
        case "Mobility-focused": "Mobility athlete"
        case "Mixed training": "All-rounder"
        default: "Building your baseline"
        }
    }

    // These describe the mix of logged sessions. Rep counts and loads are
    // reported independently because neither establishes a person's training goal.
    var category: String {
        guard classifiedWorkouts >= 3 else { return "Limited history" }
        let contributions = counts.values.reduce(0, +)
        func dominates(_ count: Int) -> Bool { count * 5 >= contributions * 3 }
        if dominates(runs) { return "Running-focused" }
        if dominates(counts[.resistance, default: 0]) { return "Resistance-focused" }
        if dominates(counts[.cardio, default: 0]) { return "Cardio-focused" }
        if dominates(counts[.mobility, default: 0]) { return "Mobility-focused" }
        return "Mixed training"
    }

    var note: String? {
        if classifiedWorkouts < 3 { return "A pattern needs at least three classified workouts." }
        if counts.values.reduce(0, +) > classifiedWorkouts { return "Mixed workouts can count in more than one category." }
        return nil
    }

    struct Metric {
        let key: String
        let value: String
    }

    @MainActor func metrics(language: LanguageState) -> [Metric] {
        var rows = [Metric(key: "Classified workouts", value: String(classifiedWorkouts))]
        let weekly = (Double(classifiedWorkouts) * 7 / 90).formatted(.number.locale(language.language.locale).precision(.fractionLength(0...1)))
        rows.append(Metric(key: "Workouts per week", value: weekly))
        rows += Mode.allCases.map { Metric(key: $0.rawValue, value: String(counts[$0, default: 0])) }
        if runs > 0 { rows.append(Metric(key: "Running", value: String(runs))) }
        if let recentMedianReps {
            let value = recentMedianReps.formatted(.number.locale(language.language.locale).precision(.fractionLength(0...1)))
            rows.append(Metric(key: "Recent median reps per resistance session", value: value))
        }
        return rows
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private enum Receipt: Hashable {
        case session(UUID), external(UUID), orbit(UUID)
    }

    private static let catalogUnits = Dictionary(ExerciseCatalog.all.map { ($0.movementID, $0.unit) },
                                                uniquingKeysWith: { first, _ in first })

    static func summarize(ownerID: UUID, data: DashboardData, through to: String) -> Self {
        let from = APEXDateMath.adding(days: -89, to: to)
        let split = APEXDateMath.adding(days: -44, to: to)
        let window = from...to
        let sessions = data.workoutSessions.filter { $0.userID == ownerID && $0.completed }
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let units = Dictionary(data.exercises.filter { $0.userID == ownerID }.map { ($0.id, $0.repUnit) },
                               uniquingKeysWith: { first, _ in first })
        var modes: [Receipt: Set<Mode>] = [:]
        var runs: Set<Receipt> = []
        var seen = Set<UUID>()
        var repsBySession: [UUID: Int] = [:]
        var loadLogs: [Int: [WorkoutLog]] = [:]

        for log in data.workoutLogs where log.userID == ownerID && !log.skipped {
            guard let session = byID[log.sessionID], window.contains(session.date), seen.insert(log.id).inserted else { continue }
            let movement = MovementTiming.movement(named: log.exerciseName, movementID: log.movementID)
            let descriptor = ExerciseLogging.descriptor(for: movement)
            if log.exerciseName.contains(" · "), let treadmill = ManualWorkout.parseTreadmill(log.exerciseName),
               treadmill.metrics.durationMinutes > 0, treadmill.metrics.distanceKM > 0 {
                modes[.session(session.id), default: []].insert(.cardio)
                if movement?.id == "run_outdoor" || treadmill.name.lowercased().split(whereSeparator: { !$0.isLetter }).contains(where: { $0 == "run" || $0 == "running" }) { runs.insert(.session(session.id)) }
                continue
            }
            guard ExerciseLogging.isValid(WorkoutReceipt.editInput(log), descriptor: descriptor) else { continue }
            switch movement?.entityType {
            case "cardio_modality", "conditioning_complex":
                modes[.session(session.id), default: []].insert(.cardio)
                if movement?.id == "run_outdoor" { runs.insert(.session(session.id)) }
            case "yoga_pose", "mobility_drill", "balance_drill":
                modes[.session(session.id), default: []].insert(.mobility)
            case "resistance_isometric":
                modes[.session(session.id), default: []].insert(.resistance)
            case "resistance_dynamic", nil:
                let load = log.weightKG ?? 0
                guard movement != nil || StrengthProgress.isKnownFamilyAlias(log.exerciseName) || (load.isFinite && load > 0),
                      let reps = log.reps, reps > 0, descriptor.fields.contains(.reps),
                      [log.exerciseID.flatMap { units[$0] }, movement.flatMap { catalogUnits[$0.id] }]
                        .compactMap({ $0 }).allSatisfy({ $0 == "reps" || $0 == "max" }) else { continue }
                modes[.session(session.id), default: []].insert(.resistance)
                if session.date >= split { repsBySession[session.id, default: 0] += reps }
                if load.isFinite && load > 0 { loadLogs[reps, default: []].append(log) }
            default: break
            }
        }

        let ownedImports = data.importedActivities.filter { $0.userID == ownerID }
        let hidden = Set(ownedImports.filter { $0.hiddenAt != nil }.map { $0.healthKitWorkoutID ?? $0.id })
        let visible = ownedImports.filter { !ExternalWorkoutImport.isAPEXBundleIdentifier($0.sourceBundleIdentifier ?? "") }
            .sorted { $0.apexWorkoutSessionID != nil && $1.apexWorkoutSessionID == nil }
        var importedIDs = Set<UUID>()
        var importedRuns: [String: [Date]] = [:]
        for row in visible {
            let identity = row.healthKitWorkoutID ?? row.id
            let linked = row.apexWorkoutSessionID.flatMap { byID[$0] }
            guard !hidden.contains(identity), row.durationMinutes > 0, let activity = activityType(row),
                  row.apexWorkoutSessionID == nil || linked != nil, window.contains(linked?.date ?? row.date),
                  importedIDs.insert(identity).inserted else { continue }
            let id = linked.map { Receipt.session($0.id) } ?? .external(identity)
            modes[id, default: []].insert(activity.mode)
            if activity.running {
                runs.insert(id)
                if let start = ExternalWorkoutImport.parseTimestamp(row.startedAt) {
                    importedRuns[row.date, default: []].append(start)
                }
            }
        }

        var orbitKeys = Set<String>()
        for run in data.orbitRuns where run.userID == ownerID && run.status == "completed" && window.contains(run.localDate) {
            guard let distance = run.metrics["distance_m"]?.numberValue, distance.isFinite, distance > 0,
                  let start = ExternalWorkoutImport.parseTimestamp(run.startedAt),
                  let end = ExternalWorkoutImport.parseTimestamp(run.endedAt), end > start,
                  orbitKeys.insert(run.clientIdempotencyKey.isEmpty ? run.id.uuidString : run.clientIdempotencyKey).inserted,
                  !(importedRuns[run.localDate] ?? []).contains(where: { abs($0.timeIntervalSince(start)) <= 120 }) else { continue }
            runs.insert(.orbit(run.id))
            modes[.orbit(run.id), default: []].insert(.cardio)
        }
        let counts = modes.values.reduce(into: [Mode: Int]()) { result, contributions in
            for mode in contributions { result[mode, default: 0] += 1 }
        }
        return Self(from: from, to: to, classifiedWorkouts: modes.count, counts: counts, runs: runs.count,
                    recentMedianReps: median(repsBySession.values.map(Double.init)),
                    matchedLoad: compareLoads(loadLogs, split: split, ownerID: ownerID, sessions: sessions, exercises: data.exercises),
                    muscleGrowthGoal: data.settings?.userID == ownerID && NutritionGoalPolicy.context(from: data.settings)?.trainingGoal == "muscle")
    }

    private static let importedTypes: [String: Mode] = {
        var result: [String: Mode] = [:]
        for (name, kind) in HealthImport.activityKind {
            result[name.lowercased()] = kind == "strength" ? .resistance : kind == "endurance" ? .cardio : .mobility
        }
        for name in ["run", "indoorrun", "outdoorrun", "indoorwalk", "outdoorwalk", "walking", "indoorcycling",
                     "outdoorcycling", "indoorcycle", "outdoorcycle", "hiit", "stairclimber", "stairclimbing"] { result[name] = .cardio }
        for name in ["barre", "stretching", "mobility"] { result[name] = .mobility }
        for name in ["strengthtraining", "weighttraining"] { result[name] = .resistance }
        return result
    }()

    private static func activityType(_ row: ImportedActivity) -> (mode: Mode, running: Bool)? {
        for label in [row.workoutNameKey, row.activity].compactMap({ $0 }) {
            let key = label.lowercased().replacingOccurrences(of: "health.workout.", with: "").filter(\.isLetter)
            if let mode = importedTypes[key] {
                return (mode, ["running", "run", "indoorrun", "outdoorrun"].contains(key))
            }
        }
        return nil
    }

    private static func compareLoads(_ logsByReps: [Int: [WorkoutLog]], split: String, ownerID: UUID,
                                     sessions: [WorkoutSession], exercises: [Exercise]) -> MatchedLoad? {
        var best: (support: Int, key: String, load: MatchedLoad)?
        for (reps, logs) in logsByReps {
            for variation in StrengthProgress.exerciseHistory(ownerID: ownerID, sessions: sessions, logs: logs, exercises: exercises) {
                let points = variation.points
                guard let earlier = median(points.filter { $0.date < split }.map(\.topWeight)),
                      let recent = median(points.filter { $0.date >= split }.map(\.topWeight)) else { continue }
                if let best, points.count < best.support
                    || (points.count == best.support && (variation.key > best.key || (variation.key == best.key && reps >= best.load.reps))) {
                    continue
                }
                best = (points.count, variation.key, MatchedLoad(exercise: variation.name, reps: reps, earlierKG: earlier, recentKG: recent))
            }
        }
        return best?.load
    }
}
