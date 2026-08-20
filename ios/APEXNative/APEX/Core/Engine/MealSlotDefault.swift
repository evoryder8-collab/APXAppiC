import Foundation

/// Which meal a food logged at this hour most likely belongs to.
///
/// The clock decides, with one exception the user controls: a late evening
/// entry is a snack by default, but people who train at night are usually
/// eating a real dinner at that hour, not picking at something. The setting
/// exists so that call is theirs.
enum MealSlotDefault {

    /// The hour after which a meal is no longer treated as dinner by the clock.
    static let lateEveningHour = 21

    /// The hour from which the adaptive rule treats a late meal as dinner.
    static let adaptiveDinnerFromHour = 19

    static func slot(hour: Int, adaptiveLateDinner: Bool) -> String {
        if hour < 11 { return "breakfast" }
        if hour < 16 { return "lunch" }
        if hour < lateEveningHour { return "dinner" }
        /* Past nine in the evening. Snack unless the user has said their late
           meals are proper ones, which is the whole point of the setting. */
        return adaptiveLateDinner && hour >= adaptiveDinnerFromHour ? "dinner" : "snack"
    }
}
