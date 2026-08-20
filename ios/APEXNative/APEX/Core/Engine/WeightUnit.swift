import Foundation

/// Kilograms or pounds, wherever a bodyweight or a load is shown.
///
/// Everything is stored and calculated in kilograms, because every formula in
/// the app expects them and round-tripping through pounds would introduce drift
/// into numbers that are compared week to week. Only the display converts.
enum WeightUnit: String, Sendable, CaseIterable {
    case kilograms = "kg"
    case pounds = "lb"

    static let poundsPerKilogram = 2.2046226218

    var suffix: String { rawValue }

    func value(fromKilograms kilograms: Double) -> Double {
        self == .pounds ? kilograms * Self.poundsPerKilogram : kilograms
    }

    func kilograms(fromValue value: Double) -> Double {
        self == .pounds ? value / Self.poundsPerKilogram : value
    }

    /// A weight with its unit, rounded the way a person would say it.
    ///
    /// Pounds get no decimal: nobody weighs themselves to a tenth of a pound,
    /// and the extra digit only makes the number look busier than it is.
    func format(kilograms: Double) -> String {
        let converted = value(fromKilograms: kilograms)
        return self == .pounds
            ? "\(Int(converted.rounded())) \(suffix)"
            : (converted == converted.rounded()
                ? "\(Int(converted)) \(suffix)"
                : String(format: "%.1f %@", converted, suffix))
    }

    /// The unit the account has chosen, defaulting to kilograms.
    static func current(_ settings: UserSettings?) -> WeightUnit {
        guard let raw = settings?.addons["weight_unit"]?.stringValue else { return .kilograms }
        return WeightUnit(rawValue: raw) ?? .kilograms
    }
}
