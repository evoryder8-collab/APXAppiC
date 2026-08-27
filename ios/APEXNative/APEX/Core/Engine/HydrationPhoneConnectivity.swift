import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class HydrationPhoneConnectivity: NSObject, WCSessionDelegate {
    var mutationHandler: ((HydrationCompanionMutation) async -> Void)?
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

    func publish(_ snapshot: HydrationCompanionSnapshot) {
        guard let session, let data = try? snapshot.encoded() else { return }
        let payload = [HydrationCompanionKeys.snapshot: data]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // The next real hydration change or app activation sends the latest
            // snapshot again. There is intentionally no retry timer or polling.
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
        try? session.updateApplicationContext([
            HydrationCompanionKeys.disconnected: true,
            HydrationCompanionKeys.disconnectedRevision:
                HydrationComplicationRefreshPolicy.revision(),
        ])
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
    ) {}

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
        guard let data = payload[HydrationCompanionKeys.mutation] as? Data,
              let mutation = try? HydrationCompanionMutation.decode(data) else { return }
        Task { @MainActor [weak self] in
            await self?.mutationHandler?(mutation)
        }
    }
}
