import Foundation

enum LiftedMassComparison {
    private struct Landmark: Decodable {
        let name: String
        let kg: Double
        let source: URL
        let artwork: String?
        let fact: String?
        let factSource: URL?
        let translations: [String: [String]]?
    }

    struct Comparison {
        let caption: String
        let source: URL
        var fact: String?
        var factSource: URL?
        var artworkURL: URL?
    }

    private static let objects = landmarks("lifted-mass-landmarks")
    private static let heroes = landmarks("hero-lift-landmarks")

    private static func landmarks(_ file: String) -> [Landmark] {
        guard let url = Bundle.main.url(forResource: file, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Landmark].self, from: data) else { return [] }
        return values
    }

    static func formattedMass(_ kilograms: Double, locale: Locale) -> String {
        let units = ["kg", "t", "kt", "Mt", "Gt", "Tt", "Pt", "Et", "Zt", "Yt", "Rt", "Qt"]
        var index = 0
        var amount = kilograms
        while amount >= 1000 && index + 1 < units.count {
            amount /= 1000
            index += 1
        }
        return amount.formatted(.number.locale(locale).precision(.significantDigits(1...5))) + " " + units[index]
    }

    private static func pick(_ matches: [Landmark], kilograms: Double) -> Landmark? {
        guard !matches.isEmpty else { return nil }
        return matches[Int(kilograms.rounded(.down).truncatingRemainder(dividingBy: Double(matches.count)))]
    }

    @MainActor
    static func caption(kilograms: Double) -> Comparison? {
        guard kilograms.isFinite, kilograms > 0 else { return nil }
        func distance(_ mass: Double) -> Double { abs(log(kilograms / mass)) }
        let catalog = objects.filter { kilograms / $0.kg >= 0.1 }
        let close = catalog.filter { distance($0.kg) <= log(1.1) }
        let multiples = catalog.filter { $0.kg <= kilograms && $0.kg * 8 >= kilograms }
        let preferClose = kilograms.rounded(.down).truncatingRemainder(dividingBy: 3) == 0 && !close.isEmpty
        guard let match = pick(preferClose ? close : multiples, kilograms: kilograms) ?? catalog.min(by: { distance($0.kg) < distance($1.kg) })
        else { return nil }
        let ratio = kilograms / match.kg
        let language = LanguageState.shared
        let multiplier = ratio.formatted(.number.locale(language.language.locale).precision(.significantDigits(1...3)))
        let reference = formattedMass(match.kg, locale: language.language.locale)
        let words = match.translations?[language.language.rawValue]
        let name = words?.first ?? match.name
        let caption = "≈ " + multiplier + " × " + name + " (" + reference + ")"
        return Comparison(caption: caption, source: match.source, fact: words?.last ?? match.fact,
                          factSource: match.factSource ?? match.source,
                          artworkURL: match.artwork.flatMap { Bundle.main.url(forResource: $0, withExtension: nil, subdirectory: "award-objects") })
    }

    @MainActor
    static func heroCaption(kilograms: Double) -> Comparison? {
        guard kilograms.isFinite, kilograms > 0,
              let first = heroes.first(where: { $0.kg >= kilograms }) else { return nil }
        let tier = heroes.filter { $0.kg >= kilograms && $0.kg <= first.kg * 1.1 }
        guard let hero = pick(tier, kilograms: kilograms) else { return nil }
        let language = LanguageState.shared
        let mass = formattedMass(hero.kg, locale: language.language.locale)
        let caption = language.text("Fictional one-lift benchmark · {hero} · {mass}")
            .replacingOccurrences(of: "{hero}", with: language.text(hero.name))
            .replacingOccurrences(of: "{mass}", with: mass)
        return Comparison(caption: caption, source: hero.source)
    }
}
