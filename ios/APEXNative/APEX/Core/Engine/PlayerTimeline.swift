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

    struct WorkPosition: Hashable, Sendable {
        let exerciseIndex: Int
        let setNumber: Int
        let groupID: UUID?
        let groupLabel: String?
        let groupPosition: Int?
        let groupSize: Int
    }

    private struct PersistenceKey: Hashable {
        let exerciseID: UUID
        let setNumber: Int
    }

    enum BreakKind: Hashable, Sendable {
        case ordinary
        case groupTransition
        case groupRecovery
    }

    struct BreakPlan: Hashable, Sendable {
        let kind: BreakKind
        let duration: Int
        let nextLabel: String
    }

    /// A rest is authored data. In particular, zero means "continue without
    /// recovery" and must never be promoted to a default by a minimum clamp.
    static func restCountdownSeconds(_ plan: BreakPlan?, fallback: Int) -> Int {
        max(0, plan?.duration ?? fallback)
    }

    /// The adjusted plan owns warm-up timing. An empty or zero-length warm-up
    /// starts directly at the first working set.
    static func warmupCountdownSeconds(text: String, duration: Int) -> Int? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              duration > 0 else { return nil }
        return duration
    }

    private struct GroupMember: Hashable, Sendable {
        let exerciseIndex: Int
        let position: Int
    }

    private struct ValidGroup: Sendable {
        let id: UUID
        let label: String
        let members: [GroupMember]
    }

    static func workSequence(_ exercises: [Exercise]) -> [WorkPosition] {
        makeWorkSequence(exercises: exercises, plannedSets: exercises.map { max(1, $0.sets) })
    }

    static func workSequence(_ plan: PlannedDay) -> [WorkPosition] {
        makeWorkSequence(
            exercises: plan.exercises.map(\.exercise),
            plannedSets: plan.exercises.map { max(1, $0.plannedSets) }
        )
    }

    /// Both session modes can hand persistence exercise-major inputs. Once a
    /// valid linked group exists, canonical history must instead match the
    /// round-major sequence the athlete performed (A1, A2, A1, A2).
    static func persistenceOrder(
        _ inputs: [WorkoutSetInput],
        exercises: [Exercise]
    ) -> [WorkoutSetInput] {
        let sequence = workSequence(exercises)
        guard sequence.contains(where: { $0.groupID != nil }) else { return inputs }

        var inputIndex: [PersistenceKey: Int] = [:]
        for (index, input) in inputs.enumerated() {
            guard let exerciseID = input.exerciseID else { continue }
            let key = PersistenceKey(exerciseID: exerciseID, setNumber: input.setNumber)
            if inputIndex[key] == nil { inputIndex[key] = index }
        }
        let orderedIndices = sequence.compactMap { position in
            inputIndex[PersistenceKey(
                exerciseID: exercises[position.exerciseIndex].id,
                setNumber: position.setNumber
            )]
        }
        let included = Set(orderedIndices)
        return orderedIndices.map { inputs[$0] }
            + inputs.indices.filter { !included.contains($0) }.map { inputs[$0] }
    }

    private static func makeWorkSequence(
        exercises: [Exercise],
        plannedSets: [Int]
    ) -> [WorkPosition] {
        let workSets = zip(exercises, plannedSets).map { exercise, sets in
            exercise.repUnit == "check" ? 1 : max(1, sets)
        }
        var candidates: [UUID: [GroupMember]] = [:]
        for (exerciseIndex, exercise) in exercises.enumerated() {
            guard let id = exercise.workGroupID,
                  let position = exercise.workGroupPosition,
                  position > 0,
                  exercise.repUnit != "check" else { continue }
            candidates[id, default: []].append(
                GroupMember(exerciseIndex: exerciseIndex, position: position)
            )
        }

        let valid = candidates.compactMap { id, members -> (UUID, [GroupMember])? in
            guard members.count >= 2,
                  Set(members.map(\.position)).count == members.count else { return nil }
            return (id, members.sorted {
                $0.position == $1.position
                    ? $0.exerciseIndex < $1.exerciseIndex
                    : $0.position < $1.position
            })
        }
        .sorted { left, right in
            (left.1.map(\.exerciseIndex).min() ?? .max)
                < (right.1.map(\.exerciseIndex).min() ?? .max)
        }
        .enumerated()
        .map { index, entry in
            ValidGroup(
                id: entry.0,
                label: index < 26 ? String(UnicodeScalar(65 + index)!) : "G\(index + 1)",
                members: entry.1
            )
        }

        var groupByExercise: [Int: ValidGroup] = [:]
        for group in valid {
            for member in group.members { groupByExercise[member.exerciseIndex] = group }
        }

        var consumed = Set<UUID>()
        var sequence: [WorkPosition] = []
        for exerciseIndex in exercises.indices {
            guard let group = groupByExercise[exerciseIndex] else {
                for setNumber in 1...workSets[exerciseIndex] {
                    sequence.append(WorkPosition(
                        exerciseIndex: exerciseIndex,
                        setNumber: setNumber,
                        groupID: nil,
                        groupLabel: nil,
                        groupPosition: nil,
                        groupSize: 1
                    ))
                }
                continue
            }
            guard consumed.insert(group.id).inserted else { continue }
            let rounds = group.members.map { workSets[$0.exerciseIndex] }.max() ?? 1
            for round in 1...rounds {
                for member in group.members where round <= workSets[member.exerciseIndex] {
                    sequence.append(WorkPosition(
                        exerciseIndex: member.exerciseIndex,
                        setNumber: round,
                        groupID: group.id,
                        groupLabel: "\(group.label)\(member.position)",
                        groupPosition: member.position,
                        groupSize: group.members.count
                    ))
                }
            }
        }
        return sequence
    }

    private static func nextLabel(_ position: WorkPosition, exercise: Exercise) -> String {
        if let label = position.groupLabel {
            return "\(label) · \(exercise.name), round \(position.setNumber)"
        }
        return "\(exercise.name), set \(position.setNumber)"
    }

    static func breakPlan(
        after current: WorkPosition,
        before next: WorkPosition,
        exercises: [Exercise]
    ) -> BreakPlan {
        let exercise = exercises[current.exerciseIndex]
        let nextExercise = exercises[next.exerciseIndex]
        let sameGroup = current.groupID != nil && current.groupID == next.groupID
        if sameGroup, current.setNumber == next.setNumber {
            return BreakPlan(
                kind: .groupTransition,
                duration: 15,
                nextLabel: nextLabel(next, exercise: nextExercise)
            )
        }
        if sameGroup, next.setNumber > current.setNumber, let groupID = current.groupID {
            let recovery = exercises
                .filter { $0.workGroupID == groupID }
                .map(\.restSeconds)
                .max() ?? 0
            return BreakPlan(
                kind: .groupRecovery,
                duration: recovery,
                nextLabel: nextLabel(next, exercise: nextExercise)
            )
        }
        let duration = current.exerciseIndex == next.exerciseIndex
            ? exercise.restSeconds
            : MovementTiming.transitionSeconds(
                finished: MovementTiming.movement(named: exercise.name),
                next: MovementTiming.movement(named: nextExercise.name),
                authoredRest: exercise.restSeconds
            )
        return BreakPlan(
            kind: .ordinary,
            duration: duration,
            nextLabel: nextLabel(next, exercise: nextExercise)
        )
    }

    // MARK: - Timeline

    static func build(_ plan: PlannedDay) -> [Block] {
        var blocks: [Block] = []
        if !plan.warmup.isEmpty, plan.warmupDuration > 0 {
            blocks.append(.warmup(text: plan.warmup, duration: plan.warmupDuration))
        }

        let sequence = workSequence(plan)
        for (sequenceIndex, position) in sequence.enumerated() {
            let index = position.exerciseIndex
            let planned = plan.exercises[index]
            let exercise = planned.exercise
            if exercise.repUnit == "check" {
                blocks.append(.check(exerciseIndex: index))
                continue
            }

            let setNumber = position.setNumber
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
                    /* Every single-sided movement needs the switch, not only
                       the ones whose name happens to say "split squat", and it
                       lasts as long as the movement makes it last. */
                    if side == .left, sideIndex < sides.count - 1 {
                        let timing = MovementTiming.movement(named: exercise.name)
                        blocks.append(.sideSwitch(
                            exerciseIndex: index,
                            setNumber: setNumber,
                            duration: MovementTiming.sideSwitchSeconds(for: timing)
                        ))
                    }
                }

            let nextPosition = sequenceIndex + 1 < sequence.count ? sequence[sequenceIndex + 1] : nil
            if let nextPosition {
                let sameExercise = index == nextPosition.exerciseIndex
                let reviewExercise = setNumber == planned.plannedSets && !sameExercise
                let rest = breakPlan(
                    after: position,
                    before: nextPosition,
                    exercises: plan.exercises.map(\.exercise)
                )
                if rest.duration > 0 || reviewExercise {
                blocks.append(.rest(
                    exerciseIndex: index,
                    afterSet: setNumber,
                    duration: rest.duration,
                    nextLabel: rest.nextLabel,
                    captureLoad: !reviewExercise && exercise.incrementKG > 0,
                    reviewExercise: reviewExercise
                ))
                }
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

    struct RestoredCountdown: Hashable, Sendable {
        let remaining: Int
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

    /// Reconciles a countdown after suspension or process termination. Passive
    /// timers use real wall time; an active set keeps its value and requires an
    /// explicit resume so background throttling cannot fabricate work.
    static func reconcileCountdown(
        block: Block?,
        remaining: Int,
        paused: Bool,
        persistedAt: String?,
        now: Date = .now
    ) -> RestoredCountdown {
        let safeRemaining = max(0, remaining)
        guard !paused, let persistedAt else {
            return RestoredCountdown(remaining: safeRemaining, paused: paused)
        }
        if block?.isSet == true {
            return RestoredCountdown(remaining: safeRemaining, paused: true)
        }
        guard block?.isPassiveTimer == true else {
            return RestoredCountdown(remaining: safeRemaining, paused: paused)
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let persisted = parser.date(from: persistedAt)
                ?? ISO8601DateFormatter().date(from: persistedAt) else {
            return RestoredCountdown(remaining: safeRemaining, paused: paused)
        }
        let wallSeconds = Int(max(0, now.timeIntervalSince(persisted)).rounded(.down))
        return RestoredCountdown(
            remaining: max(0, safeRemaining - wallSeconds),
            paused: false
        )
    }

    // MARK: - Interrupted guided session

    struct SessionDraft: Codable, Equatable, Sendable {
        var version = 1
        let userID: UUID
        let dayID: UUID
        let date: String
        let lite: Bool
        let exerciseIDs: [UUID]
        var phase: String
        var currentIndex: Int
        var currentSet: Int
        var actualReps: Int
        var currentWeight: Double
        var timerRemaining: Int
        var timerTotal: Int
        var paused: Bool
        var setInputs: [WorkoutSetInput]
        var startedAt: Date
        var repElapsed: Double
        var announcedRep: Int
        var persistedAt: String
    }

    enum DraftStore {
        private static let prefix = "apex.guided-workout.v1"

        private static func key(
            userID: UUID,
            dayID: UUID,
            date: String,
            lite: Bool
        ) -> String {
            "\(prefix).\(userID.uuidString.lowercased()).\(dayID.uuidString.lowercased()).\(date).\(lite ? "lite" : "full")"
        }

        static func save(
            _ draft: SessionDraft,
            defaults: UserDefaults = .standard
        ) {
            guard let data = try? JSONEncoder().encode(draft) else { return }
            defaults.set(
                data,
                forKey: key(
                    userID: draft.userID,
                    dayID: draft.dayID,
                    date: draft.date,
                    lite: draft.lite
                )
            )
        }

        static func load(
            userID: UUID,
            dayID: UUID,
            date: String,
            lite: Bool,
            exerciseIDs: [UUID],
            defaults: UserDefaults = .standard
        ) -> SessionDraft? {
            guard let data = defaults.data(forKey: key(
                userID: userID,
                dayID: dayID,
                date: date,
                lite: lite
            )),
            let draft = try? JSONDecoder().decode(SessionDraft.self, from: data),
            draft.version == 1,
            draft.userID == userID,
            draft.dayID == dayID,
            draft.date == date,
            draft.lite == lite,
            draft.exerciseIDs == exerciseIDs else { return nil }
            return draft
        }

        static func clear(
            userID: UUID,
            dayID: UUID,
            date: String,
            lite: Bool,
            defaults: UserDefaults = .standard
        ) {
            defaults.removeObject(forKey: key(
                userID: userID,
                dayID: dayID,
                date: date,
                lite: lite
            ))
        }
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
