import Foundation

/*
 * Keeps a finished session's receipts in the order it was actually performed.
 *
 * A 1:1 port of src/lib/workoutLogOrder.ts. Logs are grouped by exercise, each
 * exercise is positioned by its earliest recorded set, and the planned order
 * settles legacy rows that all share one timestamp.
 */
enum WorkoutLogOrder {
    private static func key(for log: WorkoutLog) -> String {
        if let id = log.exerciseID { return "id:\(id.uuidString)" }
        return "name:\(log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    private static func timestamp(_ value: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
        return nil
    }

    static func performedOrder(_ data: DashboardData, sessionID: UUID) -> [WorkoutLog] {
        let session = data.workoutSessions.first { $0.id == sessionID }
        let planned = data.exercises
            .filter { $0.programDayID == session?.programDayID }
            .sorted { $0.sortOrder < $1.sortOrder }
        var plannedByID: [UUID: Int] = [:]
        var plannedByName: [String: Int] = [:]
        for (index, exercise) in planned.enumerated() {
            plannedByID[exercise.id] = index
            plannedByName[exercise.name.trimmingCharacters(in: .whitespaces).lowercased()] = index
        }

        struct Group {
            var firstIndex: Int
            var firstTimestamp: Double?
            var plannedOrder: Int?
            var logs: [WorkoutLog]
        }
        var groups: [String: Group] = [:]
        var order: [String] = []

        for (index, log) in data.workoutLogs.enumerated() where log.sessionID == sessionID {
            let groupKey = key(for: log)
            let recordedAt = timestamp(log.createdAt)
            let plannedOrder = log.exerciseID.flatMap { plannedByID[$0] }
                ?? plannedByName[log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()]

            if var group = groups[groupKey] {
                group.logs.append(log)
                if let recordedAt, group.firstTimestamp == nil || recordedAt < group.firstTimestamp! {
                    group.firstTimestamp = recordedAt
                }
                if group.plannedOrder == nil, let plannedOrder { group.plannedOrder = plannedOrder }
                groups[groupKey] = group
            } else {
                groups[groupKey] = Group(
                    firstIndex: index,
                    firstTimestamp: recordedAt,
                    plannedOrder: plannedOrder,
                    logs: [log]
                )
                order.append(groupKey)
            }
        }

        return order
            .compactMap { groups[$0] }
            .sorted { left, right in
                if let l = left.firstTimestamp, let r = right.firstTimestamp, l != r { return l < r }
                if let l = left.plannedOrder, let r = right.plannedOrder, l != r { return l < r }
                if left.plannedOrder != nil && right.plannedOrder == nil { return true }
                if left.plannedOrder == nil && right.plannedOrder != nil { return false }
                return left.firstIndex < right.firstIndex
            }
            .flatMap { group in
                group.logs.sorted { left, right in
                    if left.setNumber != right.setNumber { return left.setNumber < right.setNumber }
                    return (timestamp(left.createdAt) ?? 0) < (timestamp(right.createdAt) ?? 0)
                }
            }
    }
}
