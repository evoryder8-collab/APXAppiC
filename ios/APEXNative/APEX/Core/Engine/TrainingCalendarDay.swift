import Foundation

/// The factual state of one date in a programme calendar.
///
/// A missing programme day is deliberately not synonymous with rest. Sparse
/// induction plans are the one exception: their scoped day IDs prescribe the
/// training days, so the remaining dates inside that induction window are
/// intentional recovery days.
struct TrainingCalendarDay: Equatable, Identifiable, Sendable {
    enum State: String, CaseIterable, Hashable, Sendable {
        case scheduled
        case rest
        case deload
        case completed
        case partiallyCompleted
        case missed
        case manuallyLogged
        case custom
        case noPrescription

        var label: String {
            switch self {
            case .scheduled: "Scheduled"
            case .rest: "Rest"
            case .deload: "Deload"
            case .completed: "Completed"
            case .partiallyCompleted: "Partially completed"
            case .missed: "Missed"
            case .manuallyLogged: "Manually logged"
            case .custom: "Custom workout"
            case .noPrescription: "No prescription"
            }
        }

        var shortLabel: String {
            switch self {
            case .scheduled: "PLAN"
            case .rest: "REST"
            case .deload: "EASY"
            case .completed: "DONE"
            case .partiallyCompleted: "PART"
            case .missed: "MISS"
            case .manuallyLogged: "LOG"
            case .custom: "OWN"
            case .noPrescription: "NONE"
            }
        }

        var symbolName: String {
            switch self {
            case .scheduled: "calendar.badge.clock"
            case .rest: "moon.zzz.fill"
            case .deload: "arrow.down.circle.fill"
            case .completed: "checkmark.circle.fill"
            case .partiallyCompleted: "circle.lefthalf.filled"
            case .missed: "xmark.circle.fill"
            case .manuallyLogged: "square.and.pencil"
            case .custom: "slider.horizontal.3"
            case .noPrescription: "minus.circle"
            }
        }
    }

    let date: String
    let state: State
    let title: String
    let dayType: String?
    let programDayID: UUID?
    let sessionID: UUID?
    let isDeload: Bool

    var id: String { date }

    var accessibilityStatus: String {
        isDeload && state != .deload ? "\(state.label), deload" : state.label
    }

    static func resolve(
        _ data: DashboardData,
        slug: String,
        date: String,
        today: String = Date().apexDateKey,
        userID explicitUserID: UUID? = nil
    ) -> TrainingCalendarDay {
        guard APEXDateMath.date(from: date) != nil else {
            return empty(date: date)
        }

        let userID = explicitUserID ?? data.profile?.userID ?? data.settings?.userID
        func belongsToUser(_ candidate: UUID) -> Bool {
            userID.map { $0 == candidate } ?? true
        }

        let programs = data.programs
            .filter { belongsToUser($0.userID) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let programByID = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
        let program = programs.first { $0.slug == slug }

        let historicalDays = data.programDays.filter { day in
            belongsToUser(day.userID) && programByID[day.programID] != nil
        }
        let dayByID = Dictionary(uniqueKeysWithValues: historicalDays.map { ($0.id, $0) })
        let activeDays = TrainingInduction.activeProgramDays(in: data, userID: userID).filter { day in
            belongsToUser(day.userID) && programByID[day.programID] != nil
        }

        let settingsBelongToUser = data.settings.map { belongsToUser($0.userID) } ?? true
        let activeIDs = settingsBelongToUser
            ? TrainingPlanEngine.activeInductionDayIDs(data, slug: slug)
                .map { Set($0.map { $0.lowercased() }) }
            : nil
        let insideWindow = settingsBelongToUser
            ? TrainingPlanEngine.isInsideInductionWindow(data, slug: slug, date: date)
            : true

        let programmeDays = activeDays.filter { $0.programID == program?.id }
        let activeProgrammeDays = programmeDays.filter { day in
            activeIDs.map { $0.contains(day.id.uuidString.lowercased()) } ?? true
        }
        let weekday = APEXDateMath.isoWeekday(date)
        let prescribedDay = insideWindow
            ? activeProgrammeDays
                .filter { $0.weekday == weekday }
                .sorted(by: authoredOrder)
                .first
            : nil

        let datedSessions = data.workoutSessions.filter { session in
            session.date == date && belongsToUser(session.userID)
        }
        let logSessionIDs = Set(
            data.workoutLogs
                .filter { belongsToUser($0.userID) }
                .map(\.sessionID)
        )
        func hasProgress(_ session: WorkoutSession) -> Bool {
            session.startedAt != nil || logSessionIDs.contains(session.id)
        }
        func sessionDay(_ session: WorkoutSession) -> ProgramDay? {
            dayByID[session.programDayID]
        }
        func isCustom(_ session: WorkoutSession) -> Bool {
            guard let day = sessionDay(session) else { return false }
            return day.dayType.lowercased() == "custom"
                || programByID[day.programID]?.slug == "custom"
        }
        func isCurrentProgramme(_ session: WorkoutSession) -> Bool {
            sessionDay(session)?.programID == program?.id || session.isEventRecovery
        }
        func recorded(_ session: WorkoutSession) -> Bool {
            session.completed || hasProgress(session)
        }
        func newest(_ candidates: [WorkoutSession]) -> WorkoutSession? {
            candidates.sorted { left, right in
                let leftDate = left.completedAt ?? left.startedAt ?? ""
                let rightDate = right.completedAt ?? right.startedAt ?? ""
                if leftDate != rightDate { return leftDate > rightDate }
                return left.id.uuidString > right.id.uuidString
            }.first
        }

        let relevantSessions = datedSessions.filter { session in
            ManualWorkout.title(fromNotes: session.notes) != nil
                || isCustom(session)
                || isCurrentProgramme(session)
        }
        let deload = (data.deloadMarks ?? []).contains { mark in
            mark.date == date && belongsToUser(mark.userID)
        } || relevantSessions.contains(where: \.isDeload)

        if let manual = newest(relevantSessions.filter {
            ManualWorkout.title(fromNotes: $0.notes) != nil && recorded($0)
        }) {
            let day = sessionDay(manual)
            return TrainingCalendarDay(
                date: date,
                state: .manuallyLogged,
                title: ManualWorkout.title(fromNotes: manual.notes) ?? "Manual workout",
                dayType: day?.dayType ?? "custom",
                programDayID: day?.id,
                sessionID: manual.id,
                isDeload: deload
            )
        }

        if let custom = newest(relevantSessions.filter { isCustom($0) && recorded($0) }) {
            let day = sessionDay(custom)
            return TrainingCalendarDay(
                date: date,
                state: .custom,
                title: day?.name ?? "Custom workout",
                dayType: day?.dayType ?? "custom",
                programDayID: day?.id,
                sessionID: custom.id,
                isDeload: deload
            )
        }

        let programmeSessions = relevantSessions.filter(isCurrentProgramme)
        if let completed = newest(programmeSessions.filter(\.completed)) {
            let day = sessionDay(completed) ?? prescribedDay
            return TrainingCalendarDay(
                date: date,
                state: .completed,
                title: completed.isEventRecovery ? "Recovery session" : (day?.name ?? "Completed workout"),
                dayType: day?.dayType,
                programDayID: day?.id,
                sessionID: completed.id,
                isDeload: deload
            )
        }

        if let partial = newest(programmeSessions.filter { !$0.completed && hasProgress($0) }) {
            let day = sessionDay(partial) ?? prescribedDay
            return TrainingCalendarDay(
                date: date,
                state: .partiallyCompleted,
                title: day?.name ?? "Partial workout",
                dayType: day?.dayType,
                programDayID: day?.id,
                sessionID: partial.id,
                isDeload: deload
            )
        }

        if deload {
            return TrainingCalendarDay(
                date: date,
                state: .deload,
                title: prescribedDay.map { "Deload · \($0.name)" } ?? "Deload",
                dayType: prescribedDay?.dayType,
                programDayID: prescribedDay?.id,
                sessionID: nil,
                isDeload: true
            )
        }

        if let prescribedDay {
            let isRest = prescribedDay.dayType.lowercased() == "rest"
            return TrainingCalendarDay(
                date: date,
                state: isRest ? .rest : (date < today ? .missed : .scheduled),
                title: prescribedDay.name,
                dayType: prescribedDay.dayType,
                programDayID: prescribedDay.id,
                sessionID: nil,
                isDeload: false
            )
        }

        let isIntentionalSparseRest = program != nil
            && insideWindow
            && activeIDs != nil
            && !activeProgrammeDays.isEmpty
        if isIntentionalSparseRest {
            return TrainingCalendarDay(
                date: date,
                state: .rest,
                title: "Rest",
                dayType: "rest",
                programDayID: nil,
                sessionID: nil,
                isDeload: false
            )
        }

        return empty(date: date)
    }

    private static func authoredOrder(_ left: ProgramDay, _ right: ProgramDay) -> Bool {
        if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
        return left.id.uuidString < right.id.uuidString
    }

    private static func empty(date: String) -> TrainingCalendarDay {
        TrainingCalendarDay(
            date: date,
            state: .noPrescription,
            title: "No workout prescribed",
            dayType: nil,
            programDayID: nil,
            sessionID: nil,
            isDeload: false
        )
    }
}
