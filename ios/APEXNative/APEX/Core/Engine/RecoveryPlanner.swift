import Foundation

enum RecoveryPlanner {
    enum Target: String, CaseIterable, Identifiable, Sendable {
        case joint
        case flexibility
        var id: String { rawValue }
    }

    enum Source: String, CaseIterable, Identifiable, Sendable {
        case guided
        case external
        var id: String { rawValue }
    }

    struct Result: Sendable {
        let planID: UUID
        let days: [ProgramDay]
        let exercises: [Exercise]
    }

    private struct ExerciseTemplate {
        let name: String
        let movementID: String
        let sets: Int
        let minimum: Int
        let maximum: Int
        let unit: String
        let perSide: Bool
        let rest: Int
        let note: String
    }

    private static let jointRoutine = [
        ExerciseTemplate(name: "Cat-Cow", movementID: "cat_cow", sets: 2, minimum: 6, maximum: 8, unit: "reps", perSide: false, rest: 15, note: "Move slowly through a comfortable range."),
        ExerciseTemplate(name: "Wall Slide", movementID: "wall_slide", sets: 2, minimum: 8, maximum: 10, unit: "reps", perSide: false, rest: 15, note: "Keep the motion smooth and pain-free."),
        ExerciseTemplate(name: "Ankle Mobility Rock", movementID: "joint_circles", sets: 2, minimum: 8, maximum: 10, unit: "reps", perSide: true, rest: 15, note: "Keep the heel grounded; do not force range."),
        ExerciseTemplate(name: "90/90 Hip Mobility", movementID: "ninety_ninety_hip", sets: 2, minimum: 20, maximum: 30, unit: "seconds", perSide: true, rest: 15, note: "Use light tension, never sharp pain."),
    ]

    private static let flexibilityRoutine = [
        ExerciseTemplate(name: "90/90 Hip Mobility", movementID: "ninety_ninety_hip", sets: 2, minimum: 20, maximum: 30, unit: "seconds", perSide: true, rest: 15, note: "Use light tension, never sharp pain."),
        ExerciseTemplate(name: "Hip Flexor Stretch", movementID: "hip_flexor_stretch", sets: 2, minimum: 20, maximum: 30, unit: "seconds", perSide: true, rest: 15, note: "Keep the pelvis controlled and breathe normally."),
        ExerciseTemplate(name: "Thoracic Rotation", movementID: "thoracic_extension", sets: 2, minimum: 6, maximum: 8, unit: "reps", perSide: true, rest: 15, note: "Rotate only through a comfortable range."),
        ExerciseTemplate(name: "Child's Pose", movementID: "childs_pose", sets: 2, minimum: 20, maximum: 30, unit: "seconds", perSide: false, rest: 15, note: "Breathe easily and stop if symptoms worsen."),
    ]

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private static func date(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func adding(_ days: Int, to key: String) -> String? {
        guard let value = date(key), let next = calendar.date(byAdding: .day, value: days, to: value) else { return nil }
        return self.key(next)
    }

    private static func weekday(_ key: String) -> Int {
        guard let value = date(key) else { return 1 }
        let weekday = calendar.component(.weekday, from: value)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func daysApart(_ lhs: String, _ rhs: String) -> Int {
        guard let left = date(lhs), let right = date(rhs) else { return 0 }
        return abs(calendar.dateComponents([.day], from: left, to: right).day ?? 0)
    }

    static func day(_ row: ProgramDay, matches date: String) -> Bool {
        if let scheduled = row.scheduledDate { return scheduled == date }
        return row.weekday == weekday(date)
    }

    private static func trainingLoad(on date: String, existingDays: [ProgramDay]) -> Double {
        existingDays.reduce(0) { total, row in
            guard row.isActive, day(row, matches: date) else { return total }
            if row.scheduledDate != nil { return total + 12 }
            switch row.dayType {
            case "mobility", "fix": return total + 1
            case "custom", "coach": return total + 3
            case "t25": return total + 4
            default: return total + 6
            }
        }
    }

    static func scheduledDates(
        startDate: String,
        existingDays: [ProgramDay],
        weeks: Int = 4,
        sessionsPerWeek: Int = 2
    ) -> [String] {
        var result: [String] = []
        for week in 0..<weeks {
            let candidates = (0..<7).compactMap { adding((week * 7) + $0, to: startDate) }
            let ranked = candidates.sorted {
                let left = trainingLoad(on: $0, existingDays: existingDays)
                let right = trainingLoad(on: $1, existingDays: existingDays)
                return left == right ? $0 < $1 : left < right
            }
            var selected = ranked.first.map { [$0] } ?? []
            while selected.count < sessionsPerWeek {
                let remaining = ranked.filter { !selected.contains($0) }
                let separated = remaining.filter { candidate in
                    selected.allSatisfy { daysApart(candidate, $0) >= 2 }
                }
                let pool = separated.isEmpty ? remaining : separated
                guard let next = pool.min(by: { left, right in
                    let leftGap = selected.map { daysApart(left, $0) }.min() ?? 0
                    let rightGap = selected.map { daysApart(right, $0) }.min() ?? 0
                    let leftScore = trainingLoad(on: left, existingDays: existingDays) + abs(Double(3 - leftGap)) * 0.25
                    let rightScore = trainingLoad(on: right, existingDays: existingDays) + abs(Double(3 - rightGap)) * 0.25
                    return leftScore == rightScore ? left < right : leftScore < rightScore
                }) else { break }
                selected.append(next)
            }
            result.append(contentsOf: selected.sorted())
        }
        return result
    }

    private static func program(in data: DashboardData, ownerID: UUID, date: String) -> Program? {
        let owned = data.programs.filter { $0.userID == ownerID }
        if let transition = owned.first(where: { $0.slug == "transition" }),
           TrainingPlanEngine.isInsideInductionWindow(data, slug: "transition", date: date) {
            return transition
        }
        if let main = owned.first(where: { $0.slug == "main" }),
           TrainingPlanEngine.isInsideInductionWindow(data, slug: "main", date: date) {
            return main
        }
        if data.settings?.addons["training_induction"]?.objectValue == nil {
            return owned.first(where: { $0.slug == "main" }) ?? owned.first(where: { $0.slug == "transition" })
        }
        return nil
    }

    private static func exerciseRows(
        ownerID: UUID,
        dayID: UUID,
        target: Target,
        source: Source,
        makeID: () -> UUID
    ) -> [Exercise] {
        let templates: [ExerciseTemplate]
        if source == .external {
            templates = [ExerciseTemplate(
                name: "Mobility Flow", movementID: "mobility_flow", sets: 1,
                minimum: 10, maximum: 15, unit: "minutes", perSide: false, rest: 0,
                note: "Follow a mobility or recovery routine you trust. Log it only after you complete it."
            )]
        } else {
            templates = target == .joint ? jointRoutine : flexibilityRoutine
        }
        return templates.enumerated().map { index, template in
            Exercise(
                id: makeID(), userID: ownerID, programDayID: dayID,
                name: template.name, movementID: template.movementID,
                workGroupID: nil, workGroupPosition: nil,
                sets: template.sets, repMin: template.minimum, repMax: template.maximum,
                repUnit: template.unit, perSide: template.perSide, restSeconds: template.rest,
                tempoUp: 2, tempoDown: 2, tempoPause: 0,
                tempoNote: "Controlled, comfortable movement", notes: template.note,
                incrementKG: 0, isLite: false, optional: false, sortOrder: index
            )
        }
    }

    static func build(
        data: DashboardData,
        ownerID: UUID,
        startDate: String,
        target: Target,
        source: Source,
        makeID: @escaping () -> UUID = { UUID() }
    ) -> Result {
        let planID = makeID()
        let dates = scheduledDates(startDate: startDate, existingDays: data.programDays)
        var days: [ProgramDay] = []
        var exercises: [Exercise] = []
        for (index, scheduledDate) in dates.enumerated() {
            guard let program = program(in: data, ownerID: ownerID, date: scheduledDate) else { continue }
            let dayID = makeID()
            let day = ProgramDay(
                id: dayID, userID: ownerID, programID: program.id,
                weekday: weekday(scheduledDate),
                name: target == .joint ? "Joint care" : "Flexibility reset",
                dayType: "mobility",
                estimatedMinutes: source == .external ? 15 : target == .joint ? 12 : 14,
                warmupNote: "Move in a comfortable, pain-free range. Stop if symptoms worsen.",
                sortOrder: 900 + index,
                scheduledDate: scheduledDate,
                recoveryPlanID: planID,
                recoveryTarget: target.rawValue,
                recoverySource: source.rawValue
            )
            days.append(day)
            exercises.append(contentsOf: exerciseRows(
                ownerID: ownerID, dayID: dayID, target: target, source: source, makeID: makeID
            ))
        }
        return Result(planID: planID, days: days, exercises: exercises)
    }

    static func futureRowsToDeactivate(
        _ rows: [ProgramDay],
        ownerID: UUID,
        target: Target,
        today: String,
        protectedDayIDs: Set<UUID> = []
    ) -> [ProgramDay] {
        rows.compactMap { row in
            guard row.userID == ownerID,
                  row.isActive,
                  row.recoveryTarget == target.rawValue,
                  row.recoveryPlanID != nil,
                  !protectedDayIDs.contains(row.id),
                  let date = row.scheduledDate,
                  date >= today else { return nil }
            var copy = row
            copy.isActive = false
            return copy
        }
    }
}
