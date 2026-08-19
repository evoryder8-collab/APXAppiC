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
