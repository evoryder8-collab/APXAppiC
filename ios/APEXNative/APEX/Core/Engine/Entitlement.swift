import Foundation

/// Who can use what, and what it costs.
///
/// The model is a full-access trial rather than a crippled free tier: a
/// training app cannot prove itself in a week of partial features, and a plan
/// generator that hands back half a programme is worse than no demonstration
/// at all. Everything works for fourteen days, which is two complete training
/// weeks, then it asks.
enum Entitlement {

    enum Tier: String, Codable, Sendable, CaseIterable {
        case premium
        case coach
    }

    /// Why someone currently has access. Order matters: the first true reason
    /// wins, and `founding` outranks everything so a bespoke account is never
    /// shown a countdown or a price.
    enum Access: Equatable, Sendable {
        case founding
        case developerCode
        case subscribed(Tier)
        case trial(daysRemaining: Int)
        case expired
    }

    /// Two complete training weeks. Long enough to finish a programme block and
    /// see progression happen, which is the thing worth paying for.
    static let trialDays = 14

    // MARK: - Pricing

    /// Prices in Swiss francs, held as integers of rappen so no rounding error
    /// can reach a price tag.
    struct Price: Equatable, Sendable {
        let monthlyRappen: Int
        /// Optional so a tier can be offered monthly only. Both tiers currently
        /// have a yearly plan at roughly a third off.
        let yearlyRappen: Int?

        /// What the yearly plan saves against twelve months, as a whole percent.
        var yearlySavingPercent: Int? {
            guard let yearlyRappen, monthlyRappen > 0 else { return nil }
            let full = monthlyRappen * 12
            return Int(((Double(full - yearlyRappen) / Double(full)) * 100).rounded())
        }
    }

    static func price(_ tier: Tier) -> Price {
        switch tier {
        case .premium: Price(monthlyRappen: 990, yearlyRappen: 7_900)
        case .coach: Price(monthlyRappen: 2_900, yearlyRappen: 22_900)
        }
    }

    /// Seats included in the Coach tier before per-seat pricing starts.
    static let coachIncludedSeats = 3
    static let coachExtraSeatRappen = 600

    /// What a coach pays each month for a roster of this size.
    static func coachMonthlyRappen(seats: Int) -> Int {
        let base = price(.coach).monthlyRappen
        guard seats > coachIncludedSeats else { return base }
        return base + (seats - coachIncludedSeats) * coachExtraSeatRappen
    }

    // MARK: - Access

    /// Resolve what this account is entitled to, right now.
    ///
    /// `trialStarted` is when the account first opened the app rather than when
    /// it was created, so an account made in advance does not burn its trial
    /// sitting unopened.
    static func access(
        foundingMember: Bool,
        developerCodeRedeemed: Bool,
        subscribedTier: Tier?,
        subscriptionExpires: Date?,
        trialStarted: Date?,
        now: Date = Date()
    ) -> Access {
        if foundingMember { return .founding }
        if developerCodeRedeemed { return .developerCode }
        if let subscribedTier, let expiry = subscriptionExpires, expiry > now {
            return .subscribed(subscribedTier)
        }
        // A subscription with no expiry recorded is treated as active: failing
        // open is the right way round when the alternative is locking a paying
        // customer out over a missing field.
        if let subscribedTier, subscriptionExpires == nil {
            return .subscribed(subscribedTier)
        }
        guard let trialStarted else { return .trial(daysRemaining: trialDays) }
        let elapsed = Calendar.current.dateComponents([.day], from: trialStarted, to: now).day ?? 0
        let remaining = trialDays - elapsed
        return remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    /// Everything except an expired trial keeps the app open.
    static func isUnlocked(_ access: Access) -> Bool { access != .expired }

    /// Features that exist only for coaches. Client rosters and plan authoring
    /// are a different job from training yourself, not a bigger version of it.
    ///
    /// Predefined meal lists are deliberately not here: they are useful to
    /// anyone who eats the same things most weeks, and putting them behind the
    /// trainer tier would punish ordinary users for a habit the app should
    /// encourage.
    enum CoachFeature: String, CaseIterable, Sendable {
        case clientRoster
        case planAuthoring
        case clientTargets
    }

    static func allows(_ feature: CoachFeature, access: Access) -> Bool {
        switch access {
        case .founding, .developerCode: true
        case .subscribed(let tier): tier == .coach
        case .trial: true
        case .expired: false
        }
    }
}
