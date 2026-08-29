import Foundation

/*
 * Port of src/lib/healthImport.ts.
 *
 * The web imports Apple Health by stream-parsing a near-gigabyte export.xml.
 * Native does not need the file: HealthKit holds the same history on device
 * and can be queried directly, so only the shape and the merge policy are
 * ported. The policy is the part that matters and it is unchanged:
 *
 *   - absence of data never penalises anything; an import is a positive
 *     signal only, so a day without the watch stays a day without the watch
 *   - a manual entry in APEX always wins; imports only fill what is empty
 *   - water may rise but never fall, because a drink logged by hand that
 *     HealthKit never saw is still a drink
 *   - re-importing is safe: a workout already recorded is not duplicated
 */
enum HealthImport {
    struct Nutrition: Hashable, Sendable {
        var kcal: Double = 0
        var protein: Double = 0
        var fat: Double = 0
        var carbs: Double = 0
    }

    struct Workout: Hashable, Sendable {
        let date: String
        let activity: String
        let kind: String
        let durationMinutes: Int
        let source: String
    }

    struct Parsed: Sendable {
        var nutrition: [String: Nutrition] = [:]
        /// Litres per date.
        var water: [String: Double] = [:]
        /// Kilograms, last reading of the day.
        var weight: [String: Double] = [:]
        var vo2Max: [String: Double] = [:]
        var restingHeartRate: [String: Double] = [:]
        var workouts: [Workout] = []
    }

    /// Anything shorter is a stray reading, not a session worth importing.
    static let minimumWorkoutMinutes = 8

    /* HealthKit activity types the app has an opinion about. An unmapped type
       is skipped rather than guessed at, matching the web. */
    static let activityKind: [String: String] = [
        "TraditionalStrengthTraining": "strength",
        "FunctionalStrengthTraining": "strength",
        "CoreTraining": "strength",
        "HighIntensityIntervalTraining": "endurance",
        "Running": "endurance",
        "Cycling": "endurance",
        "Swimming": "endurance",
        "Rowing": "endurance",
        "Elliptical": "endurance",
        "StairClimbing": "endurance",
        "JumpRope": "endurance",
        "CrossTraining": "endurance",
        "MixedCardio": "endurance",
        "Hiking": "endurance",
        "WaterSports": "endurance",
        "Yoga": "mobility",
        "Flexibility": "mobility",
        "MindAndBody": "mobility",
        "Pilates": "mobility",
    ]

    struct Result: Hashable, Sendable {
        let dailyLogsTouched: Int
        let metricsTouched: Int
        let workoutsAdded: Int
        let latestWeight: Double?
        let latestVO2Max: Double?
        let dateRange: [String]?
    }

    struct Rows: Sendable {
        let dailyLogs: [DailyLog]
        let metrics: [HealthMetric]
        let activities: [ImportedActivity]
        let result: Result
    }

    static func buildRows(
        parsed: Parsed,
        userID: UUID,
        dailyLogs existingLogs: [DailyLog],
        metrics existingMetrics: [HealthMetric],
        activities existingActivities: [ImportedActivity],
        makeActivityID: () -> UUID = { UUID() }
    ) -> Rows {
        var byDate: [String: DailyLog] = [:]
        for log in existingLogs { byDate[log.date] = log }

        var dailyLogs: [DailyLog] = []
        let nutritionDates = Set(parsed.nutrition.keys).union(parsed.water.keys)
        for date in nutritionDates.sorted() {
            var next = byDate[date] ?? DailyLog(
                id: APEXStableID.scopedUUID(namespace: "daily-log", date: date, userID: userID),
                userID: userID,
                date: date,
                kcal: nil, proteinG: nil, fatG: nil, carbsG: nil,
                waterL: 0, estimatedTDEE: nil, computedPAL: nil,
                activityMode: "quick", weightKG: nil
            )
            var changed = false

            /* A manual entry always wins, so only an empty field is filled. */
            if let nutrition = parsed.nutrition[date], nutrition.kcal > 0, next.kcal == nil {
                next.kcal = Int(nutrition.kcal.rounded())
                next.proteinG = next.proteinG ?? Int(nutrition.protein.rounded())
                next.fatG = next.fatG ?? Int(nutrition.fat.rounded())
                next.carbsG = next.carbsG ?? Int(nutrition.carbs.rounded())
                changed = true
            }
            /* Water rises but never falls: a glass logged by hand that
               HealthKit never saw was still drunk. */
            if let water = parsed.water[date], water > next.waterL {
                next.waterL = (water * 4).rounded() / 4
                changed = true
            }
            if changed { dailyLogs.append(next) }
        }

        var existingMetricByDate: [String: HealthMetric] = [:]
        for metric in existingMetrics { existingMetricByDate[metric.date] = metric }
        let metricDates = Set(parsed.weight.keys)
            .union(parsed.vo2Max.keys)
            .union(parsed.restingHeartRate.keys)
        var metrics: [HealthMetric] = []
        for date in metricDates.sorted() {
            let previous = existingMetricByDate[date]
            let row = HealthMetric(
                id: previous?.id ?? APEXStableID.scopedUUID(namespace: "health-metric", date: date, userID: userID),
                userID: userID,
                date: date,
                weightKG: parsed.weight[date] ?? previous?.weightKG,
                vo2Max: parsed.vo2Max[date] ?? previous?.vo2Max,
                restingHeartRate: parsed.restingHeartRate[date] ?? previous?.restingHeartRate
            )
            if previous == nil
                || previous?.weightKG != row.weightKG
                || previous?.vo2Max != row.vo2Max
                || previous?.restingHeartRate != row.restingHeartRate {
                metrics.append(row)
            }
        }

        /* Re-import safe: a workout on the same date, of the same kind and
           length, is the one already recorded. */
        var seen = Set(existingActivities.map { "\($0.date)|\($0.kind)|\($0.durationMinutes)" })
        var activities: [ImportedActivity] = []
        for workout in parsed.workouts {
            let key = "\(workout.date)|\(workout.kind)|\(workout.durationMinutes)"
            guard seen.insert(key).inserted else { continue }
            activities.append(ImportedActivity(
                id: makeActivityID(),
                userID: userID,
                date: workout.date,
                kind: workout.kind,
                activity: workout.activity,
                durationMinutes: workout.durationMinutes,
                source: workout.source
            ))
        }

        let weightDates = parsed.weight.keys.sorted()
        let vo2Dates = parsed.vo2Max.keys.sorted()
        let allDates = (nutritionDates.union(metricDates)).sorted()
        return Rows(
            dailyLogs: dailyLogs,
            metrics: metrics,
            activities: activities,
            result: Result(
                dailyLogsTouched: dailyLogs.count,
                metricsTouched: metrics.count,
                workoutsAdded: activities.count,
                latestWeight: weightDates.last.flatMap { parsed.weight[$0] },
                latestVO2Max: vo2Dates.last.flatMap { parsed.vo2Max[$0] },
                dateRange: allDates.isEmpty ? nil : [allDates[0], allDates[allDates.count - 1]]
            )
        )
    }
}

struct HealthWorkoutChangeSet: Hashable, Sendable {
    let workouts: [HealthWorkoutSnapshot]
    let deletedWorkoutIDs: Set<UUID>
    let anchorData: Data?

    init(
        workouts: [HealthWorkoutSnapshot],
        deletedWorkoutIDs: Set<UUID>,
        anchorData: Data? = nil
    ) {
        self.workouts = workouts
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.anchorData = anchorData
    }
}

enum ExternalWorkoutImport {
    struct APEXSessionIdentity: Hashable, Sendable {
        let id: UUID
        let startedAt: Date
    }

    struct Reconciliation: Equatable, Sendable {
        let upserts: [ImportedActivity]
        let importedActivityIDsToDelete: [UUID]
        let activityLogIDsToDelete: [UUID]

        static let unchanged = Reconciliation(
            upserts: [],
            importedActivityIDsToDelete: [],
            activityLogIDsToDelete: []
        )
    }

    static func reconcile(
        changeSet: HealthWorkoutChangeSet?,
        existing: [ImportedActivity],
        apexSessions: [APEXSessionIdentity],
        ownerID: UUID,
        legacyActivityLogIDs: Set<UUID>
    ) -> Reconciliation {
        guard let changeSet else { return .unchanged }

        let existingForOwner = existing.filter { $0.userID == ownerID }
        let existingRowsByWorkoutID = Dictionary(
            grouping: existingForOwner.compactMap { row in
                row.healthKitWorkoutID.map { ($0, row) }
            },
            by: \.0
        )
        let affectedWorkoutIDs = Set(changeSet.workouts.map(\.id))
            .union(changeSet.deletedWorkoutIDs)
        var rowIDsToDelete = Set(existingForOwner.compactMap { row -> UUID? in
            if isAPEXMirror(row, apexSessions: apexSessions) { return row.id }
            if let workoutID = row.healthKitWorkoutID {
                return changeSet.deletedWorkoutIDs.contains(workoutID) ? row.id : nil
            }
            return affectedWorkoutIDs.contains(row.id) ? row.id : nil
        })
        var seenWorkoutIDs = Set<UUID>()
        var upserts: [ImportedActivity] = []

        for workout in changeSet.workouts {
            guard seenWorkoutIDs.insert(workout.id).inserted else { continue }
            guard changeSet.deletedWorkoutIDs.contains(workout.id) == false else { continue }

            let existingRows = existingRowsByWorkoutID[workout.id]?.map(\.1) ?? []
            let legacyRows = existingForOwner.filter {
                $0.healthKitWorkoutID == nil && $0.id == workout.id
            }
            if isAPEXMirror(workout, apexSessions: apexSessions) {
                rowIDsToDelete.formUnion(existingRows.map(\.id))
                rowIDsToDelete.formUnion(legacyRows.map(\.id))
                continue
            }

            let preservedLink = (existingRows + legacyRows)
                .filter { isAPEXBundleIdentifier($0.sourceBundleIdentifier ?? "") == false }
                .compactMap(\.apexWorkoutSessionID)
                .sorted { $0.uuidString < $1.uuidString }
                .first
            let replacement = importedActivity(
                from: workout,
                ownerID: ownerID,
                hiddenAt: (existingRows + legacyRows).compactMap(\.hiddenAt).max(),
                preservingLinkedSessionID: preservedLink
            )
            rowIDsToDelete.formUnion(
                existingRows.lazy.filter { $0.id != replacement.id }.map(\.id)
            )
            let canonicalRows = existingRows.filter { $0.id == replacement.id }
            if canonicalRows.count != 1 || canonicalRows[0] != replacement || legacyRows.isEmpty == false {
                upserts.append(replacement)
            }
        }

        let rowsToDelete = rowIDsToDelete
            .sorted { $0.uuidString < $1.uuidString }

        let logsToDelete = legacyActivityLogIDs
            .intersection(affectedWorkoutIDs)
            .sorted { $0.uuidString < $1.uuidString }

        return Reconciliation(
            upserts: upserts,
            importedActivityIDsToDelete: rowsToDelete,
            activityLogIDsToDelete: logsToDelete
        )
    }

    static func persistenceBatches(
        _ rows: [ImportedActivity],
        maximumCount: Int = 100
    ) -> [[ImportedActivity]] {
        guard rows.isEmpty == false else { return [] }
        let size = max(1, maximumCount)
        return stride(from: 0, to: rows.count, by: size).map { lowerBound in
            Array(rows[lowerBound..<min(lowerBound + size, rows.count)])
        }
    }

    static func importedActivity(
        from workout: HealthWorkoutSnapshot,
        ownerID: UUID,
        hiddenAt: String? = nil,
        preservingLinkedSessionID: UUID? = nil
    ) -> ImportedActivity {
        ImportedActivity(
            id: accountScopedID(ownerID: ownerID, workoutID: workout.id),
            userID: ownerID,
            date: workout.date,
            kind: avatarKind(for: workout.kind),
            activity: workout.activityName,
            durationMinutes: workout.durationMinutes,
            source: workout.sourceName,
            healthKitWorkoutID: workout.id,
            startedAt: workout.startedAt.ISO8601Format(),
            endedAt: workout.endedAt.ISO8601Format(),
            workoutNameKey: workout.activityNameKey,
            distanceKM: workout.distanceKM,
            activeEnergyKcal: workout.activeEnergyKcal,
            sourceBundleIdentifier: workout.sourceBundleIdentifier,
            activityTypeRaw: workout.activityTypeRaw,
            apexWorkoutSessionID: workout.apexSessionID ?? preservingLinkedSessionID,
            hiddenAt: hiddenAt
        )
    }

    static func isAPEXMirror(
        _ workout: HealthWorkoutSnapshot,
        apexSessions: [APEXSessionIdentity]
    ) -> Bool {
        guard isAPEXBundleIdentifier(workout.sourceBundleIdentifier) else { return false }
        if let apexSessionID = workout.apexSessionID,
           apexSessions.contains(where: { $0.id == apexSessionID }) {
            return true
        }
        return apexSessions.contains {
            abs($0.startedAt.timeIntervalSince(workout.startedAt)) < 5 * 60
        }
    }

    static func isAPEXMirror(
        _ activity: ImportedActivity,
        apexSessions: [APEXSessionIdentity]
    ) -> Bool {
        guard activity.sourceBundleIdentifier.map(isAPEXBundleIdentifier) == true else { return false }
        if let sessionID = activity.apexWorkoutSessionID,
           apexSessions.contains(where: { $0.id == sessionID }) {
            return true
        }
        guard let startedAt = parseTimestamp(activity.startedAt) else { return false }
        return apexSessions.contains {
            abs($0.startedAt.timeIntervalSince(startedAt)) < 5 * 60
        }
    }

    static func isAPEXBundleIdentifier(_ value: String) -> Bool {
        value == "ch.apexperformance.APEX"
            || value.hasPrefix("ch.apexperformance.APEX.")
    }

    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func avatarKind(for workoutKind: String) -> String {
        switch workoutKind {
        case "run", "walk", "hiit", "endurance": return "endurance"
        case "strength": return "strength"
        case "mobility": return "mobility"
        default: return "mobility"
        }
    }

    private static func accountScopedID(ownerID: UUID, workoutID: UUID) -> UUID {
        let owner = ownerID.uuid
        let workout = workoutID.uuid
        var bytes: [UInt8] = [
            owner.0 ^ workout.0, owner.1 ^ workout.1,
            owner.2 ^ workout.2, owner.3 ^ workout.3,
            owner.4 ^ workout.4, owner.5 ^ workout.5,
            owner.6 ^ workout.6, owner.7 ^ workout.7,
            owner.8 ^ workout.8, owner.9 ^ workout.9,
            owner.10 ^ workout.10, owner.11 ^ workout.11,
            owner.12 ^ workout.12, owner.13 ^ workout.13,
            owner.14 ^ workout.14, owner.15 ^ workout.15,
        ]
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum WearableWorkoutLinking {
    private static let automaticLeadWindow: TimeInterval = 5 * 60

    static func candidatesForDay(
        activities: [ImportedActivity],
        ownerID: UUID,
        date: String
    ) -> [ImportedActivity] {
        activities
            .filter {
                selectable($0, ownerID: ownerID, date: date)
            }
            .sorted {
                let left = ExternalWorkoutImport.parseTimestamp($0.startedAt ?? $0.endedAt)
                    ?? ExternalWorkoutImport.parseDay($0.date)
                    ?? .distantPast
                let right = ExternalWorkoutImport.parseTimestamp($1.startedAt ?? $1.endedAt)
                    ?? ExternalWorkoutImport.parseDay($1.date)
                    ?? .distantPast
                if left != right { return left > right }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    static func explicitLink(
        _ activity: ImportedActivity,
        to session: WorkoutSession
    ) -> ImportedActivity? {
        if activity.apexWorkoutSessionID == session.id { return activity }
        guard selectable(activity, ownerID: session.userID, date: session.date) else { return nil }
        return activity.linkingToAPEXSession(session.id)
    }

    static func automaticLinks(
        sessions: [WorkoutSession],
        activities: [ImportedActivity],
        ownerID: UUID
    ) -> [ImportedActivity] {
        let linkedSessionIDs = Set(activities.compactMap { activity -> UUID? in
            guard activity.userID == ownerID,
                  let sessionID = activity.apexWorkoutSessionID,
                  ExternalWorkoutImport.isAPEXBundleIdentifier(
                    activity.sourceBundleIdentifier ?? ""
                  ) == false else { return nil }
            return sessionID
        })
        let eligibleSessions = sessions.filter {
            $0.userID == ownerID
                && $0.completed
                && linkedSessionIDs.contains($0.id) == false
                && ExternalWorkoutImport.parseTimestamp($0.startedAt) != nil
                && ExternalWorkoutImport.parseTimestamp($0.completedAt) != nil
        }
        let eligibleActivities = activities.filter {
            selectable($0, ownerID: ownerID, date: $0.date)
        }
        var activityIDsBySession: [UUID: [UUID]] = [:]
        var sessionIDsByActivity: [UUID: [UUID]] = [:]

        for session in eligibleSessions {
            for activity in eligibleActivities where activity.date == session.date {
                guard overlapsAutomaticWindow(session: session, activity: activity) else { continue }
                activityIDsBySession[session.id, default: []].append(activity.id)
                sessionIDsByActivity[activity.id, default: []].append(session.id)
            }
        }

        let activitiesByID = Dictionary(uniqueKeysWithValues: eligibleActivities.map { ($0.id, $0) })
        return eligibleSessions.compactMap { session in
            guard let candidateIDs = activityIDsBySession[session.id],
                  candidateIDs.count == 1,
                  let activityID = candidateIDs.first,
                  sessionIDsByActivity[activityID]?.count == 1,
                  let activity = activitiesByID[activityID] else { return nil }
            return activity.linkingToAPEXSession(session.id)
        }
    }

    private static func selectable(
        _ activity: ImportedActivity,
        ownerID: UUID,
        date: String
    ) -> Bool {
        activity.userID == ownerID
            && activity.date == date
            && activity.healthKitWorkoutID != nil
            && activity.hiddenAt == nil
            && activity.apexWorkoutSessionID == nil
            && ExternalWorkoutImport.isAPEXBundleIdentifier(
                activity.sourceBundleIdentifier ?? ""
            ) == false
    }

    private static func overlapsAutomaticWindow(
        session: WorkoutSession,
        activity: ImportedActivity
    ) -> Bool {
        guard let sessionStart = ExternalWorkoutImport.parseTimestamp(session.startedAt),
              let sessionEnd = ExternalWorkoutImport.parseTimestamp(session.completedAt),
              let activityStart = ExternalWorkoutImport.parseTimestamp(activity.startedAt),
              activityStart >= sessionStart.addingTimeInterval(-automaticLeadWindow),
              activityStart <= sessionEnd else { return false }
        guard let activityEnd = ExternalWorkoutImport.parseTimestamp(activity.endedAt) else {
            return activityStart >= sessionStart
        }
        return activityEnd >= sessionStart
    }
}

enum WearableLinkRequest: Equatable, Sendable {
    case automatic
    case none
    case activity(UUID)
}
