import Foundation

/// The supplement catalogue, and a search that forgives how it is typed.
///
/// People do not spell these. "ashwaganda", "citruline", "kreatine" and "alpha
/// gpc" all have to find the right row, because a picker that only matches
/// exact prefixes is slower than typing the name in by hand -- which is what
/// it is replacing.
///
/// Matching runs in tiers so the ordering stays predictable: an exact name or
/// alias first, then a prefix, then a contained substring, then an approximate
/// match by edit distance. Within a tier, shorter names win, so "Creatine
/// Monohydrate" beats a longer entry that merely contains the word.
enum SupplementCatalogue {
    struct Entry: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let aliases: [String]
        let category: String
        let doses: [Double]
        let unit: String
        let evidence: String
        let summary: String
        let timing: String

        /// How well supported this is, said plainly. A catalogue that presents
        /// tribulus and creatine identically is not being straight with anyone.
        var evidenceLabel: String {
            switch evidence {
            case "strong": return "Strong evidence"
            case "moderate": return "Moderate evidence"
            case "limited": return "Limited evidence"
            default: return "Not supported by evidence"
            }
        }

        func formattedDose(_ value: Double) -> String {
            let rounded = value.rounded()
            let number = value == rounded
                ? String(Int(rounded))
                : String(format: "%.1f", value)
            return "\(number) \(unit)"
        }
    }

    private struct Payload: Decodable {
        let categories: [String]
        let supplements: [Entry]
    }

    private static let payload: Payload = {
        guard let url = Bundle.main.url(forResource: "supplement-catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload(categories: [], supplements: []) }
        return decoded
    }()

    static var all: [Entry] { payload.supplements }
    static var categories: [String] { payload.categories }

    private static func normalise(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Levenshtein distance, capped: past the limit the exact figure does not
    /// matter, only that it is too far to be what was meant.
    private static func editDistance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...max(1, lhs.count) {
            guard i <= lhs.count else { break }
            current[0] = i
            var rowBest = current[0]
            for j in 1...max(1, rhs.count) {
                guard j <= rhs.count else { break }
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    /// A typo budget that scales with the word: one slip in a short name, more
    /// in a long one, because "ashwaganda" is two edits from "ashwagandha".
    private static func tolerance(for query: String) -> Int {
        switch query.count {
        case 0...4: return 1
        case 5...8: return 2
        default: return 3
        }
    }

    static func search(_ raw: String, limit: Int = 40) -> [Entry] {
        let query = normalise(raw)
        guard !query.isEmpty else {
            return Array(all.sorted { $0.name < $1.name }.prefix(limit))
        }
        let queryChars = Array(query)
        let budget = tolerance(for: query)

        var scored: [(entry: Entry, tier: Int, length: Int)] = []
        for entry in all {
            let candidates = [entry.name] + entry.aliases
            var best: Int?
            for candidate in candidates {
                let target = normalise(candidate)
                guard !target.isEmpty else { continue }
                let tier: Int
                if target == query {
                    tier = 0
                } else if target.hasPrefix(query) {
                    tier = 1
                } else if target.contains(query) {
                    tier = 2
                } else if editDistance(queryChars, Array(target), limit: budget) <= budget {
                    tier = 3
                } else if target.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
                    tier = 2
                } else {
                    continue
                }
                best = min(best ?? tier, tier)
            }
            if let best { scored.append((entry, best, entry.name.count)) }
        }

        return scored
            .sorted {
                $0.tier != $1.tier ? $0.tier < $1.tier
                    : $0.length != $1.length ? $0.length < $1.length
                    : $0.entry.name < $1.entry.name
            }
            .prefix(limit)
            .map(\.entry)
    }
}
