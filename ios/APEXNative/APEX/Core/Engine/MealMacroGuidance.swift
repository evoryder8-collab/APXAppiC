import Foundation

/*
 * Port of src/lib/mealMacroGuidance.ts.
 *
 * A meal target is a distribution guide, not a medical ceiling, so what
 * counts as "over" depends on the person and the goal rather than on one
 * fixed number. A recomp keeps carbohydrate and fat distribution tighter; a
 * deliberate lean bulk is allowed a wider meal-to-meal range, because eating
 * more in one meal than another is how a bulk actually works.
 */
enum MealMacroGuidance {
    enum Macro: String, Sendable, CaseIterable {
        case protein, carbs, fat
    }

    enum State: String, Sendable {
        case below
        case reached
        case above
        case high
    }

    struct Status: Hashable, Sendable {
        let state: State
        /// Share of the meal guide reached, where 1 is exactly on it.
        let completion: Double
        /// Grams past the guide, never negative.
        let overBy: Double
        /// The point past which a meal reads as genuinely high.
        let upperGuide: Int
    }

    private static func upperMultiplier(persona: String, goal: String, macro: Macro) -> Double {
        if persona == "constantine", goal == "recomp" {
            return macro == .protein ? 1.4 : 1.15
        }
        if persona == "june", goal == "bulk" {
            return macro == .protein ? 1.55 : 1.4
        }
        if goal == "bulk" { return macro == .protein ? 1.5 : 1.35 }
        if goal == "recomp" { return macro == .protein ? 1.4 : 1.2 }
        return macro == .protein ? 1.45 : 1.25
    }

    static func status(
        value: Double,
        target: Double,
        macro: Macro,
        persona: String,
        goal: String
    ) -> Status {
        let safeTarget = max(1, target)
        let completion = max(0, value / safeTarget)
        let overBy = max(0, ((value - safeTarget) * 10).rounded() / 10)
        let upperGuide = Int((safeTarget * upperMultiplier(persona: persona, goal: goal, macro: macro)).rounded())
        let state: State
        if completion < 0.85 {
            state = .below
        } else if value <= safeTarget {
            state = .reached
        } else if value <= Double(upperGuide) {
            state = .above
        } else {
            state = .high
        }
        return Status(state: state, completion: completion, overBy: overBy, upperGuide: upperGuide)
    }
}
