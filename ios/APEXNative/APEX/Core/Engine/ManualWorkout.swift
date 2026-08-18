import Foundation

/*
 * Logging a session that was not on the plan.
 *
 * A port of the parts of src/lib/manualWorkout.ts the native logger needs: the
 * marker that identifies a manual session and carries its title, the treadmill
 * encoding that keeps distance, incline and duration inside an exercise name,
 * and the reconciliation that lets an edit reuse the rows it is replacing.
 */
enum ManualWorkout {
    static let prefix = "APEX_MANUAL_V1"
    private static let automaticTitle = "__APEX_AUTOMATIC_TITLE__"

    struct SetDraft: Identifiable, Hashable {
        var id = UUID()
        var reps: Int = 10
        var weightKG: Double = 0
    }

    struct TreadmillDraft: Hashable {
        var distanceKM: Double = 0
        var inclineDegrees: Double = 0
        var durationMinutes: Int = 0
    }

    struct ExerciseDraft: Identifiable, Hashable {
        var id = UUID()
        var catalogID: String?
        var name: String
        var sets: [SetDraft] = [SetDraft()]
        var treadmill: TreadmillDraft?
    }

    // MARK: - The manual marker

    static func notes(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let value = trimmed.isEmpty ? automaticTitle : trimmed
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
        return "\(prefix)|\(encoded)"
    }

    static func title(fromNotes notes: String) -> String? {
        guard notes.hasPrefix("\(prefix)|") else { return nil }
        let raw = String(notes.dropFirst(prefix.count + 1))
        guard let decoded = raw.removingPercentEncoding else { return "Workout" }
        return decoded.isEmpty || decoded == automaticTitle ? "Workout" : decoded
    }

    static func hasAutomaticTitle(_ notes: String) -> Bool {
        guard notes.hasPrefix("\(prefix)|") else { return false }
        let raw = String(notes.dropFirst(prefix.count + 1))
        return raw.removingPercentEncoding == automaticTitle
    }

    // MARK: - Treadmill

    static func encodeTreadmill(name: String, metrics: TreadmillDraft) -> String {
        let distance = max(0, metrics.distanceKM)
        let incline = max(0, metrics.inclineDegrees)
        let duration = max(0, metrics.durationMinutes)
        return "\(name) · \(number(distance)) km · \(number(incline))° · \(duration) min"
    }

    static func parseTreadmill(_ value: String) -> (name: String, metrics: TreadmillDraft)? {
        let pattern = #"^(.+?) · ([\d.,]+) km · ([\d.,]+)° · ([\d.,]+) min$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value, range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges == 5
        else { return nil }
        func part(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range])
        }
        let numbers = (2...4).map { Double(part($0).replacingOccurrences(of: ",", with: ".")) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        return (
            part(1),
            TreadmillDraft(
                distanceKM: numbers[0]!,
                inclineDegrees: numbers[1]!,
                durationMinutes: Int(numbers[2]!.rounded())
            )
        )
    }

    /// The plain movement name, with any treadmill metrics stripped back off.
    static func baseName(_ value: String) -> String {
        parseTreadmill(value)?.name ?? value
    }

    // MARK: - Reconciliation

    /*
     * An edit rewrites a session's rows. Matching each replacement to the row it
     * supersedes, by movement and set number, lets the write reuse existing ids
     * rather than deleting everything and inserting again, which would leave a
     * window where the workout looked empty.
     */
    static func reconcile(
        existing: [WorkoutLog],
        next: [WorkoutLog]
    ) -> (logs: [WorkoutLog], staleIDs: [UUID]) {
        var available: [String: [WorkoutLog]] = [:]
        let sorted = existing.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.setNumber != $1.setNumber { return $0.setNumber < $1.setNumber }
            return $0.id.uuidString < $1.id.uuidString
        }
        for log in sorted {
            let key = "\(baseName(log.exerciseName))\u{0}\(log.setNumber)"
            available[key, default: []].append(log)
        }

        var reused: Set<UUID> = []
        let logs = next.map { log -> WorkoutLog in
            let key = "\(baseName(log.exerciseName))\u{0}\(log.setNumber)"
            guard let match = available[key]?.first(where: { !reused.contains($0.id) }) else { return log }
            reused.insert(match.id)
            var updated = log
            updated = WorkoutLog(
                id: match.id,
                userID: log.userID,
                sessionID: log.sessionID,
                exerciseID: log.exerciseID,
                exerciseName: log.exerciseName,
                setNumber: log.setNumber,
                weightKG: log.weightKG,
                reps: log.reps,
                rir: log.rir,
                skipped: log.skipped,
                overrideFlag: log.overrideFlag,
                createdAt: log.createdAt
            )
            return updated
        }
        return (logs, existing.filter { !reused.contains($0.id) }.map(\.id))
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
