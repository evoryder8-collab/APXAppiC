import Foundation

enum ExerciseLoggingKind: String, CaseIterable, Sendable {
    case strength
    case bodyweight
    case isometric
    case carry
    case cardio
    case mobility
    case interval
    case circuit
}

enum ExerciseLoggingField: String, Sendable {
    case reps
    case signedLoad
    case rir
    case duration
    case distance
    case contacts
    case completion
    case rounds
    case work
    case recovery
}

struct ExerciseLoggingDescriptor: Equatable, Sendable {
    let kind: ExerciseLoggingKind
    let fields: [ExerciseLoggingField]
    let isSupported: Bool
}

enum ExerciseProgress: Equatable, Sendable {
    case improved
    case maintained
    case regressed
    case adherence
    case incomparable
}

enum ExerciseLogging {
    static func descriptor(
        movementNamed name: String,
        movementID: String? = nil
    ) -> ExerciseLoggingDescriptor {
        descriptor(for: MovementTiming.movement(named: name, movementID: movementID))
    }

    static func descriptor(for movement: MovementTiming.Movement?) -> ExerciseLoggingDescriptor {
        let kind = kind(for: movement)
        switch kind {
        case .strength, .bodyweight:
            if movement?.prescriptionMode == "contacts" {
                return ExerciseLoggingDescriptor(
                    kind: kind,
                    fields: [.contacts],
                    isSupported: true
                )
            }
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.reps, .signedLoad, .rir],
                isSupported: true
            )
        case .isometric:
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.duration, .signedLoad],
                isSupported: true
            )
        case .carry:
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.duration, .distance, .signedLoad],
                isSupported: true
            )
        case .cardio:
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.duration, .distance],
                isSupported: true
            )
        case .mobility:
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.duration, .completion],
                isSupported: true
            )
        case .interval:
            return ExerciseLoggingDescriptor(
                kind: kind,
                fields: [.rounds, .work, .recovery],
                isSupported: true
            )
        case .circuit:
            return ExerciseLoggingDescriptor(kind: kind, fields: [], isSupported: false)
        }
    }

    static func derivedPaceSecondsPerKilometre(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> Double? {
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) * 1_000 / distanceMeters
    }

    /// Clear irrelevant observations and make unassisted bodyweight an explicit zero.
    static func normalized(_ input: WorkoutSetInput) -> WorkoutSetInput {
        let descriptor = descriptor(
            movementNamed: input.exerciseName,
            movementID: input.movementID
        )
        return normalized(input, descriptor: descriptor)
    }

    static func normalized(
        _ input: WorkoutSetInput,
        descriptor: ExerciseLoggingDescriptor
    ) -> WorkoutSetInput {
        let clear = input.skipped || !descriptor.isSupported
        let has: (ExerciseLoggingField) -> Bool = { descriptor.fields.contains($0) }
        let load: Double? = {
            guard !clear, has(.signedLoad) else { return nil }
            if let weight = input.weightKG, weight.isFinite { return weight }
            return descriptor.kind == .bodyweight ? 0 : nil
        }()
        let effort: Int? = {
            guard !clear, has(.rir), let rir = input.rir, (0...5).contains(rir) else { return nil }
            return rir
        }()
        return WorkoutSetInput(
            exerciseID: input.exerciseID,
            exerciseName: input.exerciseName,
            setNumber: input.setNumber,
            weightKG: load,
            reps: !clear && has(.reps) ? positive(input.reps) : nil,
            rir: effort,
            movementID: input.movementID,
            durationSeconds: !clear && has(.duration) ? positive(input.durationSeconds) : nil,
            distanceMeters: !clear && has(.distance) ? positive(input.distanceMeters) : nil,
            contacts: !clear && has(.contacts) ? positive(input.contacts) : nil,
            rounds: !clear && has(.rounds) ? positive(input.rounds) : nil,
            workSeconds: !clear && has(.work) ? positive(input.workSeconds) : nil,
            recoverySeconds: !clear && has(.recovery) ? positive(input.recoverySeconds) : nil,
            skipped: input.skipped
        )
    }

    /// A completed row is valid only when its kind's measured facts are complete.
    static func isValid(_ input: WorkoutSetInput) -> Bool {
        let descriptor = descriptor(
            movementNamed: input.exerciseName,
            movementID: input.movementID
        )
        return isValid(input, descriptor: descriptor)
    }

    static func isResolved(_ input: WorkoutSetInput) -> Bool {
        input.skipped || isValid(input)
    }

    static func resolvingAsSkipped(_ input: WorkoutSetInput) -> WorkoutSetInput {
        var skipped = input
        skipped.skipped = true
        return normalized(skipped)
    }

    static func isValid(
        _ input: WorkoutSetInput,
        descriptor: ExerciseLoggingDescriptor
    ) -> Bool {
        guard descriptor.isSupported else { return false }
        let value = normalized(input, descriptor: descriptor)
        switch descriptor.kind {
        case .strength, .bodyweight:
            return descriptor.fields.contains(.contacts)
                ? value.contacts != nil
                : value.reps != nil
        case .isometric:
            return value.durationSeconds != nil
        case .carry:
            return (value.durationSeconds != nil) != (value.distanceMeters != nil)
        case .cardio:
            return value.durationSeconds != nil && value.distanceMeters != nil
        case .mobility:
            return true
        case .interval:
            return value.rounds != nil && value.workSeconds != nil && value.recoverySeconds != nil
        case .circuit:
            return false
        }
    }

    static func hasPrimaryFacts(
        descriptor: ExerciseLoggingDescriptor,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?,
        contacts: Int?,
        rounds: Int?,
        workSeconds: Int?,
        recoverySeconds: Int? = nil
    ) -> Bool {
        guard descriptor.isSupported else { return false }
        if descriptor.fields.contains(.completion) { return true }
        if descriptor.fields.contains(.contacts) { return (contacts ?? 0) > 0 }
        if descriptor.fields.contains(.rounds) || descriptor.fields.contains(.work) {
            return (rounds ?? 0) > 0 && (workSeconds ?? 0) > 0 && (recoverySeconds ?? 0) > 0
        }
        if descriptor.fields.contains(.reps) { return (reps ?? 0) > 0 }
        if descriptor.fields.contains(.duration) || descriptor.fields.contains(.distance) {
            return (durationSeconds ?? 0) > 0 || (distanceMeters ?? 0) > 0
        }
        return false
    }

    static func factSummary(_ log: WorkoutLog) -> [String] {
        if log.skipped { return ["Not completed"] }
        let descriptor = descriptor(
            movementNamed: log.exerciseName,
            movementID: log.movementID
        )
        var facts: [String] = []
        if descriptor.fields.contains(.reps), let reps = log.reps { facts.append("\(reps) reps") }
        if descriptor.fields.contains(.signedLoad), let load = log.weightKG {
            facts.append("\(number(load)) kg")
        }
        if descriptor.fields.contains(.rir), let rir = log.rir { facts.append("RIR \(rir)") }
        if descriptor.fields.contains(.duration), let duration = log.durationSeconds {
            facts.append("\(duration) sec")
        }
        if descriptor.fields.contains(.distance), let distance = log.distanceMeters {
            facts.append("\(number(distance)) m")
        }
        if descriptor.fields.contains(.contacts), let contacts = log.contacts {
            facts.append("\(contacts) contacts")
        }
        if descriptor.fields.contains(.rounds), let rounds = log.rounds {
            facts.append("\(rounds) rounds")
        }
        if descriptor.fields.contains(.work), let work = log.workSeconds {
            facts.append("\(work) sec work")
        }
        if descriptor.fields.contains(.recovery), let recovery = log.recoverySeconds {
            facts.append("\(recovery) sec recovery")
        }
        if descriptor.fields.contains(.completion), facts.isEmpty { facts.append("Completed") }
        if descriptor.kind == .cardio,
           let distance = log.distanceMeters,
           let duration = log.durationSeconds,
           let pace = derivedPaceSecondsPerKilometre(
            distanceMeters: distance,
            durationSeconds: duration
           ) {
            let rounded = Int(pace.rounded())
            facts.append(String(format: "%d:%02d /km", rounded / 60, rounded % 60))
        }
        return facts
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func kind(for movement: MovementTiming.Movement?) -> ExerciseLoggingKind {
        guard let movement else { return .strength }
        switch movement.entityType {
        case "cardio_modality":
            return .cardio
        case "movement_sequence":
            return .circuit
        case "conditioning_complex":
            return .interval
        case "balance_drill", "mobility_drill", "skill_drill", "yoga_pose":
            return .mobility
        case "resistance_isometric":
            return movement.prescriptionMode == "carry" ? .carry : .isometric
        case "plyometric":
            return .bodyweight
        case "resistance_dynamic":
            let bodyweight = !movement.loadable
                || movement.disciplines.contains("calisthenics")
                || movement.id == "assisted_pull_up_machine"
            return bodyweight ? .bodyweight : .strength
        default:
            return .strength
        }
    }
}
