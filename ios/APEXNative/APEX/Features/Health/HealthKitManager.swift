import Foundation
import HealthKit
import Observation

struct HealthSnapshot: Sendable {
    let date: String
    let weightKG: Double?
    let vo2Max: Double?
    let restingHeartRate: Double?
    let dietaryWaterL: Double?
    let importableDietaryWaterL: Double?
    let steps: Double?
    let activeEnergyKcal: Double?
    let exerciseMinutes: Double?
    let sleepDurationHours: Double?
    let heartRateVariabilityMS: Double?
    let workouts: [HealthWorkoutSnapshot]
}

enum HealthWaterWriteState: Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

enum HealthWaterWriteError: LocalizedError {
    case unavailable
    case denied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health water tracking is unavailable."
        case .denied:
            return "Water write access is off. Enable APEX in Health > Data Access & Devices."
        }
    }
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

struct HealthWaterTotals: Sendable {
    let total: Double?
    let importableDrink: Double?

    static let unavailable = HealthWaterTotals(total: nil, importableDrink: nil)
}

enum HealthMetricRead<Value: Sendable>: Sendable {
    case available(Value)
    case unavailable

    static func capture(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> HealthMetricRead<Value> {
        do {
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            return .available(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable
        }
    }

    var completed: Bool {
        switch self {
        case .available: true
        case .unavailable: false
        }
    }

    func resolved(or fallback: @autoclosure () -> Value) -> Value {
        switch self {
        case let .available(value): value
        case .unavailable: fallback()
        }
    }
}

struct HealthTodayReadings: Sendable {
    let weightKG: HealthMetricRead<Double?>
    let vo2Max: HealthMetricRead<Double?>
    let restingHeartRate: HealthMetricRead<Double?>
    let dietaryWater: HealthMetricRead<HealthWaterTotals>
    let steps: HealthMetricRead<Double?>
    let activeEnergyKcal: HealthMetricRead<Double?>
    let exerciseMinutes: HealthMetricRead<Double?>
    let sleepDurationHours: HealthMetricRead<Double?>
    let heartRateVariabilityMS: HealthMetricRead<Double?>
    let workouts: HealthMetricRead<[HealthWorkoutSnapshot]>

    var hasCompletedQuery: Bool {
        weightKG.completed
            || vo2Max.completed
            || restingHeartRate.completed
            || dietaryWater.completed
            || steps.completed
            || activeEnergyKcal.completed
            || exerciseMinutes.completed
            || sleepDurationHours.completed
            || heartRateVariabilityMS.completed
            || workouts.completed
    }

    func snapshot(date: String) -> HealthSnapshot {
        let water = dietaryWater.resolved(or: .unavailable)
        return HealthSnapshot(
            date: date,
            weightKG: weightKG.resolved(or: nil),
            vo2Max: vo2Max.resolved(or: nil),
            restingHeartRate: restingHeartRate.resolved(or: nil),
            dietaryWaterL: water.total,
            importableDietaryWaterL: water.importableDrink,
            steps: steps.resolved(or: nil),
            activeEnergyKcal: activeEnergyKcal.resolved(or: nil),
            exerciseMinutes: exerciseMinutes.resolved(or: nil),
            sleepDurationHours: sleepDurationHours.resolved(or: nil),
            heartRateVariabilityMS: heartRateVariabilityMS.resolved(or: nil),
            workouts: workouts.resolved(or: [])
        )
    }
}

enum HealthTodayReadError: Error, Equatable {
    case allQueriesUnavailable
}

struct HealthTodayQueryPlan: Sendable {
    let weightKG: @Sendable () async throws -> Double?
    let vo2Max: @Sendable () async throws -> Double?
    let restingHeartRate: @Sendable () async throws -> Double?
    let dietaryWater: @Sendable () async throws -> HealthWaterTotals
    let steps: @Sendable () async throws -> Double?
    let activeEnergyKcal: @Sendable () async throws -> Double?
    let exerciseMinutes: @Sendable () async throws -> Double?
    let sleepDurationHours: @Sendable () async throws -> Double?
    let heartRateVariabilityMS: @Sendable () async throws -> Double?
    let workouts: @Sendable () async throws -> [HealthWorkoutSnapshot]

    func snapshot(date: String) async throws -> HealthSnapshot {
        async let weight = HealthMetricRead<Double?>.capture(weightKG)
        async let vo2 = HealthMetricRead<Double?>.capture(vo2Max)
        async let resting = HealthMetricRead<Double?>.capture(restingHeartRate)
        async let water = HealthMetricRead<HealthWaterTotals>.capture(dietaryWater)
        async let stepCount = HealthMetricRead<Double?>.capture(steps)
        async let energy = HealthMetricRead<Double?>.capture(activeEnergyKcal)
        async let exercise = HealthMetricRead<Double?>.capture(exerciseMinutes)
        async let sleep = HealthMetricRead<Double?>.capture(sleepDurationHours)
        async let hrv = HealthMetricRead<Double?>.capture(heartRateVariabilityMS)
        async let workoutList = HealthMetricRead<[HealthWorkoutSnapshot]>.capture(workouts)

        let readings = try await HealthTodayReadings(
            weightKG: weight,
            vo2Max: vo2,
            restingHeartRate: resting,
            dietaryWater: water,
            steps: stepCount,
            activeEnergyKcal: energy,
            exerciseMinutes: exercise,
            sleepDurationHours: sleep,
            heartRateVariabilityMS: hrv,
            workouts: workoutList
        )
        try Task.checkCancellation()
        guard readings.hasCompletedQuery else {
            throw HealthTodayReadError.allQueriesUnavailable
        }
        return readings.snapshot(date: date)
    }
}

extension HealthSnapshot {
    var hasImportableSignal: Bool {
        (steps ?? 0) > 0
            || (activeEnergyKcal ?? 0) > 0
            || (exerciseMinutes ?? 0) > 0
            || weightKG != nil
            || vo2Max != nil
            || restingHeartRate != nil
            || dietaryWaterL != nil
            || sleepDurationHours != nil
            || heartRateVariabilityMS != nil
            || !workouts.isEmpty
    }
}

@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    var isAvailable = HKHealthStore.isHealthDataAvailable()
    var isAuthorized = false
    var waterWriteState: HealthWaterWriteState = .notDetermined
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
            refreshWaterWriteState()
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
        refreshWaterWriteState()
        guard let snapshot = try? await readToday() else { return nil }
        guard snapshot.hasImportableSignal else { return nil }
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

        let plan = HealthTodayQueryPlan(
            weightKG: { [self] in
                try await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
            },
            vo2Max: { [self] in
                try await latestQuantity(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
            },
            restingHeartRate: { [self] in
                try await latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
            },
            dietaryWater: { [self] in
                try await dietaryWaterTotals(start: start, end: end)
            },
            steps: { [self] in
                try await cumulativeQuantity(.stepCount, unit: .count(), start: start, end: end)
            },
            activeEnergyKcal: { [self] in
                try await cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
            },
            exerciseMinutes: { [self] in
                try await cumulativeQuantity(.appleExerciseTime, unit: .minute(), start: start, end: end)
            },
            sleepDurationHours: { [self] in
                try await sleepDurationHours(endingAt: end)
            },
            heartRateVariabilityMS: { [self] in
                try await latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
            },
            workouts: { [self] in
                try await workoutSnapshots(start: start, end: end)
            }
        )
        return try await plan.snapshot(date: Date().apexDateKey)
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
        guard liters.isFinite, liters > 0 else { return }
        let type = try await authorizedWaterType()
        let identifier = UUID()
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .liter(), doubleValue: liters),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyExternalUUID: identifier.uuidString,
                HKMetadataKeySyncIdentifier: "apex.hydration.phone.\(identifier.uuidString.lowercased())",
                HKMetadataKeySyncVersion: 1,
            ]
        )
        try await store.save(sample)
    }

    /// Mirrors the day's food-derived water as one replaceable HealthKit fact.
    /// A stable account/day identifier prevents meal edits from accumulating
    /// duplicate samples while retaining provenance for other apps.
    func syncFoodWater(liters: Double, on date: Date, accountID: UUID) async throws {
        guard date <= Date().addingTimeInterval(60) else { return }
        let type = try await authorizedWaterType()
        let dateKey = date.apexDateKey
        let syncIdentifier = HydrationReconciliation.foodSyncIdentifier(
            accountID: accountID,
            dateKey: dateKey
        )
        let defaults = UserDefaults.standard
        let amountKey = "apex.hk.food.amount.\(syncIdentifier)"
        let normalized = liters.isFinite ? max(0, (liters * 1_000).rounded() / 1_000) : 0
        if let previous = defaults.object(forKey: amountKey) as? Double,
           abs(previous - normalized) < 0.000_5 {
            return
        }

        let versionKey = "apex.hk.food.version.\(syncIdentifier)"
        let nextVersion = max(
            defaults.integer(forKey: versionKey) + 1,
            Int(Date().timeIntervalSince1970)
        )
        if normalized <= 0.000_5 {
            let authored = try await foodSamples(
                type: type,
                syncIdentifier: syncIdentifier,
                date: date
            )
            if !authored.isEmpty { try await store.delete(authored) }
        } else {
            let dayStart = Calendar.current.startOfDay(for: date)
            let noon = Calendar.current.date(byAdding: .hour, value: 12, to: dayStart) ?? date
            let timestamp = min(noon, Date())
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .liter(), doubleValue: normalized),
                start: timestamp,
                end: timestamp,
                metadata: [
                    HKMetadataKeySyncIdentifier: syncIdentifier,
                    HKMetadataKeySyncVersion: nextVersion,
                    HKMetadataKeyFoodType: "Food-derived water",
                    HydrationReconciliation.foodMetadataKey: HydrationReconciliation.foodMetadataValue,
                ]
            )
            try await store.save(sample)
        }
        defaults.set(nextVersion, forKey: versionKey)
        defaults.set(normalized, forKey: amountKey)
    }

    func reconnectWaterAccess() async {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        else {
            waterWriteState = .unavailable
            message = HealthWaterWriteError.unavailable.localizedDescription
            return
        }
        do {
            try await store.requestAuthorization(toShare: [type], read: [type])
            refreshWaterWriteState()
            message = waterWriteState == .authorized
                ? "Apple Health water sharing is connected."
                : HealthWaterWriteError.denied.localizedDescription
        } catch {
            refreshWaterWriteState()
            message = error.localizedDescription
        }
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

    private func dietaryWaterTotals(start: Date, end: Date) async throws -> HealthWaterTotals {
        guard let type = quantity(.dietaryWater) else {
            return HealthWaterTotals(total: nil, importableDrink: nil)
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, rawSamples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: rawSamples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return HealthWaterTotals(total: 0, importableDrink: 0) }

        var classified: [HydrationReconciliation.Sample] = []
        var total = 0.0
        for sample in samples {
            let liters = sample.quantity.doubleValue(for: .liter())
            guard liters.isFinite, liters > 0 else { continue }
            total += liters
            let bundle = sample.sourceRevision.source.bundleIdentifier
            let isFood = sample.metadata?[HydrationReconciliation.foodMetadataKey] as? String
                == HydrationReconciliation.foodMetadataValue
            let source: HydrationReconciliation.Source
            if isFood {
                source = .apexFood
            } else if bundle == HydrationReconciliation.phoneBundleIdentifier {
                source = .apexPhone
            } else if bundle == HydrationReconciliation.watchBundleIdentifier {
                source = .apexWatch
            } else {
                source = .external
            }
            classified.append(.init(liters: liters, source: source))
        }
        return HealthWaterTotals(
            total: total,
            importableDrink: HydrationReconciliation.importableDrinkLiters(classified)
        )
    }

    private func authorizedWaterType() async throws -> HKQuantityType {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        else {
            waterWriteState = .unavailable
            throw HealthWaterWriteError.unavailable
        }
        if store.authorizationStatus(for: type) == .notDetermined {
            try await store.requestAuthorization(toShare: [type], read: [type])
        }
        refreshWaterWriteState()
        guard waterWriteState == .authorized else { throw HealthWaterWriteError.denied }
        return type
    }

    private func refreshWaterWriteState() {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        else {
            waterWriteState = .unavailable
            return
        }
        switch store.authorizationStatus(for: type) {
        case .notDetermined:
            waterWriteState = .notDetermined
        case .sharingDenied:
            waterWriteState = .denied
        case .sharingAuthorized:
            waterWriteState = .authorized
        @unknown default:
            waterWriteState = .notDetermined
        }
    }

    private func foodSamples(
        type: HKQuantityType,
        syncIdentifier: String,
        date: Date
    ) async throws -> [HKQuantitySample] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, rawSamples, error in
                if let error { continuation.resume(throwing: error); return }
                let matching = (rawSamples as? [HKQuantitySample] ?? []).filter {
                    $0.metadata?[HKMetadataKeySyncIdentifier] as? String == syncIdentifier
                }
                continuation.resume(returning: matching)
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
