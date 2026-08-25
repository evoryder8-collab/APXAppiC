import SwiftUI
import HealthKit
import WatchKit

@MainActor
final class WatchWorkoutSessionController: NSObject, ObservableObject {
    static let shared = WatchWorkoutSessionController()

    @Published private(set) var isActive = false
    @Published private(set) var activityName = "Workout"

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start(_ configuration: HKWorkoutConfiguration) async {
        if session != nil { return }
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
            session = nil
            builder = nil
            isActive = false
        }
    }

    func stop() async {
        guard let session, let builder else { return }
        let end = Date()
        session.end()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.endCollection(withEnd: end) { _, _ in continuation.resume() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.finishWorkout { _, _ in continuation.resume() }
        }
        self.session = nil
        self.builder = nil
        isActive = false
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
        Task { @MainActor [weak self] in
            self?.session = nil
            self?.builder = nil
            self?.isActive = false
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.session = nil
            self?.builder = nil
            self?.isActive = false
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
            await WatchWorkoutSessionController.shared.start(workoutConfiguration)
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
