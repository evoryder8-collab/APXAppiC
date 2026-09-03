import Foundation
import Observation

/// The live answer to "can this account use the app", kept in one place so no
/// screen has to work it out for itself.
@Observable
@MainActor
final class EntitlementStore {

    private static let sponsoredCacheLifetime: TimeInterval = 24 * 60 * 60

    private struct AccessEvidence: Sendable {
        let id: UUID
        let envelope: AccountAccessEnvelope
        /// Time already elapsed between the server observation being cached
        /// and this evidence being loaded.
        let baseElapsed: TimeInterval
        /// Monotonic point at which this process accepted the evidence.
        let acceptedSystemUptime: TimeInterval
        /// Live responses carry a server-computed answer for this exact build.
        /// Cached responses recompute it from their durable minimum-build fact.
        let updateRequired: Bool
    }

    private struct Evaluation: Sendable {
        let access: Entitlement.Access
        let hasIndividualAccess: Bool
        let deadlineDelay: TimeInterval?
        let recoveryReason: RecoveryReason?
    }

    enum Resolution: Equatable, Sendable {
        case resolving
        case resolved
        case failed
    }

    enum RecoveryReason: Equatable, Sendable {
        case updateRequired
        case revoked
        case expired
        case locked
        case unavailable
    }

    static let shared = EntitlementStore()

    private(set) var access: Entitlement.Access = .locked
    private(set) var resolution: Resolution = .resolving
    private(set) var resolvedUserID: UUID?
    private(set) var hasIndividualAccess = false
    private(set) var recoveryReason: RecoveryReason? = .unavailable
    /// Exposed for deterministic contract tests and diagnostics. Production
    /// invalidation is driven by one sleeping task, never a polling timer.
    private(set) var scheduledAccessDeadlineUptime: TimeInterval?
    private var latestObservation: Date?
    @ObservationIgnored private var evidence: AccessEvidence?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var accessDeniedHandler: ((UUID) -> Void)?

    var isUnlocked: Bool { Entitlement.isUnlocked(access) }

    func allows(_ feature: Entitlement.CoachFeature) -> Bool {
        Entitlement.allows(feature, access: access)
    }

    func setAccessDeniedHandler(_ handler: @escaping (UUID) -> Void) {
        accessDeniedHandler = handler
    }

    // MARK: - Resolution

    /// Clear the previous account's answer before any fallible network work.
    func prepareForAccount(_ userID: UUID) {
        guard resolvedUserID != userID else { return }
        resolvedUserID = userID
        access = .locked
        resolution = .resolving
        hasIndividualAccess = false
        recoveryReason = .unavailable
        latestObservation = nil
        evidence = nil
        cancelDeadline()
    }

    func resetAccount() {
        resolvedUserID = nil
        access = .locked
        resolution = .resolving
        hasIndividualAccess = false
        recoveryReason = .unavailable
        latestObservation = nil
        evidence = nil
        cancelDeadline()
    }

    /// Accept an access response only for the current owner and only when it is
    /// at least as new as the answer already published. A delayed request from
    /// before a revoke/grant transition can therefore never roll state back.
    @discardableResult
    func resolve(
        envelope: AccountAccessEnvelope,
        expectedUserID: UUID,
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        // Deliberately do not compare a live response with `now`. The RPC has
        // already resolved state using the server clock. Device clock skew
        // must neither shorten nor extend that answer.
        _ = now
        guard resolvedUserID == expectedUserID,
              envelope.userID == expectedUserID,
              let observation = envelope.observationDate else { return false }
        if let latestObservation, observation < latestObservation { return false }

        latestObservation = observation
        let acceptedEvidence = AccessEvidence(
            id: UUID(),
            envelope: envelope,
            baseElapsed: 0,
            acceptedSystemUptime: systemUptime,
            updateRequired: envelope.updateRequired
        )
        evidence = acceptedEvidence
        publish(acceptedEvidence, systemUptime: systemUptime)
        return true
    }

    /// Resolve owner-scoped offline evidence. Its age is calculated from the
    /// cached server observation plus nonnegative elapsed local time, never by
    /// comparing the grant directly with today's device wall clock.
    @discardableResult
    func resolve(
        cached: CachedAccountAccess,
        expectedUserID: UUID,
        currentBuild: Int,
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bootSessionID: String? = SystemBootSession.identifier()
    ) -> Bool {
        let envelope = cached.envelope
        let permanentIndividual = envelope.state == .granted && envelope.expiresAt == nil
        let boundedAccessCouldUnlock = !permanentIndividual
            && (envelope.state == .granted || envelope.sponsoredSeatActive)
        if boundedAccessCouldUnlock {
            guard let savedSystemUptime = cached.savedSystemUptime,
                  let savedBootSessionID = cached.savedBootSessionID,
                  let bootSessionID,
                  savedBootSessionID == bootSessionID,
                  systemUptime >= savedSystemUptime else { return false }
        }
        guard resolvedUserID == expectedUserID,
              envelope.userID == expectedUserID,
              let observation = envelope.observationDate,
              let elapsed = cached.elapsedTime(now: now, systemUptime: systemUptime)
        else { return false }
        if let latestObservation, observation < latestObservation { return false }

        latestObservation = observation
        let acceptedEvidence = AccessEvidence(
            id: UUID(),
            envelope: envelope,
            baseElapsed: elapsed,
            acceptedSystemUptime: systemUptime,
            updateRequired: currentBuild < envelope.minimumBuild
        )
        evidence = acceptedEvidence
        publish(acceptedEvidence, systemUptime: systemUptime)
        return true
    }

    /// Re-evaluate the accepted evidence at a monotonic instant. Returning
    /// false means the published answer did not change; callers never need to
    /// poll this because the store schedules its nearest deadline itself.
    @discardableResult
    func reevaluateAccess(
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard let evidence else { return false }
        return publish(evidence, systemUptime: systemUptime)
    }

    func markUnavailable(expectedUserID: UUID) {
        guard resolvedUserID == expectedUserID, resolution == .resolving else { return }
        resolution = .failed
        access = .locked
        hasIndividualAccess = false
        recoveryReason = .unavailable
        evidence = nil
        cancelDeadline()
        accessDeniedHandler?(expectedUserID)
    }

    @discardableResult
    private func publish(
        _ evidence: AccessEvidence,
        systemUptime: TimeInterval
    ) -> Bool {
        let evaluation = evaluate(evidence, systemUptime: systemUptime)
        let changed = resolution != .resolved
            || access != evaluation.access
            || hasIndividualAccess != evaluation.hasIndividualAccess
            || recoveryReason != evaluation.recoveryReason

        if resolution != .resolved { resolution = .resolved }
        if access != evaluation.access { access = evaluation.access }
        if hasIndividualAccess != evaluation.hasIndividualAccess {
            hasIndividualAccess = evaluation.hasIndividualAccess
        }
        if recoveryReason != evaluation.recoveryReason {
            recoveryReason = evaluation.recoveryReason
        }
        scheduleDeadline(
            evidenceID: evidence.id,
            delay: evaluation.deadlineDelay,
            systemUptime: systemUptime
        )
        if changed,
           !Entitlement.isUnlocked(evaluation.access),
           let resolvedUserID {
            accessDeniedHandler?(resolvedUserID)
        }
        return changed
    }

    private func evaluate(
        _ evidence: AccessEvidence,
        systemUptime: TimeInterval
    ) -> Evaluation {
        guard systemUptime >= evidence.acceptedSystemUptime,
              let serverObservation = evidence.envelope.observationDate else {
            return Evaluation(
                access: .locked,
                hasIndividualAccess: false,
                deadlineDelay: nil,
                recoveryReason: .unavailable
            )
        }

        let elapsed = evidence.baseElapsed
            + (systemUptime - evidence.acceptedSystemUptime)
        let effectiveServerNow = serverObservation.addingTimeInterval(elapsed)
        let individualAccess: Bool
        let individualDeadline: TimeInterval?
        if evidence.envelope.state == .granted {
            if let rawExpiry = evidence.envelope.expiresAt,
               let expiry = AccountAccessEnvelope.parse(rawExpiry) {
                let remaining = expiry.timeIntervalSince(effectiveServerNow)
                individualAccess = remaining > 0
                individualDeadline = individualAccess ? remaining : nil
            } else if evidence.envelope.expiresAt == nil {
                individualAccess = true
                individualDeadline = nil
            } else {
                // A malformed finite deadline can never become permanent.
                individualAccess = false
                individualDeadline = nil
            }
        } else {
            individualAccess = false
            individualDeadline = nil
        }

        let sponsoredRemaining = Self.sponsoredCacheLifetime - elapsed
        let sponsoredAccess = evidence.envelope.sponsoredSeatActive
            && sponsoredRemaining > 0

        if evidence.updateRequired {
            return Evaluation(
                access: .updateRequired,
                hasIndividualAccess: individualAccess,
                deadlineDelay: nil,
                recoveryReason: .updateRequired
            )
        }
        if individualAccess {
            return Evaluation(
                access: .testFlight,
                hasIndividualAccess: true,
                deadlineDelay: individualDeadline,
                recoveryReason: nil
            )
        }
        if sponsoredAccess {
            return Evaluation(
                access: .sponsored,
                hasIndividualAccess: false,
                deadlineDelay: sponsoredRemaining,
                recoveryReason: nil
            )
        }
        let recoveryReason: RecoveryReason
        switch evidence.envelope.state {
        case .revoked:
            recoveryReason = .revoked
        case .expired:
            recoveryReason = .expired
        case .locked, .missing:
            recoveryReason = .locked
        case .granted:
            recoveryReason = evidence.envelope.expiresAt == nil ? .unavailable : .expired
        }
        return Evaluation(
            access: .locked,
            hasIndividualAccess: false,
            deadlineDelay: nil,
            recoveryReason: recoveryReason
        )
    }

    private func scheduleDeadline(
        evidenceID: UUID,
        delay: TimeInterval?,
        systemUptime: TimeInterval
    ) {
        guard let delay, delay > 0 else {
            cancelDeadline()
            return
        }
        let target = systemUptime + delay
        if let scheduledAccessDeadlineUptime,
           abs(scheduledAccessDeadlineUptime - target) < 0.001,
           deadlineTask != nil {
            return
        }

        deadlineTask?.cancel()
        scheduledAccessDeadlineUptime = target
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  self.evidence?.id == evidenceID else { return }
            self.deadlineTask = nil
            self.scheduledAccessDeadlineUptime = nil
            // Sleeping can resume a fraction early. The scheduled monotonic
            // target is the authoritative lower bound for this evaluation.
            _ = self.reevaluateAccess(
                systemUptime: max(ProcessInfo.processInfo.systemUptime, target)
            )
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledAccessDeadlineUptime = nil
    }

    #if DEBUG
    /// Deterministic local fixtures have no authenticated Supabase server. This
    /// debug-only hook keeps UI automation independent without becoming a
    /// release access path.
    func resolveDebugFixture(userID: UUID, sponsoredSeatActive: Bool = false) {
        prepareForAccount(userID)
        resolution = .resolved
        if sponsoredSeatActive {
            access = .sponsored
            hasIndividualAccess = false
        } else {
            access = .testFlight
            hasIndividualAccess = true
        }
        recoveryReason = nil
        evidence = nil
        cancelDeadline()
    }
    #endif
}
