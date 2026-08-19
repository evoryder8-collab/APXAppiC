import Foundation

/*
 * The meal blocks a day always has.
 *
 * A port of the defaults in src/lib/mealBlocks.ts. The web guarantees these
 * exist: whatever a person has configured is merged over a fixed set, so a day
 * always has its slots to fill even before anything is logged and even before
 * a schedule has been saved. The native Dayline had no such floor, so a fresh
 * day arrived with nothing on it at all.
 */
enum MealBlocks {
    struct Block: Identifiable, Hashable, Sendable {
        let id: String
        let kind: String
        var time: String
        var enabled: Bool

        var label: String {
            switch kind {
            case "breakfast": "Breakfast"
            case "lunch": "Lunch"
            case "dinner": "Dinner"
            case "snack": "Snack"
            case "post_workout": "Evening recovery"
            default: kind.capitalized
            }
        }
    }

    static let defaults: [Block] = [
        Block(id: "breakfast", kind: "breakfast", time: "07:00", enabled: true),
        Block(id: "lunch", kind: "lunch", time: "13:00", enabled: true),
        Block(id: "dinner", kind: "dinner", time: "19:00", enabled: true),
        Block(id: "snack", kind: "snack", time: "16:00", enabled: true),
        Block(id: "post_workout", kind: "post_workout", time: "21:00", enabled: true),
    ]

    private static func validClock(_ value: String?, fallback: String) -> String {
        guard let value, value.count == 5, value.dropFirst(2).first == ":" else { return fallback }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0..<24).contains(hours), (0..<60).contains(minutes)
        else { return fallback }
        return value
    }

    /// Stored settings merged over the defaults, so the set is always complete.
    static func normalized(_ value: JSONValue?) -> [Block] {
        let supplied = Dictionary(
            (value?.objectValue?["blocks"]?.arrayValue ?? [])
                .compactMap { item -> (String, [String: JSONValue])? in
                    guard let row = item.objectValue, let id = row["id"]?.stringValue else { return nil }
                    return (id, row)
                },
            uniquingKeysWith: { first, _ in first }
        )
        var blocks = defaults.map { fallback -> Block in
            let stored = supplied[fallback.id]
            return Block(
                id: fallback.id,
                kind: fallback.kind,
                time: validClock(stored?["time"]?.stringValue, fallback: fallback.time),
                enabled: stored?["enabled"]?.boolValue ?? fallback.enabled
            )
        }
        /* A day with every block switched off has nothing to log against, so
           the first one comes back on. */
        if !blocks.contains(where: \.enabled) { blocks[0].enabled = true }
        return blocks
    }

    static func enabled(_ value: JSONValue?) -> [Block] {
        normalized(value).filter(\.enabled).sorted { $0.time < $1.time }
    }
}
