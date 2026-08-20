import Foundation
import HealthKit
import Observation

struct HealthSnapshot: Sendable {
    let date: String
    let weightKG: Double?
    let vo2Max: Double?
    let restingHeartRate: Double?
    let dietaryWaterL: Double?
    let steps: Double?
    let activeEnergyKcal: Double?
    let exerciseMinutes: Double?
    let sleepDurationHours: Double?
    let heartRateVariabilityMS: Double?
    let workouts: [HealthWorkoutSnapshot]
}

struct HealthWorkoutSnapshot: Hashable, Sendable {
    let id: UUID
    let date: String
    let startedAt: Date
    let endedAt: Date
    let kind: String
    let activityName: String
    let durationMinutes: Int
    let distanceKM: Double?
    let activeEnergyKcal: Double?
}

@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    var isAvailable = HKHealthStore.isHealthDataAvailable()
    var isAuthorized = false
    var isSyncing = false
    var lastSnapshot: HealthSnapshot?
    var message: String?

    /// Not private: the history reader lives in its own file to keep the
    /// today-path and the backfill path separate.
    let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var importHandler: (@MainActor @Sendable (HealthSnapshot) async -> Void)?

    private init() {}

    func requestAccessAndImport() async -> HealthSnapshot? {
        guard isAvailable else {
            message = "Apple Health is not available on this device."
            return nil
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let read = Set(readTypes)
            let share = Set(writeTypes)
            try await store.requestAuthorization(toShare: share, read: read)
            isAuthorized = true
            let snapshot = try await readToday()
            lastSnapshot = snapshot
            message = "Apple Health synced. APEX only imported the categories you allowed."
            await enableBackgroundDelivery()
            startBackgroundMonitoring(handler: importHandler)
            return snapshot
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// Read today's activity without ever raising a permission prompt.
    ///
    /// The card used to show "no wearable data" on any day the user had not
    /// tapped refresh, which is most days: the phone counts steps whether or
    /// not a watch is worn, and that was simply being thrown away. Reading an
    /// unauthorised type returns nothing rather than prompting, so this is safe
    /// to call on every open.
    ///
    /// Returns nil when nothing was readable, so a silent failure never
    /// overwrites a hand-entered day with zeroes.
    func silentRefresh() async -> HealthSnapshot? {
        guard isAvailable else { return nil }
        guard let snapshot = try? await readToday() else { return nil }
        let hasActivity = (snapshot.steps ?? 0) > 0
            || (snapshot.activeEnergyKcal ?? 0) > 0
            || (snapshot.exerciseMinutes ?? 0) > 0
        guard hasActivity || snapshot.weightKG != nil || snapshot.sleepDurationHours != nil else {
            return nil
        }
        isAuthorized = true
        lastSnapshot = snapshot
        /* Keep it current for the rest of the day rather than only at open. */
        await enableBackgroundDelivery()
        startBackgroundMonitoring(handler: importHandler)
        return snapshot
    }

    func readToday() async throws -> HealthSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = Date()

        async let weight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let vo2 = latestQuantity(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let resting = latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let water = cumulativeQuantity(.dietaryWater, unit: .liter(), start: start, end: end)
        async let steps = cumulativeQuantity(.stepCount, unit: .count(), start: start, end: end)
        async let energy = cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exercise = cumulativeQuantity(.appleExerciseTime, unit: .minute(), start: start, end: end)
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let sleep = sleepDurationHours(endingAt: end)
        async let workouts = workoutSnapshots(start: start, end: end)

        return try await HealthSnapshot(
            date: Date().apexDateKey,
            weightKG: weight,
            vo2Max: vo2,
            restingHeartRate: resting,
            dietaryWaterL: water,
            steps: steps,
            activeEnergyKcal: energy,
            exerciseMinutes: exercise,
            sleepDurationHours: sleep,
            heartRateVariabilityMS: hrv,
            workouts: workouts
        )
    }

    func startBackgroundMonitoring(
        handler: (@MainActor @Sendable (HealthSnapshot) async -> Void)?
    ) {
        if let handler { importHandler = handler }
        guard observerQueries.isEmpty, isAvailable else { return }
        for sampleType in [
            quantity(.bodyMass), quantity(.dietaryWater), quantity(.vo2Max),
            quantity(.restingHeartRate), quantity(.stepCount), quantity(.activeEnergyBurned),
            quantity(.appleExerciseTime), quantity(.heartRateVariabilitySDNN),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis), HKObjectType.workoutType()
        ].compactMap({ $0 }) {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                completion()
                Task { @MainActor [weak self] in
                    guard let self, let snapshot = try? await self.readToday() else { return }
                    self.lastSnapshot = snapshot
                    if let importHandler = self.importHandler { await importHandler(snapshot) }
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    func saveWater(liters: Double, date: Date = .now) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .liter(), doubleValue: liters),
            start: date,
            end: date,
            metadata: [HKMetadataKeyExternalUUID: UUID().uuidString]
        )
        try await store.save(sample)
    }

    private var readTypes: [HKObjectType] {
        [
            quantity(.bodyMass), quantity(.vo2Max), quantity(.restingHeartRate),
            quantity(.dietaryWater), quantity(.stepCount), quantity(.activeEnergyBurned),
            quantity(.appleExerciseTime), quantity(.heartRateVariabilitySDNN),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis), HKObjectType.workoutType()
        ].compactMap { $0 }
    }

    private var writeTypes: [HKSampleType] {
        [quantity(.dietaryWater), HKObjectType.workoutType()].compactMap { $0 }
    }

    private func quantity(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: identifier)
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = quantity(identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func cumulativeQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        guard let type = quantity(identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sleepDurationHours(endingAt end: Date) async throws -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let start = Calendar.current.date(byAdding: .hour, value: -18, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let asleep = (samples as? [HKCategorySample] ?? []).compactMap { sample -> DateInterval? in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                    switch value {
                    case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                        return DateInterval(start: sample.startDate, end: sample.endDate)
                    default:
                        return nil
                    }
                }
                guard !asleep.isEmpty else { continuation.resume(returning: nil); return }
                var merged: [DateInterval] = []
                for interval in asleep.sorted(by: { $0.start < $1.start }) {
                    if let last = merged.last, interval.start <= last.end {
                        merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
                    } else {
                        merged.append(interval)
                    }
                }
                continuation.resume(returning: merged.reduce(0) { $0 + $1.duration } / 3_600)
            }
            store.execute(query)
        }
    }

    private func workoutSnapshots(start: Date, end: Date) async throws -> [HealthWorkoutSnapshot] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    let identity = Self.workoutIdentity(workout.workoutActivityType)
                    return HealthWorkoutSnapshot(
                        id: workout.uuid,
                        date: workout.startDate.apexDateKey,
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        kind: identity.kind,
                        activityName: identity.name,
                        durationMinutes: Int((workout.duration / 60).rounded()),
                        distanceKM: workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                        activeEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    nonisolated private static func workoutIdentity(_ type: HKWorkoutActivityType) -> (kind: String, name: String) {
        switch type {
        case .running: ("run", "Running")
        case .walking, .hiking: ("walk", type == .hiking ? "Hiking" : "Walking")
        case .traditionalStrengthTraining, .functionalStrengthTraining: ("strength", "Strength training")
        case .highIntensityIntervalTraining: ("hiit", "High-intensity intervals")
        case .yoga, .flexibility, .mindAndBody: ("mobility", "Mobility or yoga")
        default: ("other", "Apple Health workout")
        }
    }

    private func enableBackgroundDelivery() async {
        for type in [
            quantity(.bodyMass), quantity(.dietaryWater), quantity(.vo2Max),
            quantity(.restingHeartRate), quantity(.stepCount), quantity(.activeEnergyBurned),
            quantity(.appleExerciseTime), quantity(.heartRateVariabilitySDNN),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis), HKObjectType.workoutType()
        ].compactMap({ $0 }) {
            try? await store.enableBackgroundDelivery(for: type, frequency: .hourly)
        }
    }
}
