import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchHydrationConnectivity: NSObject, WCSessionDelegate {
    var snapshotHandler: ((HydrationCompanionSnapshot) -> Void)?
    var supplementSnapshotHandler: ((WatchSupplementSnapshot) -> Void)?
    var disconnectHandler: ((String) -> Void)?
    var workoutCommandHandler: ((WatchWorkoutCommand) -> Void)?
    var readyHandler: (() -> Void)?
    private let session: WCSession?

    init(isEnabled: Bool = true) {
        if isEnabled, WCSession.isSupported() {
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

    func send(_ mutation: WatchSupplementMutation) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(mutation) else { return }
        let payload: [String: Any] = [WatchSupplementKeys.mutation: data]
        let isQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo[WatchSupplementKeys.mutation] as? Data,
                  let decoded = try? JSONDecoder().decode(WatchSupplementMutation.self, from: queued)
            else { return false }
            return decoded.id == mutation.id
        }
        if !isQueued { session.transferUserInfo(payload) }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func requestLatest() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchSupplementKeys.request: true], replyHandler: nil, errorHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil else { return }
        receive(session.receivedApplicationContext, notifyReady: true)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in self?.readyHandler?() }
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

    nonisolated private func receive(_ payload: [String: Any], notifyReady: Bool = false) {
        let disconnected = payload[HydrationCompanionKeys.disconnected] as? Bool == true
        let revision = payload[HydrationCompanionKeys.disconnectedRevision] as? String
            ?? HydrationComplicationRefreshPolicy.revision()
        let command = (payload[HydrationCompanionKeys.workoutCommand] as? Data)
            .flatMap { try? WatchWorkoutCommand.decode($0) }
        let snapshot = (payload[HydrationCompanionKeys.snapshot] as? Data)
            .flatMap { try? HydrationCompanionSnapshot.decode($0) }
        let supplements = (payload[WatchSupplementKeys.snapshot] as? Data)
            .flatMap { try? JSONDecoder().decode(WatchSupplementSnapshot.self, from: $0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if disconnected {
                self.disconnectHandler?(revision)
                return
            }
            // Account authorization from hydration precedes the checklist in
            // the same actor turn; independently scheduled callbacks can race.
            if let snapshot { self.snapshotHandler?(snapshot) }
            if let supplements { self.supplementSnapshotHandler?(supplements) }
            if let command { self.workoutCommandHandler?(command) }
            if notifyReady { self.readyHandler?() }
        }
    }
}
