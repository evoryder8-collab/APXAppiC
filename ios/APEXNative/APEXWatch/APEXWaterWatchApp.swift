import Foundation
import SwiftUI
import HealthKit
import WatchKit

@MainActor
final class WatchWorkoutSessionController: NSObject, ObservableObject {
    static let shared = WatchWorkoutSessionController()

    @Published private(set) var isActive = false
    @Published private(set) var activityName = "Workout"

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionLaunchID: UUID?
    private var activeOwnerID: UUID?
    private var pendingConfigurations: [HKWorkoutConfiguration] = []
    private var launchLedger: WatchWorkoutLaunchLedger
    private var isDrainingConfigurations = false
    private var boundaryStopsInFlight: Set<UUID> = []

    private static let launchLedgerKey =
        "ch.apexperformance.APEX.watch.workout-launch-ledger.v1"

    private override init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.launchLedgerKey),
           let restored = try? JSONDecoder().decode(WatchWorkoutLaunchLedger.self, from: data) {
            launchLedger = restored
        } else {
            launchLedger = WatchWorkoutLaunchLedger()
        }
        super.init()
    }

    /// HealthKit and WatchConnectivity are separate delivery paths. Hold an
    /// early configuration until the phone's owner-qualified launch identity
    /// arrives instead of starting an anonymous workout.
    func receive(_ configuration: HKWorkoutConfiguration) async {
        pendingConfigurations.append(configuration)
        await drainConfigurations()
    }

    func receive(_ command: WatchWorkoutCommand) async {
        let effect = launchLedger.receive(command)
        persistLaunchLedger()
        if case .stopActive(let launchID) = effect {
            await stopSession(matching: launchID)
        }
        await drainConfigurations()
    }

    func updateActiveOwner(_ ownerID: UUID?, revision: String? = nil) {
        let previousOwnerID = activeOwnerID
        activeOwnerID = ownerID

        let ownersToRevoke: Set<UUID>
        if let previousOwnerID, previousOwnerID != ownerID {
            ownersToRevoke = [previousOwnerID]
        } else if previousOwnerID == nil, let ownerID {
            // A restored ledger can outlive the hydration store. When its
            // canonical snapshot resolves, retire only launches from another
            // owner before accepting this owner's configuration.
            ownersToRevoke = launchLedger.representedOwnerIDs.subtracting([ownerID])
        } else {
            ownersToRevoke = []
        }
        let boundaryRevision = revision ?? HydrationComplicationRefreshPolicy.revision()
        var launchIDsToStop: [UUID] = []
        for oldOwnerID in ownersToRevoke {
            if case .stopActive(let launchID) = launchLedger.revoke(
                ownerID: oldOwnerID,
                revision: boundaryRevision
            ) {
                launchIDsToStop.append(launchID)
            }
        }
        persistLaunchLedger()
        scheduleBoundaryStops(launchIDsToStop)
    }

    func disconnect(ownerID: UUID?, revision: String) {
        guard let disconnectedOwnerID = ownerID ?? launchLedger.active?.ownerID else { return }
        activeOwnerID = WatchWorkoutOwnerBoundary.ownerAfterDisconnect(
            activeOwnerID: activeOwnerID,
            disconnectedOwnerID: disconnectedOwnerID
        )
        let effect = launchLedger.disconnect(
            ownerID: disconnectedOwnerID,
            revision: revision
        )
        persistLaunchLedger()
        var launchIDsToStop: [UUID] = []
        if case .stopActive(let launchID) = effect {
            launchIDsToStop.append(launchID)
        }
        scheduleBoundaryStops(launchIDsToStop)
    }

    private func drainConfigurations() async {
        guard !isDrainingConfigurations, boundaryStopsInFlight.isEmpty else { return }
        isDrainingConfigurations = true
        defer { isDrainingConfigurations = false }

        while !pendingConfigurations.isEmpty,
              let resolution = launchLedger.resolveNextConfiguration(
                  activeOwnerID: activeOwnerID
              ) {
            let configuration = pendingConfigurations.removeFirst()
            persistLaunchLedger()
            switch resolution {
            case .discard:
                continue
            case .start(let intent):
                await start(configuration, intent: intent)
            }
        }
    }

    private func scheduleBoundaryStops(_ launchIDs: [UUID]) {
        let newlyScheduled = launchIDs.filter {
            boundaryStopsInFlight.insert($0).inserted
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for launchID in newlyScheduled {
                await stopSession(matching: launchID)
                boundaryStopsInFlight.remove(launchID)
            }
            await drainConfigurations()
        }
    }

    private func start(
        _ configuration: HKWorkoutConfiguration,
        intent: WatchWorkoutLaunchIntent
    ) async {
        guard session == nil,
              launchLedger.permitsStart(
                  launchID: intent.id,
                  ownerID: intent.ownerID,
                  activeOwnerID: activeOwnerID
              ) else {
            launchLedger.finishActive(launchID: intent.id)
            persistLaunchLedger()
            return
        }
        do {
            let workoutType = HKObjectType.workoutType()
            var share: Set<HKSampleType> = [workoutType]
            if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                share.insert(energy)
            }
            let read: Set<HKObjectType> = [
                HKObjectType.quantityType(forIdentifier: .heartRate),
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            ].compactMap { $0 }.reduce(into: Set<HKObjectType>()) { $0.insert($1) }
            try await healthStore.requestAuthorization(toShare: share, read: read)

            // Authorization can present UI and suspend this task. Recheck the
            // durable launch after every await so a stop or account disconnect
            // that arrived meanwhile wins causally.
            guard session == nil,
                  launchLedger.permitsStart(
                      launchID: intent.id,
                      ownerID: intent.ownerID,
                      activeOwnerID: activeOwnerID
                  ) else { return }

            let workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            workoutSession.delegate = self
            workoutBuilder.delegate = self
            session = workoutSession
            builder = workoutBuilder
            sessionLaunchID = intent.id
            activityName = Self.label(for: configuration.activityType)
            isActive = true
            let start = Date()
            workoutSession.startActivity(with: start)
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                workoutBuilder.beginCollection(withStart: start) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: WatchWorkoutSessionError.collectionFailed) }
                }
            }
        } catch {
            if sessionLaunchID == intent.id {
                session?.end()
            }
            launchLedger.finishActive(launchID: intent.id)
            persistLaunchLedger()
            clearSession(matching: intent.id)
        }
    }

    func stop() async {
        if let launchID = sessionLaunchID ?? launchLedger.active?.id {
            launchLedger.finishActive(launchID: launchID)
            persistLaunchLedger()
            await stopSession(matching: launchID)
            return
        }
        await stopUnidentifiedSession()
    }

    private func stopSession(matching launchID: UUID) async {
        guard sessionLaunchID == launchID else { return }
        await stopUnidentifiedSession(expectedLaunchID: launchID)
    }

    private func stopUnidentifiedSession(expectedLaunchID: UUID? = nil) async {
        guard let session, let builder else {
            if let expectedLaunchID { clearSession(matching: expectedLaunchID) }
            return
        }
        let end = Date()
        session.end()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.endCollection(withEnd: end) { _, _ in continuation.resume() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.finishWorkout { _, _ in continuation.resume() }
        }
        if let expectedLaunchID {
            clearSession(matching: expectedLaunchID)
        } else {
            self.session = nil
            self.builder = nil
            sessionLaunchID = nil
            isActive = false
        }
    }

    private func clearSession(matching launchID: UUID) {
        guard sessionLaunchID == launchID else { return }
        self.session = nil
        self.builder = nil
        sessionLaunchID = nil
        isActive = false
    }

    private func handleSessionTermination(sessionIdentifier: ObjectIdentifier) {
        guard let session, ObjectIdentifier(session) == sessionIdentifier else { return }
        if let launchID = sessionLaunchID {
            launchLedger.finishActive(launchID: launchID)
            persistLaunchLedger()
            clearSession(matching: launchID)
        } else {
            self.session = nil
            builder = nil
            isActive = false
        }
    }

    private func persistLaunchLedger() {
        guard let data = try? JSONEncoder().encode(launchLedger) else { return }
        defaults.set(data, forKey: Self.launchLedgerKey)
    }

    private static func label(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "Strength"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        case .running: "Running"
        case .cycling: "Cycling"
        case .walking: "Walking"
        default: "Workout"
        }
    }
}

private enum WatchWorkoutSessionError: Error { case collectionFailed }

extension WatchWorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            self?.handleSessionTermination(sessionIdentifier: sessionIdentifier)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            self?.handleSessionTermination(sessionIdentifier: sessionIdentifier)
        }
    }
}

extension WatchWorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}
}

final class APEXWatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchWorkoutSessionController.shared.receive(workoutConfiguration)
        }
    }
}

@main
struct APEXWaterWatchApp: App {
    @WKApplicationDelegateAdaptor(APEXWatchApplicationDelegate.self) private var appDelegate
    @StateObject private var hydration = WatchHydrationStore()
    @StateObject private var workout = WatchWorkoutSessionController.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHydrationView()
            }
            .environmentObject(hydration)
            .environmentObject(workout)
        }
    }
}
