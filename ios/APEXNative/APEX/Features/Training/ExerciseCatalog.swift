import Foundation

/*
 * The searchable movement library behind the custom workout builder.
 *
 * Generated from the web's src/data/exerciseCatalog.ts by
 * Tools/generate-exercise-catalog.mts, so the two platforms offer the same
 * movements with the same defaults and the same translations. Regenerate
 * after editing the web catalogue rather than editing this data by hand.
 */
struct ExerciseCatalogItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let movementID: String
    let name: String
    let category: String
    let categories: [String]
    let equipment: String
    let muscles: [String]
    let dayType: String
    let sets: Int
    let reps: Int
    let rest: Int
    let unit: String
    let perSide: Bool
    let loadable: Bool
    let incrementKG: Double
    let names: [String: String]
    let aliases: [String: [String]]

    /// The person's own language, falling back to the catalogue name.
    func localizedName(_ language: AppLanguage) -> String {
        names[language.rawValue] ?? name
    }

    /// Matches on the display name and on every alias in every language, so
    /// "flotari" finds push-ups whichever language the app is set to.
    func matches(_ query: String, language: AppLanguage) -> Bool {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard !needle.isEmpty else { return true }
        var haystack = [id, movementID, name, equipment, localizedName(language)]
        haystack.append(contentsOf: names.values)
        haystack.append(contentsOf: aliases.values.flatMap { $0 })
        haystack.append(contentsOf: muscles)
        haystack.append(contentsOf: categories)
        return haystack.contains {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(needle)
        }
    }
}

struct ExerciseCatalogCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

enum ExerciseCatalog {
    private struct Payload: Codable {
        let categories: [ExerciseCatalogCategory]
        let categoryOrders: [String: [String]]
        let exercises: [ExerciseCatalogItem]
    }

    private static let payload: Payload = {
        guard let url = Bundle.main.url(forResource: "exercise-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            /* An empty catalogue still lets the builder open and explain
               itself, rather than taking the screen down with it. */
            return Payload(categories: [], categoryOrders: [:], exercises: [])
        }
        return decoded
    }()

    static var all: [ExerciseCatalogItem] { payload.exercises }
    static var categories: [ExerciseCatalogCategory] { payload.categories }

    private static let movementIDsByName: [String: String] = {
        var names: [String: String] = [:]
        for item in all {
            let labels = [item.id, item.movementID, item.name] + Array(item.names.values) + item.aliases.values.flatMap { $0 }
            for label in labels {
                let key = lookupKey(label)
                if names[key] == nil { names[key] = item.movementID }
            }
        }
        return names
    }()

    static func movementID(matchingName name: String) -> String? {
        movementIDsByName[lookupKey(name)]
    }

    private static func lookupKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private static let artworkIDs = Set(all.map(\.movementID))

    // Search aliases include substitutions like “Any 10-min HIIT video” → Burpee.
    // Only exact catalog names and verified names from legacy programmes identify a photo.
    private static let artworkIDsByName: [String: Set<String>] = {
        var names: [String: Set<String>] = [:]
        for item in all {
            for label in [item.name, item.name + "s"] + Array(item.names.values) {
                names[lookupKey(label), default: []].insert(item.movementID)
            }
        }
        for (name, id) in [
            "Weighted backpack push-up": "weighted_push_up",
            "Strict Bodyweight Push-Up": "push_up",
            "Strict Push-Up": "push_up",
            "Strict Push-Up Max Test": "push_up",
            "Strict Push-Up Back-Off at 60–70%": "push_up",
            "Weighted Push-Up Back-Off": "weighted_push_up",
            "Weighted Dumbbell Hip Thrust": "hip_thrust_dumbbell",
            "Dumbbell Overhead Press": "dumbbell_overhead_press",
            "Dumbbell lateral raise": "lateral_raise",
            "Backpack RDL": "backpack_rdl",
            "Band Pull-Aparts (finisher if fresh)": "band_pull_apart",
            "Band Pull-Aparts (posture closer)": "band_pull_apart",
            "Diamond Pushups": "diamond_push_up",
            "Weighted Pushups": "weighted_push_up",
            "Thoracic Extension over chair edge": "thoracic_extension",
            "One-Arm Supported Dumbbell Row": "one_arm_dumbbell_row",
            "Front Lunge": "forward_lunge",
        ] {
            names[lookupKey(name), default: []].insert(id)
        }
        return names
    }()

    // Some historical programme rows use a logging substitute or offer a choice.
    // The single photo on that ID would prescribe a different variant or apparatus.
    private static let unillustratedPrescriptions = Set([
        "Band Abduction", "Band-Assisted Chin-Up", "Gimbal Front Hold", "Posture and Wrist Circuit",
        "B-Stance or Single-Leg Hip Thrust", "Single-Leg or B-Stance Hip Thrust",
        "Weighted or Feet-Elevated Push-Up", "Diamond or Close-Grip Push-Up", "Suitcase Hold or March",
        "Any 10-min HIIT video", "FocusT25 session (Shaun T), Alpha or Beta cycle",
        "Functional stretch flow (saved YouTube favorite)", "Band or DB Curls", "Hammer or Incline DB Curls",
        "Bulgarian Split Squat (backpack)", "Calf Raises (backpack, off a step)", "Calf Raises (single-leg or backpack)",
        "Heel-Elevated Goblet Squat (backpack)", "Pike Pushups (feet on chair)", "Pull-Ups (different grip than Wed)",
        "Walking Lunges (backpack)", "Weighted Pushups (handles, backpack)", "Sliding Leg Curl (towel)",
    ].map(lookupKey))

    static func artworkMovementID(for exercise: Exercise) -> String? {
        if let id = exercise.movementID {
            guard artworkIDs.contains(id), !FocusT25.isFocusName(exercise.name),
                  !unillustratedPrescriptions.contains(lookupKey(exercise.name)) else { return nil }
            return id
        }
        if artworkIDs.contains(exercise.name) { return exercise.name }
        let matches = artworkIDsByName[lookupKey(exercise.name)]
        return matches?.count == 1 ? matches?.first : nil
    }

    static func search(_ query: String, category: String, language: AppLanguage) -> [ExerciseCatalogItem] {
        let matches = all.filter { item in
            (category == "all" || item.categories.contains(category)) && item.matches(query, language: language)
        }
        guard let order = payload.categoryOrders[category] else { return matches }
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return matches.sorted { left, right in
            (ranks[left.id] ?? Int.max) < (ranks[right.id] ?? Int.max)
        }
    }
}
