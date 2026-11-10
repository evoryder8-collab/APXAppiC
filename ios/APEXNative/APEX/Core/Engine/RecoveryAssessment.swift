import Foundation

/*
 * What the watch saw last night, turned into what to do today.
 *
 * A port of assessRecovery from src/lib/personalProtocol.ts. Sleep and
 * readiness were already being imported and stored; nothing read them, so the
 * number sat in settings doing no work. This is the part that reads it.
 *
 * The two sources are not interchangeable. Apple's Sleep Score measures the
 * night; a wearable's own recovery score measures readiness and treats sleep as supporting
 * context. Their bands are different and are kept different here.
 */
enum RecoveryAssessment {
    enum State: String, Sendable, Comparable {
        case veryLow = "very_low"
        case low
        case normal
        case strong

        private var rank: Int {
            switch self {
            case .veryLow: 0
            case .low: 1
            case .normal: 2
            case .strong: 3
            }
        }

        static func < (lhs: State, rhs: State) -> Bool { lhs.rank < rhs.rank }
    }

    struct Checkin: Equatable, Sendable {
        let date: String
        /// "apple" or "other".
        let source: String
        let sleepScore: Int?
        let sleepPercent: Int?
        let recoveryPercent: Int?
        let updatedAt: String
    }

    /*
     * Reasons to take a borderline morning more seriously. None of these is a
     * verdict on its own; together they are the difference between a light day
     * and a rest day.
     */
    struct Context: Sendable {
        var consecutiveLowMornings: Int = 0
        var decliningPerformance = false
        var increasedJointDiscomfort = false
        var highSoreness = false
        var demandingMassageDay = false
        var recentGimbalEvent = false
        var repeatedShortSleep = false

        var escalators: Int {
            [
                consecutiveLowMornings >= 2,
                decliningPerformance,
                increasedJointDiscomfort,
                highSoreness,
                demandingMassageDay,
                recentGimbalEvent,
                repeatedShortSleep,
            ].filter { $0 }.count
        }

        /// The signals read from stored history, in the words shown beside a stricter verdict.
        var reasons: [String] {
            [
                consecutiveLowMornings >= 2 ? "low scores on consecutive mornings" : nil,
                repeatedShortSleep ? "short sleep on recent nights" : nil,
                increasedJointDiscomfort ? "an elevated joint check-in" : nil,
            ].compactMap { $0 }
        }
    }

    struct Verdict: Equatable, Sendable {
        let state: State
        let source: String
        let title: String
        let guidance: String
        /// Why the verdict is stricter than the score's own band; empty when it is not.
        var reasons: [String] = []
    }

    /// The morning verdict for a stored check-in, weighed against the days around it.
    static func verdict(for entry: Checkin, addons: [String: JSONValue]?) -> Verdict {
        assess(entry, context: context(for: entry, addons: addons))
    }

    /// What stored history says about the days up to a morning: low scores in a row, short measured
    /// nights and the joint check-in still in force. Two of them make a low morning recovery first.
    static func context(for entry: Checkin, addons: [String: JSONValue]?) -> Context {
        var context = Context()
        let mornings = Dictionary(
            history(from: addons).filter { $0.source == entry.source }.map { ($0.date, $0) },
            uniquingKeysWith: { _, later in later }
        )
        var day = entry.date
        while context.consecutiveLowMornings < 14, let morning = mornings[day],
              let score = entry.source == "apple" ? morning.sleepScore : morning.recoveryPercent,
              score <= (entry.source == "apple" ? 60 : 33) {
            context.consecutiveLowMornings += 1
            let before = APEXDateMath.adding(days: -1, to: day)
            guard before != day else { break }
            day = before
        }

        // Short sleep is under six hours; repeated is two of the three nights up to this morning.
        let nights = sleepHistory(from: addons)
        let recent = (0..<3).compactMap { nights[APEXDateMath.adding(days: -$0, to: entry.date)] }
        context.repeatedShortSleep = recent.filter { $0 < 6 }.count >= 2

        context.increasedJointDiscomfort = StrengthProgress.currentCheckin(
            StrengthProgress.checkins(from: addons), on: entry.date
        )?.isElevated ?? false
        return context
    }

    /// Measured hours asleep per night, keyed by the morning's date. The one night an older build
    /// kept in the recovery context counts as well.
    static func sleepHistory(from addons: [String: JSONValue]?) -> [String: Double] {
        var nights: [String: Double] = [:]
        func add(_ date: JSONValue?, _ hours: JSONValue?) {
            guard let date = date?.stringValue, let hours = hours?.numberValue, hours.isFinite, hours >= 0 else { return }
            nights[date] = max(hours, nights[date] ?? 0)
        }
        let latest = addons?["apple_recovery_context"]?.objectValue
        add(latest?["date"], latest?["sleep_duration_hours"])
        for row in addons?["apple_sleep_history"]?.arrayValue ?? [] {
            add(row.objectValue?["date"], row.objectValue?["hours"])
        }
        return nights
    }

    static func assess(_ entry: Checkin, context: Context = Context()) -> Verdict {
        let main = entry.source == "apple" ? entry.sleepScore : entry.recoveryPercent
        let score = max(0, min(100, main ?? 0))

        var state: State
        if entry.source == "apple" {
            /* Apple watchOS 26 classifications: 0-40 Very Low, 41-60 Low,
               61-80 OK, 81-95 High and 96+ Very High. Sleep Score is not HRV. */
            state = score <= 40 ? .veryLow : (score <= 60 ? .low : (score <= 80 ? .normal : .strong))
        } else {
            /* A wearable's recovery score is the readiness input and follows its own red,
               yellow and green presentation. */
            state = score <= 20 ? .veryLow : (score <= 33 ? .low : (score <= 66 ? .normal : .strong))
            if (entry.sleepPercent ?? 100) <= 40, state == .strong { state = .normal }
        }

        let band = state
        let escalation = context.escalators
        if state == .low, escalation >= 2 { state = .veryLow }
        if state == .normal, escalation >= 3 { state = .low }
        let reasons = state == band ? [] : context.reasons

        switch state {
        case .strong:
            return Verdict(
                state: state, source: entry.source,
                title: "Ready for the planned session",
                guidance: "Follow the planned session normally."
            )
        case .normal:
            return Verdict(
                state: state, source: entry.source,
                title: "Normal training readiness",
                guidance: "Follow the plan and keep the prescribed repetitions in reserve."
            )
        case .low:
            return Verdict(
                state: state, source: entry.source,
                title: "Protect the priority work",
                guidance: "Keep the priority strength work, reduce optional volume and prefer Stretch over optional conditioning.",
                reasons: reasons
            )
        case .veryLow:
            return Verdict(
                state: state, source: entry.source,
                title: "Recovery first today",
                guidance: "Use reduced volume, Stretch or rest. Avoid adding extra training.",
                reasons: reasons
            )
        }
    }

    private static func percent(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite else { return nil }
        return max(0, min(100, Int(number.rounded())))
    }

    /// Reads stored check-ins, dropping any that lack the score their own
    /// source depends on rather than scoring them as zero.
    static func history(from addons: [String: JSONValue]?) -> [Checkin] {
        guard let items = addons?["recovery_history"]?.arrayValue else { return [] }
        return items.compactMap { item -> Checkin? in
            guard let row = item.objectValue,
                  let date = row["date"]?.stringValue,
                  let updatedAt = row["updated_at"]?.stringValue
            else { return nil }
            let source = row["source"]?.stringValue == "other" ? "other" : "apple"
            let sleepScore = percent(row["sleep_score"])
            let sleepPercent = percent(row["sleep_pct"])
            let recoveryPercent = percent(row["recovery_pct"])
            if source == "apple", sleepScore == nil { return nil }
            if source == "other", sleepPercent == nil || recoveryPercent == nil { return nil }
            return Checkin(
                date: date,
                source: source,
                sleepScore: source == "apple" ? sleepScore : nil,
                sleepPercent: source == "other" ? sleepPercent : nil,
                recoveryPercent: source == "other" ? recoveryPercent : nil,
                updatedAt: updatedAt
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// The night that ends on `day`: 18:00 the evening before to 12:00. The window is fixed, so a
    /// read at 22:00 sees the same night as a read at 08:00 and an afternoon nap stays outside it.
    static func nightSleepWindow(endingOn day: Date, calendar: Calendar = .current) -> DateInterval? {
        let morning = calendar.startOfDay(for: day)
        guard let eve = calendar.date(byAdding: .day, value: -1, to: morning),
              let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: eve),
              let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Hours asleep inside the window, with overlapping Watch and iPhone intervals counted once.
    static func nightSleepHours(asleep: [DateInterval], window: DateInterval) -> Double? {
        var merged: [DateInterval] = []
        let inside = asleep.compactMap { $0.intersection(with: window) }.filter { $0.duration > 0 }
        for interval in inside.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        guard !merged.isEmpty else { return nil }
        return merged.reduce(0) { $0 + $1.duration } / 3_600
    }

    /// Settings addons after an Apple Health read. A later read of the same night can add hours
    /// and never takes them away: the sleep query can fail while the other readings arrive.
    static func addons(
        _ addons: [String: JSONValue], storingHealthRead date: String, sleepHours: Double?,
        heartRateVariabilityMS: Double?, restingHeartRate: Double?, updatedAt: String
    ) -> [String: JSONValue] {
        var addons = addons
        let stored = addons["apple_recovery_context"]?.objectValue
        let storedHours = stored?["date"]?.stringValue == date ? stored?["sleep_duration_hours"]?.numberValue : nil
        let hours = [sleepHours, storedHours].compactMap { $0 }.max()
        if let hours {
            // Each night is kept, so the morning verdict can see a run of short ones.
            var nights = sleepHistory(from: addons)
            nights[date] = hours
            addons["apple_sleep_history"] = .array(nights.sorted { $0.key < $1.key }.suffix(730).map {
                .object(["date": .string($0.key), "hours": .number($0.value)])
            })
        }
        addons["apple_recovery_context"] = .object([
            "date": .string(date),
            "sleep_duration_hours": hours.map(JSONValue.number) ?? .null,
            "heart_rate_variability_ms": heartRateVariabilityMS.map(JSONValue.number) ?? .null,
            "resting_heart_rate": restingHeartRate.map(JSONValue.number) ?? .null,
            "source": .string("apple_health"),
            "updated_at": .string(updatedAt)
        ])
        return addons
    }

    /// HealthKit exposes the measured sleep interval but not the Sleep app's
    /// composite score. Keep the measured fact available without relabelling
    /// it as a score derived from duration alone.
    static func sleepDurationHours(_ data: DashboardData, date: String) -> Double? {
        guard let context = data.settings?.addons["apple_recovery_context"]?.objectValue,
              context["date"]?.stringValue == date,
              let hours = context["sleep_duration_hours"]?.numberValue,
              hours.isFinite,
              hours >= 0
        else { return nil }
        return hours
    }

    /// Only an explicitly recorded vendor score is a check-in. Measured sleep
    /// duration remains context and is never promoted into Apple's 0–100 score.
    static func todaysCheckin(_ data: DashboardData, date: String) -> Checkin? {
        history(from: data.settings?.addons).last(where: { $0.date == date })
    }
}
