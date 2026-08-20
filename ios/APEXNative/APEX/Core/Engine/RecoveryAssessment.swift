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
    }

    struct Verdict: Equatable, Sendable {
        let state: State
        let source: String
        let title: String
        let guidance: String
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

        let escalation = context.escalators
        if state == .low, escalation >= 2 { state = .veryLow }
        if state == .normal, escalation >= 3 { state = .low }

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
                guidance: "Keep the priority strength work, reduce optional volume and prefer Stretch over optional conditioning."
            )
        case .veryLow:
            return Verdict(
                state: state, source: entry.source,
                title: "Recovery first today",
                guidance: "Use reduced volume, Stretch or rest. Avoid adding extra training."
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

    /*
     * Apple Health gives hours slept, not a score. Converting is a judgement,
     * so it is a deliberately plain one: eight hours is the anchor, and the
     * result is treated as an Apple-style sleep score.
     */
    static func checkinFromSleepHours(_ hours: Double, date: String, updatedAt: String) -> Checkin {
        let score = max(0, min(100, Int((hours / 8 * 100).rounded())))
        return Checkin(
            date: date, source: "apple", sleepScore: score,
            sleepPercent: nil, recoveryPercent: nil, updatedAt: updatedAt
        )
    }

    /// The reading for a date, preferring a recorded check-in and falling back
    /// to whatever the watch imported that morning.
    static func todaysCheckin(_ data: DashboardData, date: String) -> Checkin? {
        if let recorded = history(from: data.settings?.addons).last(where: { $0.date == date }) {
            return recorded
        }
        guard let context = data.settings?.addons["apple_recovery_context"]?.objectValue,
              context["date"]?.stringValue == date,
              let hours = context["sleep_duration_hours"]?.numberValue
        else { return nil }
        return checkinFromSleepHours(
            hours,
            date: date,
            updatedAt: context["updated_at"]?.stringValue ?? ""
        )
    }
}
