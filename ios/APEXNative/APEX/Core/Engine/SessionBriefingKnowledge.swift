import Foundation

extension SessionBriefing {
    enum MovementFamily: String, CaseIterable, Equatable, Sendable {
        case strengthBodyweight
        case mobility
        case yoga
        case isometric
        case carry
        case cardio
        case interval
        case recovery
    }

    enum SessionPosition: Equatable, Sendable {
        case before
        case after
    }

    enum ExperienceBand: Equatable, Sendable {
        case littleHistory
        case developingHistory
        case establishedHistory
    }

    struct KnowledgeContext: Equatable, Sendable {
        let position: SessionPosition
        let movementFamilies: [MovementFamily]
        let movementNames: [String]
        let painReported: Bool
        let elevatedJointCheckIn: Bool
        let hypermobilityReported: Bool
        let experience: ExperienceBand
    }

    struct Knowledge: Equatable, Sendable {
        let lessonKeys: [String]
        let contextNoteKey: String?
        let cautionKeys: [String]

        static let empty = Knowledge(
            lessonKeys: [],
            contextNoteKey: nil,
            cautionKeys: []
        )
    }

    enum Copy {
        static let strengthBodyweight = "Strength and bodyweight work improve when the same positions stay repeatable. Load, leverage, range and tempo can all progress the exercise; a grinding rep is not required for every useful set."
        static let mobility = "Mobility work can change what range feels available now, often through tolerance and stiffness. Range that lasts also needs repeated exposure and strength near the edge you can control."
        static let mobilityMethods = "Static holds, dynamic repetitions, PNF and loaded end-range work are different tools. For a prescribed static stretch, roughly 30–60 seconds is a useful working range; dynamic work fits the warm-up better."
        static let mobilityBoundary = "A pinch or hard joint block is not a cue to pull harder. Bone shape, the joint and its capsule can limit a position as well as muscle tolerance."
        static let yoga = "Yoga here is practice, not a contest for the deepest pose. Use steady breathing and a position you can control."
        static let isometric = "An isometric builds strength most strongly around the angle and task you hold. End the hold when the position or normal breathing gives way."
        static let carry = "A carry links grip, trunk control and gait under load. Reduce the load if you have to lean or shorten your steps to keep moving."
        static let cardio = "Steady cardio is its own aerobic session, not a failed interval workout. Keep the prescribed effort sustainable instead of turning every session into a time trial."
        static let interval = "Recovery makes hard intervals repeatable. Start at a pace that lets the later work bouts still look like the first ones."
        static let recovery = "Easy recovery work may change short-term range or soreness, but it does not break fascia, clear lactate to prevent next-day soreness, or erase training stress. Finish fresher than you started."

        static let littleHistory = "With only a small amount of logged history, make repeatable technique the baseline today. Leave room to learn what normal effort feels like."
        static let developingHistory = "Your recent sessions are the useful comparison. Match their clean repetitions or steady pace before you add difficulty."
        static let establishedHistory = "You have enough history to compare this session with your own pattern. Use that pattern, not somebody else’s standard, to judge today’s work."
        static let afterSession = "This session is already complete. Use the briefing to understand what you trained; it is not a prompt to add bonus work."

        static let reportedPain = "You reported pain or irritation during setup. Pain is not a mobility target: reduce or stop a movement that reproduces it, and get qualified help if it persists or worsens."
        static let elevatedJoint = "Your latest joint check-in was elevated. Keep the affected area away from sharp or worsening pain and adjust the session instead of testing the symptom."
        static let hypermobility = "More range is not the goal when you already have it. Stay short of a passive end position and train control there."
        static let neuralWarning = "A broad muscle pull can be part of a stretch; tingling, burning, numbness or an electric line is not a cue to push farther. Back off and seek assessment if it persists."
        static let yogaBoundary = "Pregnancy, glaucoma, fragile bones and some other conditions can require yoga modifications, especially for heat, long supine holds, inversions or forceful breath work. Use qualified guidance when any of these applies."
    }

    static func knowledgeContext(
        dayType: String,
        exerciseNames: [String],
        date: String?,
        data: DashboardData
    ) -> KnowledgeContext {
        let completedSessions = data.workoutSessions.filter { $0.completed }
        return knowledgeContext(
            dayType: dayType,
            exerciseNames: exerciseNames,
            date: date,
            completedSessionDates: completedSessions.map(\.date),
            completedSessionCount: completedSessions.count,
            addons: data.settings?.addons
        )
    }

    static func knowledgeContext(
        dayType: String,
        exerciseNames: [String],
        date: String?,
        completedSessionDates: [String],
        completedSessionCount: Int,
        addons: [String: JSONValue]?
    ) -> KnowledgeContext {
        var families: [MovementFamily] = []
        for exerciseName in exerciseNames {
            guard let family = movementFamily(for: exerciseName),
                  !families.contains(family) else { continue }
            families.append(family)
        }
        if families.isEmpty, let fallback = fallbackFamily(for: dayType) {
            families = [fallback]
        }

        let induction = addons?["training_induction"]?.objectValue
        let painReported = induction?["pain_areas"]?.arrayValue?.contains { value in
            guard let area = value.stringValue else { return false }
            return !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true

        let latestCheckin = StrengthProgress.checkins(from: addons)
            .max { $0.date < $1.date }
        let elevatedJointCheckIn = latestCheckin.map {
            max($0.arms, $0.core, $0.legs) >= 4
        } ?? false

        let structuredHypermobility = addons?["hypermobility_baseline"]?
            .objectValue?["reported"]?.boolValue
        let hypermobilityReported = structuredHypermobility
            ?? addons?["hypermobility_reported"]?.boolValue
            ?? false

        let position: SessionPosition
        if let date, completedSessionDates.contains(date) {
            position = .after
        } else {
            position = .before
        }

        let experience: ExperienceBand
        switch max(0, completedSessionCount) {
        case 0..<6:
            experience = .littleHistory
        case 6..<24:
            experience = .developingHistory
        default:
            experience = .establishedHistory
        }

        return KnowledgeContext(
            position: position,
            movementFamilies: families,
            movementNames: exerciseNames,
            painReported: painReported,
            elevatedJointCheckIn: elevatedJointCheckIn,
            hypermobilityReported: hypermobilityReported,
            experience: experience
        )
    }

    static func knowledge(context: KnowledgeContext) -> Knowledge {
        var lessonKeys = context.movementFamilies
            .prefix(3)
            .compactMap(primaryLesson(for:))

        if context.movementFamilies.contains(.mobility) {
            if lessonKeys.count >= 3,
               let removableIndex = lessonKeys.indices.reversed().first(where: {
                   lessonKeys[$0] != Copy.mobility && $0 != lessonKeys.startIndex
               }) {
                lessonKeys.remove(at: removableIndex)
            }
            lessonKeys.append(Copy.mobilityMethods)
        }

        let contextNoteKey: String?
        if context.position == .after {
            contextNoteKey = Copy.afterSession
        } else {
            switch context.experience {
            case .littleHistory:
                contextNoteKey = Copy.littleHistory
            case .developingHistory:
                contextNoteKey = Copy.developingHistory
            case .establishedHistory:
                contextNoteKey = Copy.establishedHistory
            }
        }

        var cautionKeys: [String] = []
        if context.hypermobilityReported { cautionKeys.append(Copy.hypermobility) }
        if context.painReported { cautionKeys.append(Copy.reportedPain) }
        if context.elevatedJointCheckIn { cautionKeys.append(Copy.elevatedJoint) }
        if context.movementFamilies.contains(.mobility) {
            cautionKeys.append(Copy.mobilityBoundary)
            cautionKeys.append(Copy.neuralWarning)
        }
        if context.movementFamilies.contains(.yoga) { cautionKeys.append(Copy.yogaBoundary) }

        return Knowledge(
            lessonKeys: Array(lessonKeys.prefix(3)),
            contextNoteKey: contextNoteKey,
            cautionKeys: orderedUnique(cautionKeys)
        )
    }

    private static func movementFamily(for exerciseName: String) -> MovementFamily? {
        guard let movement = MovementTiming.movement(named: exerciseName) else { return nil }
        if movement.entityType == "yoga_pose" { return .yoga }

        let descriptor = ExerciseLogging.descriptor(for: movement)
        guard descriptor.isSupported else { return nil }
        switch descriptor.kind {
        case .strength, .bodyweight:
            return .strengthBodyweight
        case .mobility:
            return .mobility
        case .isometric:
            return .isometric
        case .carry:
            return .carry
        case .cardio:
            return .cardio
        case .interval, .circuit:
            return .interval
        }
    }

    private static func fallbackFamily(for dayType: String) -> MovementFamily? {
        let value = dayType.lowercased()
        if value.contains("rest") || value.contains("recovery") { return .recovery }
        if value.contains("yoga") { return .yoga }
        if value.contains("mobility") || value == "fix" { return .mobility }
        if value.contains("interval") || value.contains("conditioning") { return .interval }
        if value.contains("cardio") { return .cardio }
        return nil
    }

    private static func primaryLesson(for family: MovementFamily) -> String? {
        switch family {
        case .strengthBodyweight: Copy.strengthBodyweight
        case .mobility: Copy.mobility
        case .yoga: Copy.yoga
        case .isometric: Copy.isometric
        case .carry: Copy.carry
        case .cardio: Copy.cardio
        case .interval: Copy.interval
        case .recovery: Copy.recovery
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
