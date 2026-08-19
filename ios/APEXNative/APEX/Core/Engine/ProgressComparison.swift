import Foundation

/*
 * Port of the decision-making half of src/lib/progressComparison.ts.
 *
 * The poster is drawn on a canvas in the browser; on iOS that belongs to Core
 * Graphics, so only the content rules are ported. What matters here is the
 * strength figure a before-and-after actually claims.
 */
enum ProgressComparison {
    enum ExportMode: String, Sendable {
        case detailed
        case minimal
    }

    struct Strength: Hashable, Sendable {
        /// Mean change in average load per set, or nil when nothing repeats.
        let averageLoadDeltaKG: Double?
        let matchedExercises: Int
        let loadedSets: Int
    }

    struct PosterContent: Hashable, Sendable {
        let stats: Bool
        let athlete: Bool
        let pose: Bool
        let privateFooter: Bool
    }

    static func resolveExportMode(_ value: JSONValue?) -> ExportMode {
        if case .string("minimal") = value { return .minimal }
        return .detailed
    }

    static func posterContent(_ mode: ExportMode) -> PosterContent {
        let detailed = mode == .detailed
        return PosterContent(stats: detailed, athlete: detailed, pose: detailed, privateFooter: detailed)
    }

    private static func logKey(_ log: WorkoutLog) -> String {
        if let id = log.exerciseID { return "id:\(id.uuidString.lowercased())" }
        return "name:\(log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(max(1, values.count))
    }

    /* Compare like with like: each movement contributes one delta, between
       its earliest and latest session inside the photo window. Without this a
       squat-heavy day would dominate purely by having more sets. */
    static func strength(
        sessions allSessions: [WorkoutSession],
        logs allLogs: [WorkoutLog],
        firstDate: String,
        secondDate: String
    ) -> Strength {
        let from = min(firstDate, secondDate)
        let to = max(firstDate, secondDate)
        var sessionDates: [UUID: String] = [:]
        for session in allSessions where session.completed && session.date >= from && session.date <= to {
            sessionDates[session.id] = session.date
        }
        let logs = allLogs.filter { log in
            !log.skipped && (log.weightKG ?? 0) > 0 && sessionDates[log.sessionID] != nil
        }

        var grouped: [String: [UUID: [Double]]] = [:]
        for log in logs {
            grouped[logKey(log), default: [:]][log.sessionID, default: []].append(log.weightKG ?? 0)
        }

        var deltas: [Double] = []
        for bySession in grouped.values {
            let points = bySession.compactMap { sessionID, weights -> (date: String, id: UUID, average: Double)? in
                guard let date = sessionDates[sessionID] else { return nil }
                return (date, sessionID, mean(weights))
            }.sorted {
                $0.date == $1.date
                    ? $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
                    : $0.date < $1.date
            }
            guard points.count >= 2, let first = points.first, let last = points.last else { continue }
            deltas.append(last.average - first.average)
        }

        return Strength(
            averageLoadDeltaKG: deltas.isEmpty ? nil : (mean(deltas) * 10).rounded() / 10,
            matchedExercises: deltas.count,
            loadedSets: logs.count
        )
    }
}
