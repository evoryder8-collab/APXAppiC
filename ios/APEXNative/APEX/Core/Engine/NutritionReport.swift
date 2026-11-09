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
    }

    enum Focus: Sendable, Equatable { case proteinLow, proteinHigh, caloriesLow, caloriesHigh, loggingGaps }

    let from: String
    let to: String
    let periodDays: Int
    let loggedDays: Int
    let macros: [Macro]
    let score: Int?
    let stars: Int
    let strengths: [Kind]
    let focus: [Focus]
    let waterLitres: Double
    let waterDays: Int

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
        var loggedDays = 0
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
            if ledger.drinkML > 0 { waterDays += 1 }

            guard let eaten = eaten(meals: mealsByDay[day] ?? [], log: logsByDay[day]), eaten.kcal > 0 else { continue }
            loggedDays += 1
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
                } else {
                    onTarget[kind, default: 0] += 1
                }
            }
        }

        guard loggedDays > 0 || drinkML > 0 else { return nil }

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
            loggedDays > 0 ? Double(onTarget[kind] ?? 0) / Double(loggedDays) : 0
        }

        let score: Int? = targets != nil && loggedDays >= minimumScoredDays
            ? Int((100 * scoreWeights.reduce(0) { $0 + $1.value * rate($1.key) }).rounded())
            : nil

        return NutritionReport(
            from: dates.lowerBound,
            to: dates.upperBound,
            periodDays: days.count,
            loggedDays: loggedDays,
            macros: macros,
            score: score,
            stars: score.map { Int((Double($0) / 20).rounded()) } ?? 0,
            strengths: targets == nil || loggedDays == 0 ? [] : Kind.allCases.filter { rate($0) >= 0.8 },
            focus: focus(macros: macros, loggedDays: loggedDays, periodDays: days.count),
            waterLitres: Double(drinkML) / 1_000,
            waterDays: waterDays
        )
    }

    private static func focus(macros: [Macro], loggedDays: Int, periodDays: Int) -> [Focus] {
        var result: [Focus] = []
        if loggedDays > 0, let protein = macros.first(where: { $0.kind == .protein }),
           let calories = macros.first(where: { $0.kind == .calories }),
           protein.target != nil {
            let proteinRate = Double(protein.onTargetDays) / Double(loggedDays)
            let caloriesRate = Double(calories.onTargetDays) / Double(loggedDays)
            if Double(protein.overDays) >= Double(loggedDays) / 2 { result.append(.proteinHigh) }
            if proteinRate < 0.7, protein.underDays > protein.overDays { result.append(.proteinLow) }
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
