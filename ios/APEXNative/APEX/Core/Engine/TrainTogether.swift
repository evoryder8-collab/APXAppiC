import Foundation

/*
 * Train together: one guided workout drives every phone in a room.
 *
 * The room is one small snapshot (`State`). Everything a phone shows is derived
 * from it by `Timeline.now`: the step, the set, the time left. Automatic steps
 * (a rest running out, a counted set reaching its target, a side switch) need
 * no message, because every phone derives them from the same plan and the
 * same server clock. Only a press changes the snapshot, and each press is a
 * pure function of the snapshot (`Timeline.apply`).
 */
enum TrainTogether {
    /// Every set starts this long after its step begins, so the rep counter and
    /// the figure start together on every phone whatever the voice is saying.
    static let leadInSeconds: TimeInterval = 5
    static let webBase = "https://evoryder8-collab.github.io/APXAppiC/#/join/"

    enum Kind: String, Codable, Sendable { case friends, `class` }

    enum Phase: String, Codable, Sendable {
        case lobby, warmup, work
        case sideSwitch = "side_switch"
        case rest, review

        /// A step with a clock that pause, +30 s and "next" act on.
        var isRunning: Bool { self == .warmup || self == .work || self == .sideSwitch || self == .rest }
    }

    typealias Side = GuidedSetExecution.Side

    struct State: Codable, Equatable, Sendable {
        var phase: Phase
        var position: Int
        var side: Side?
        /// Server time the current step's clock started, moved on by any pause.
        var anchor: Date
        var pausedAt: Date?
        var extraSeconds: Int
        /// Counts step boundaries. Phones tell a new step from a paused or
        /// re-sent one by this number, never by a timestamp.
        var step: Int
        var sound: Bool
        var voice: Bool
        /// The challenge wheel, in a room still choosing its workout.
        var wheel: Wheel?

        enum CodingKeys: String, CodingKey {
            case phase, position, side, anchor, step, sound, voice, wheel
            case pausedAt = "paused_at"
            case extraSeconds = "extra_seconds"
        }

        static func lobby(at time: Date) -> State {
            State(phase: .lobby, position: 0, side: nil, anchor: time, pausedAt: nil,
                  extraSeconds: 0, step: 0, sound: true, voice: false)
        }
    }

    /// The exercise list frozen into a room, without anyone's private row IDs.
    struct PlanExercise: Codable, Equatable, Sendable {
        var name: String
        var movementID: String?
        var workGroupID: UUID?
        var workGroupPosition: Int?
        var sets: Int
        var repMin: Int
        var repMax: Int
        var repUnit: String
        var perSide: Bool
        var restSeconds: Int
        var tempoUp: Double
        var tempoDown: Double
        var tempoPause: Double
        var tempoNote: String
        var notes: String
        var incrementKG: Double
        var optional: Bool

        enum CodingKeys: String, CodingKey {
            case name, sets, notes, optional
            case movementID = "movement_id"
            case workGroupID = "work_group_id"
            case workGroupPosition = "work_group_position"
            case repMin = "rep_min"
            case repMax = "rep_max"
            case repUnit = "rep_unit"
            case perSide = "per_side"
            case restSeconds = "rest_sec"
            case tempoUp = "tempo_up_s"
            case tempoDown = "tempo_down_s"
            case tempoPause = "tempo_pause_s"
            case tempoNote = "tempo_note"
            case incrementKG = "increment_kg"
        }

        init(_ exercise: Exercise) {
            name = exercise.name
            movementID = exercise.movementID
            workGroupID = exercise.workGroupID
            workGroupPosition = exercise.workGroupPosition
            sets = max(1, exercise.sets)
            repMin = exercise.repMin
            repMax = exercise.repMax
            repUnit = exercise.repUnit
            perSide = exercise.perSide
            restSeconds = exercise.restSeconds
            tempoUp = exercise.tempoUp
            tempoDown = exercise.tempoDown
            tempoPause = exercise.tempoPause
            tempoNote = exercise.tempoNote
            // The host's own notes on an exercise are private and stay in their account.
            notes = ""
            incrementKG = exercise.incrementKG
            optional = exercise.optional
        }

        func exercise(id: UUID, userID: UUID, programDayID: UUID, sortOrder: Int) -> Exercise {
            // Bounded as the server bounds them, so no room can send a phone numbers it cannot count with.
            Exercise(
                id: id, userID: userID, programDayID: programDayID, name: name,
                movementID: movementID, workGroupID: workGroupID, workGroupPosition: workGroupPosition,
                sets: min(max(1, sets), 20), repMin: min(max(0, repMin), 1_000), repMax: min(max(0, repMax), 1_000),
                repUnit: repUnit, perSide: perSide, restSeconds: min(max(0, restSeconds), 3_600),
                tempoUp: min(max(0, tempoUp), 30), tempoDown: min(max(0, tempoDown), 30),
                tempoPause: min(max(0, tempoPause), 30), tempoNote: tempoNote, notes: notes,
                incrementKG: incrementKG, isLite: false, optional: optional, sortOrder: sortOrder
            )
        }
    }

    struct Plan: Codable, Equatable, Sendable {
        var name: String
        var warmupText: String
        var warmupDuration: Int
        var exercises: [PlanExercise]

        enum CodingKeys: String, CodingKey {
            case name, exercises
            case warmupText = "warmup_text"
            case warmupDuration = "warmup_duration"
        }
    }

    /// The rows a joiner's own account gets, so the normal player and the
    /// normal save run on them. Stable IDs make joining twice a no-op.
    struct AnchorRows: Equatable, Sendable {
        let program: Program
        let day: ProgramDay
        let exercises: [Exercise]
    }

    static func anchorRows(plan: Plan, roomID: UUID, title: String, ownerID: UUID) -> AnchorRows {
        let program = Program(
            id: APEXStableID.scopedUUID(namespace: "train-together-program", date: "group", userID: ownerID),
            userID: ownerID, slug: "group", name: "Train together",
            description: "Workouts done together with others."
        )
        let room = roomID.uuidString.lowercased()
        let day = ProgramDay(
            id: APEXStableID.scopedUUID(namespace: "train-together-day", date: room, userID: ownerID),
            userID: ownerID, programID: program.id, weekday: 1, name: title, dayType: "custom",
            estimatedMinutes: 0, warmupNote: plan.warmupText, sortOrder: 0,
            sessionMode: WorkoutSessionMode.guided.rawValue, isActive: false
        )
        let exercises = plan.exercises.enumerated().map { index, item in
            item.exercise(
                id: APEXStableID.scopedUUID(namespace: "train-together-exercise", date: "\(room):\(index)", userID: ownerID),
                userID: ownerID, programDayID: day.id, sortOrder: index
            )
        }
        return AnchorRows(program: program, day: day, exercises: exercises)
    }

    // MARK: - Codes and links

    static let codeAlphabet = Set(#"ABCDEFGHJKMNPQRSTUVWXYZ23456789"#)

    /// A code typed, pasted alone, or inside a shared link or a message.
    static func code(in text: String) -> String? {
        let upper = text.uppercased()
        if let range = upper.range(of: #"JOIN/([A-Z0-9]{6})"#, options: .regularExpression) {
            let candidate = String(upper[range].suffix(6))
            if candidate.allSatisfy(codeAlphabet.contains) { return candidate }
        }
        let compact = upper.filter { !$0.isWhitespace && $0 != "-" }
        if compact.count == 6, compact.allSatisfy(codeAlphabet.contains) { return compact }
        return nil
    }

    static func shareURL(code: String) -> URL? { URL(string: webBase + code) }
    static func appURL(code: String) -> URL? { URL(string: "apex://join/\(code)") }

    // MARK: - Timeline

    struct Step: Equatable, Sendable {
        var phase: Phase
        var position: Int
        var side: Side?
        /// The state's step number plus the automatic steps rolled since.
        var index: Int
        var start: Date
        var elapsed: TimeInterval
        /// Nil: the step waits for a press (a set tapped Done, the review).
        var duration: TimeInterval?
        var paused: Bool

        var remaining: TimeInterval? { duration.map { max(0, $0 - elapsed) } }

        func isSameStep(as other: Step) -> Bool {
            index == other.index && phase == other.phase && position == other.position && side == other.side
        }
    }

    enum Action: Equatable, Sendable {
        case start
        /// "Set done", "Skip warm-up", "Continue" on a side switch, and
        /// "Next set" during a rest.
        case advance
        case pause
        case resume
        case addTime(Int)
        case jump(position: Int)
        case backToWarmup
        case sound(Bool)
        case voice(Bool)
        /// The host's focus for the wheel; a new focus clears the last spin.
        case wheelFocus(Focus)
        /// A spin drawn on the host's phone, started at the press.
        case spin(slots: [String], landing: Int)
    }

    struct Timeline: Sendable {
        let exercises: [Exercise]
        let sequence: [PlayerTimeline.WorkPosition]
        let warmupSeconds: Int?

        init(exercises: [Exercise], warmupText: String, warmupDuration: Int) {
            self.exercises = exercises
            sequence = PlayerTimeline.workSequence(exercises)
            warmupSeconds = PlayerTimeline.warmupCountdownSeconds(text: warmupText, duration: warmupDuration)
        }

        func exercise(at position: Int) -> Exercise? {
            sequence.indices.contains(position) ? exercises[sequence[position].exerciseIndex] : nil
        }

        func leadIn(_ side: Side?) -> TimeInterval { side == .right ? 0 : TrainTogether.leadInSeconds }

        func startOfWork(_ position: Int) -> (Phase, Int, Side?) {
            guard let exercise = exercise(at: position) else { return (.review, max(0, sequence.count - 1), nil) }
            return (.work, position, PlayerTimeline.usesSides(exercise) ? .left : nil)
        }

        func duration(_ phase: Phase, _ position: Int, _ side: Side?, extra: Int) -> TimeInterval? {
            switch phase {
            case .lobby, .review:
                return nil
            case .warmup:
                return TimeInterval((warmupSeconds ?? 0) + min(max(0, extra), 3_600))
            case .work:
                guard let exercise = exercise(at: position) else { return nil }
                if let hold = PlayerTimeline.timedSeconds(exercise) {
                    return leadIn(side) + TimeInterval(hold)
                }
                guard PlayerTimeline.usesAutomaticCadence(for: exercise),
                      let moving = PlayerTimeline.countedSetSeconds(exercise) else { return nil }
                return leadIn(side) + moving
            case .sideSwitch:
                guard let exercise = exercise(at: position) else { return 0 }
                let movement = MovementTiming.movement(named: exercise.name, movementID: exercise.movementID)
                return TimeInterval(MovementTiming.sideSwitchSeconds(for: movement) + min(max(0, extra), 3_600))
            case .rest:
                return TimeInterval(restSeconds(after: position) + min(max(0, extra), 3_600))
            }
        }

        func restSeconds(after position: Int) -> Int {
            guard sequence.indices.contains(position), sequence.indices.contains(position + 1) else { return 0 }
            let plan = PlayerTimeline.breakPlan(after: sequence[position], before: sequence[position + 1], exercises: exercises)
            return PlayerTimeline.restCountdownSeconds(plan, fallback: exercises[sequence[position].exerciseIndex].restSeconds)
        }

        func next(_ phase: Phase, _ position: Int, _ side: Side?) -> (Phase, Int, Side?) {
            switch phase {
            case .lobby:
                return warmupSeconds == nil ? startOfWork(0) : (.warmup, 0, nil)
            case .warmup:
                return startOfWork(0)
            case .work:
                if side == .left { return (.sideSwitch, position, .left) }
                return position + 1 < sequence.count ? (.rest, position, nil) : (.review, position, nil)
            case .sideSwitch:
                return (.work, position, .right)
            case .rest:
                return startOfWork(position + 1)
            case .review:
                return (phase, position, side)
            }
        }

        /// Where the room is at `time`, rolling through every automatic step.
        func now(_ state: State, at time: Date) -> Step {
            var phase = state.phase
            var position = state.position
            var side = state.side
            var start = state.anchor
            var extra = state.extraSeconds
            var index = state.step
            // A paused room stands still at the moment it was paused.
            let clock = state.pausedAt ?? time
            // A position has at most four steps (left, switch, right, rest).
            for _ in 0...(sequence.count * 4 + 4) {
                let duration = self.duration(phase, position, side, extra: extra)
                let elapsed = max(0, clock.timeIntervalSince(start))
                guard let duration, elapsed >= duration, phase != .lobby else {
                    return Step(phase: phase, position: position, side: side, index: index, start: start,
                                elapsed: duration.map { min(elapsed, $0) } ?? elapsed,
                                duration: duration, paused: state.pausedAt != nil)
                }
                start = start.addingTimeInterval(duration)
                (phase, position, side) = next(phase, position, side)
                extra = 0
                index += 1
            }
            return Step(phase: phase, position: position, side: side, index: index, start: start,
                        elapsed: 0, duration: nil, paused: state.pausedAt != nil)
        }

        /// The work steps a phone passed between two looks at the room, oldest
        /// first. They are only filled in when the room simply ran on; after a
        /// jump the sets in between were never done, so only `from` counts.
        func workPassed(from: Step, to: Step) -> [(position: Int, side: Side?)] {
            let own = from.phase == .work ? [(position: from.position, side: from.side)] : []
            let hops = to.index - from.index
            guard hops > 1, hops <= sequence.count * 4 + 4 else { return own }
            var cursor = (from.phase, from.position, from.side)
            var passed: [(position: Int, side: Side?)] = []
            for _ in 0..<hops {
                if cursor.0 == .work { passed.append((cursor.1, cursor.2)) }
                cursor = next(cursor.0, cursor.1, cursor.2)
            }
            return cursor == (to.phase, to.position, to.side) ? passed : own
        }

        /// The snapshot after a press made at `time`.
        func apply(_ action: Action, to state: State, at pressTime: Date) -> State {
            // Whole milliseconds, as the snapshot travels, so this phone and the server hold the same times.
            let time = Self.milliseconds(pressTime)
            let step = now(state, at: time)
            // A press acts on what every phone shows now, not on the stored step,
            // which automatic steps may have rolled past.
            var next = state
            if !(step.phase == state.phase && step.position == state.position && step.side == state.side) {
                next.extraSeconds = 0
            }
            (next.phase, next.position, next.side) = (step.phase, step.position, step.side)
            next.anchor = Self.milliseconds(step.start)
            next.step = step.index

            func begin(_ target: (Phase, Int, Side?)) {
                (next.phase, next.position, next.side) = target
                next.anchor = time
                next.pausedAt = nil
                next.extraSeconds = 0
                next.step = step.index + 1
            }

            switch action {
            case .start:
                // A room still choosing its workout has nothing to start.
                guard state.phase == .lobby, !sequence.isEmpty else { return state }
                begin(self.next(.lobby, 0, nil))
            case .advance:
                guard step.phase.isRunning else { return state }
                begin(self.next(step.phase, step.position, step.side))
            case .pause:
                guard next.pausedAt == nil, step.phase.isRunning else { return state }
                next.pausedAt = time
            case .resume:
                guard let pausedAt = next.pausedAt else { return state }
                next.anchor = next.anchor.addingTimeInterval(max(0, time.timeIntervalSince(pausedAt)))
                next.pausedAt = nil
            case .addTime(let seconds):
                guard step.phase.isRunning, step.phase != .work, seconds > 0 else { return state }
                next.extraSeconds += seconds
            case .jump(let position):
                guard sequence.indices.contains(position), state.phase != .lobby else { return state }
                begin(startOfWork(position))
            case .backToWarmup:
                guard warmupSeconds != nil, state.phase != .lobby else { return state }
                begin((.warmup, 0, nil))
            case .sound(let on):
                var changed = state
                changed.sound = on
                return changed
            case .voice(let on):
                var changed = state
                changed.voice = on
                return changed
            // The wheel only turns while the room is still choosing its workout.
            case .wheelFocus(let focus):
                guard state.phase == .lobby, sequence.isEmpty,
                      state.wheel?.focus != focus || state.wheel?.spin != nil else { return state }
                var changed = state
                changed.wheel = Wheel(focus: focus, spin: nil)
                return changed
            case .spin(let slots, let landing):
                guard state.phase == .lobby, sequence.isEmpty,
                      slots.indices.contains(landing), slots.count <= Wheel.mostSlots else { return state }
                var changed = state
                changed.wheel = Wheel(
                    focus: state.wheel?.focus ?? .fullBody,
                    spin: Wheel.Spin(at: time, slots: slots, landing: landing)
                )
                return changed
            }
            return next
        }

        static func milliseconds(_ date: Date) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        }

        /// What a set's counter shows after `elapsed` seconds of its step: reps,
        /// or seconds held for a timed hold.
        func counted(at position: Int, side: Side?, elapsed: TimeInterval) -> (reps: Int, holdLeft: TimeInterval?) {
            guard let exercise = exercise(at: position) else { return (0, nil) }
            let moving = max(0, elapsed - leadIn(side))
            if let hold = PlayerTimeline.timedSeconds(exercise) {
                return (min(hold, Int(moving)), max(0, TimeInterval(hold) - moving))
            }
            guard PlayerTimeline.usesAutomaticCadence(for: exercise) else {
                return (PlayerTimeline.repTarget(exercise) ?? 0, nil)
            }
            return (PlayerTimeline.countedRep(after: moving, for: exercise) ?? 0, nil)
        }
    }

    // MARK: - Server clock

    /// The phone's offset from the server, from the round trip with the
    /// shortest wait: offset = server time − the trip's midpoint.
    struct ClockSample: Equatable, Sendable {
        let sent: Date
        let received: Date
        let server: Date

        var roundTrip: TimeInterval { received.timeIntervalSince(sent) }
        var offset: TimeInterval { server.timeIntervalSince(sent.addingTimeInterval(roundTrip / 2)) }
    }

    static func clockOffset(_ samples: [ClockSample]) -> TimeInterval {
        samples.filter { $0.roundTrip >= 0 }.min { $0.roundTrip < $1.roundTrip }?.offset ?? 0
    }
}

extension TrainTogether.State {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decode(TrainTogether.Phase.self, forKey: .phase)
        position = try values.decode(Int.self, forKey: .position)
        side = try values.decodeIfPresent(TrainTogether.Side.self, forKey: .side)
        anchor = try values.decode(Date.self, forKey: .anchor)
        pausedAt = try values.decodeIfPresent(Date.self, forKey: .pausedAt)
        extraSeconds = try values.decode(Int.self, forKey: .extraSeconds)
        step = try values.decode(Int.self, forKey: .step)
        sound = try values.decode(Bool.self, forKey: .sound)
        voice = try values.decode(Bool.self, forKey: .voice)
        // A wheel this phone cannot read never costs it the rest of the room.
        wheel = try? values.decodeIfPresent(TrainTogether.Wheel.self, forKey: .wheel)
    }
}
