import Foundation

enum WaterVolumeComparison {
    private struct Landmark: Decodable {
        let name: String
        let singular: String
        let plural: String?
        let litres: Double
        let translations: [String: String]
    }

    struct Comparison {
        let caption: String
        let name: String
        let litres: Double
        /// nil when no close match exists and the caption names a milestone instead.
        let count: Int?
    }

    struct Milestone {
        let name: String
        let litres: Double
    }

    private static let landmarks: [Landmark] = {
        guard let url = Bundle.main.url(forResource: "water-volume-landmarks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Landmark].self, from: data) else { return [] }
        return values
    }()

    static var count: Int { landmarks.count }

    private static func match(litres: Double) -> (landmark: Landmark, count: Int?)? {
        for count in 1...6 {
            let candidates = count == 1 ? landmarks : landmarks.filter { $0.plural != nil }
            func difference(_ landmark: Landmark) -> Double {
                abs(litres - Double(count) * landmark.litres)
            }
            if let best = candidates.min(by: { difference($0) < difference($1) }),
               difference(best) / litres <= (count == 1 ? 0.12 : 0.08) {
                return (best, count)
            }
        }
        // The catalogue is ordered by volume. A gap still has a real milestone on either side.
        guard let milestone = landmarks.last(where: { $0.litres <= litres }) ?? landmarks.first else { return nil }
        return (milestone, nil)
    }

    @MainActor
    private static func localizedName(_ landmark: Landmark) -> String {
        landmark.translations[LanguageState.shared.language.rawValue] ?? landmark.name
    }

    @MainActor
    static func caption(litres: Double) -> Comparison? {
        guard litres.isFinite, litres > 0, let (match, count) = match(litres: litres) else { return nil }
        let language = LanguageState.shared
        let name = localizedName(match)
        let caption: String
        switch count {
        case 1?:
            caption = language.language == .english
                ? language.format("Enough to fill %@", match.singular)
                : name + " · " + language.text("About the same volume")
        case let count?:
            caption = language.language == .english
                ? language.format("Enough to fill %d %@", count, match.plural ?? match.name)
                : name + " · " + language.format("About %d of these", count)
        case nil:
            caption = name + " · " + language.text(match.litres <= litres ? "Milestone passed" : "Next milestone")
        }
        return Comparison(caption: caption, name: name, litres: match.litres, count: count)
    }

    @MainActor
    static func next(after litres: Double) -> Milestone? {
        guard let landmark = landmarks.first(where: { $0.litres > litres }) else { return nil }
        return Milestone(name: localizedName(landmark), litres: landmark.litres)
    }
}
