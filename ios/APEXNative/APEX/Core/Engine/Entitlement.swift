import Foundation
import Darwin

/// A durable identity for the current device boot. Uptime alone is not a boot
/// identity: after a reboot it can eventually overtake the value saved by an
/// earlier boot. `kern.boottime` is covered by the app's declared
/// SystemBootTime/35F9.1 elapsed-time purpose.
enum SystemBootSession {
    static func identifier() -> String? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let status = withUnsafeMutablePointer(to: &bootTime) { pointer in
            sysctlbyname("kern.boottime", pointer, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return "\(bootTime.tv_sec):\(bootTime.tv_usec)"
    }
}

/// The single server-owned answer to whether the authenticated account may
/// enter this client. It is deliberately independent of `Profile`: a new
/// account can be entitled before onboarding has created any health record.
struct AccountAccessEnvelope: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case granted
        case expired
        case revoked
        case locked
        case missing
    }

    let userID: UUID
    let state: State
    let expiresAt: String?
    let updatedAt: String?
    let serverNow: String
    let sponsoredSeatActive: Bool
    let minimumBuild: Int
    let updateRequired: Bool
    let webBetaCodesEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case state
        case userID = "user_id"
        case expiresAt = "expires_at"
        case updatedAt = "entitlement_updated_at"
        case serverNow = "server_now"
        case sponsoredSeatActive = "sponsored_seat_active"
        case minimumBuild = "minimum_build"
        case updateRequired = "update_required"
        case webBetaCodesEnabled = "web_beta_codes_enabled"
    }

    var observationDate: Date? { Self.parse(serverNow) }

    static func parse(_ value: String) -> Date? {
        if let plain = ISO8601DateFormatter().date(from: value) { return plain }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

/// A server access answer plus the local instant at which it was safely
/// persisted. The server's clock remains the authority; local time is used
/// only to measure how much nonnegative time has elapsed while offline.
struct CachedAccountAccess: Codable, Equatable, Sendable {
    let envelope: AccountAccessEnvelope
    let savedAt: Date
    let savedSystemUptime: TimeInterval?
    let savedBootSessionID: String?

    init(
        envelope: AccountAccessEnvelope,
        savedAt: Date,
        savedSystemUptime: TimeInterval?,
        savedBootSessionID: String? = SystemBootSession.identifier()
    ) {
        self.envelope = envelope
        self.savedAt = savedAt
        self.savedSystemUptime = savedSystemUptime
        self.savedBootSessionID = savedBootSessionID
    }

    /// Prefer monotonic elapsed time while the device remains in the same boot
    /// session. After a reboot, fall back to wall time. A wall-clock rollback
    /// is rejected even when uptime advanced: accepting it could extend a
    /// finite grant indefinitely by repeatedly turning the clock backwards.
    func elapsedTime(
        now: Date,
        systemUptime: TimeInterval
    ) -> TimeInterval? {
        let wallElapsed = now.timeIntervalSince(savedAt)
        guard wallElapsed >= 0 else { return nil }
        if let savedSystemUptime, systemUptime >= savedSystemUptime {
            let uptimeElapsed = systemUptime - savedSystemUptime
            let bootEpochShift = (now.timeIntervalSince1970 - systemUptime)
                - (savedAt.timeIntervalSince1970 - savedSystemUptime)
            // A materially earlier estimated boot epoch means the wall clock
            // moved backwards during this boot. Do not let that extend cache.
            guard bootEpochShift >= -300 else { return nil }
            if abs(bootEpochShift) <= 300 {
                // Monotonic time wins on the same boot; max also absorbs small
                // backwards wall adjustments without extending the grant.
                return max(wallElapsed, uptimeElapsed)
            }
        }
        return wallElapsed
    }
}

/// Who can use what.
///
/// Access is granted only by the authenticated account's server envelope or
/// by its active coach-sponsored seat.
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
        /// The release-wide account grant used by the TestFlight phase.
        case testFlight
        /// A free client seat owned by an active, server-authorised coach.
        /// It unlocks the client experience, never coach administration.
        case sponsored
        case updateRequired
        case locked
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

    static func isUnlocked(_ access: Access) -> Bool {
        switch access {
        case .locked, .updateRequired: false
        default: true
        }
    }

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
