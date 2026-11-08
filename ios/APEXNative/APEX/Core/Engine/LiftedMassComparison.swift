import Foundation

enum LiftedMassComparison {
    private struct Landmark: Decodable {
        let name: String
        let singular: String?
        let plural: String?
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

    private struct MassWords: Decodable {
        let one: [String]
        let other: [String]?
        let atLeast: String
    }

    private static let massWords: [String: MassWords] = {
        guard let url = Bundle.main.url(forResource: "lifted-mass-units", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: MassWords].self, from: data)) ?? [:]
    }()

    static func formattedMass(_ kilograms: Double, locale: Locale, partial: Bool = false) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        let key = language == "de" && locale.region?.identifier == "CH" ? "de-CH" : language
        let style = FloatingPointFormatStyle<Double>.number.locale(locale)
            .precision(.significantDigits(1...5)).rounded(rule: partial ? .down : .toNearestOrAwayFromZero)
        guard let words = massWords[key] ?? massWords["en"] else {
            return (partial ? "at least " : "") + kilograms.formatted(style) + " kg"
        }
        let scales: [Double] = [1, 1e3, 1e6, 1e9, 1e12, 1e15, 1e18, 1e21, 1e24, 1e27, 1e30, 1e33]
        let unit = scales.lastIndex(where: { kilograms >= $0 }) ?? 0
        let amount = kilograms / scales[unit]
        let number = amount.formatted(style)
        var mass = number + " kg"
        if unit > 0 {
            let singular = number == 1.0.formatted(style)
            let forms = singular ? words.one : words.other ?? words.one
            let lastTwo = amount.truncatingRemainder(dividingBy: 100)
            let needsDe = language == "ro" && amount.rounded() == amount && amount >= 20 && (lastTwo == 0 || lastTwo >= 20)
            let separator = language == "ja" ? "" : needsDe ? " de " : " "
            mass = number + separator + forms[unit - 1]
        }
        return partial ? words.atLeast.replacingOccurrences(of: "{}", with: mass) : mass
    }

    private static func pick(_ matches: [Landmark], kilograms: Double) -> Landmark? {
        guard !matches.isEmpty else { return nil }
        return matches[Int(kilograms.rounded(.down).truncatingRemainder(dividingBy: Double(matches.count)))]
    }

    private static func objectMatch(kilograms: Double) -> (landmark: Landmark, count: Int?)? {
        for count in 1...6 {
            let candidates = count == 1 ? objects : objects.filter { $0.plural != nil }
            func difference(_ landmark: Landmark) -> Double {
                abs(kilograms - Double(count) * landmark.kg)
            }
            if let best = candidates.min(by: { difference($0) < difference($1) }),
               difference(best) / kilograms <= (count == 1 ? 0.12 : 0.08) {
                return (best, count)
            }
        }
        // The catalogue is ordered by mass. A gap still has a real milestone on either side.
        guard let milestone = objects.last(where: { $0.kg <= kilograms }) ?? objects.first else { return nil }
        return (milestone, nil)
    }

    @MainActor
    static func caption(kilograms: Double) -> Comparison? {
        guard kilograms.isFinite, kilograms > 0, let (match, count) = objectMatch(kilograms: kilograms) else { return nil }
        let language = LanguageState.shared
        let words = match.translations?[language.language.rawValue]
        let name = words?.first ?? match.name
        let caption: String
        if let count {
            if count == 1 {
                if language.language == .english {
                    guard let singular = match.singular else { return nil }
                    caption = language.format("About the weight of %@", singular)
                } else {
                    caption = name + " · " + language.text("About the same weight")
                }
            } else if language.language == .english {
                guard let plural = match.plural else { return nil }
                caption = language.format("Around %dx %@", count, plural.prefix(1).uppercased() + plural.dropFirst())
            } else {
                caption = name + " · " + language.format("About %d of these", count)
            }
        } else {
            caption = name + " · " + language.text(match.kg <= kilograms ? "Milestone passed" : "Next milestone")
        }
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
