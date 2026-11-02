import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class HydrationPhoneConnectivity: NSObject, WCSessionDelegate {
    var mutationHandler: ((HydrationCompanionMutation) async -> Void)?
    var supplementMutationHandler: ((WatchSupplementMutation) async -> Void)?
    var companionRefreshHandler: (() -> Void)?
    private let session: WCSession?
    private let defaults = UserDefaults.standard
    private static let visibleSignatureKey =
        "ch.apexperformance.APEX.watch.complication.visible-signature.v1"

    override init() {
        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(_ snapshot: HydrationCompanionSnapshot, supplements: WatchSupplementSnapshot) {
        guard let session, let data = try? snapshot.encoded(),
              supplements.ownerID == snapshot.ownerID,
              let supplementData = try? JSONEncoder().encode(supplements) else { return }
        // Both features share the one latest application context. Publishing a
        // checklist must never replace hydration or consume complication quota.
        var payload = session.applicationContext
        payload.removeValue(forKey: HydrationCompanionKeys.disconnected)
        payload.removeValue(forKey: HydrationCompanionKeys.disconnectedRevision)
        payload[HydrationCompanionKeys.snapshot] = data
        payload[WatchSupplementKeys.snapshot] = supplementData
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
#if os(iOS)
        let visibleSignature = HydrationComplicationRefreshPolicy.visibleSignature(
            ownerID: snapshot.ownerID,
            localDate: snapshot.localDate,
            totalML: snapshot.totalML,
            targetML: snapshot.targetML,
            composition: snapshot.composition
        )
        if HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
            complicationEnabled: session.isComplicationEnabled,
            remainingTransfers: session.remainingComplicationUserInfoTransfers,
            previousVisibleSignature: defaults.string(forKey: Self.visibleSignatureKey),
            newVisibleSignature: visibleSignature
        ) {
            session.transferCurrentComplicationUserInfo(payload)
            defaults.set(visibleSignature, forKey: Self.visibleSignatureKey)
        }
#endif
    }

    func publishDisconnected() {
        guard let session else { return }
        let payload: [String: Any] = [
            HydrationCompanionKeys.disconnected: true,
            HydrationCompanionKeys.disconnectedRevision:
                HydrationComplicationRefreshPolicy.revision(),
        ]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func send(_ command: WatchWorkoutCommand) {
        guard let session, let data = try? command.encoded() else { return }
        let payload: [String: Any] = [HydrationCompanionKeys.workoutCommand: data]
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        Task { @MainActor [weak self] in self?.companionRefreshHandler?() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in self?.companionRefreshHandler?() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        let mutation = (payload[HydrationCompanionKeys.mutation] as? Data)
            .flatMap { try? HydrationCompanionMutation.decode($0) }
        let supplementMutation = (payload[WatchSupplementKeys.mutation] as? Data)
            .flatMap { try? JSONDecoder().decode(WatchSupplementMutation.self, from: $0) }
        let requestsSnapshot = payload[WatchSupplementKeys.request] as? Bool == true
        Task { @MainActor [weak self] in
            if requestsSnapshot { self?.companionRefreshHandler?() }
            if let mutation { await self?.mutationHandler?(mutation) }
            if let supplementMutation { await self?.supplementMutationHandler?(supplementMutation) }
        }
    }
}
