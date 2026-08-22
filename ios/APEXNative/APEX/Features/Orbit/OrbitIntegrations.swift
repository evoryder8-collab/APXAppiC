import Foundation

struct OrbitNutritionAdjustment: Hashable, Sendable {
    let kcal: Int
    let carbsG: Int
    let proteinG: Int
    let fatG: Int
    let timing: String
    let explanation: String
}

struct OrbitFoodMemorySuggestion: Hashable, Sendable {
    let food: Food
    let amount: Double
    let unit: String
    let nutrients: FoodNutrients
}

struct OrbitTrainingAdjustment: Hashable, Sendable {
    let action: String
    let explanation: String
    let reversible: Bool
}

struct OrbitAvatarContribution: Hashable, Sendable {
    let enduranceMinutes: Int
    let jointSignal: Double
    let lowerBodySignal: Double
    let pacingDisciplineSignal: Double
    let explanation: String
}

enum OrbitIntegrations {
    /// Builds the same immutable structured meal record used by Nutrition.
    static func nutritionMealDraft(
        run: OrbitRunRecord,
        suggestion: OrbitFoodMemorySuggestion?
    ) -> MealComposerDraft? {
        guard let suggestion, UUID(uuidString: suggestion.food.id) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        let finishedAt = formatter.date(from: run.endedAt) ?? formatter.date(from: run.updatedAt) ?? .now
        return MealComposerDraft(
            id: APEXStableID.scopedUUID(namespace: "orbit-nutrition:\(run.id.uuidString.lowercased())", date: run.localDate, userID: run.userID),
            localDate: run.localDate, mealSlot: "post-workout", displayName: "Orbit recovery",
            finishedAt: finishedAt, sourcePresetID: nil, sourcePlannedMealID: nil,
            replaceMealID: nil, loggedAs: "custom",
            items: [MealComposerItem(food: suggestion.food, quantity: suggestion.amount, unit: suggestion.unit)]
        )
    }

    /// Replaces only the deterministic integration row for this Orbit run.
    static func reconciledActivityLogs(existing: [ActivityLog], generated: ActivityLog) -> [ActivityLog] {
        var result = existing.filter { $0.id != generated.id }
        result.append(generated)
        return result
    }

    static func nutritionAdjustment(run: OrbitRunRecord, weightKG: Double) -> OrbitNutritionAdjustment {
        let durationMinutes = (run.metrics["moving_s"]?.numberValue ?? 0) / 60
        if durationMinutes < 60 {
            return .init(
                kcal: 0, carbsG: 0, proteinG: 0, fatG: 0,
                timing: "normal_meals",
                explanation: "This run fits inside the normal daily meal pattern. Orbit does not add food automatically."
            )
        }
        if durationMinutes < 90 {
            let carbs = Int(min(45, weightKG * 0.5).rounded())
            return .init(
                kcal: carbs * 4, carbsG: carbs, proteinG: 0, fatG: 0,
                timing: "pre_and_post",
                explanation: "Optional \(carbs) g carbohydrate adjustment around the run. Review the exact change before applying it."
            )
        }
        let duringHours = max(0, durationMinutes / 60 - 1)
        let carbs = Int(min(120, 30 + duringHours * 35).rounded())
        let protein = Int(min(30, max(20, weightKG * 0.3)).rounded())
        return .init(
            kcal: carbs * 4 + protein * 4,
            carbsG: carbs, proteinG: protein, fatG: 0,
            timing: "during_and_recovery",
            explanation: "Long-run rehearsal: \(carbs) g carbohydrate across familiar pre-run, during-run and recovery foods, plus \(protein) g recovery protein. Nothing changes until you apply it."
        )
    }

    static func foodMemorySuggestion(
        adjustment: OrbitNutritionAdjustment,
        foods: [Food],
        preferences: [FoodPreference]
    ) -> OrbitFoodMemorySuggestion? {
        guard adjustment.carbsG > 0 else { return nil }
        let preferencesByFood = Dictionary(uniqueKeysWithValues: preferences.map { ($0.foodID, $0) })
        let candidates = foods.filter { food in
            guard food.kcal100 != nil, food.protein100 != nil,
                  let carbs = food.carbs100, food.fat100 != nil,
                  carbs >= 20
            else { return false }
            guard let id = UUID(uuidString: food.id) else { return false }
            return preferencesByFood[id]?.hidden != true
        }
        .sorted { lhs, rhs in
            let left = UUID(uuidString: lhs.id).flatMap { preferencesByFood[$0] }
            let right = UUID(uuidString: rhs.id).flatMap { preferencesByFood[$0] }
            if (left?.favourite ?? false) != (right?.favourite ?? false) {
                return left?.favourite == true
            }
            return (left?.usageCount ?? 0) > (right?.usageCount ?? 0)
        }
        guard let food = candidates.first,
              let carbsPer100 = food.carbs100,
              carbsPer100 > 0
        else { return nil }
        let amount = max(5, (Double(adjustment.carbsG) / carbsPer100 * 100 / 5).rounded() * 5)
        let unit = food.nutritionBasis == "per_100ml" ? "ml" : "g"
        return .init(food: food, amount: amount, unit: unit, nutrients: food.nutrients(forEquivalentAmount: amount))
    }

    static func trainingAdjustment(
        run: OrbitRunRecord,
        sessions: [WorkoutSession],
        programDays: [ProgramDay]
    ) -> OrbitTrainingAdjustment {
        let effort = run.checkIn["perceived_effort"]?.numberValue ?? 0
        let legs = run.checkIn["legs"]?.stringValue ?? ""
        let duration = run.metrics["moving_s"]?.numberValue ?? 0
        let highCost = effort >= 8 || legs == "very_heavy" || duration >= 120 * 60
        guard highCost else {
            return .init(action: "none", explanation: "The run does not require a strength-programme change.", reversible: true)
        }
        let dayTypes = Dictionary(uniqueKeysWithValues: programDays.map { ($0.id, $0.dayType) })
        let nextLower = sessions
            .filter { $0.date > run.localDate && ["legs_a", "legs_b"].contains(dayTypes[$0.programDayID] ?? "") }
            .sorted { $0.date < $1.date }
            .first
        guard let nextLower else {
            return .init(
                action: "replace_next_quality_with_easy",
                explanation: "The run carried high recovery cost. Orbit proposes easy running next instead of another demanding run.",
                reversible: true
            )
        }
        return .init(
            action: "protect_next_lower",
            explanation: "The run carried high recovery cost and the next lower-body session is \(nextLower.date). Orbit proposes protecting that session rather than silently moving it.",
            reversible: true
        )
    }

    static func avatarContribution(run: OrbitRunRecord) -> OrbitAvatarContribution {
        let minutes = Int(((run.metrics["moving_s"]?.numberValue ?? 0) / 60).rounded())
        let paces: [Double]
        if case .array(let values)? = run.metrics["splits"] {
            paces = values.compactMap { value in
                guard let object = value.objectValue,
                      (object["distance_m"]?.numberValue ?? 0) >= 900
                else { return nil }
                return object["pace_sec_km"]?.numberValue
            }
        } else {
            paces = []
        }
        let mean = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
        let variation: Double
        if let mean, mean > 0, paces.count >= 2 {
            variation = sqrt(paces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(paces.count)) / mean
        } else {
            variation = 0
        }
        return .init(
            enduranceMinutes: minutes,
            jointSignal: run.checkIn["discomfort"]?.stringValue == "none" ? min(1, Double(minutes) / 90) : 0,
            lowerBodySignal: min(1, Double(minutes) / 75),
            pacingDisciplineSignal: variation > 0 ? max(0, 1 - variation * 8) : 0,
            explanation: "Orbit contributes \(minutes) recorded endurance minutes. The Avatar receives one authoritative endurance record, not raw GPS points."
        )
    }
}
