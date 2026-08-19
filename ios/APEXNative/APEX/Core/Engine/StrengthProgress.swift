import Foundation

/*
 * Port of src/lib/strengthProgress.ts.
 *
 * Turns completed sets into a strength history: an estimated one-rep max per
 * exercise per session, what changed since last time, and what the weekly
 * joint check-in says about whether to keep pushing.
 */
enum StrengthProgress {
    enum JointRegion: String, Sendable, CaseIterable {
        case arms, core, legs
    }

    enum DeloadState: String, Sendable {
        case clear
        case watch
        case regionalDeload = "regional_deload"
        case wholeDeload = "whole_deload"
        case stopAndReview = "stop_and_review"
    }

    struct Point: Hashable, Sendable {
        let sessionID: UUID
        let date: String
        let topWeight: Double
        let estimated1RM: Double
        let volume: Double
        let setWeights: [Int: Double]
    }

    struct Series: Hashable, Sendable {
        let key: String
        let exerciseID: UUID?
        let name: String
        let points: [Point]
    }

    struct SessionInsight: Hashable, Sendable {
        let key: String
        let name: String
        let current: Point
        let previous: Point?
        /// The point the comparison is made against, preferring 30-90 days back.
        let reference: Point?
        let daysCompared: Int?
        let loadDelta: Double?
        let estimated1RMDelta: Double?
    }

    struct JointCheckin: Hashable, Sendable {
        let date: String
        let arms: Int
        let core: Int
        let legs: Int

        subscript(region: JointRegion) -> Int {
            switch region {
            case .arms: arms
            case .core: core
            case .legs: legs
            }
        }
    }

    struct JointAssessment: Hashable, Sendable {
        let state: DeloadState
        let affected: [JointRegion]
        let average: Double
        let highest: Int
        let rising: [JointRegion]
    }

    // MARK: - Helpers

    /// JavaScript's Math.round rounds half up; Swift rounds half away from
    /// zero. Deltas here can be negative, so the JS rule is kept exactly.
    private static func roundJS(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    private static func round1(_ value: Double) -> Double {
        roundJS(value * 10) / 10
    }

    private static func exerciseKey(_ log: WorkoutLog) -> String {
        if let id = log.exerciseID { return "id:\(id.uuidString.lowercased())" }
        return "name:\(log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func daysBetween(_ earlier: String, _ later: String) -> Int {
        guard let start = APEXDateMath.date(from: earlier), let end = APEXDateMath.date(from: later) else { return 0 }
        return max(0, Int(roundJS(end.timeIntervalSince(start) / 86_400)))
    }

    // MARK: - Estimated one-rep max

    static func estimatedOneRepMax(weight: Double, reps: Int?) -> Double {
        guard weight.isFinite, weight > 0 else { return 0 }
        guard let reps, reps > 1 else { return roundJS(weight * 10) / 10 }
        /* Epley is capped at 15 reps on purpose: higher-rep sets estimate a
           maximum poorly and would manufacture spectacular fake gains. */
        let bounded = Double(min(15, reps))
        return roundJS(weight * (1 + bounded / 30) * 10) / 10
    }

    // MARK: - Series

    static func buildSeries(sessions allSessions: [WorkoutSession], logs: [WorkoutLog]) -> [Series] {
        var sessions: [UUID: WorkoutSession] = [:]
        for session in allSessions where session.completed { sessions[session.id] = session }

        struct Group {
            var exerciseID: UUID?
            var name: String
            var sessions: [UUID: [WorkoutLog]] = [:]
            var order: [UUID] = []
        }
        var grouped: [String: Group] = [:]
        var groupOrder: [String] = []

        for log in logs {
            guard !log.skipped, let weight = log.weightKG, weight > 0, sessions[log.sessionID] != nil else { continue }
            let key = exerciseKey(log)
            if grouped[key] == nil {
                grouped[key] = Group(exerciseID: log.exerciseID, name: log.exerciseName)
                groupOrder.append(key)
            }
            if grouped[key]?.sessions[log.sessionID] == nil { grouped[key]?.order.append(log.sessionID) }
            grouped[key]?.sessions[log.sessionID, default: []].append(log)
        }

        return groupOrder.compactMap { key -> Series? in
            guard let group = grouped[key] else { return nil }
            let points = group.order.compactMap { sessionID -> Point? in
                guard let session = sessions[sessionID], let logs = group.sessions[sessionID] else { return nil }
                let usable = logs.filter { ($0.weightKG ?? 0) > 0 }
                guard !usable.isEmpty else { return nil }
                let topWeight = usable.compactMap(\.weightKG).max() ?? 0
                let best = usable.map { estimatedOneRepMax(weight: $0.weightKG ?? 0, reps: $0.reps) }.max() ?? 0
                let volume = usable.reduce(0.0) { $0 + ($1.weightKG ?? 0) * Double(max(0, $1.reps ?? 0)) }
                var setWeights: [Int: Double] = [:]
                for log in usable { setWeights[log.setNumber] = log.weightKG ?? 0 }
                return Point(
                    sessionID: sessionID, date: session.date, topWeight: topWeight,
                    estimated1RM: best, volume: volume, setWeights: setWeights
                )
            }.sorted {
                $0.date == $1.date
                    ? $0.sessionID.uuidString.lowercased() < $1.sessionID.uuidString.lowercased()
                    : $0.date < $1.date
            }
            guard !points.isEmpty else { return nil }
            return Series(key: key, exerciseID: group.exerciseID, name: group.name, points: points)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Session insights

    static func sessionInsights(
        sessions: [WorkoutSession],
        logs: [WorkoutLog],
        sessionID: UUID
    ) -> [SessionInsight] {
        guard let current = sessions.first(where: { $0.id == sessionID }) else { return [] }

        return buildSeries(sessions: sessions, logs: logs).compactMap { series -> SessionInsight? in
            guard let point = series.points.first(where: { $0.sessionID == sessionID }) else { return nil }
            let prior = series.points.filter { $0.date < current.date }
            let previous = prior.last
            /* Prefer a meaningful 30-90 day comparison. When history is newer,
               the earliest prior point is still more honest than inventing a
               horizon that does not exist. */
            let withinNinety = prior.filter { daysBetween($0.date, current.date) <= 90 }
            let reference = withinNinety.first ?? previous
            return SessionInsight(
                key: series.key,
                name: series.name,
                current: point,
                previous: previous,
                reference: reference,
                daysCompared: reference.map { daysBetween($0.date, current.date) },
                loadDelta: reference.map { round1(point.topWeight - $0.topWeight) },
                estimated1RMDelta: reference.map { round1(point.estimated1RM - $0.estimated1RM) }
            )
        }.sorted { ($0.loadDelta ?? -.infinity) > ($1.loadDelta ?? -.infinity) }
    }

    // MARK: - Joint check-ins

    static func assess(_ current: JointCheckin, previous: JointCheckin? = nil) -> JointAssessment {
        let regions = JointRegion.allCases
        let scores = regions.map { current[$0] }
        let affected = regions.filter { current[$0] >= 5 }
        let rising = previous.map { prior in regions.filter { current[$0] - prior[$0] >= 2 } } ?? []
        let highest = scores.max() ?? 0
        let average = roundJS(Double(scores.reduce(0, +)) / Double(scores.count) * 10) / 10
        let severe = regions.filter { current[$0] >= 9 }
        let high = regions.filter { current[$0] >= 7 }
        let elevated = regions.filter { current[$0] >= 6 }

        var state: DeloadState = .clear
        if !severe.isEmpty { state = .stopAndReview }
        else if high.count >= 2 || elevated.count >= 2 || average >= 7 { state = .wholeDeload }
        else if high.count == 1 { state = .regionalDeload }
        else if !affected.isEmpty || !rising.isEmpty { state = .watch }

        return JointAssessment(
            state: state,
            affected: severe.isEmpty ? affected : severe,
            average: average,
            highest: highest,
            rising: rising
        )
    }

    static func checkinDue(_ checkins: [JointCheckin], today: String, intervalDays: Int = 7) -> Bool {
        guard let latest = checkins.max(by: { $0.date < $1.date }) else { return true }
        return daysBetween(latest.date, today) >= intervalDays
    }

    /// Check-ins live in settings addons, the same place the web keeps them.
    static func checkins(from addons: [String: JSONValue]?) -> [JointCheckin] {
        guard case .array(let rows)? = addons?["joint_checkins"] else { return [] }
        return rows.compactMap { row in
            guard case .object(let fields) = row,
                  case .string(let date)? = fields["date"] else { return nil }
            func score(_ key: String) -> Int {
                guard case .number(let value)? = fields[key] else { return 0 }
                return max(0, min(10, Int(value)))
            }
            return JointCheckin(date: date, arms: score("arms"), core: score("core"), legs: score("legs"))
        }
    }
}
