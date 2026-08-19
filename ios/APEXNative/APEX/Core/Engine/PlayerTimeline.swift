import Foundation

/*
 * Port of src/lib/playerTimeline.ts.
 *
 * Turns an adjusted plan into the ordered blocks the guided player walks
 * through: warm-up, sets, side switches, rests, per-exercise logs, done.
 *
 * The judgements worth keeping are all about not manufacturing work that did
 * not happen. A passive timer may keep counting in the background, but an
 * active set may not, because a throttled app must never invent completed
 * repetitions. A restored set waits for an explicit resume. And a prefill
 * scans backwards for the closest real entry rather than falling back to a
 * recommendation the person already overrode.
 */
enum PlayerTimeline {
    enum Side: String, Sendable { case left, right }

    enum Block: Hashable, Sendable {
        case warmup(text: String, duration: Int)
        case check(exerciseIndex: Int)
        case set(
            exerciseIndex: Int,
            setNumber: Int,
            totalSets: Int,
            side: Side?,
            resultKey: String,
            targetReps: Int?,
            repDuration: Double,
            timed: Int?
        )
        case sideSwitch(exerciseIndex: Int, setNumber: Int, duration: Int)
        case rest(
            exerciseIndex: Int,
            afterSet: Int,
            duration: Int,
            nextLabel: String,
            captureLoad: Bool,
            reviewExercise: Bool
        )
        case log(exerciseIndex: Int)
        case done

        /// Warm-ups, rests and side switches may keep counting while the app
        /// is backgrounded. An active set may not.
        var isPassiveTimer: Bool {
            switch self {
            case .warmup, .rest, .sideSwitch: true
            default: false
            }
        }

        var isSet: Bool {
            if case .set = self { return true }
            return false
        }
    }

    // MARK: - Per-exercise arithmetic

    static func repTarget(_ exercise: Exercise) -> Int? {
        guard exercise.repUnit != "max" else { return nil }
        return Int((Double(exercise.repMin + exercise.repMax) / 2).rounded())
    }

    static func repDuration(_ exercise: Exercise) -> Double {
        max(1.6, exercise.tempoUp + exercise.tempoDown + exercise.tempoPause + 0.4)
    }

    static func timedSeconds(_ exercise: Exercise) -> Int? {
        let mid = Int((Double(exercise.repMin + exercise.repMax) / 2).rounded())
        if exercise.repUnit == "seconds" { return mid }
        if exercise.repUnit == "minutes" { return mid * 60 }
        return nil
    }

    // MARK: - Timeline

    static func build(_ plan: PlannedDay) -> [Block] {
        var blocks: [Block] = []
        if !plan.warmup.isEmpty, plan.warmupDuration > 0 {
            blocks.append(.warmup(text: plan.warmup, duration: plan.warmupDuration))
        }

        for (index, planned) in plan.exercises.enumerated() {
            let exercise = planned.exercise
            if exercise.repUnit == "check" {
                blocks.append(.check(exerciseIndex: index))
                continue
            }

            for setNumber in 1...max(1, planned.plannedSets) {
                let sides: [Side?] = exercise.perSide ? [.left, .right] : [nil]
                for (sideIndex, side) in sides.enumerated() {
                    let suffix = side.map { "-\($0.rawValue)" } ?? ""
                    blocks.append(.set(
                        exerciseIndex: index,
                        setNumber: setNumber,
                        totalSets: planned.plannedSets,
                        side: side,
                        resultKey: "\(index)-\(setNumber)\(suffix)",
                        targetReps: repTarget(exercise),
                        repDuration: repDuration(exercise),
                        timed: timedSeconds(exercise)
                    ))
                    /* A split squat needs a moment to reset the rear foot;
                       other per-side work does not. */
                    if side == .left,
                       sideIndex < sides.count - 1,
                       exercise.name.range(
                           of: "(?:bulgarian|split[\\s-]?squat)",
                           options: [.regularExpression, .caseInsensitive]
                       ) != nil {
                        blocks.append(.sideSwitch(exerciseIndex: index, setNumber: setNumber, duration: 3))
                    }
                }

                let isLast = setNumber == planned.plannedSets
                if !isLast, exercise.restSeconds > 0 {
                    blocks.append(.rest(
                        exerciseIndex: index,
                        afterSet: setNumber,
                        duration: exercise.restSeconds,
                        nextLabel: "\(exercise.name), set \(setNumber + 1)",
                        captureLoad: exercise.incrementKG > 0,
                        reviewExercise: false
                    ))
                }
            }

            let next = index + 1 < plan.exercises.count ? plan.exercises[index + 1] : nil
            if let next, exercise.restSeconds > 0 {
                blocks.append(.rest(
                    exerciseIndex: index,
                    afterSet: planned.plannedSets,
                    duration: exercise.restSeconds,
                    nextLabel: next.name,
                    captureLoad: false,
                    reviewExercise: true
                ))
            } else {
                blocks.append(.log(exerciseIndex: index))
            }
        }

        blocks.append(.done)
        return blocks
    }

    // MARK: - Restoring a session

    struct Restored: Hashable, Sendable {
        let elapsed: Double
        let paused: Bool
    }

    static func reconcileElapsed(
        block: Block?,
        elapsed: Double,
        paused: Bool,
        persistedAt: String?,
        now: Date = .now
    ) -> Restored {
        let safe = max(0, elapsed.isFinite ? elapsed : 0)
        guard !paused, let persistedAt else { return Restored(elapsed: safe, paused: paused) }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let persisted = parser.date(from: persistedAt) ?? ISO8601DateFormatter().date(from: persistedAt) else {
            return Restored(elapsed: safe, paused: paused)
        }
        if block?.isPassiveTimer == true {
            return Restored(elapsed: safe + max(0, now.timeIntervalSince(persisted)), paused: false)
        }
        /* A restored active set waits for an explicit resume, so time away
           from the app never becomes repetitions nobody performed. */
        if block?.isSet == true { return Restored(elapsed: safe, paused: true) }
        return Restored(elapsed: safe, paused: paused)
    }

    // MARK: - Prefills

    /// The closest captured load is the least surprising default for the next
    /// set, and beats a recommendation the person has already overridden.
    static func prefillWeight(
        setWeights: [Double?],
        setNumber: Int,
        exerciseWeight: Double?,
        recommendedWeight: Double?
    ) -> Double? {
        let current = max(0, setNumber - 1)
        var index = min(current, setWeights.count - 1)
        while index >= 0 {
            if let candidate = setWeights[index], candidate.isFinite { return candidate }
            index -= 1
        }
        if let exerciseWeight, exerciseWeight.isFinite { return exerciseWeight }
        if let recommendedWeight, recommendedWeight.isFinite { return recommendedWeight }
        return nil
    }

    /// A correction entered during a break beats the count the cadence engine
    /// produced, which in turn beats the authored target.
    static func prefillReps(
        setReps: [Int?],
        setNumber: Int,
        countedReps: Int?,
        targetReps: Int?
    ) -> Int {
        let current = max(0, setNumber - 1)
        var index = min(current, setReps.count - 1)
        while index >= 0 {
            if let candidate = setReps[index] { return max(0, candidate) }
            index -= 1
        }
        if let countedReps { return max(0, countedReps) }
        if let targetReps { return max(0, targetReps) }
        return 0
    }

    /// Per-side work counts as the weaker side, never the stronger one.
    static func countedReps(
        _ counted: [String: Int],
        exerciseIndex: Int,
        setNumber: Int,
        perSide: Bool
    ) -> Int? {
        let key = "\(exerciseIndex)-\(setNumber)"
        if let explicit = counted[key] { return explicit }
        guard perSide else { return nil }
        let left = counted["\(key)-left"]
        let right = counted["\(key)-right"]
        if left == nil, right == nil { return nil }
        guard let left else { return right }
        guard let right else { return left }
        return min(left, right)
    }

    // MARK: - Estimates

    static func estimatedMinutes(_ plan: PlannedDay) -> Int {
        var seconds = 0.0
        for block in build(plan) {
            switch block {
            case .warmup(_, let duration):
                seconds += Double(duration)
            case .rest(_, _, let duration, _, _, _):
                seconds += Double(duration)
            case .sideSwitch(_, _, let duration):
                seconds += Double(duration)
            case .set(_, _, _, _, _, let targetReps, let repDuration, let timed):
                if let timed { seconds += Double(timed) }
                else { seconds += Double(targetReps ?? 12) * repDuration }
            case .check(let index):
                let exercise = plan.exercises[index].exercise
                if !FocusT25.isFocusName(exercise.name) {
                    seconds += 30
                } else {
                    /* An episode declares its own length in its notes; only
                       fall back to the standard 25 when it does not. */
                    let explicit = exercise.notes.range(
                        of: "\\|\\s*(\\d+)\\s*min\\s*\\|",
                        options: [.regularExpression, .caseInsensitive]
                    ).flatMap { range -> Int? in
                        Int(exercise.notes[range].filter(\.isNumber))
                    }
                    seconds += Double(max(1, explicit ?? 25)) * 60
                }
            case .log:
                seconds += 20
            case .done:
                break
            }
        }
        return max(1, Int((seconds / 60).rounded()))
    }

    struct DurationBreakdown: Hashable, Sendable {
        let total: Int
        let primary: Int
        let focusT25: Int
    }

    static func durationBreakdown(
        _ plan: PlannedDay,
        authoredFullMinutes: Int,
        lite: Bool
    ) -> DurationBreakdown {
        let total = max(1, lite ? estimatedMinutes(plan) : authoredFullMinutes)
        let mixedConditioning = plan.programDay?.dayType != "t25"
            && plan.exercises.contains { FocusT25.isConditioningName($0.exercise.name) }
        let focusT25 = mixedConditioning ? 25 : 0
        return DurationBreakdown(total: total, primary: max(1, total - focusT25), focusT25: focusT25)
    }

    /// Optional work is offered, not planned, so it is not counted.
    static func plannedSetCount(_ plan: PlannedDay) -> Int {
        plan.exercises.reduce(0) { $0 + ($1.exercise.optional ? 0 : $1.plannedSets) }
    }
}
