import Foundation

enum WorkoutInsights {
    struct Summary: Equatable, Sendable {
        let from: String
        let to: String
        let workouts: Int
        let activeDays: Int
        let durationMinutes: Int
        let activeEnergyKcal: Double?
        let sets: Int
        let reps: Int
        let volumeKG: Double?
        let distanceKM: Double?
        let anniversaryYears: Int?
    }

    static func summarize(
        ownerID: UUID,
        from requestedFrom: String,
        to requestedTo: String,
        sessions allSessions: [WorkoutSession],
        logs allLogs: [WorkoutLog],
        importedActivities allImportedActivities: [ImportedActivity]
    ) -> Summary {
        let from = min(requestedFrom, requestedTo)
        let to = max(requestedFrom, requestedTo)
        let allOwnedSessions = allSessions.filter { $0.userID == ownerID && $0.completed }
        let allExternal = allImportedActivities.filter { activity in
            activity.userID == ownerID
                && activity.hiddenAt == nil
                && !ExternalWorkoutImport.isAPEXBundleIdentifier(activity.sourceBundleIdentifier ?? "")
        }
        let sessions = allOwnedSessions.filter { $0.date >= from && $0.date <= to }
        let sessionIDs = Set(sessions.map(\.id))
        let external = allExternal.filter { $0.date >= from && $0.date <= to }
        let linkedSessionIDs = Set(external.compactMap { activity -> UUID? in
            guard let sessionID = activity.apexWorkoutSessionID, sessionIDs.contains(sessionID) else { return nil }
            return sessionID
        })
        let logs = allLogs.filter { log in
            log.userID == ownerID && sessionIDs.contains(log.sessionID) && !log.skipped
        }

        var durationMinutes = external.reduce(0) { total, activity in
            total + max(0, activity.durationMinutes)
        }
        for session in sessions where !linkedSessionIDs.contains(session.id) {
            if let minutes = validDurationMinutes(startedAt: session.startedAt, completedAt: session.completedAt) {
                durationMinutes += minutes
            } else {
                let seconds = logs
                    .filter { $0.sessionID == session.id }
                    .reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) }
                if seconds > 0 { durationMinutes += max(1, Int((Double(seconds) / 60).rounded())) }
            }
        }

        let energyFacts = external.compactMap { activity -> Double? in
            guard let value = activity.activeEnergyKcal, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let externalDistanceFacts = external.compactMap { activity -> Double? in
            guard let value = activity.distanceKM, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let loggedDistanceFacts = logs.compactMap { log -> Double? in
            guard !linkedSessionIDs.contains(log.sessionID),
                  let value = log.distanceMeters, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let reps = logs.reduce(0) { $0 + max(0, $1.reps ?? 0) }
        let volumeFacts = logs.compactMap { log -> Double? in
            guard let weight = log.weightKG, let repetitions = log.reps,
                  weight > 0, repetitions > 0 else { return nil }
            return weight * Double(repetitions)
        }
        let activeDates = Set(sessions.map(\.date) + external.map(\.date))
        let standaloneExternal = external.filter { activity in
            guard let sessionID = activity.apexWorkoutSessionID else { return true }
            return !sessionIDs.contains(sessionID)
        }
        let oldestEvidenceDate = (allOwnedSessions.map(\.date) + allExternal.map(\.date)).min()
        let distanceFacts = externalDistanceFacts.reduce(0, +) + loggedDistanceFacts.reduce(0, +) / 1_000

        return Summary(
            from: from,
            to: to,
            workouts: sessions.count + standaloneExternal.count,
            activeDays: activeDates.count,
            durationMinutes: durationMinutes,
            activeEnergyKcal: energyFacts.isEmpty ? nil : energyFacts.reduce(0, +),
            sets: logs.count,
            reps: reps,
            volumeKG: volumeFacts.isEmpty ? nil : volumeFacts.reduce(0, +),
            distanceKM: externalDistanceFacts.isEmpty && loggedDistanceFacts.isEmpty ? nil : distanceFacts,
            anniversaryYears: anniversaryYears(oldestEvidenceDate: oldestEvidenceDate, from: from, to: to)
        )
    }

    static func anniversaryYears(oldestEvidenceDate: String?, from: String, to: String) -> Int? {
        guard let oldestEvidenceDate,
              let oldest = ISO8601DateFormatter.apexDateOnly.date(from: oldestEvidenceDate),
              let start = ISO8601DateFormatter.apexDateOnly.date(from: from),
              let end = ISO8601DateFormatter.apexDateOnly.date(from: to),
              start <= end else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for years in [10, 5, 1] {
            guard let boundary = calendar.date(byAdding: .year, value: -years, to: end) else { continue }
            if start <= boundary && oldest <= boundary { return years }
        }
        return nil
    }

    private static func validDurationMinutes(startedAt: String?, completedAt: String?) -> Int? {
        guard let startedAt, let completedAt,
              let start = parseTimestamp(startedAt), let end = parseTimestamp(completedAt), end > start else { return nil }
        return max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions.insert(.withFractionalSeconds)
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
