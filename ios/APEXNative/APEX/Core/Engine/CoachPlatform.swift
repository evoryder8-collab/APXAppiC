import Foundation

enum CoachConsentScope: String, Codable, CaseIterable, Hashable, Sendable {
    case nutrition
    case workouts
    case activity
    case hydration
    case supplements
    case avatar
    case measurements
    case notes
    case recovery
    case visualProgress = "visual_progress"
}

enum CoachRelationshipStatus: String, Codable, Hashable, Sendable {
    case invited
    case active
    case grace
    case ended
}

enum CoachSeatState: String, Codable, Hashable, Sendable {
    case pending
    case active
    case grace
    case released
}

struct CoachClientPolicy: Equatable, Sendable {
    let canUseSponsoredApp: Bool
    let canFollowCoachPlan: Bool
    let coachPlanReadOnly: Bool
    let canCreateCustomWorkouts: Bool
    let canRebuildFitnessPlan: Bool
    let canUseOrbit: Bool
    let canUseNutrition: Bool
    let canUseAvatar: Bool
    let canViewVisualProgress: Bool

    static func resolve(
        relationshipStatus: CoachRelationshipStatus?,
        seatState: CoachSeatState?,
        consentedScopes: Set<CoachConsentScope>,
        individualAccess: Bool
    ) -> CoachClientPolicy {
        let active = relationshipStatus == .active && seatState == .active
        let grace = relationshipStatus == .grace || seatState == .grace
        let relationshipExists = active || grace
        return CoachClientPolicy(
            canUseSponsoredApp: active,
            canFollowCoachPlan: active,
            coachPlanReadOnly: grace,
            canCreateCustomWorkouts: individualAccess || !relationshipExists,
            canRebuildFitnessPlan: individualAccess || !relationshipExists,
            canUseOrbit: individualAccess || !relationshipExists,
            canUseNutrition: individualAccess || !relationshipExists || active,
            canUseAvatar: individualAccess || !relationshipExists || active,
            canViewVisualProgress: individualAccess || !relationshipExists
        )
    }
}

struct CoachPlanChecklist: Codable, Hashable, Sendable {
    var nutrition: Bool
    var workouts: Bool
    var supplements: Bool
    var hydration: Bool
    var schedule: Bool
    var reviewDate: Bool

    enum CodingKeys: String, CodingKey {
        case nutrition, workouts, supplements, hydration, schedule
        case reviewDate = "review_date"
    }

    static let empty = CoachPlanChecklist(
        nutrition: false,
        workouts: false,
        supplements: false,
        hydration: false,
        schedule: false,
        reviewDate: false
    )

    var isComplete: Bool {
        nutrition && workouts && supplements && hydration && schedule && reviewDate
    }
}

struct CoachExerciseTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var movementID: String
    var name: String
    var sets: Int
    var targetMin: Int
    var targetMax: Int
    var unit: String
    var perSide: Bool
    var restSeconds: Int
    var tempoUpSeconds: Double
    var tempoDownSeconds: Double
    var tempoPauseSeconds: Double
    var notes: String
    var optional: Bool
    var groupID: UUID?
    var groupPosition: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, sets, unit, notes, optional
        case movementID = "movement_id"
        case targetMin = "target_min"
        case targetMax = "target_max"
        case perSide = "per_side"
        case restSeconds = "rest_seconds"
        case tempoUpSeconds = "tempo_up_seconds"
        case tempoDownSeconds = "tempo_down_seconds"
        case tempoPauseSeconds = "tempo_pause_seconds"
        case groupID = "group_id"
        case groupPosition = "group_position"
    }
}

struct CoachSessionTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var weekday: Int
    var name: String
    var sessionMode: WorkoutSessionMode
    var estimatedMinutes: Int
    var warmupNote: String
    var exercises: [CoachExerciseTemplate]

    enum CodingKeys: String, CodingKey {
        case id, weekday, name, exercises
        case sessionMode = "session_mode"
        case estimatedMinutes = "estimated_minutes"
        case warmupNote = "warmup_note"
    }
}

struct CoachPlanDraft: Codable, Hashable, Sendable {
    var title: String
    var objective: String
    var coachNote: String
    var reviewDate: String?
    var checklist: CoachPlanChecklist
    var sessions: [CoachSessionTemplate]

    enum CodingKeys: String, CodingKey {
        case title, objective, checklist, sessions
        case coachNote = "coach_note"
        case reviewDate = "review_date"
    }

    static let empty = CoachPlanDraft(
        title: "",
        objective: "",
        coachNote: "",
        reviewDate: nil,
        checklist: .empty,
        sessions: []
    )
}

struct CoachPlanValidationIssue: Equatable, Sendable {
    enum Code: String, Sendable {
        case tooLong
        case titleRequired
        case objectiveRequired
        case reviewDate
        case checklist
        case sessionsRequired
        case sessionCount
        case duplicateID
        case weekday
        case sessionName
        case estimatedMinutes
        case exerciseCount
        case movement
        case exerciseName
        case sets
        case target
        case targetOrder
        case unit
        case rest
        case tempo
        case group
    }

    let code: Code
    let path: String
}

enum CoachPlanValidator {
    struct Result: Equatable, Sendable {
        let publishable: Bool
        let issues: [CoachPlanValidationIssue]
    }

    private static let units: Set<String> = ["reps", "seconds", "minutes", "metres", "steps", "rounds"]

    static func validate(
        _ plan: CoachPlanDraft,
        publishing: Bool,
        knownMovementIDs: Set<String>? = nil
    ) -> Result {
        var issues: [CoachPlanValidationIssue] = []
        let title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = plan.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 80 { issues.append(.init(code: .tooLong, path: "plan.title")) }
        if objective.count > 240 { issues.append(.init(code: .tooLong, path: "plan.objective")) }
        if plan.coachNote.count > 4_000 { issues.append(.init(code: .tooLong, path: "plan.coach_note")) }
        if publishing && title.count < 2 { issues.append(.init(code: .titleRequired, path: "plan.title")) }
        if publishing && objective.count < 2 { issues.append(.init(code: .objectiveRequired, path: "plan.objective")) }
        if let reviewDate = plan.reviewDate, validDate(reviewDate) == false {
            issues.append(.init(code: .reviewDate, path: "plan.review_date"))
        } else if publishing && plan.reviewDate == nil {
            issues.append(.init(code: .reviewDate, path: "plan.review_date"))
        }
        if publishing && !plan.checklist.isComplete {
            issues.append(.init(code: .checklist, path: "plan.checklist"))
        }
        if publishing && plan.sessions.isEmpty {
            issues.append(.init(code: .sessionsRequired, path: "plan.sessions"))
        }
        if plan.sessions.count > 7 { issues.append(.init(code: .sessionCount, path: "plan.sessions")) }

        var identifiers = Set<UUID>()
        for (sessionIndex, session) in plan.sessions.enumerated() {
            let path = String(format: "plan.sessions[%d]", sessionIndex)
            if !identifiers.insert(session.id).inserted {
                issues.append(.init(code: .duplicateID, path: "\(path).id"))
            }
            if !(1...7).contains(session.weekday) { issues.append(.init(code: .weekday, path: "\(path).weekday")) }
            let sessionName = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !(2...80).contains(sessionName.count) { issues.append(.init(code: .sessionName, path: "\(path).name")) }
            if !(5...360).contains(session.estimatedMinutes) {
                issues.append(.init(code: .estimatedMinutes, path: "\(path).estimated_minutes"))
            }
            if session.warmupNote.count > 1_000 { issues.append(.init(code: .tooLong, path: "\(path).warmup_note")) }
            if (publishing && session.exercises.isEmpty) || session.exercises.count > 30 {
                issues.append(.init(code: .exerciseCount, path: "\(path).exercises"))
            }
            for (exerciseIndex, exercise) in session.exercises.enumerated() {
                let exercisePath = String(format: "%@.exercises[%d]", path, exerciseIndex)
                if !identifiers.insert(exercise.id).inserted {
                    issues.append(.init(code: .duplicateID, path: "\(exercisePath).id"))
                }
                if exercise.movementID.count < 2 || (knownMovementIDs?.contains(exercise.movementID) == false) {
                    issues.append(.init(code: .movement, path: "\(exercisePath).movement_id"))
                }
                let exerciseName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !(2...120).contains(exerciseName.count) {
                    issues.append(.init(code: .exerciseName, path: "\(exercisePath).name"))
                }
                if !(1...12).contains(exercise.sets) { issues.append(.init(code: .sets, path: "\(exercisePath).sets")) }
                if !(1...600).contains(exercise.targetMin) || !(1...600).contains(exercise.targetMax) {
                    issues.append(.init(code: .target, path: "\(exercisePath).target"))
                } else if exercise.targetMin > exercise.targetMax {
                    issues.append(.init(code: .targetOrder, path: "\(exercisePath).target"))
                }
                if !units.contains(exercise.unit) { issues.append(.init(code: .unit, path: "\(exercisePath).unit")) }
                if !(0...600).contains(exercise.restSeconds) { issues.append(.init(code: .rest, path: "\(exercisePath).rest_seconds")) }
                let tempo = [exercise.tempoUpSeconds, exercise.tempoDownSeconds, exercise.tempoPauseSeconds]
                if tempo.contains(where: { !$0.isFinite || $0 < 0 || $0 > 30 }) {
                    issues.append(.init(code: .tempo, path: "\(exercisePath).tempo"))
                }
                if (exercise.groupID == nil) != (exercise.groupPosition == nil)
                    || exercise.groupPosition.map({ !(1...30).contains($0) }) == true {
                    issues.append(.init(code: .group, path: "\(exercisePath).group"))
                }
                if exercise.notes.count > 1_000 { issues.append(.init(code: .tooLong, path: "\(exercisePath).notes")) }
            }
        }
        return Result(publishable: publishing && issues.isEmpty, issues: issues)
    }

    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }
}

enum CoachProfileStatus: String, Codable, Hashable, Sendable {
    case development
    case active
    case suspended
}

struct CoachProfileSummary: Codable, Hashable, Sendable {
    let status: CoachProfileStatus
    let displayName: String
    let seatLimit: Int
    let activeSeats: Int

    enum CodingKeys: String, CodingKey {
        case status
        case displayName = "display_name"
        case seatLimit = "seat_limit"
        case activeSeats = "active_seats"
    }
}

struct CoachSponsorshipSummary: Codable, Hashable, Sendable {
    let relationshipID: UUID
    let coachDisplayName: String
    let relationshipStatus: CoachRelationshipStatus
    let seatState: CoachSeatState
    let offeredScopes: Set<CoachConsentScope>
    let consentedScopes: Set<CoachConsentScope>
    let graceEndsAt: String?

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case coachDisplayName = "coach_display_name"
        case relationshipStatus = "relationship_status"
        case seatState = "seat_state"
        case offeredScopes = "offered_scopes"
        case consentedScopes = "consented_scopes"
        case graceEndsAt = "grace_ends_at"
    }
}

enum CoachPlanStatus: String, Codable, Hashable, Sendable {
    case draft
    case published
    case superseded
}

struct CoachCurrentPlan: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let relationshipID: UUID
    let version: Int
    let status: CoachPlanStatus
    let title: String
    let objective: String
    let coachNote: String
    let reviewDate: String?
    let checklist: CoachPlanChecklist
    let plan: CoachPlanDraft
    let publishedAt: String?
    let acknowledgedAt: String?
    let activatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, version, status, title, objective, checklist, plan
        case relationshipID = "relationship_id"
        case coachNote = "coach_note"
        case reviewDate = "review_date"
        case publishedAt = "published_at"
        case acknowledgedAt = "acknowledged_at"
        case activatedAt = "activated_at"
    }
}

struct CoachAccountCapabilities: Codable, Hashable, Sendable {
    let coachWorkspace: Bool
    let sponsoredClient: Bool

    enum CodingKeys: String, CodingKey {
        case coachWorkspace = "coach_workspace"
        case sponsoredClient = "sponsored_client"
    }

    static let none = CoachAccountCapabilities(coachWorkspace: false, sponsoredClient: false)
}

struct CoachAccountContext: Codable, Hashable, Sendable {
    let coach: CoachProfileSummary?
    let sponsorship: CoachSponsorshipSummary?
    let currentPlan: CoachCurrentPlan?
    let capabilities: CoachAccountCapabilities

    enum CodingKeys: String, CodingKey {
        case coach, sponsorship, capabilities
        case currentPlan = "current_plan"
    }

    static let empty = CoachAccountContext(
        coach: nil,
        sponsorship: nil,
        currentPlan: nil,
        capabilities: .none
    )
}

enum CoachRosterAttention: String, Codable, Hashable, Sendable {
    case planMissing = "plan_missing"
    case reviewDue = "review_due"
    case awaitingAcknowledgement = "awaiting_acknowledgement"
    case seatGrace = "seat_grace"

    static func resolve(
        relationshipStatus: CoachRelationshipStatus,
        planVersion: Int?,
        planPublishedAt: String?,
        acknowledgedAt: String?,
        reviewDate: String?,
        today: String
    ) -> [CoachRosterAttention] {
        if relationshipStatus == .grace { return [.seatGrace] }
        guard relationshipStatus == .active else { return [] }
        guard planVersion != nil else { return [.planMissing] }
        var answer: [CoachRosterAttention] = []
        if let reviewDate,
           let review = ISO8601DateOnly.date(reviewDate),
           let anchor = ISO8601DateOnly.date(today),
           review.timeIntervalSince(anchor) <= 7 * 86_400 {
            answer.append(.reviewDue)
        }
        if planPublishedAt != nil && acknowledgedAt == nil { answer.append(.awaitingAcknowledgement) }
        return answer
    }
}

private enum ISO8601DateOnly {
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}

struct CoachRosterEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let clientUserID: UUID
    let displayName: String
    let relationshipStatus: CoachRelationshipStatus
    let seatState: CoachSeatState
    let consentedScopes: Set<CoachConsentScope>
    let planVersion: Int?
    let planTitle: String?
    let reviewDate: String?
    let publishedAt: String?
    let acknowledgedAt: String?
    let activatedAt: String?
    let attention: [CoachRosterAttention]

    enum CodingKeys: String, CodingKey {
        case id, attention
        case clientUserID = "client_user_id"
        case displayName = "display_name"
        case relationshipStatus = "relationship_status"
        case seatState = "seat_state"
        case consentedScopes = "consented_scopes"
        case planVersion = "plan_version"
        case planTitle = "plan_title"
        case reviewDate = "review_date"
        case publishedAt = "published_at"
        case acknowledgedAt = "acknowledged_at"
        case activatedAt = "activated_at"
    }
}

struct CoachInvitationReceipt: Codable, Hashable, Sendable {
    let invitationID: UUID
    let token: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case invitationID = "invitation_id"
        case expiresAt = "expires_at"
    }
}

struct CoachInvitationPreview: Codable, Hashable, Sendable {
    let coachDisplayName: String
    let requestedScopes: Set<CoachConsentScope>
    let visualProgressRequested: Bool
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case coachDisplayName = "coach_display_name"
        case requestedScopes = "requested_scopes"
        case visualProgressRequested = "visual_progress_requested"
        case expiresAt = "expires_at"
    }
}

struct CoachPlanVersionReceipt: Codable, Hashable, Sendable {
    let id: UUID
    let relationshipID: UUID
    let version: Int
    let status: CoachPlanStatus

    enum CodingKeys: String, CodingKey {
        case id, version, status
        case relationshipID = "relationship_id"
    }
}

struct CoachClientMeasurements: Codable, Hashable, Sendable {
    let sex: String
    let heightCM: Double
    let weightKG: Double
    let bodyFatPercent: Double?
    let birthdate: String

    enum CodingKeys: String, CodingKey {
        case sex, birthdate
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_pct"
    }
}

struct CoachClientWorkoutSummary: Codable, Hashable, Sendable {
    let completed30Days: Int
    let lastCompletedAt: String?

    enum CodingKeys: String, CodingKey {
        case completed30Days = "completed_30d"
        case lastCompletedAt = "last_completed_at"
    }
}

struct CoachClientNutritionSummary: Codable, Hashable, Sendable {
    let daysObserved: Int
    let averageKcal: Double?

    enum CodingKeys: String, CodingKey {
        case daysObserved = "days_observed"
        case averageKcal = "average_kcal"
    }
}

struct CoachClientHydrationSummary: Codable, Hashable, Sendable {
    let daysObserved: Int
    let averageLitres: Double?

    enum CodingKeys: String, CodingKey {
        case daysObserved = "days_observed"
        case averageLitres = "average_litres"
    }
}

struct CoachClientOverview: Codable, Hashable, Sendable {
    let relationshipID: UUID
    let clientUserID: UUID
    let displayName: String
    let relationshipStatus: CoachRelationshipStatus
    let seatState: CoachSeatState
    let consentedScopes: Set<CoachConsentScope>
    let measurements: CoachClientMeasurements?
    let avatar: [String: JSONValue]?
    let workouts: CoachClientWorkoutSummary?
    let nutrition: CoachClientNutritionSummary?
    let hydration: CoachClientHydrationSummary?
    let visualProgressShared: Bool
    let currentPlan: CoachCurrentPlan?

    enum CodingKeys: String, CodingKey {
        case measurements, avatar, workouts, nutrition, hydration
        case relationshipID = "relationship_id"
        case clientUserID = "client_user_id"
        case displayName = "display_name"
        case relationshipStatus = "relationship_status"
        case seatState = "seat_state"
        case consentedScopes = "consented_scopes"
        case visualProgressShared = "visual_progress_shared"
        case currentPlan = "current_plan"
    }
}

struct CoachPlanActivationReceipt: Codable, Hashable, Sendable {
    let planVersionID: UUID
    let programID: UUID
    let installedDayIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case planVersionID = "plan_version_id"
        case programID = "program_id"
        case installedDayIDs = "installed_day_ids"
    }
}
