import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class HydrationPhoneConnectivity: NSObject, WCSessionDelegate {
    var mutationHandler: ((HydrationCompanionMutation) async -> Void)?
    private let session: WCSession?

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
        do {
            try session.updateApplicationContext([HydrationCompanionKeys.snapshot: data])
        } catch {
            // The next real hydration change or app activation sends the latest
            // snapshot again. There is intentionally no retry timer or polling.
        }
    }

    func publishDisconnected() {
        guard let session else { return }
        try? session.updateApplicationContext([HydrationCompanionKeys.disconnected: true])
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
