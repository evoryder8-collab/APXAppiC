import Foundation

/*
 * Smart progression: the next-load recommendation and the Overload Guardian.
 *
 * A 1:1 port of src/lib/progression.ts. The universal rule is that hitting the
 * top of the rep range on every set with clean form earns one increment next
 * session; anything short of that repeats the load.
 */
struct ExerciseHistoryPoint: Equatable, Sendable {
    let date: String
    let topWeight: Double
    /// Hit the top of the rep range on every set.
    let allTopReps: Bool
    let atTargetRIR: Bool
}

struct LoadRecommendation: Sendable {
    let weight: Double?
    let reason: String
    let previous: (weight: Double, date: String)?
    let history: [ExerciseHistoryPoint]
    let typicalIncrement: Double
}

struct GuardianVerdict: Equatable, Sendable {
    let triggered: Bool
    let safeLoad: Double
    let jump: Double
    let typical: Double
}

enum ProgressionEngine {
    static func compare(
        previous: WorkoutLog,
        current: WorkoutLog,
        descriptor: ExerciseLoggingDescriptor
    ) -> ExerciseProgress {
        guard !previous.skipped, !current.skipped else { return .incomparable }
        let oldLoad = previous.weightKG
        let newLoad = current.weightKG
        let oneLoadMissing = (oldLoad == nil) != (newLoad == nil)
        let loadImproved = oldLoad.flatMap { old in newLoad.map { $0 > old } } ?? false
        let loadRegressed = oldLoad.flatMap { old in newLoad.map { $0 < old } } ?? false

        switch descriptor.kind {
        case .strength, .bodyweight:
            if descriptor.fields == [.contacts] { return .adherence }
            guard let oldReps = previous.reps, let newReps = current.reps else {
                return .incomparable
            }
            guard let oldRIR = previous.rir, let newRIR = current.rir, !oneLoadMissing else {
                return .incomparable
            }
            if newRIR < oldRIR { return .regressed }
            return pareto(
                improving: [newReps > oldReps, loadImproved],
                regressing: [newReps < oldReps, loadRegressed]
            )
        case .isometric:
            guard let oldDuration = previous.durationSeconds,
                  let newDuration = current.durationSeconds,
                  !oneLoadMissing
            else { return .incomparable }
            return pareto(
                improving: [newDuration > oldDuration, loadImproved],
                regressing: [newDuration < oldDuration, loadRegressed]
            )
        case .carry:
            let dose: (old: Double, new: Double)
            if let oldDistance = previous.distanceMeters,
               let newDistance = current.distanceMeters,
               previous.durationSeconds == nil,
               current.durationSeconds == nil {
                dose = (oldDistance, newDistance)
            } else if let oldDuration = previous.durationSeconds,
                      let newDuration = current.durationSeconds,
                      previous.distanceMeters == nil,
                      current.distanceMeters == nil {
                dose = (Double(oldDuration), Double(newDuration))
            } else {
                return .incomparable
            }
            if oneLoadMissing { return .incomparable }
            return pareto(
                improving: [dose.new > dose.old, loadImproved],
                regressing: [dose.new < dose.old, loadRegressed]
            )
        case .cardio:
            guard let oldDistance = previous.distanceMeters,
                  let newDistance = current.distanceMeters,
                  let oldDuration = previous.durationSeconds,
                  let newDuration = current.durationSeconds,
                  let oldPace = ExerciseLogging.derivedPaceSecondsPerKilometre(
                    distanceMeters: oldDistance,
                    durationSeconds: oldDuration
                  ),
                  let newPace = ExerciseLogging.derivedPaceSecondsPerKilometre(
                    distanceMeters: newDistance,
                    durationSeconds: newDuration
                  )
            else { return .incomparable }
            return pareto(
                improving: [newDistance > oldDistance, newPace < oldPace],
                regressing: [newDistance < oldDistance, newPace > oldPace]
            )
        case .interval:
            guard let oldRounds = previous.rounds,
                  let newRounds = current.rounds,
                  let oldWork = previous.workSeconds,
                  let newWork = current.workSeconds,
                  let oldRecovery = previous.recoverySeconds,
                  let newRecovery = current.recoverySeconds
            else { return .incomparable }
            return pareto(
                improving: [newRounds > oldRounds, newWork > oldWork, newRecovery < oldRecovery],
                regressing: [newRounds < oldRounds, newWork < oldWork, newRecovery > oldRecovery]
            )
        case .mobility:
            return .adherence
        case .circuit:
            return .incomparable
        }
    }

    static func latestProgress(
        _ data: DashboardData,
        current: WorkoutLog
    ) -> ExerciseProgress? {
        let sessions = Dictionary(
            data.workoutSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        guard let currentSession = sessions[current.sessionID] else { return nil }
        let previous = data.workoutLogs
            .filter { candidate in
                guard candidate.id != current.id,
                      candidate.sessionID != current.sessionID,
                      !candidate.skipped,
                      candidate.setNumber == current.setNumber,
                      sameLoggedMovement(candidate, current),
                      let candidateSession = sessions[candidate.sessionID],
                      candidateSession.date <= currentSession.date
                else { return false }
                return candidateSession.date < currentSession.date
                    || candidate.createdAt < current.createdAt
            }
            .sorted { left, right in
                let leftDate = sessions[left.sessionID]?.date ?? ""
                let rightDate = sessions[right.sessionID]?.date ?? ""
                return leftDate == rightDate
                    ? left.createdAt < right.createdAt
                    : leftDate < rightDate
            }
            .last
        guard let previous else { return nil }
        return compare(
            previous: previous,
            current: current,
            descriptor: ExerciseLogging.descriptor(
                movementNamed: current.exerciseName,
                movementID: current.movementID
            )
        )
    }

    private static func sameLoggedMovement(_ left: WorkoutLog, _ right: WorkoutLog) -> Bool {
        guard left.userID == right.userID else { return false }
        let leftMovement = MovementTiming.movement(
            named: left.exerciseName,
            movementID: left.movementID
        )?.id ?? left.movementID
        let rightMovement = MovementTiming.movement(
            named: right.exerciseName,
            movementID: right.movementID
        )?.id ?? right.movementID
        if let leftMovement, let rightMovement {
            return leftMovement == rightMovement
        }
        if let leftExercise = left.exerciseID,
           let rightExercise = right.exerciseID,
           leftExercise == rightExercise {
            return true
        }
        return movementKey(left.exerciseName) == movementKey(right.exerciseName)
    }

    private static func pareto(
        improving: [Bool],
        regressing: [Bool]
    ) -> ExerciseProgress {
        if regressing.contains(true) { return .regressed }
        if improving.contains(true) { return .improved }
        return .maintained
    }

    private static func movementKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func history(_ data: DashboardData, exercise: Exercise) -> [ExerciseHistoryPoint] {
        let sessionsByID = Dictionary(
            data.workoutSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        struct Bucket {
            var weights: [Double] = []
            var reps: [(reps: Int?, rir: Int?)] = []
        }
        var byDate: [String: Bucket] = [:]
        let targetMovement = movementKey(exercise.name)
        for log in data.workoutLogs {
            let isSameMovement = log.exerciseID == exercise.id || (
                log.userID == exercise.userID &&
                movementKey(log.exerciseName) == targetMovement
            )
            guard isSameMovement, !log.skipped else { continue }
            guard let session = sessionsByID[log.sessionID] else { continue }
            var bucket = byDate[session.date] ?? Bucket()
            if let weight = log.weightKG { bucket.weights.append(weight) }
            bucket.reps.append((log.reps, log.rir))
            byDate[session.date] = bucket
        }
        return byDate
            .map { date, bucket in
                ExerciseHistoryPoint(
                    date: date,
                    topWeight: bucket.weights.max() ?? 0,
                    allTopReps: !bucket.reps.isEmpty && bucket.reps.allSatisfy {
                        guard let reps = $0.reps else { return false }
                        return reps >= exercise.repMax && exercise.repMax > 0
                    },
                    atTargetRIR: !bucket.reps.isEmpty && bucket.reps.allSatisfy {
                        guard let rir = $0.rir else { return false }
                        return rir >= 2
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }

    static func typicalIncrement(_ history: [ExerciseHistoryPoint], fallback: Double) -> Double {
        var diffs: [Double] = []
        for index in 1..<max(history.count, 1) {
            let delta = history[index].topWeight - history[index - 1].topWeight
            if delta > 0 { diffs.append(delta) }
        }
        guard !diffs.isEmpty else { return fallback == 0 ? 2.5 : fallback }
        diffs.sort()
        return diffs[diffs.count / 2]
    }

    static func recommend(_ data: DashboardData, exercise: Exercise) -> LoadRecommendation {
        let points = history(data, exercise: exercise)
        let increment = exercise.incrementKG
        let typical = typicalIncrement(points, fallback: increment)
        guard let last = points.last else {
            return LoadRecommendation(
                weight: nil,
                reason: "First session, pick a comfortable load",
                previous: nil,
                history: points,
                typicalIncrement: typical
            )
        }
        if increment > 0, last.allTopReps, last.atTargetRIR {
            return LoadRecommendation(
                weight: last.topWeight + increment,
                reason: "Top of rep range on all sets last time. +\(formatted(increment)) kg earned",
                previous: (last.topWeight, last.date),
                history: points,
                typicalIncrement: typical
            )
        }
        return LoadRecommendation(
            weight: last.topWeight == 0 ? nil : last.topWeight,
            reason: "Repeat last load and chase the top of the rep range",
            previous: (last.topWeight, last.date),
            history: points,
            typicalIncrement: typical
        )
    }

    /*
     * Overload Guardian: a manual entry that spikes past about 1.5x the typical
     * increment earns a science note before it counts. Muscle adapts faster than
     * tendon, and collagen remodels over weeks to months.
     */
    static func guardianCheck(
        entered: Double,
        recommendation: LoadRecommendation,
        factor: Double
    ) -> GuardianVerdict {
        let typical = max(recommendation.typicalIncrement, 1)
        guard let lastWeight = recommendation.previous?.weight, entered > lastWeight else {
            return GuardianVerdict(triggered: false, safeLoad: entered, jump: 0, typical: typical)
        }
        let jump = entered - lastWeight
        let triggered = jump > typical * factor
        let safeLoad = triggered ? ((lastWeight + typical) * 2).rounded() / 2 : entered
        return GuardianVerdict(triggered: triggered, safeLoad: safeLoad, jump: jump, typical: typical)
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
