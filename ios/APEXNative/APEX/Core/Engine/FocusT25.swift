import Foundation

/*
 * The V8 protocol's conditioning schedule.
 *
 * A 1:1 port of src/lib/focusT25.ts. The week number drives which episode is
 * prescribed, whether the week is a scheduled deload, and whether Tuesday
 * carries the fresh strict push-up maximum, so both platforms have to agree on
 * it exactly or the same Tuesday would prescribe two different sessions.
 */
enum FocusT25 {
    static let prefix = "Focus T25"

    struct Prescription: Equatable, Sendable {
        let episode: String
        let minutes: Int
        let rpe: String
        let kind: String
        let note: String
    }

    static func protocolWeek(start: String, date: String) -> Int {
        let days = APEXDateMath.calendarDaysBetween(from: start, to: date)
        return max(1, Int(floor(Double(days) / 7.0)) + 1)
    }

    static func isDeloadWeek(_ week: Int) -> Bool {
        week == 4 || week == 8 || week == 12
    }

    /// Periodic, not weekly: the benchmark opens each four-week block.
    static func isPushupTestWeek(_ week: Int) -> Bool {
        week == 1 || week == 5 || week == 9 || week == 13
    }

    static func isFocusName(_ name: String) -> Bool {
        name.lowercased().hasPrefix(prefix.lowercased())
    }

    static func isConditioningName(_ name: String) -> Bool {
        isFocusName(name) && name.range(of: "stretch", options: .caseInsensitive) == nil
    }

    static func resolve(persona: String, weekday: Int, week: Int) -> Prescription? {
        guard persona == "constantine" || persona == "june" else { return nil }
        let deload = isDeloadWeek(week)
        if deload, weekday != 2, weekday != 4 { return nil }

        let month = week <= 4 ? 1 : (week <= 8 ? 2 : 3)

        if weekday == 4 {
            return Prescription(
                episode: "Stretch",
                minutes: 25,
                rpe: "easy",
                kind: "mobility",
                note: "Keep this restorative. No loaded work and no effort target."
            )
        }

        if weekday == 2 {
            let episode = month == 1 ? "Ab Intervals" : (month == 2 ? "Dynamic Core" : "Core Speed")
            return Prescription(
                episode: episode,
                minutes: 25,
                rpe: persona == "constantine" ? "RPE 6–7" : "controlled",
                kind: "core",
                note: isPushupTestWeek(week)
                    ? "Optional after the push-up test. Keep it easy enough to preserve recovery."
                    : "Strength first, then Focus T25. Separate them by several hours when practical."
            )
        }

        if weekday == 3 {
            let episode = month == 1 ? "Lower Focus" : (month == 2 ? "Speed 2.0" : "Speed 3.0")
            return Prescription(
                episode: episode,
                minutes: 25,
                rpe: month == 2 && persona == "constantine" ? "RPE 7–8" : "RPE 7 cap",
                kind: "conditioning",
                note: month == 3 && week == 9
                    ? "Use the modifier this week. Strength first and separate sessions by at least four hours when possible."
                    : "Strength first and separate sessions by at least four hours when possible. If consecutive, use the modifier and cap effort."
            )
        }

        if persona == "constantine", weekday == 5 {
            let episode = month == 1 ? "Speed 1.0" : (month == 2 ? "Core Cardio" : "The Pyramid")
            return Prescription(
                episode: episode,
                minutes: 25,
                rpe: "RPE 7",
                kind: "conditioning",
                note: "This belongs to the Light option only. Use low-impact modifications and stop at RPE 6–7. Full Legs B ends after strength."
            )
        }

        return nil
    }
}

/// Date arithmetic on the app's own yyyy-MM-dd keys, matching the web's habit
/// of parsing at midday so a timezone can never shift a day boundary.
enum APEXDateMath {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    static func key(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func calendarDaysBetween(from: String, to: String) -> Int {
        guard let start = date(from: from), let end = date(from: to) else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// Monday is 1, Sunday is 7, as the programme's weekday column expects.
    static func isoWeekday(_ key: String) -> Int {
        guard let date = date(from: key) else { return 1 }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func adding(days: Int, to key: String) -> String {
        guard let date = date(from: key),
              let moved = calendar.date(byAdding: .day, value: days, to: date)
        else { return key }
        return self.key(from: moved)
    }
}
