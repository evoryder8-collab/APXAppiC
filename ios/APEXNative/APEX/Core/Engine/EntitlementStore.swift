import Foundation
import CryptoKit

/// The live answer to "can this account use the app", kept in one place so no
/// screen has to work it out for itself.
@Observable
@MainActor
final class EntitlementStore {

    static let shared = EntitlementStore()

    private(set) var access: Entitlement.Access = .trial(daysRemaining: Entitlement.trialDays)

    var isUnlocked: Bool { Entitlement.isUnlocked(access) }

    /// Whether to show a countdown. Founding members and subscribers should
    /// never see one, and neither should someone on their first day.
    var trialDaysRemaining: Int? {
        if case .trial(let days) = access { return days }
        return nil
    }

    func allows(_ feature: Entitlement.CoachFeature) -> Bool {
        Entitlement.allows(feature, access: access)
    }

    // MARK: - Beta unlock

    /* The code is compared as a hash so the plain string is not sitting in the
       binary for anyone who runs `strings` on it. This is a beta convenience,
       not a security boundary, and it is not treated as one. */
    private static let developerCodeHash =
        "1f0a81ad875113b14cdbe6b14df69d4297e6e630feb37136a1b529e4683cabf6"
    private static let redeemedKey = "apex.entitlement.developerCode"

    var developerCodeRedeemed: Bool {
        UserDefaults.standard.bool(forKey: Self.redeemedKey)
    }

    /// Returns whether the code was accepted.
    @discardableResult
    func redeem(code: String) -> Bool {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digest = SHA256.hash(data: Data(normalised.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == Self.developerCodeHash else { return false }
        UserDefaults.standard.set(true, forKey: Self.redeemedKey)
        return true
    }

    // MARK: - Resolution

    func resolve(profile: Profile?) {
        guard let profile else { return }
        access = Entitlement.access(
            foundingMember: profile.foundingMember ?? false,
            developerCodeRedeemed: developerCodeRedeemed,
            subscribedTier: profile.subscriptionTier.flatMap(Entitlement.Tier.init(rawValue:)),
            subscriptionExpires: profile.subscriptionExpiresAt.flatMap(Self.parse),
            trialStarted: profile.trialStartedAt.flatMap(Self.parse)
        )
    }

    /* Built per call rather than cached: a formatter is not Sendable, this runs
       a handful of times per launch, and a subscription expiry silently failing
       to parse would lock out someone who has paid. */
    private static func parse(_ value: String) -> Date? {
        if let plain = ISO8601DateFormatter().date(from: value) { return plain }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}
