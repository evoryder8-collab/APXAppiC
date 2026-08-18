import Foundation

/*
 * The predefined list behind each meal.
 *
 * A port of the athlete support protocol and the goal scaling the web applies
 * to it. The list doubles as a shopping list and as something to eat when the
 * decision itself is the hard part, and a person can rewrite it: an edited list
 * is stored per persona, slot, goal and language, and replaces the default from
 * then on.
 */
enum MealProtocolGuide {
    /// A guide line resolved into something the food search can act on.
    struct Query: Identifiable, Hashable {
        let line: String
        var id: String { line }

        var search: String { MealProtocolGuide.foodQuery(line).query }
        var quantity: Double { MealProtocolGuide.foodQuery(line).quantity }
        var unit: String { MealProtocolGuide.foodQuery(line).unit }
    }

    struct ProtocolMeal: Sendable {
        let time: String
        let name: String
        let foods: [String]
    }

    /// Slot order inside a persona's protocol.
    private static let slotIndex: [String: Int] = [
        "breakfast": 0, "lunch": 1, "snack": 2, "dinner": 3,
    ]

    static let protocols: [String: [ProtocolMeal]] = [
        "constantine": [
            ProtocolMeal(time: "07:00", name: "Overnight oat jar", foods: [
                "70 g organic whole-grain oats",
                "250 ml Migros Oh! protein-rich milk",
                "20 g LeeSport unflavoured whey isolate",
                "100 g berries",
                "1 kiwi",
                "15 g walnuts",
                "10-15 g seed blend",
                "5 g coconut flakes",
                "Optional boiled egg",
            ]),
            ProtocolMeal(time: "13:00", name: "Lunch", foods: [
                "70 g dry bulgur",
                "10 g EVOO",
                "Cherry tomatoes",
                "Raw spring onion",
                "Vegetables",
                "150 g saved protein or whey providing 35-40 g protein",
            ]),
            ProtocolMeal(time: "15:30", name: "Snack", foods: [
                "1 banana or another saved fruit",
            ]),
            ProtocolMeal(time: "19:15", name: "Dinner", foods: [
                "300 g sweet potato, cooked",
                "150 g chicken breast, cooked",
                "100 g mixed vegetables, cooked",
                "10 g extra virgin olive oil",
                "Iodized salt",
            ]),
        ],
        "june": [
            ProtocolMeal(time: "07:00", name: "Overnight oat jar", foods: [
                "65 g oats",
                "250 ml Migros Oh! protein-rich milk",
                "10 g whey isolate when useful",
                "100 g berries",
                "1 kiwi",
                "15 g walnuts",
                "15 g seed blend",
            ]),
            ProtocolMeal(time: "13:00", name: "Lunch", foods: [
                "75 g dry bulgur",
                "10-15 g EVOO",
                "Tomatoes",
                "Spring onion",
                "Vegetables",
                "100-120 g saved protein or whey providing 25-30 g protein",
                "Optional half avocado with a lean protein",
            ]),
            ProtocolMeal(time: "15:30", name: "Snack", foods: [
                "1 banana or another saved fruit",
            ]),
            ProtocolMeal(time: "19:15", name: "Dinner", foods: [
                "300 g sweet potato, cooked",
                "110 g salmon fillet, cooked",
                "100 g mixed vegetables, cooked",
                "10 g extra virgin olive oil",
                "70 g avocado with a lean protein",
            ]),
        ],
    ]

    /* Only the staples scale with the goal; a kiwi is a kiwi at any calorie
       target. Amounts round to the nearest five so the list stays weighable. */
    private static let scalableTerms = [
        "oat", "oats", "bulgur", "sweet potato", "rice", "evoo",
        "walnut", "walnuts", "seed", "seeds", "protein", "whey",
    ]

    static func goalAdjusted(_ line: String, persona: String, goal: String) -> String {
        let scale: Double = persona == "june"
            ? (goal == "recomp" ? 0.85 : (goal == "maintain" ? 0.93 : 1))
            : (goal == "bulk" ? 1.1 : (goal == "maintain" ? 1.04 : 1))
        let lowered = line.lowercased()
        guard scale != 1, scalableTerms.contains(where: { lowered.contains($0) }) else { return line }

        let pattern = #"^(\d+)(?:-(\d+))?\s*(g|ml)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return line }

        func value(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return Int(line[range])
        }
        guard let lowValue = value(1),
              let unitRange = Range(match.range(at: 3), in: line)
        else { return line }
        let unit = String(line[unitRange])

        func rounded(_ raw: Int) -> Int {
            max(1, Int((Double(raw) * scale / 5).rounded()) * 5)
        }
        let low = rounded(lowValue)
        let high = value(2).map(rounded)
        let amount = (high != nil && high! != low) ? "\(low)-\(high!)" : "\(low)"

        guard let full = Range(match.range, in: line) else { return line }
        return line.replacingCharacters(in: full, with: "\(amount) \(unit)")
    }

    /// The key an edited list is stored under, so a change to one meal on one
    /// goal does not silently rewrite the others.
    static func overrideKey(persona: String, slot: String, goal: String, language: String) -> String {
        "\(persona):\(slot):\(goal):\(language)"
    }

    /// The list to show: the person's own edit when there is one, otherwise the
    /// protocol adjusted for the goal they are on.
    static func lines(
        persona: String,
        slot: String,
        goal: String,
        language: String,
        overrides: [String: JSONValue]?
    ) -> [String] {
        let key = overrideKey(persona: persona, slot: slot, goal: goal, language: language)
        if let saved = overrides?[key]?.arrayValue?.compactMap(\.stringValue), !saved.isEmpty {
            return saved
        }
        guard let index = slotIndex[slot],
              let meals = protocols[persona],
              index < meals.count
        else { return [] }
        return meals[index].foods.map { goalAdjusted($0, persona: persona, goal: goal) }
    }

    /*
     * A guide line points at a food and an amount. "300 g sweet potato, cooked"
     * searches for sweet potato at 300 g; a line with no number is a nudge
     * rather than a measurement, so it opens the search at a round 100 g.
     */
    static func foodQuery(_ line: String) -> (query: String, quantity: Double, unit: String) {
        func strippedTail(_ value: String) -> String {
            value.replacingOccurrences(
                of: #"\s+(?:when|or|according|providing|with)\b.*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespaces)
        }

        let ranged = #"^(\d+)(?:-(\d+))?\s*(g|ml)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: ranged, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            func part(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: line) else { return nil }
                return String(line[range])
            }
            let low = Double(part(1) ?? "0") ?? 0
            let high = part(2).flatMap(Double.init) ?? low
            return (
                strippedTail(part(4) ?? ""),
                ((low + high) / 2).rounded(),
                (part(3) ?? "g").lowercased()
            )
        }

        if let regex = try? NSRegularExpression(pattern: #"^1\s+(.+)$"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            let name = String(line[range]).replacingOccurrences(
                of: #"\s+or\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespaces)
            return (name, 1, "piece")
        }

        let plain = line
            .replacingOccurrences(of: #"^Optional\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+or\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return (plain, 100, "g")
    }
}
