import Foundation

struct AdaptiveMeal: Identifiable, Equatable, Sendable {
    let source: Meal
    let kcal: Int
    let proteinG: Int
    let fatG: Int
    let carbsG: Int
    let portionNote: String

    var id: UUID { source.id }
}

enum AdaptiveMealPlanEngine {
    static func build(
        meals: [Meal],
        targets: NutritionTargets,
        dayLabel: String
    ) -> [AdaptiveMeal] {
        guard !meals.isEmpty, targets.isPublishable else { return [] }
        let ordered = meals.sorted { $0.sortOrder < $1.sortOrder }
        let referenceProtein = max(1, ordered.reduce(0) { $0 + $1.proteinG })
        let referenceFat = max(1, ordered.reduce(0) { $0 + $1.fatG })
        let referenceCarbs = max(1, ordered.reduce(0) { $0 + $1.carbsG })
        let proteinScale = min(1.25, max(0.65, Double(targets.proteinG) / Double(referenceProtein)))
        let fatScale = min(1.4, max(0.45, Double(targets.fatG) / Double(referenceFat)))
        let carbScale = min(1.6, max(0.4, Double(targets.carbsG) / Double(referenceCarbs)))

        let kcal = allocate(total: targets.targetCalories, weights: ordered.map(\.kcal))
        let protein = allocate(total: targets.proteinG, weights: ordered.map(\.proteinG))
        let fat = allocate(total: targets.fatG, weights: ordered.map(\.fatG))
        let carbs = allocate(total: targets.carbsG, weights: ordered.map(\.carbsG))

        return ordered.indices.map { index in
            let meal = ordered[index]
            return AdaptiveMeal(
                source: meal,
                kcal: kcal[index],
                proteinG: protein[index],
                fatG: fat[index],
                carbsG: carbs[index],
                portionNote: note(
                    for: meal,
                    dayLabel: dayLabel,
                    proteinScale: proteinScale,
                    fatScale: fatScale,
                    carbScale: carbScale
                )
            )
        }
    }

    private static func allocate(total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let positiveTotal = weights.reduce(0) { $0 + max(0, $1) }
        if positiveTotal == 0 {
            let even = total / weights.count
            return weights.indices.map { even + ($0 < total - even * weights.count ? 1 : 0) }
        }
        let exact = weights.map { Double(total * max(0, $0)) / Double(positiveTotal) }
        var result = exact.map { Int(floor($0)) }
        let remaining = total - result.reduce(0, +)
        let order = exact.indices.sorted {
            let left = exact[$0] - floor(exact[$0])
            let right = exact[$1] - floor(exact[$1])
            return left == right ? $0 < $1 : left > right
        }
        if remaining > 0 {
            for offset in 0..<remaining { result[order[offset % order.count]] += 1 }
        }
        return result
    }

    private static func note(
        for meal: Meal,
        dayLabel: String,
        proteinScale: Double,
        fatScale: Double,
        carbScale: Double
    ) -> String {
        let key = meal.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "oat jar", let base = grams(of: "oats", in: meal.foods) {
            return "\(dayLabel) day: oats \(stepped(base, scale: carbScale, step: 5, minimum: 35)) g instead of \(base) g."
        }
        if key == "bulgur snack", let base = grams(of: "bulgur", in: meal.foods) {
            return "\(dayLabel) day: dry bulgur \(stepped(base, scale: carbScale, step: 5, minimum: 35)) g instead of \(base) g."
        }
        if key == "dinner", let base = grams(of: "sweet potato", in: meal.foods) {
            return "\(dayLabel) day: sweet potato \(stepped(base, scale: carbScale, step: 25, minimum: 150)) g instead of \(base) g."
        }
        if key == "breakfast", let base = grams(of: "nut mix", in: meal.foods) ?? grams(of: "walnuts", in: meal.foods) {
            return "\(dayLabel) day: protein stays pinned; nut mix adjusts to \(stepped(base, scale: fatScale, step: 5, minimum: 15)) g."
        }
        if key == "casein shake" {
            let base = grams(of: "casein", in: meal.foods) ?? 45
            return "\(dayLabel) day: casein remains protein-led at \(stepped(base, scale: proteinScale, step: 5, minimum: 25)) g."
        }
        return "\(dayLabel) day: carbohydrate portions move first; protein moves last."
    }

    private static func grams(of ingredient: String, in text: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: ingredient)
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*g\s+(?:dry\s+)?"# + escaped
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let amount = Double(text[range])
        else { return nil }
        return Int(amount.rounded())
    }

    private static func stepped(_ base: Int, scale: Double, step: Int, minimum: Int) -> Int {
        max(minimum, Int((Double(base) * scale / Double(step)).rounded()) * step)
    }
}
