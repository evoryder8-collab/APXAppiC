import Foundation

/// What the Avatar report's nutrition page draws: eaten totals against today's targets,
/// a consistency score, and drinks logged. Every rule reuses one the app already applies.
struct NutritionReport: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable { case calories, protein, carbs, fat }

    struct Macro: Sendable, Equatable {
        let kind: Kind
        let average: Double
        let target: Double?
        let onTargetDays: Int
        let underDays: Int
        let overDays: Int
        /// Days that count toward the score. Eating more protein than the target is never a miss.
        var metDays: Int { kind == .protein ? onTargetDays + overDays : onTargetDays }
    }

    enum Focus: Sendable, Equatable { case proteinLow, caloriesLow, caloriesHigh, loggingGaps }

    /// One verdict for the score hero. Picked by the first matching rule in `verdictRules`.
    enum Verdict: String, Sendable, CaseIterable {
        case baseline, dialedIn, onTarget, proteinPro, onTheRise, slippingLately, weekendDrift
        case solidBase, gettingThere, findingRhythm, needsAttention
    }

    /// The facts the verdict rules read; `trend` and `weekendGap` are day-score differences, nil without enough days.
    struct VerdictInput: Sendable {
        var score: Int?
        var proteinRate = 0.0
        var trend: Double?
        var weekendGap: Double?
    }

    struct Creatine: Sendable, Equatable {
        /// Picked by the first matching rule in `badgeRules`.
        enum Badge: String, Sendable, CaseIterable {
            case freshStart, champ, lockedIn, onARoll, comeback, lapsed, weekendGaps, almostDaily, stopStart, buildTheStreak
        }
        let firstDay: String
        let takenDays: Int
        let trackedDays: Int
        let longestStreak: Int
        let currentStreak: Int
        let score: Int
        let badge: Badge
    }

    let from: String
    let to: String
    /// Calendar days from the first nutrition, water or creatine entry in the range to its end.
    let periodDays: Int
    /// Fully logged days; every average, day count and the score are based on these.
    let loggedDays: Int
    /// Days with some food logged but too few meals to judge the whole day.
    let partialDays: Int
    let macros: [Macro]
    let score: Int?
    let stars: Int
    let strengths: [Kind]
    let focus: [Focus]
    let waterLitres: Double
    let waterDays: Int
    let verdict: Verdict
    let creatine: Creatine?

    private static let verdictRules: [(Verdict, @Sendable (VerdictInput) -> Bool)] = [
        (.baseline, { $0.score == nil }),
        (.dialedIn, { ($0.score ?? 0) >= 90 }),
        (.onTarget, { ($0.score ?? 0) >= 80 }),
        (.proteinPro, { $0.proteinRate >= 0.9 }),
        (.onTheRise, { ($0.trend ?? 0) >= 15 }),
        (.slippingLately, { ($0.trend ?? 0) <= -15 }),
        (.weekendDrift, { ($0.weekendGap ?? 0) >= 25 }),
        (.solidBase, { ($0.score ?? 0) >= 65 }),
        (.gettingThere, { ($0.score ?? 0) >= 50 }),
        (.findingRhythm, { ($0.score ?? 0) >= 35 }),
        (.needsAttention, { _ in true }),
    ]

    static func verdict(_ input: VerdictInput) -> Verdict {
        verdictRules.first { $0.1(input) }?.0 ?? .needsAttention
    }

    private struct BadgeInput {
        let taken, tracked, longest, current, score, lastFortnight: Int
        let weekendMissShare: Double
    }

    private static let badgeRules: [(Creatine.Badge, @Sendable (BadgeInput) -> Bool)] = [
        (.freshStart, { $0.tracked < 14 }),
        (.champ, { $0.score >= 90 && $0.longest >= 21 }),
        (.lockedIn, { $0.score >= 85 }),
        (.onARoll, { $0.current >= 7 }),
        (.comeback, { $0.lastFortnight >= 12 && $0.score < 70 }),
        (.lapsed, { $0.lastFortnight == 0 }),
        (.weekendGaps, { $0.score >= 55 && $0.weekendMissShare >= 0.6 }),
        (.almostDaily, { $0.score >= 70 }),
        (.stopStart, { $0.longest <= 3 && $0.taken >= 6 }),
        (.buildTheStreak, { _ in true }),
    ]

    // Calories (0.90...1.10) and protein's floor (0.95) are the brain engine's hit rules.
    // The protein ceiling and the carbs and fat bands are display rules for this page.
    private static let bands: [Kind: ClosedRange<Double>] = [
        .calories: 0.90...1.10,
        .protein: 0.95...1.25,
        .carbs: 0.80...1.20,
        .fat: 0.80...1.20,
    ]
    private static let scoreWeights: [Kind: Double] = [.protein: 0.40, .calories: 0.30, .carbs: 0.15, .fat: 0.15]
    private static let minimumScoredDays = 7
    private static let fullDayMeals = 3
    // Stars step with the verdict tiers, so four stars always means a strong score.
    private static let starFloors = [90, 75, 55, 35, 15]
    private static let trendWindow = 14
    private static let bandTolerance = 1e-9

    private struct Eaten {
        var kcal = 0.0
        var values: [Kind: Double] = [:]
    }

    static func summarize(ownerID: UUID, data: DashboardData, dates: ClosedRange<String>) -> NutritionReport? {
        let days = dayKeys(dates)
        guard !days.isEmpty else { return nil }
        let inRange = Set(days)

        var mealsByDay: [String: [LoggedMeal]] = [:]
        for meal in data.loggedMeals where meal.userID == ownerID && inRange.contains(meal.localDate) {
            mealsByDay[meal.localDate, default: []].append(meal)
        }
        var logsByDay: [String: DailyLog] = [:]
        for log in data.dailyLogs where log.userID == ownerID && inRange.contains(log.date) {
            if logsByDay[log.date] == nil { logsByDay[log.date] = log }
        }
        var eventsByDay: [String: [HydrationEvent]] = [:]
        for event in data.hydrationEvents ?? [] where event.userID == ownerID && inRange.contains(event.localDate) {
            eventsByDay[event.localDate, default: []].append(event)
        }

        let targets = targets(ownerID: ownerID, data: data)
        var sums: [Kind: Double] = [:]
        var recorded: [Kind: Int] = [:]
        var onTarget: [Kind: Int] = [:]
        var under: [Kind: Int] = [:]
        var over: [Kind: Int] = [:]
        let settings = data.settings?.userID == ownerID ? data.settings : nil
        let expectedMeals = FitnessBrainService.mealRhythmHistory(from: settings?.addons).compactMapValues { $0.expectedMeals }
        var loggedDays = 0
        var partialDays = 0
        var firstEvidence: String?
        var dayScores: [(day: String, score: Double)] = []
        var drinkML = 0
        var waterDays = 0

        for day in days {
            let ledger = HydrationLedger.resolve(
                ownerID: ownerID,
                date: day,
                events: eventsByDay[day] ?? [],
                legacyDrinkLiters: logsByDay[day]?.waterL ?? 0
            )
            drinkML += ledger.drinkML
            if ledger.drinkML > 0 {
                waterDays += 1
                firstEvidence = firstEvidence ?? day
            }

            let meals = mealsByDay[day] ?? []
            guard let eaten = eaten(meals: meals, log: logsByDay[day]), eaten.kcal > 0 else { continue }
            firstEvidence = firstEvidence ?? day
            // The app does not penalise an incomplete diary, so a day with fewer meals than a full day
            // of eating is a partial log, not a day of under-eating. A manual daily total counts as full.
            guard meals.isEmpty || meals.count >= min(fullDayMeals, Int(expectedMeals[day] ?? Double(fullDayMeals))) else {
                partialDays += 1
                continue
            }
            loggedDays += 1
            var dayScore = 0.0
            for kind in Kind.allCases {
                guard let value = eaten.values[kind] else { continue }
                sums[kind, default: 0] += value
                recorded[kind, default: 0] += 1
                guard let target = targets?[kind], target > 0, let band = bands[kind] else { continue }
                let ratio = value / target
                if ratio < band.lowerBound - bandTolerance {
                    under[kind, default: 0] += 1
                } else if ratio > band.upperBound + bandTolerance {
                    over[kind, default: 0] += 1
                    if kind == .protein { dayScore += 100 * (scoreWeights[kind] ?? 0) }
                } else {
                    onTarget[kind, default: 0] += 1
                    dayScore += 100 * (scoreWeights[kind] ?? 0)
                }
            }
            dayScores.append((day, dayScore))
        }

        let creatine = creatine(ownerID: ownerID, data: data, days: days)
        guard loggedDays > 0 || partialDays > 0 || drinkML > 0 || creatine != nil else { return nil }
        // The period starts when the person started logging, not at an earlier training import.
        let started = [firstEvidence, creatine?.firstDay].compactMap { $0 }.min() ?? dates.lowerBound
        let periodDays = days.filter { $0 >= started }.count

        let macros = Kind.allCases.map { kind in
            Macro(
                kind: kind,
                average: (recorded[kind] ?? 0) > 0 ? sums[kind, default: 0] / Double(recorded[kind] ?? 1) : 0,
                target: targets?[kind],
                onTargetDays: onTarget[kind] ?? 0,
                underDays: under[kind] ?? 0,
                overDays: over[kind] ?? 0
            )
        }
        let rate = { (kind: Kind) -> Double in
            guard loggedDays > 0, let macro = macros.first(where: { $0.kind == kind }) else { return 0 }
            return Double(macro.metDays) / Double(loggedDays)
        }

        let score: Int? = targets != nil && loggedDays >= minimumScoredDays
            ? Int((100 * scoreWeights.reduce(0) { $0 + $1.value * rate($1.key) }).rounded())
            : nil

        return NutritionReport(
            from: started,
            to: dates.upperBound,
            periodDays: periodDays,
            loggedDays: loggedDays,
            partialDays: partialDays,
            macros: macros,
            score: score,
            stars: score.map { value in starFloors.filter { value >= $0 }.count } ?? 0,
            strengths: targets == nil || loggedDays == 0 ? [] : Kind.allCases.filter { rate($0) >= 0.8 },
            focus: focus(macros: macros, loggedDays: loggedDays, periodDays: periodDays),
            waterLitres: Double(drinkML) / 1_000,
            waterDays: waterDays,
            verdict: verdict(VerdictInput(
                score: score,
                proteinRate: rate(.protein),
                trend: trend(dayScores.map(\.score)),
                weekendGap: weekendGap(dayScores)
            )),
            creatine: creatine
        )
    }

    private static func average(_ values: some Collection<Double>) -> Double {
        values.reduce(0, +) / Double(max(1, values.count))
    }

    /// The last two weeks of logged days against everything logged before them.
    private static func trend(_ scores: [Double]) -> Double? {
        let earlier = scores.dropLast(trendWindow)
        guard earlier.count >= minimumScoredDays, scores.count - earlier.count >= minimumScoredDays else { return nil }
        return average(scores.suffix(trendWindow)) - average(earlier)
    }

    private static func weekendGap(_ scores: [(day: String, score: Double)]) -> Double? {
        let weekend = scores.filter { isWeekend($0.day) }.map(\.score)
        let weekdays = scores.filter { !isWeekend($0.day) }.map(\.score)
        guard weekend.count >= 4, weekdays.count >= 4 else { return nil }
        return average(weekdays) - average(weekend)
    }

    private static func isWeekend(_ day: String) -> Bool {
        let formatter = ISO8601DateFormatter.apexDateOnly
        guard let date = formatter.date(from: day) else { return false }
        return [1, 7].contains(formatter.calendar.component(.weekday, from: date))
    }

    /// Daily creatine, keyed on the day a check-off belongs to, so a past day ticked later still counts.
    private static func creatine(ownerID: UUID, data: DashboardData, days: [String]) -> Creatine? {
        let ids = Set(data.supplements.filter {
            $0.userID == ownerID && !$0.trainingDaysOnly && isCreatine($0.name)
        }.map(\.id))
        let inRange = Set(days)
        let taken = Set(data.supplementLogs.filter {
            $0.userID == ownerID && ids.contains($0.supplementID) && inRange.contains($0.date)
        }.map(\.date))
        guard let first = taken.min() else { return nil }
        var tracked = days.filter { $0 >= first }
        // The range's last day can still be ticked, so while it is open it is not a miss: not for the streak, the score or the day count.
        if let last = tracked.last, !taken.contains(last) { tracked.removeLast() }
        var longest = 0, run = 0
        for day in tracked {
            run = taken.contains(day) ? run + 1 : 0
            longest = max(longest, run)
        }
        let current = tracked.reversed().prefix { taken.contains($0) }.count
        let missed = tracked.filter { !taken.contains($0) }
        let score = Int((100 * Double(taken.count) / Double(tracked.count)).rounded())
        let input = BadgeInput(
            taken: taken.count, tracked: tracked.count, longest: longest, current: current, score: score,
            lastFortnight: days.suffix(trendWindow).filter(taken.contains).count,
            weekendMissShare: missed.isEmpty ? 0 : Double(missed.filter(isWeekend).count) / Double(missed.count)
        )
        return Creatine(
            firstDay: first, takenDays: taken.count, trackedDays: tracked.count, longestStreak: longest, currentStreak: current,
            score: score, badge: badgeRules.first { $0.1(input) }?.0 ?? .buildTheStreak
        )
    }

    private static func isCreatine(_ name: String) -> Bool {
        // The catalogue has no Japanese or Thai aliases, so those spellings are matched by name.
        SupplementCatalogue.search(name, limit: 1).first?.id == "creatine_monohydrate"
            || name.contains("クレアチン") || name.contains("ครีเอทีน")
    }

    private static func focus(macros: [Macro], loggedDays: Int, periodDays: Int) -> [Focus] {
        var result: [Focus] = []
        if loggedDays > 0, let protein = macros.first(where: { $0.kind == .protein }),
           let calories = macros.first(where: { $0.kind == .calories }),
           protein.target != nil {
            let proteinRate = Double(protein.metDays) / Double(loggedDays)
            let caloriesRate = Double(calories.metDays) / Double(loggedDays)
            // Only when the average is short too, so the card never contradicts the ring above it.
            if proteinRate < 0.7, protein.average < (protein.target ?? 0) { result.append(.proteinLow) }
            if caloriesRate < 0.7 { result.append(calories.underDays > calories.overDays ? .caloriesLow : .caloriesHigh) }
        }
        if Double(loggedDays) < 0.6 * Double(periodDays) { result.append(.loggingGaps) }
        return Array(result.prefix(2))
    }

    /// Same fallback as the Nutrition screen: logged meals win, the daily log fills in otherwise.
    private static func eaten(meals: [LoggedMeal], log: DailyLog?) -> Eaten? {
        if !meals.isEmpty {
            let kcal = meals.reduce(0) { $0 + $1.totalKcal }
            return Eaten(kcal: kcal, values: [
                .calories: kcal,
                .protein: meals.reduce(0) { $0 + $1.totalProteinG },
                .carbs: meals.reduce(0) { $0 + $1.totalCarbsG },
                .fat: meals.reduce(0) { $0 + $1.totalFatG },
            ])
        }
        guard let log else { return nil }
        var values: [Kind: Double] = [:]
        if let kcal = log.kcal { values[.calories] = Double(kcal) }
        if let protein = log.proteinG { values[.protein] = Double(protein) }
        if let carbs = log.carbsG { values[.carbs] = Double(carbs) }
        if let fat = log.fatG { values[.fat] = Double(fat) }
        return Eaten(kcal: values[.calories] ?? 0, values: values)
    }

    /// Calories and macros do not vary by day, so no activity is passed. Targets are not
    /// stored per day, so the whole period is judged against today's.
    private static func targets(ownerID: UUID, data: DashboardData) -> [Kind: Double]? {
        guard let profile = data.profile, profile.userID == ownerID else { return nil }
        let settings = data.settings?.userID == ownerID ? data.settings : nil
        let result = EnergyEngine.targets(
            profile: profile,
            logs: [],
            catalog: [],
            planContext: NutritionGoalPolicy.context(from: settings),
            settings: settings,
            wearableActiveCalories: nil
        )
        guard result.isPublishable else { return nil }
        return [
            .calories: Double(result.targetCalories),
            .protein: Double(result.proteinG),
            .carbs: Double(result.carbsG),
            .fat: Double(result.fatG),
        ]
    }

    private static func dayKeys(_ dates: ClosedRange<String>) -> [String] {
        let formatter = ISO8601DateFormatter.apexDateOnly
        guard var day = formatter.date(from: dates.lowerBound),
              let last = formatter.date(from: dates.upperBound) else { return [] }
        var keys: [String] = []
        while day <= last {
            keys.append(formatter.string(from: day))
            guard let next = formatter.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }
}
