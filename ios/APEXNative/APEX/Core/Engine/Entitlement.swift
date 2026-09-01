import Foundation

/// Who can use what, and what it costs.
///
/// During beta, access is granted only by an account-owned server fact: a
/// founding profile, a claimed beta code, or an active subscription.
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
        case beta
        case subscribed(Tier)
        /// A free client seat owned by an active, server-authorised coach.
        /// It unlocks the client experience, never coach administration.
        case sponsored
        case locked
    }

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
    static func access(
        foundingMember: Bool,
        betaCodeRedeemed: Bool,
        subscribedTier: Tier?,
        subscriptionExpires: Date?,
        sponsoredSeatActive: Bool = false,
        now: Date = Date()
    ) -> Access {
        if foundingMember { return .founding }
        if betaCodeRedeemed { return .beta }
        if let subscribedTier, let expiry = subscriptionExpires, expiry > now {
            return .subscribed(subscribedTier)
        }
        // A subscription with no expiry recorded is treated as active: failing
        // open is the right way round when the alternative is locking a paying
        // customer out over a missing field.
        if let subscribedTier, subscriptionExpires == nil {
            return .subscribed(subscribedTier)
        }
        if sponsoredSeatActive { return .sponsored }
        return .locked
    }

    static func isUnlocked(_ access: Access) -> Bool { access != .locked }

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
        // Coach authority is now a dedicated server capability, not a price,
        // beta flag, founding account, or client sponsorship side effect.
        _ = feature
        _ = access
        return false
    }
}
