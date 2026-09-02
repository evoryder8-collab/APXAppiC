import Foundation
import CryptoKit

/// The live answer to "can this account use the app", kept in one place so no
/// screen has to work it out for itself.
@Observable
@MainActor
final class EntitlementStore {

    static let shared = EntitlementStore()

    private(set) var access: Entitlement.Access = .locked
    private(set) var resolvedUserID: UUID?
    private(set) var hasIndividualAccess = false

    var isUnlocked: Bool { Entitlement.isUnlocked(access) }

    func allows(_ feature: Entitlement.CoachFeature) -> Bool {
        Entitlement.allows(feature, access: access)
    }

    // MARK: - Beta unlock

    /// What happened when a code was entered.
    enum RedeemOutcome: Equatable {
        case unlocked
        case alreadyRedeemed
        case notRecognised
        case notSignedIn
        case unavailable
    }

    /// A shared beta code, which belongs to whichever account claims it first.
    ///
    /// This cannot be decided on the device: a local flag is per install, so
    /// the same code would work again on another phone, or after deleting and
    /// reinstalling. The claim is recorded against the account server side.
    func redeemBeta(
        code: String,
        expectedUserID: UUID,
        service: SupabaseService
    ) async throws -> RedeemOutcome {
        guard resolvedUserID == expectedUserID else { return .notSignedIn }
        guard await service.currentUserID() == expectedUserID else { return .notSignedIn }

        let result: String
        do {
            result = try await service.redeemBetaCode(hash: hash(of: code))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard resolvedUserID == expectedUserID else { return .notSignedIn }
            guard await service.currentUserID() == expectedUserID else { return .notSignedIn }
            return .unavailable
        }

        guard resolvedUserID == expectedUserID else { return .notSignedIn }
        guard await service.currentUserID() == expectedUserID else { return .notSignedIn }

        switch result {
        case "ok": return .unlocked
        case "already_redeemed": return .alreadyRedeemed
        case "not_signed_in": return .notSignedIn
        default: return .notRecognised
        }
    }

    /// Normalised the same way on every path, so a code typed with stray
    /// spaces or in lower case still matches.
    private func hash(of code: String) -> String {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return SHA256.hash(data: Data(normalised.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Resolution

    /// Clear the previous account's answer before any fallible network work.
    func prepareForAccount(_ userID: UUID) {
        guard resolvedUserID != userID else { return }
        resolvedUserID = userID
        access = .locked
        hasIndividualAccess = false
    }

    func resetAccount() {
        resolvedUserID = nil
        access = .locked
        hasIndividualAccess = false
    }

    func resolve(profile: Profile?, sponsoredSeatActive: Bool = false) {
        guard let profile else { return }
        prepareForAccount(profile.userID)
        let individualAccess = Entitlement.access(
            foundingMember: profile.foundingMember ?? false,
            betaCodeRedeemed: profile.betaCodeRedeemed ?? false,
            subscribedTier: profile.subscriptionTier.flatMap(Entitlement.Tier.init(rawValue:)),
            subscriptionExpires: profile.subscriptionExpiresAt.flatMap(Self.parse),
            sponsoredSeatActive: false
        )
        hasIndividualAccess = Entitlement.isUnlocked(individualAccess)
        access = hasIndividualAccess ? individualAccess : Entitlement.access(
            foundingMember: false,
            betaCodeRedeemed: false,
            subscribedTier: nil,
            subscriptionExpires: nil,
            sponsoredSeatActive: sponsoredSeatActive
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
