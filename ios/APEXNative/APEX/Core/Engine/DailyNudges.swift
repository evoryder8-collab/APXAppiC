import Foundation

/// The two things worth interrupting someone's evening for.
///
/// A nudge carries numbers and a reason, never a finished sentence. The words
/// are assembled at the point of display so a Romanian or Thai user gets a
/// Romanian or Thai notification, and so the copy can change without the rules
/// changing underneath it.
///
/// A reminder that only says "you missed something" makes people feel bad and
/// changes nothing. Both of these carry the action that helps, and the protein
/// one carries a ceiling, because the predictable response to "you are short on
/// protein" is to drink 90 g at eleven at night and assume it counts.
enum DailyNudges {

    enum Kind: String, Codable, Sendable {
        case creatineMissed
        case proteinShort
    }

    struct Nudge: Identifiable, Codable, Sendable, Equatable {
        var id: String { kind.rawValue + "-" + date }
        let kind: Kind
        let date: String
        /// How far under target the day finished.
        var shortfallG: Int = 0
        /// What is worth eating tonight, which is the shortfall held under the cap.
        var tonightG: Int = 0
        /// What a single sitting can actually use, scaled to this person.
        var capG: Int = 0
        /// Fat loss and recomposition get a different reason, because that is
        /// where protein is holding muscle rather than adding it.
        var losingWeight: Bool = false
    }

    // MARK: - Protein

    /// How much protein a single sitting can actually use for muscle.
    ///
    /// Muscle protein synthesis saturates at roughly 0.4 g per kg of bodyweight
    /// in one meal (Moore 2015; Schoenfeld and Aragon 2018). Beyond that the
    /// extra is not wasted in any dangerous sense, it is simply oxidised or
    /// used elsewhere rather than building anything, which is why trying to
    /// repay a whole day in one shake does not work the way people expect.
    ///
    /// Scaled by bodyweight rather than fixed, because 40 g is a sensible
    /// catch-up for someone of 100 kg and most of a day's target for someone
    /// of 45 kg.
    static func singleSittingCapGrams(bodyweightKG: Double) -> Int {
        guard bodyweightKG > 0 else { return 30 }
        let cap = bodyweightKG * 0.4
        // Rounded to the nearest 5 g, because nobody measures to the gram, and
        // held inside a range that stays sensible at both extremes.
        return max(20, min(60, Int((cap / 5).rounded() * 5)))
    }

    /// Whether the day is short enough on protein to be worth saying so.
    ///
    /// Deliberately not a nudge for being a little under: a reminder that fires
    /// most days is one people turn off.
    static func proteinShortfall(
        consumedG: Double,
        targetG: Double,
        goal: String,
        bodyweightKG: Double
    ) -> Nudge? {
        guard targetG > 0 else { return nil }
        let shortfall = targetG - consumedG
        guard shortfall > 0 else { return nil }

        let losing = ["cut", "recomp", "lean", "fat_loss", "weight_loss"]
            .contains { goal.lowercased().contains($0) }
        // Under 85% while losing weight, under 70% otherwise.
        guard consumedG / targetG < (losing ? 0.85 : 0.70) else { return nil }

        let cap = singleSittingCapGrams(bodyweightKG: bodyweightKG)
        return Nudge(
            kind: .proteinShort,
            date: Self.today(),
            shortfallG: Int(shortfall.rounded()),
            tonightG: min(Int(shortfall.rounded()), cap),
            capG: cap,
            losingWeight: losing
        )
    }

    // MARK: - Creatine

    /// Creatine works by staying saturated, so the miss that matters is the
    /// habit rather than the single day. Worth one quiet reminder in the
    /// evening and nothing more.
    static func creatineMissed(loggedToday: Bool, inStack: Bool) -> Nudge? {
        guard inStack, !loggedToday else { return nil }
        return Nudge(kind: .creatineMissed, date: Self.today())
    }

    /// Evening, late enough that the day is a fair judgement and early enough
    /// to still act on it.
    static let eveningHour = 19
    static let eveningMinute = 30

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

/// Turns a nudge into words, in whatever language the app is currently in.
@MainActor
enum NudgeCopy {

    static func title(_ nudge: DailyNudges.Nudge, _ language: LanguageState) -> String {
        switch nudge.kind {
        case .proteinShort: language.text("Protein is short today")
        case .creatineMissed: language.text("Creatine not logged")
        }
    }

    /// One line, for the lock screen.
    static func body(_ nudge: DailyNudges.Nudge, _ language: LanguageState) -> String {
        switch nudge.kind {
        case .proteinShort:
            language.format("%d g to go. %d g tonight is enough.", nudge.shortfallG, nudge.tonightG)
        case .creatineMissed:
            language.text("It works by staying topped up. Today still counts.")
        }
    }

    /// What to say when it is opened, where there is room to be useful.
    static func detail(_ nudge: DailyNudges.Nudge, _ language: LanguageState) -> String {
        switch nudge.kind {
        case .proteinShort:
            let why = nudge.losingWeight
                ? language.text("While you are losing weight, protein is what keeps the loss coming from fat rather than muscle.")
                : language.text("Protein is the one target worth closing even on a busy day.")
            let advice = language.format(
                "You are %d g under. Do not try to repay all of it in one go: a single sitting can use about %d g for muscle, and the rest is mostly burned for energy instead. Have around %d g now and start tomorrow on target rather than behind.",
                nudge.shortfallG, nudge.capG, nudge.tonightG
            )
            return why + "\n\n" + advice
        case .creatineMissed:
            return language.text("Creatine builds up in muscle over weeks and stays there while you keep taking it, so consistency does more than any single dose.")
                + "\n\n"
                + language.text("Missing one day changes very little. Missing most days is the same as not taking it at all. There is no need to double up tomorrow: take the usual amount and carry on.")
        }
    }
}
