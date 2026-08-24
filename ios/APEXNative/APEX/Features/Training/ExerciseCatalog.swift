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
