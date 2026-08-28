import Foundation

/*
 * When a meal lands, and what that means for training.
 *
 * A port of the timing half of src/lib/mealTiming.ts. Two questions run through
 * it. Before a session: how long ago did you finish eating, and is that long
 * enough for the size of what you ate. After one: how long until the next meal
 * finished, because the gap is the part a person can actually change.
 *
 * The comfort bands are deliberately conservative estimates, not a medical
 * clearance. Energy, fat and fibre all extend the settling window because they
 * commonly increase gastric load or slow emptying.
 */
enum MealTimingEngine {
    // MARK: - Comfort windows

    enum ComfortZone: String, Sendable {
        case settling, transition, ready
    }

    struct ComfortWindow: Equatable, Sendable {
        let load: String
        let transitionAfterMinutes: Int
        let readyAfterMinutes: Int
        let fibreG: Double
    }

    struct ComfortAnchor: Equatable, Sendable {
        let startMinute: Int
        let window: ComfortWindow
    }

    struct ComfortBand: Equatable, Sendable {
        let zone: ComfortZone
        let startMinute: Int
        var endMinute: Int
    }

    struct DaylineMealTiming: Equatable, Sendable {
        let minute: Int
        let lineMinute: Int
        let recorded: Bool
    }

    struct DaylineWorkoutTiming: Equatable, Sendable {
        let sessionID: UUID
        let minute: Int
        let lineMinute: Int
    }

    /// Resolves a meal's display time exactly as the web Dayline does. A stale
    /// or malformed timestamp is never presented as recorded evidence for a
    /// different day; the configured slot remains visible instead.
    static func daylineMealTiming(
        loggedAt: String?,
        localDate: String,
        scheduledMinute: Int,
        timeZone: String
    ) -> DaylineMealTiming {
        let fallback = clockMinute(scheduledMinute)
        guard let loggedAt,
              let date = instant(loggedAt),
              daylineDateKey(for: date, timeZone: timeZone) == localDate else {
            return DaylineMealTiming(
                minute: fallback,
                lineMinute: toDaylineMinute(fallback),
                recorded: false
            )
        }
        let minute = minuteOfDay(date, timeZone: timeZone)
        return DaylineMealTiming(
            minute: minute,
            lineMinute: toDaylineMinute(minute),
            recorded: true
        )
    }

    /// A completed session is a factual Dayline event only when its completion
    /// instant resolves to the selected date in the configured timezone.
    static func daylineWorkoutTiming(
        _ session: WorkoutSession,
        localDate: String,
        timeZone: String
    ) -> DaylineWorkoutTiming? {
        guard session.completed,
              let completedAt = session.completedAt,
              let date = instant(completedAt),
              daylineDateKey(for: date, timeZone: timeZone) == localDate else { return nil }
        let minute = minuteOfDay(date, timeZone: timeZone)
        return DaylineWorkoutTiming(
            sessionID: session.id,
            minute: minute,
            lineMinute: toDaylineMinute(minute)
        )
    }

    /// Produces the actual instant represented by the 03:00–02:59 Dayline.
    /// Building wall-clock components in the selected zone avoids applying the
    /// device timezone or adding a fixed 24 hours across daylight-saving days.
    static func daylineInstant(
        localDate: String,
        lineMinute: Int,
        timeZone: String
    ) -> Date? {
        let fields = localDate.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        var noon = DateComponents()
        noon.timeZone = calendar.timeZone
        noon.year = fields[0]
        noon.month = fields[1]
        noon.day = fields[2]
        noon.hour = 12
        guard let selectedNoon = calendar.date(from: noon),
              let targetDay = calendar.date(byAdding: .day, value: max(0, lineMinute / 1_440), to: selectedNoon) else {
            return nil
        }
        let day = calendar.dateComponents([.year, .month, .day], from: targetDay)
        let minute = clockMinute(lineMinute)
        var target = DateComponents()
        target.timeZone = calendar.timeZone
        target.year = day.year
        target.month = day.month
        target.day = day.day
        target.hour = minute / 60
        target.minute = minute % 60
        return calendar.date(from: target)
    }

    static func snapDaylineMinute(_ minute: Int, increment: Int) -> Int {
        let step = [5, 15, 30, 60].contains(increment) ? increment : 30
        let clamped = min(max(minute, 180), 1_619)
        let snapped = Int((Double(clamped) / Double(step)).rounded()) * step
        return min(max(snapped, 180), 1_619)
    }

    /// Resolves a real instant onto the logical date represented by a Dayline.
    /// Times before 03:00 belong to the line that began on the previous
    /// calendar date, matching the inverse mapping in `daylineInstant`.
    static func daylineDateKey(for date: Date, timeZone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let minute = minuteOfDay(date, timeZone: timeZone)
        let logicalDate = minute < 180
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date
        return localDateKey(logicalDate, timeZone: timeZone)
    }

    private static func clockMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }

    private static func toDaylineMinute(_ minute: Int) -> Int {
        let clock = clockMinute(minute)
        return clock < 180 ? clock + 1_440 : clock
    }

    private static func localDateKey(_ date: Date, timeZone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func minuteOfDay(_ date: Date, timeZone: String) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func comfortWindow(kcal: Double, fatG: Double, fibreG: Double = 0) -> ComfortWindow {
        if kcal >= 900 || fatG >= 35 || fibreG >= 18 {
            return ComfortWindow(load: "large", transitionAfterMinutes: 120, readyAfterMinutes: 240, fibreG: fibreG)
        }
        if kcal >= 600 || fatG >= 24 || fibreG >= 13 {
            return ComfortWindow(load: "substantial", transitionAfterMinutes: 90, readyAfterMinutes: 180, fibreG: fibreG)
        }
        if kcal >= 250 || fatG >= 10 || fibreG >= 7 {
            return ComfortWindow(load: "standard", transitionAfterMinutes: 45, readyAfterMinutes: 120, fibreG: fibreG)
        }
        return ComfortWindow(load: "light", transitionAfterMinutes: 25, readyAfterMinutes: 60, fibreG: fibreG)
    }

    static func zone(minutesSinceMeal: Int, window: ComfortWindow) -> ComfortZone {
        if minutesSinceMeal < window.transitionAfterMinutes { return .settling }
        if minutesSinceMeal < window.readyAfterMinutes { return .transition }
        return .ready
    }

    /// Resolves overlapping windows by load rather than by whichever meal was
    /// logged last. A snack may extend a larger meal's context, never shorten it.
    static func mergedComfortBands(_ anchors: [ComfortAnchor]) -> [ComfortBand] {
        let valid = anchors.filter {
            $0.window.transitionAfterMinutes > 0
                && $0.window.readyAfterMinutes > $0.window.transitionAfterMinutes
        }
        let boundaries = Set(valid.flatMap { anchor in
            [
                anchor.startMinute,
                anchor.startMinute + anchor.window.transitionAfterMinutes,
                anchor.startMinute + anchor.window.readyAfterMinutes,
            ]
        }).sorted()
        var bands: [ComfortBand] = []

        for (startMinute, endMinute) in zip(boundaries, boundaries.dropFirst()) {
            let zones = valid.compactMap { anchor -> ComfortZone? in
                let elapsed = startMinute - anchor.startMinute
                guard elapsed >= 0, elapsed < anchor.window.readyAfterMinutes else { return nil }
                return elapsed < anchor.window.transitionAfterMinutes ? .settling : .transition
            }
            let resolved: ComfortZone?
            if zones.contains(.settling) {
                resolved = .settling
            } else if zones.contains(.transition) {
                resolved = .transition
            } else {
                resolved = nil
            }
            guard let resolved else { continue }

            if let last = bands.indices.last,
               bands[last].zone == resolved,
               bands[last].endMinute == startMinute {
                bands[last].endMinute = endMinute
            } else {
                bands.append(ComfortBand(zone: resolved, startMinute: startMinute, endMinute: endMinute))
            }
        }
        return bands
    }

    static func fibre(forMeal mealID: UUID, entries: [LoggedFoodEntry]) -> Double {
        let total = entries
            .filter { $0.mealID == mealID }
            .reduce(0.0) { $0 + ($1.fibreG ?? 0) }
        return (total * 10).rounded() / 10
    }

    static func comfortWindow(for meal: LoggedMeal, entries: [LoggedFoodEntry]) -> ComfortWindow {
        comfortWindow(kcal: meal.totalKcal, fatG: meal.totalFatG, fibreG: fibre(forMeal: meal.id, entries: entries))
    }

    // MARK: - Post-workout timing

    /*
     * Eating within two hours of finishing scores full marks; after that the
     * score falls away gently rather than off a cliff, because a late meal is
     * still a meal.
     */
    static func recoveryTimingScore(gapMinutes: Int?) -> Int? {
        guard let gapMinutes, gapMinutes >= 0 else { return nil }
        if gapMinutes <= 120 { return 100 }
        if gapMinutes <= 180 { return Int((100 - Double(gapMinutes - 120) * 0.25).rounded()) }
        if gapMinutes <= 240 { return Int((85 - Double(gapMinutes - 180) * 0.25).rounded()) }
        return max(0, Int((70 - Double(gapMinutes - 240) * 0.2).rounded()))
    }

    struct PostWorkoutTiming: Sendable {
        let sessionID: UUID
        let date: String
        let completedAt: String
        let mealID: UUID?
        let mealName: String?
        let mealFinishedAt: String?
        let gapMinutes: Int?
        let timingScore: Int?
        /// "recorded_finish" when a meal followed, "missing" when none did.
        let source: String
    }

    struct WorkoutMealTiming: Sendable {
        let sessionID: UUID
        let date: String
        let startedAt: String
        let mealID: UUID?
        let mealName: String?
        let waitedMinutes: Int?
        let zone: ComfortZone?
    }

    struct Analysis: Sendable {
        var recordedMeals = 0
        var estimatedMeals = 0
        var workoutsWithContext = 0
        var readyStarts = 0
        var transitionStarts = 0
        var settlingStarts = 0
        var averageWaitMinutes: Int?
        var rhythmScore: Int?
        var typicalVariationMinutes: Int?
        var workoutRelations: [WorkoutMealTiming] = []
        var completedWorkouts = 0
        var recoveryMealsRecorded = 0
        var averageRecoveryGapMinutes: Int?
        var recoveryTimingScore: Int?
        var postWorkoutRelations: [PostWorkoutTiming] = []
    }

    private static func instant(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    /// Minutes past midnight in the person's own zone.
    private static func minuteOfDay(_ value: String, timeZone: String) -> Int? {
        guard let date = instant(value) else { return nil }
        return minuteOfDay(date, timeZone: timeZone)
    }

    private static func standardDeviation(_ values: [Int]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    static func postWorkoutNutrition(
        sessions: [WorkoutSession],
        meals: [LoggedMeal],
        timeZone: String
    ) -> [PostWorkoutTiming] {
        let completed = sessions
            .filter { $0.completed && $0.completedAt != nil }
            .sorted { (instant($0.completedAt) ?? .distantPast) < (instant($1.completedAt) ?? .distantPast) }

        return completed.compactMap { session -> PostWorkoutTiming? in
            guard let completedAt = session.completedAt, let finished = instant(completedAt) else { return nil }
            /* The next meal finished within six hours belongs to this session. */
            let following = meals
                .filter { $0.localDate == session.date }
                .compactMap { meal -> (LoggedMeal, Date)? in
                    guard let at = instant(meal.loggedAt) else { return nil }
                    let gap = at.timeIntervalSince(finished)
                    guard gap >= 0, gap <= 6 * 60 * 60 else { return nil }
                    return (meal, at)
                }
                .sorted { $0.1 < $1.1 }
                .first

            guard let (meal, at) = following else {
                return PostWorkoutTiming(
                    sessionID: session.id, date: session.date, completedAt: completedAt,
                    mealID: nil, mealName: nil, mealFinishedAt: nil,
                    gapMinutes: nil, timingScore: nil, source: "missing"
                )
            }
            let gapMinutes = max(0, Int((at.timeIntervalSince(finished) / 60).rounded()))
            return PostWorkoutTiming(
                sessionID: session.id, date: session.date, completedAt: completedAt,
                mealID: meal.id, mealName: meal.displayName, mealFinishedAt: meal.loggedAt,
                gapMinutes: gapMinutes, timingScore: recoveryTimingScore(gapMinutes: gapMinutes),
                source: "recorded_finish"
            )
        }
    }

    static func analyze(
        meals: [LoggedMeal],
        entries: [LoggedFoodEntry],
        sessions: [WorkoutSession],
        timeZone: String
    ) -> Analysis {
        var analysis = Analysis()

        /* A meal counts as recorded when its finish landed on its own day. */
        let recorded = meals.filter { meal in
            guard let at = instant(meal.loggedAt) else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
            let parts = calendar.dateComponents([.year, .month, .day], from: at)
            let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return key == meal.localDate
        }
        analysis.recordedMeals = recorded.count
        analysis.estimatedMeals = meals.count - recorded.count

        var byDate: [String: [LoggedMeal]] = [:]
        for meal in recorded { byDate[meal.localDate, default: []].append(meal) }
        for key in byDate.keys {
            byDate[key]?.sort { (instant($0.loggedAt) ?? .distantPast) < (instant($1.loggedAt) ?? .distantPast) }
        }

        for session in sessions {
            guard let startedAt = session.startedAt, let start = instant(startedAt) else { continue }
            let latest = (byDate[session.date] ?? [])
                .filter { (instant($0.loggedAt) ?? .distantFuture) <= start }
                .last
            guard let latest, let ate = instant(latest.loggedAt) else {
                analysis.workoutRelations.append(
                    WorkoutMealTiming(
                        sessionID: session.id, date: session.date, startedAt: startedAt,
                        mealID: nil, mealName: nil, waitedMinutes: nil, zone: nil
                    )
                )
                continue
            }
            let waited = max(0, Int((start.timeIntervalSince(ate) / 60).rounded()))
            analysis.workoutRelations.append(
                WorkoutMealTiming(
                    sessionID: session.id, date: session.date, startedAt: startedAt,
                    mealID: latest.id, mealName: latest.displayName, waitedMinutes: waited,
                    zone: zone(minutesSinceMeal: waited, window: comfortWindow(for: latest, entries: entries))
                )
            )
        }

        let contextual = analysis.workoutRelations.filter { $0.zone != nil }
        analysis.workoutsWithContext = contextual.count
        analysis.readyStarts = contextual.filter { $0.zone == .ready }.count
        analysis.transitionStarts = contextual.filter { $0.zone == .transition }.count
        analysis.settlingStarts = contextual.filter { $0.zone == .settling }.count
        let waits = contextual.compactMap(\.waitedMinutes)
        analysis.averageWaitMinutes = waits.isEmpty ? nil : Int((Double(waits.reduce(0, +)) / Double(waits.count)).rounded())

        /* How much a slot moves around from day to day, averaged over the
           slots that have enough history to say anything. */
        let variations = ["breakfast", "lunch", "dinner", "snack"].compactMap { slot -> Double? in
            let minutes = recorded
                .filter { $0.mealSlot == slot }
                .compactMap { minuteOfDay($0.loggedAt, timeZone: timeZone) }
            return standardDeviation(minutes)
        }
        if !variations.isEmpty {
            let typical = Int((variations.reduce(0, +) / Double(variations.count)).rounded())
            analysis.typicalVariationMinutes = typical
            analysis.rhythmScore = Int(max(0, min(100, (100 - Double(typical) * 0.9).rounded())))
        }

        let post = postWorkoutNutrition(sessions: sessions, meals: meals, timeZone: timeZone)
        analysis.postWorkoutRelations = post
        analysis.completedWorkouts = post.count
        let recordedRecovery = post.filter { $0.source == "recorded_finish" }
        analysis.recoveryMealsRecorded = recordedRecovery.count
        let gaps = recordedRecovery.compactMap(\.gapMinutes)
        analysis.averageRecoveryGapMinutes = gaps.isEmpty
            ? nil : Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
        let scores = recordedRecovery.compactMap(\.timingScore)
        analysis.recoveryTimingScore = scores.isEmpty
            ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())

        return analysis
    }
}
