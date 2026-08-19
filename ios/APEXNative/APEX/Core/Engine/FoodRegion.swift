import Foundation
import StoreKit

/*
 * Port of src/lib/foodRegion.ts.
 *
 * Detected, never asked. The device already knows: someone sets their region
 * to where they live so dates, temperature and the first day of the week come
 * out right. Stored so it syncs, overridable in settings for what detection
 * cannot see - a person who moved and kept their old App Store country, or who
 * shops across a border.
 *
 * Region decides presentation and ranking. It does NOT decide how a stored
 * food is read: the carbohydrate convention is a property of each row and is
 * resolved from that row's own energy, because one catalogue holds both.
 */
enum FoodRegion: String, Sendable, CaseIterable, Identifiable {
    case europe
    case unitedStates = "united_states"
    case international

    var id: String { rawValue }

    var title: String {
        switch self {
        case .europe: "Europe"
        case .unitedStates: "United States"
        case .international: "International"
        }
    }

    /* EU and EFTA in alpha-2 and alpha-3, so a device region and an App Store
       storefront code classify without a conversion table between them. */
    private static let european: Set<String> = [
        "AT", "AUT", "BE", "BEL", "BG", "BGR", "CH", "CHE", "CY", "CYP", "CZ", "CZE",
        "DE", "DEU", "DK", "DNK", "EE", "EST", "ES", "ESP", "FI", "FIN", "FR", "FRA",
        "GB", "GBR", "GR", "GRC", "HR", "HRV", "HU", "HUN", "IE", "IRL", "IS", "ISL",
        "IT", "ITA", "LI", "LIE", "LT", "LTU", "LU", "LUX", "LV", "LVA", "MT", "MLT",
        "NL", "NLD", "NO", "NOR", "PL", "POL", "PT", "PRT", "RO", "ROU", "SE", "SWE",
        "SI", "SVN", "SK", "SVK",
    ]

    private static let unitedStatesCodes: Set<String> = ["US", "USA"]

    static func classify(_ code: String?) -> FoodRegion? {
        let value = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { return nil }
        if european.contains(value) { return .europe }
        if unitedStatesCodes.contains(value) { return .unitedStates }
        return nil
    }

    /// Region from the device, with an optional storefront as a second opinion.
    static func detected(deviceRegion: String? = Locale.current.region?.identifier, storefront: String? = nil) -> FoodRegion {
        /* The device region is the stronger signal. An App Store storefront
           follows the payment method, so it lags a move abroad by years. */
        classify(deviceRegion) ?? classify(storefront) ?? .international
    }

    /// The App Store country, used only to corroborate a device region we
    /// could not classify. Cheap, needs no permission, and never blocks.
    static func storefrontCode() async -> String? {
        await Storefront.current?.countryCode
    }

    static func normalize(_ value: JSONValue?) -> FoodRegion? {
        guard case .string(let raw) = value else { return nil }
        return FoodRegion(rawValue: raw)
    }

    /// Stored preference when there is one, otherwise what the device reports.
    static func resolved(_ settings: UserSettings?, detected: FoodRegion = FoodRegion.detected()) -> FoodRegion {
        normalize(settings?.addons["food_region"]) ?? detected
    }

    struct Presentation: Hashable, Sendable {
        /// Grams and millilitres, or ounces.
        let metric: Bool
        /// EU labelling leads with kilojoules, so both are shown.
        let showsKilojoules: Bool
        /// Which reference table generic staples are drawn from.
        let staples: String
        /// Provider country hint, so local products rank first in search.
        let providerCountry: String?
    }

    var presentation: Presentation {
        switch self {
        case .unitedStates:
            Presentation(metric: false, showsKilojoules: false, staples: "usda", providerCountry: "united-states")
        case .europe:
            Presentation(metric: true, showsKilojoules: true, staples: "swiss_fsvo", providerCountry: nil)
        case .international:
            Presentation(metric: true, showsKilojoules: false, staples: "usda", providerCountry: nil)
        }
    }

    /// Kilocalories to kilojoules, the factor fixed by EU Regulation 1169/2011.
    static func kilojoules(_ kcal: Double) -> Int {
        Int((kcal * 4.184).rounded())
    }
}
