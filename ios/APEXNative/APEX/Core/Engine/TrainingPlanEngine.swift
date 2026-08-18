import Foundation

/*
 * Plan adjustment engine: takes a calendar date and produces the session the
 * app actually prescribes, after deloads, event tapers, the championship leg
 * rule, return-from-layoff deloads and the Full/Light toggle.
 *
 * A 1:1 port of src/lib/plan.ts. Until this existed the native app showed the
 * raw programme rows, so an event week, a taper or a scheduled deload changed
 * the session on the web and changed nothing on the phone. Parity is pinned by
 * golden fixtures generated from the TypeScript itself.
 */
struct PlannedExercise: Identifiable, Hashable, Sendable {
    var exercise: Exercise
    var plannedSets: Int
    var swapped: Bool

    var id: UUID { exercise.id }
    var name: String { exercise.name }
}

struct PlannedDay: Sendable {
    var programDay: ProgramDay?
    var exercises: [PlannedExercise] = []
    var warmup: String = ""
    var warmupDuration: Int = 0
    var badges: [String] = []
    var isDeload = false
    var isEventDay = false
    var isRecoveryMicro = false
    /// 1 means untouched.
    var taperFactor: Double = 1
    var legsBlocked = false
    var layoffDeload = false
}

struct EventContext: Sendable {
    let event: EventRecord
    /// Positive before the event.
    let daysUntilStart: Int
    /// Positive after the event.
    let daysSinceEnd: Int
    let isDuring: Bool
}

enum TrainingPlanEngine {
    /* Heavy pulling and spinal loading, dropped inside the final 72 hours. */
    private static let heavyPullSpinal = [
        "pull-up", "row", "rdl", "deadlift", "squat", "leg press", "hip thrust", "lunge",
    ]

    private static func isHeavyPullSpinal(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return heavyPullSpinal.contains { lowered.contains($0) }
    }

    // MARK: - Event windows

    static func eventContext(for date: String, events: [EventRecord]) -> EventContext? {
        var best: EventContext?
        for event in events {
            let until = APEXDateMath.calendarDaysBetween(from: date, to: event.startDate)
            let since = APEXDateMath.calendarDaysBetween(from: event.endDate, to: date)
            let context = EventContext(
                event: event,
                daysUntilStart: until,
                daysSinceEnd: since,
                isDuring: until <= 0 && since <= 0
            )
            let relevant = context.isDuring || (until > 0 && until <= 7) || (since > 0 && since <= 2)
            guard relevant else { continue }
            /* Prefer during, then the closest approach, then a rebound day. */
            if best == nil
                || (context.isDuring && !(best?.isDuring ?? false))
                || (!(best?.isDuring ?? false) && abs(until) < abs(best?.daysUntilStart ?? Int.max)) {
                best = context
            }
        }
        return best
    }

    static func taperFactor(daysUntilStart: Int) -> Double {
        if daysUntilStart >= 5 || daysUntilStart < 1 { return 1 }
        if daysUntilStart >= 3 { return 0.75 }
        return 0.5
    }

    /// Gradient position 0...1 across the five approach days, for calendar tinting.
    static func approachRamp(for date: String, events: [EventRecord]) -> Double? {
        guard let context = eventContext(for: date, events: events) else { return nil }
        if context.isDuring { return 1 }
        if context.daysUntilStart >= 1 && context.daysUntilStart <= 5 {
            return Double(5 - context.daysUntilStart + 1) / 5
        }
        return nil
    }

    static func lastCompletedSessionDate(_ data: DashboardData) -> String? {
        var last: String?
        for session in data.workoutSessions where session.completed {
            if last == nil || session.date > last! { last = session.date }
        }
        return last
    }

    /// Any gap of three weeks or more earns a deload week on return.
    static func layoffActive(_ data: DashboardData, date: String) -> Bool {
        guard let last = lastCompletedSessionDate(data) else { return false }
        return APEXDateMath.calendarDaysBetween(from: last, to: date) >= 21
    }

    // MARK: - Induction window

    private static func induction(_ data: DashboardData) -> [String: JSONValue]? {
        data.settings?.addons["training_induction"]?.objectValue
    }

    static func activeInductionDayIDs(_ data: DashboardData, slug: String) -> Set<String>? {
        guard let induction = induction(data), slug == "transition" || slug == "main" else { return nil }
        let key = slug == "transition" ? "transition_day_ids" : "main_day_ids"
        let ids = induction[key]?.arrayValue?.compactMap { $0.stringValue } ?? []
        return Set(ids)
    }

    static func isInsideInductionWindow(_ data: DashboardData, slug: String, date: String) -> Bool {
        guard let induction = induction(data), slug == "transition" || slug == "main" else { return true }
        let start = induction["start_date"]?.stringValue ?? ""
        let mainStart = induction["main_start_date"]?.stringValue ?? ""
        if slug == "transition" { return date >= start && date < mainStart }
        return date >= mainStart
    }

    static func inductionWeek(_ data: DashboardData, date: String) -> Int {
        guard let start = induction(data)?["start_date"]?.stringValue else { return 1 }
        return Int(floor(Double(APEXDateMath.calendarDaysBetween(from: start, to: date)) / 7.0)) + 1
    }

    // MARK: - Substitutions

    private static func swapExercises(userID: UUID, dayID: UUID) -> [PlannedExercise] {
        func row(
            _ name: String,
            sets: Int,
            repMin: Int,
            repMax: Int,
            unit: String = "reps",
            rest: Int,
            pause: Double = 0,
            notes: String,
            order: Int
        ) -> PlannedExercise {
            PlannedExercise(
                exercise: Exercise(
                    id: APEXStableID.scopedUUID(namespace: "plan-swap", date: "\(name)-\(order)", userID: userID),
                    userID: userID,
                    programDayID: dayID,
                    name: name,
                    sets: sets,
                    repMin: repMin,
                    repMax: repMax,
                    repUnit: unit,
                    perSide: false,
                    restSeconds: rest,
                    tempoUp: 1,
                    tempoDown: 2,
                    tempoPause: pause,
                    tempoNote: "",
                    notes: notes,
                    incrementKG: 0,
                    isLite: false,
                    optional: false,
                    sortOrder: order
                ),
                plannedSets: sets,
                swapped: true
            )
        }
        return [
            row("Band Pull-Aparts", sets: 3, repMin: 20, repMax: 20, rest: 30,
                notes: "Taper swap: keeps the mid-back fresh without loading", order: 0),
            row("Band Face Pulls (2s hold)", sets: 3, repMin: 15, repMax: 20, rest: 30, pause: 2,
                notes: "Taper swap", order: 1),
            row("Thoracic Extension over chair edge", sets: 1, repMin: 60, repMax: 90, unit: "seconds", rest: 0,
                notes: "Taper swap", order: 2),
        ]
    }

    private static func recoveryMicro(userID: UUID, dayID: UUID) -> [PlannedExercise] {
        func row(
            _ name: String,
            sets: Int,
            repMin: Int,
            repMax: Int,
            unit: String,
            perSide: Bool = false,
            rest: Int,
            notes: String,
            order: Int
        ) -> PlannedExercise {
            PlannedExercise(
                exercise: Exercise(
                    id: APEXStableID.scopedUUID(namespace: "plan-micro", date: "\(name)-\(order)", userID: userID),
                    userID: userID,
                    programDayID: dayID,
                    name: name,
                    sets: sets,
                    repMin: repMin,
                    repMax: repMax,
                    repUnit: unit,
                    perSide: perSide,
                    restSeconds: rest,
                    tempoUp: 1,
                    tempoDown: 2,
                    tempoPause: 0,
                    tempoNote: "",
                    notes: notes,
                    incrementKG: 0,
                    isLite: false,
                    optional: false,
                    sortOrder: order
                ),
                plannedSets: sets,
                swapped: true
            )
        }
        return [
            row("Dead Hangs", sets: 2, repMin: 0, repMax: 0, unit: "max", rest: 45,
                notes: "Thoracic decompression after camera hours", order: 0),
            row("Couch Stretch", sets: 1, repMin: 60, repMax: 90, unit: "seconds", perSide: true, rest: 0,
                notes: "", order: 1),
            row("Band Pull-Aparts", sets: 3, repMin: 20, repMax: 20, unit: "reps", rest: 30,
                notes: "", order: 2),
        ]
    }

    // MARK: - The plan

    static func plan(_ data: DashboardData, slug: String, date: String, lite: Bool) -> PlannedDay {
        let program = data.programs.first { $0.slug == slug }
        let weekday = APEXDateMath.isoWeekday(date)
        let activeDayIDs = activeInductionDayIDs(data, slug: slug)
        let insideWindow = isInsideInductionWindow(data, slug: slug, date: date)
        let programDay: ProgramDay? = insideWindow
            ? data.programDays.first {
                $0.programID == program?.id
                    && $0.weekday == weekday
                    && (activeDayIDs == nil || activeDayIDs!.contains($0.id.uuidString.lowercased()) || activeDayIDs!.contains($0.id.uuidString))
            }
            : nil

        guard let program, let programDay else { return PlannedDay(programDay: programDay) }

        let userID = program.userID
        var badges: [String] = []
        var exercises = data.exercises
            .filter { $0.programDayID == programDay.id && $0.isLite == lite }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) }

        /* Fall back to the full list when a day has no dedicated light rows. */
        if lite && exercises.isEmpty {
            exercises = data.exercises
                .filter { $0.programDayID == programDay.id && !$0.isLite }
                .sorted { $0.sortOrder < $1.sortOrder }
                .prefix(2)
                .map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) }
            badges.append("Lite: first two exercises only")
        }
        if lite { badges.append("Lite day: every set 0-1 RIR") }

        let hasInduction = induction(data) != nil
        if hasInduction && slug == "transition" {
            let week = inductionWeek(data, date: date)
            if week <= 4 {
                exercises = exercises.map {
                    var row = $0
                    row.plannedSets = min(2, row.plannedSets)
                    return row
                }
                badges.append("Foundation week \(week) of 12: restore movement quality")
            } else if week <= 8 {
                badges.append("Foundation week \(week) of 12: build repeatable volume")
            } else {
                badges.append("Foundation week \(week) of 12: progress controlled load")
            }
        }
        if hasInduction && slug == "main" {
            badges.append("Personal main phase: progress only from clean logged sets")
        }

        let persona = data.profile?.persona.rawValue ?? "constantine"
        let protocolStart = data.settings?.addons["training_protocol"]?.objectValue?["start_date"]?.stringValue ?? date
        let protocolWeek = FocusT25.protocolWeek(start: protocolStart, date: date)
        let bespoke = slug == "main" && (persona == "constantine" || persona == "june")
        let scheduledDeload = bespoke && FocusT25.isDeloadWeek(protocolWeek)
        let scheduledTest = bespoke && weekday == 2 && FocusT25.isPushupTestWeek(protocolWeek)
        var warmup = programDay.warmupNote
        var warmupDuration = (!warmup.isEmpty && warmup.range(of: "^no loaded warm-up", options: [.regularExpression, .caseInsensitive]) == nil) ? 180 : 0

        if bespoke {
            exercises = exercises.flatMap { row -> [PlannedExercise] in
                guard FocusT25.isFocusName(row.name) else { return [row] }
                guard let prescription = FocusT25.resolve(persona: persona, weekday: weekday, week: protocolWeek) else { return [] }
                var updated = row
                updated.exercise.name = "Focus T25 · \(prescription.episode)"
                updated.exercise.notes = "Focus T25 confirmation | \(prescription.minutes) min | \(prescription.rpe) | \(prescription.note)"
                updated.exercise.optional = scheduledTest
                return [updated]
            }
            badges.append("V8.1 · week \(protocolWeek)")
            if scheduledDeload {
                badges.append("Scheduled deload week \(protocolWeek): two controlled sets and about 3 RIR")
            }
            if scheduledTest {
                badges.append("Push-up benchmark week \(protocolWeek): one fresh strict max set")
            }

            if scheduledTest {
                let t25 = exercises.filter { FocusT25.isFocusName($0.name) }
                if let firstStrength = exercises.first(where: { !FocusT25.isFocusName($0.name) })?.exercise {
                    func derived(
                        id: UUID,
                        name: String,
                        sets: Int,
                        repMin: Int,
                        repMax: Int,
                        repUnit: String,
                        rest: Int,
                        notes: String,
                        order: Int
                    ) -> PlannedExercise {
                        PlannedExercise(
                            exercise: Exercise(
                                id: id,
                                userID: firstStrength.userID,
                                programDayID: firstStrength.programDayID,
                                name: name,
                                sets: sets,
                                repMin: repMin,
                                repMax: repMax,
                                repUnit: repUnit,
                                perSide: firstStrength.perSide,
                                restSeconds: rest,
                                tempoUp: firstStrength.tempoUp,
                                tempoDown: firstStrength.tempoDown,
                                tempoPause: firstStrength.tempoPause,
                                tempoNote: firstStrength.tempoNote,
                                notes: notes,
                                incrementKG: 0,
                                isLite: firstStrength.isLite,
                                optional: firstStrength.optional,
                                sortOrder: order
                            ),
                            plannedSets: sets,
                            swapped: true
                        )
                    }

                    let test = derived(
                        id: APEXStableID.scopedUUID(
                            namespace: "v81-pushup-test", date: "\(persona)-\(protocolWeek)", userID: userID
                        ),
                        name: "Strict Push-Up Max Test",
                        sets: 1,
                        repMin: 0,
                        repMax: 0,
                        repUnit: "max",
                        rest: 180,
                        notes: "Fresh strict maximum. Stop when clean form ends, then rest three full minutes.",
                        order: 0
                    )
                    let backoffID = APEXStableID.scopedUUID(
                        namespace: "v81-pushup-backoff", date: "\(persona)-\(protocolWeek)", userID: userID
                    )
                    let backoff = persona == "constantine"
                        ? derived(
                            id: backoffID,
                            name: "Weighted Push-Up Back-Off",
                            sets: 2,
                            repMin: 12,
                            repMax: 12,
                            repUnit: firstStrength.repUnit,
                            rest: 120,
                            notes: "Two sets of 12 at about 3 RIR. Skip feet-elevated and close-grip work today.",
                            order: 1
                        )
                        : derived(
                            id: backoffID,
                            name: "Strict Push-Up Back-Off at 60–70%",
                            sets: 2,
                            repMin: 0,
                            repMax: 0,
                            repUnit: "max",
                            rest: 90,
                            notes: "End each set at 60–70% of today’s strict maximum. Skip close-grip work today.",
                            order: 1
                        )

                    exercises = [test, backoff] + t25.enumerated().map { index, row in
                        var moved = row
                        moved.exercise.sortOrder = index + 2
                        return moved
                    }
                }
            } else if protocolWeek == 1 && lite {
                /* Light already carries its own reduced rows. A second hidden
                   subtraction made Full and Light indistinguishable. */
                badges.append("Opening-week ramp selected: reduced Light prescription")
            } else if protocolWeek == 1 {
                badges.append("Full selected: complete prescribed sets. Choose Light for the opening-week ramp")
            }

            if weekday == 1 || weekday == 5 {
                badges.append("Partner-sync order: shared strength first, profile-specific finishers last")
            }
            if weekday == 5 && persona == "constantine" {
                badges.append(lite
                    ? "Light pairs reduced leg work with controlled Speed 1.0"
                    : "Full ends after strength. Speed 1.0 is not an immediate finisher")
            }
        }

        let context = eventContext(for: date, events: data.events)
        var taper: Double = 1
        var isEventDay = false
        var isRecoveryMicro = false
        var legsBlocked = false
        let isLegDay = programDay.dayType == "legs_a" || programDay.dayType == "legs_b"

        if let context {
            if context.isDuring {
                isEventDay = true
                isRecoveryMicro = true
                exercises = recoveryMicro(userID: userID, dayID: programDay.id)
                warmup = "Event day. 5-10 minutes keeps the streak and your back alive."
                warmupDuration = 60
                badges.append("\(context.event.name): recovery micro-session")
            } else if context.daysUntilStart >= 1 && context.daysUntilStart <= 7 {
                if context.event.type == "filming_championship" && isLegDay && context.daysUntilStart <= 7 {
                    legsBlocked = true
                    exercises = swapExercises(userID: userID, dayID: programDay.id)
                    badges.append("Championship rule: no leg training in the final 7 days")
                }
                taper = taperFactor(daysUntilStart: context.daysUntilStart)
                if taper < 1 {
                    let percent = Int(((1 - taper) * 100).rounded())
                    let dayWord = context.daysUntilStart == 1 ? "day" : "days"
                    badges.append("Taper: \(percent)% fewer sets, \(context.daysUntilStart) \(dayWord) to \(context.event.name)")
                }
                if context.daysUntilStart <= 3 && !legsBlocked {
                    let before = exercises.count
                    let kept = exercises.filter { !isHeavyPullSpinal($0.name) }
                    if kept.count < before {
                        exercises = (kept + swapExercises(userID: userID, dayID: programDay.id))
                            .enumerated()
                            .map { index, row in
                                var moved = row
                                moved.exercise.sortOrder = index
                                return moved
                            }
                        badges.append("Final 72 h: heavy pulling and spinal loading swapped for thoracic work")
                    }
                }
            } else if context.daysSinceEnd >= 1 && context.daysSinceEnd <= 2 {
                taper = 0.75
                badges.append("Rebound day \(context.daysSinceEnd) of 2 after \(context.event.name): reduced load")
            }
        }

        let markedDeload = (data.deloadMarks ?? []).contains { $0.date == date } || scheduledDeload
        let layoffDeload = !isEventDay && layoffActive(data, date: date)
        if layoffDeload {
            badges.append("Return from layoff: deload week. Minus 1 set, 3-4 RIR, lighter loads")
            if programDay.dayType == "t25" {
                badges.append("T25 holds until week 2. Swap in mobility instead")
            }
        }
        if markedDeload && !scheduledDeload {
            badges.append("Deload day: two controlled sets per exercise, 3-4 RIR, lighter")
        }

        exercises = exercises.map { row in
            var updated = row
            var sets = updated.plannedSets
            if taper < 1 { sets = max(1, Int((Double(sets) * taper).rounded())) }
            if (markedDeload || layoffDeload) && !isRecoveryMicro && updated.exercise.repUnit != "check" {
                sets = scheduledDeload ? min(2, sets) : max(1, sets - 1)
            }
            updated.plannedSets = sets
            return updated
        }

        /* Optional add-on protocols, Main Phase only, off by default. */
        if slug == "main", let addons = data.settings?.addons, !isEventDay {
            func addon(_ key: String, _ name: String, rest: Int, order: Int) -> PlannedExercise {
                PlannedExercise(
                    exercise: Exercise(
                        id: APEXStableID.scopedUUID(namespace: "plan-addon", date: key, userID: userID),
                        userID: userID,
                        programDayID: programDay.id,
                        name: name,
                        sets: 1,
                        repMin: 0,
                        repMax: 0,
                        repUnit: "max",
                        perSide: false,
                        restSeconds: rest,
                        tempoUp: 1,
                        tempoDown: 2,
                        tempoPause: 0,
                        tempoNote: "",
                        notes: "",
                        incrementKG: 0,
                        isLite: false,
                        optional: false,
                        sortOrder: order
                    ),
                    plannedSets: 1,
                    swapped: false
                )
            }
            if addons["endurance1"]?.boolValue == true, weekday == 4 {
                let baseline = data.profile?.baselineDate ?? date
                let weeks = Int(floor(Double(APEXDateMath.calendarDaysBetween(from: baseline, to: date)) / 7.0))
                if weeks % 2 == 0 {
                    exercises.append(addon("addon-e1a", "Endurance test: max BW pushups", rest: 120, order: 90))
                    exercises.append(addon("addon-e1b", "Endurance test: max BW pull-ups", rest: 0, order: 91))
                    badges.append("Endurance Phase 1: biweekly max test")
                }
            }
            if addons["endurance2"]?.boolValue == true, weekday == 2 {
                exercises.append(addon("addon-e2", "BW pushups to failure (strip backpack)", rest: 0, order: 92))
                badges.append("Endurance Phase 2 (needs 40+ BW pushups)")
            }
            if addons["endurance3"]?.boolValue == true, weekday == 7 {
                exercises.append(addon("addon-e3", "Pull-up ladder 1-2-3-4-5-4-3-2-1, 10s between rungs", rest: 0, order: 93))
                badges.append("Endurance Phase 3 (needs 15+ BW pull-ups)")
            }
        }

        return PlannedDay(
            programDay: programDay,
            exercises: exercises,
            warmup: warmup,
            warmupDuration: warmupDuration,
            badges: badges,
            isDeload: markedDeload || layoffDeload,
            isEventDay: isEventDay,
            isRecoveryMicro: isRecoveryMicro,
            taperFactor: taper,
            legsBlocked: legsBlocked,
            layoffDeload: layoffDeload
        )
    }
}
