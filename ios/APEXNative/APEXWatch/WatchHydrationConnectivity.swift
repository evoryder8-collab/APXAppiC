import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchHydrationConnectivity: NSObject, WCSessionDelegate {
    var snapshotHandler: ((HydrationCompanionSnapshot) -> Void)?
    var disconnectHandler: ((String) -> Void)?
    var workoutCommandHandler: ((WatchWorkoutCommand) -> Void)?
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

    func send(_ mutation: HydrationCompanionMutation) {
        guard let session, let data = try? mutation.encoded() else { return }
        let payload: [String: Any] = [HydrationCompanionKeys.mutation: data]
        // Keep a durable OS-managed copy even when the phone is reachable.
        // The phone deduplicates by mutation id, so the immediate path only
        // improves latency and cannot double-log an entry.
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
        guard error == nil else { return }
        receive(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        if payload[HydrationCompanionKeys.disconnected] as? Bool == true {
            let revision = payload[HydrationCompanionKeys.disconnectedRevision] as? String
                ?? HydrationComplicationRefreshPolicy.revision()
            Task { @MainActor [weak self] in self?.disconnectHandler?(revision) }
            return
        }
        if let data = payload[HydrationCompanionKeys.workoutCommand] as? Data,
           let command = try? WatchWorkoutCommand.decode(data) {
            Task { @MainActor [weak self] in self?.workoutCommandHandler?(command) }
            return
        }
        guard let data = payload[HydrationCompanionKeys.snapshot] as? Data,
              let snapshot = try? HydrationCompanionSnapshot.decode(data) else { return }
        Task { @MainActor [weak self] in
            self?.snapshotHandler?(snapshot)
        }
    }
}
