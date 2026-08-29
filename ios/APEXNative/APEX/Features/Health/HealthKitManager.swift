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
    let hydrationSamples: [HealthHydrationSample]
    let deletedHydrationSampleIDs: Set<UUID>
    let steps: Double?
    let activeEnergyKcal: Double?
    let exerciseMinutes: Double?
    let sleepDurationHours: Double?
    let heartRateVariabilityMS: Double?
    let workouts: [HealthWorkoutSnapshot]
}

struct HealthHydrationSample: Sendable {
    let id: UUID
    let liters: Double
    let occurredAt: Date
    let source: HydrationReconciliation.Source
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String
    let ownerID: UUID?
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
    let activityNameKey: String
    let durationMinutes: Int
    let distanceKM: Double?
    let activeEnergyKcal: Double?
    let sourceName: String
    let sourceBundleIdentifier: String
    let activityTypeRaw: Int
    let apexSessionID: UUID?

    init(
        id: UUID,
        date: String,
        startedAt: Date,
        endedAt: Date,
        kind: String,
        activityName: String,
        activityNameKey: String? = nil,
        durationMinutes: Int,
        distanceKM: Double?,
        activeEnergyKcal: Double?,
        sourceName: String = "Apple Health",
        sourceBundleIdentifier: String = "com.apple.health",
        activityTypeRaw: Int = Int(HKWorkoutActivityType.other.rawValue),
        apexSessionID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.activityName = activityName
        self.activityNameKey = activityNameKey ?? activityName
        self.durationMinutes = durationMinutes
        self.distanceKM = distanceKM
        self.activeEnergyKcal = activeEnergyKcal
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.activityTypeRaw = activityTypeRaw
        self.apexSessionID = apexSessionID
    }
}

struct HealthWaterTotals: Sendable {
    let total: Double?
    let importableDrink: Double?
    let samples: [HealthHydrationSample]
    let deletedSampleIDs: Set<UUID>

    init(
        total: Double?,
        importableDrink: Double?,
        samples: [HealthHydrationSample] = [],
        deletedSampleIDs: Set<UUID> = []
    ) {
        self.total = total
        self.importableDrink = importableDrink
        self.samples = samples
        self.deletedSampleIDs = deletedSampleIDs
    }

    static let unavailable = HealthWaterTotals(total: nil, importableDrink: nil)
}

enum HealthActivityEnergyResolver {
    static func resolve(
        activitySummaryKcal: Double?,
        cumulativeSampleKcal: Double?
    ) -> Double? {
        if let activitySummaryKcal, activitySummaryKcal.isFinite {
            return max(0, activitySummaryKcal)
        }
        guard let cumulativeSampleKcal, cumulativeSampleKcal.isFinite else {
            return nil
        }
        return max(0, cumulativeSampleKcal)
    }
}

enum HealthActivitySummaryQueryDay {
    static func components(for date: Date, calendar: Calendar) -> DateComponents {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.dateComponents([.calendar, .era, .year, .month, .day], from: date)
    }
}

private enum HealthActivityEnergyReadError: Error {
    case unavailable
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
            hydrationSamples: water.samples,
            deletedHydrationSampleIDs: water.deletedSampleIDs,
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

enum HealthWorkoutCatalog {
    struct Identity: Hashable, Sendable {
        let kind: String
        let nameKey: String
        let fallbackName: String
    }

    static var authoredNameKeys: Set<String> {
        let publicRawValues = Array(1...80) + [82, 83, 84, 3000]
        var keys = Set(publicRawValues.compactMap {
            HKWorkoutActivityType(rawValue: UInt($0)).map { identity(for: $0).nameKey }
        })
        keys.formUnion([
            identity(for: .cycling, isIndoor: true).nameKey,
            identity(for: .cycling, isIndoor: false).nameKey,
            identity(for: .running, isIndoor: true).nameKey,
            identity(for: .running, isIndoor: false).nameKey,
            identity(for: .walking, isIndoor: true).nameKey,
            identity(for: .walking, isIndoor: false).nameKey,
            "health.workout.unknown",
        ])
        return keys
    }

    static func identity(
        for type: HKWorkoutActivityType,
        isIndoor: Bool? = nil
    ) -> Identity {
        func item(_ kind: String, _ key: String, _ name: String) -> Identity {
            Identity(kind: kind, nameKey: "health.workout.\(key)", fallbackName: name)
        }

        switch type {
        case .americanFootball: return item("endurance", "american_football", "American Football")
        case .archery: return item("mobility", "archery", "Archery")
        case .australianFootball: return item("endurance", "australian_football", "Australian Football")
        case .badminton: return item("endurance", "badminton", "Badminton")
        case .baseball: return item("endurance", "baseball", "Baseball")
        case .basketball: return item("endurance", "basketball", "Basketball")
        case .bowling: return item("mobility", "bowling", "Bowling")
        case .boxing: return item("endurance", "boxing", "Boxing")
        case .climbing: return item("strength", "climbing", "Climbing")
        case .cricket: return item("endurance", "cricket", "Cricket")
        case .crossTraining: return item("strength", "cross_training", "Cross Training")
        case .curling: return item("endurance", "curling", "Curling")
        case .cycling:
            if isIndoor == true { return item("endurance", "indoor_cycling", "Indoor Cycling") }
            if isIndoor == false { return item("endurance", "outdoor_cycling", "Outdoor Cycling") }
            return item("endurance", "cycling", "Cycling")
        case .dance: return item("endurance", "dance", "Dance")
        case .danceInspiredTraining: return item("endurance", "dance_training", "Dance Training")
        case .elliptical: return item("endurance", "elliptical", "Elliptical")
        case .equestrianSports: return item("endurance", "equestrian_sports", "Equestrian Sports")
        case .fencing: return item("endurance", "fencing", "Fencing")
        case .fishing: return item("mobility", "fishing", "Fishing")
        case .functionalStrengthTraining: return item("strength", "functional_strength_training", "Functional Strength Training")
        case .golf: return item("endurance", "golf", "Golf")
        case .gymnastics: return item("strength", "gymnastics", "Gymnastics")
        case .handball: return item("endurance", "handball", "Handball")
        case .hiking: return item("endurance", "hiking", "Hiking")
        case .hockey: return item("endurance", "hockey", "Hockey")
        case .hunting: return item("endurance", "hunting", "Hunting")
        case .lacrosse: return item("endurance", "lacrosse", "Lacrosse")
        case .martialArts: return item("endurance", "martial_arts", "Martial Arts")
        case .mindAndBody: return item("mobility", "mind_and_body", "Mind and Body")
        case .mixedMetabolicCardioTraining: return item("endurance", "mixed_metabolic_cardio", "Mixed Metabolic Cardio")
        case .paddleSports: return item("endurance", "paddle_sports", "Paddle Sports")
        case .play: return item("endurance", "play", "Play")
        case .preparationAndRecovery: return item("mobility", "preparation_and_recovery", "Preparation and Recovery")
        case .racquetball: return item("endurance", "racquetball", "Racquetball")
        case .rowing: return item("endurance", "rowing", "Rowing")
        case .rugby: return item("endurance", "rugby", "Rugby")
        case .running:
            if isIndoor == true { return item("endurance", "indoor_run", "Indoor Run") }
            if isIndoor == false { return item("endurance", "outdoor_run", "Outdoor Run") }
            return item("endurance", "running", "Running")
        case .sailing: return item("endurance", "sailing", "Sailing")
        case .skatingSports: return item("endurance", "skating_sports", "Skating Sports")
        case .snowSports: return item("endurance", "snow_sports", "Snow Sports")
        case .soccer: return item("endurance", "soccer", "Soccer")
        case .softball: return item("endurance", "softball", "Softball")
        case .squash: return item("endurance", "squash", "Squash")
        case .stairClimbing: return item("endurance", "stair_climbing", "Stair Climbing")
        case .surfingSports: return item("endurance", "surfing_sports", "Surfing Sports")
        case .swimming: return item("endurance", "swimming", "Swimming")
        case .tableTennis: return item("endurance", "table_tennis", "Table Tennis")
        case .tennis: return item("endurance", "tennis", "Tennis")
        case .trackAndField: return item("endurance", "track_and_field", "Track and Field")
        case .traditionalStrengthTraining: return item("strength", "traditional_strength_training", "Traditional Strength Training")
        case .volleyball: return item("endurance", "volleyball", "Volleyball")
        case .walking:
            if isIndoor == true { return item("endurance", "indoor_walk", "Indoor Walk") }
            if isIndoor == false { return item("endurance", "outdoor_walk", "Outdoor Walk") }
            return item("endurance", "walking", "Walking")
        case .waterFitness: return item("endurance", "water_fitness", "Water Fitness")
        case .waterPolo: return item("endurance", "water_polo", "Water Polo")
        case .waterSports: return item("endurance", "water_sports", "Water Sports")
        case .wrestling: return item("strength", "wrestling", "Wrestling")
        case .yoga: return item("mobility", "yoga", "Yoga")
        case .barre: return item("mobility", "barre", "Barre")
        case .coreTraining: return item("strength", "core_training", "Core Training")
        case .crossCountrySkiing: return item("endurance", "cross_country_skiing", "Cross-Country Skiing")
        case .downhillSkiing: return item("endurance", "downhill_skiing", "Downhill Skiing")
        case .flexibility: return item("mobility", "flexibility", "Flexibility")
        case .highIntensityIntervalTraining: return item("endurance", "high_intensity_interval_training", "High Intensity Interval Training")
        case .jumpRope: return item("endurance", "jump_rope", "Jump Rope")
        case .kickboxing: return item("endurance", "kickboxing", "Kickboxing")
        case .pilates: return item("mobility", "pilates", "Pilates")
        case .snowboarding: return item("endurance", "snowboarding", "Snowboarding")
        case .stairs: return item("endurance", "stairs", "Stairs")
        case .stepTraining: return item("endurance", "step_training", "Step Training")
        case .wheelchairWalkPace: return item("endurance", "wheelchair_walk", "Wheelchair Walk")
        case .wheelchairRunPace: return item("endurance", "wheelchair_run", "Wheelchair Run")
        case .taiChi: return item("mobility", "tai_chi", "Tai Chi")
        case .mixedCardio: return item("endurance", "mixed_cardio", "Mixed Cardio")
        case .handCycling: return item("endurance", "hand_cycling", "Hand Cycling")
        case .discSports: return item("endurance", "disc_sports", "Disc Sports")
        case .fitnessGaming: return item("endurance", "fitness_gaming", "Fitness Gaming")
        case .cardioDance: return item("endurance", "cardio_dance", "Cardio Dance")
        case .socialDance: return item("endurance", "social_dance", "Social Dance")
        case .pickleball: return item("endurance", "pickleball", "Pickleball")
        case .cooldown: return item("mobility", "cooldown", "Cooldown")
        case .swimBikeRun: return item("endurance", "swim_bike_run", "Swim, Bike, Run")
        case .transition: return item("endurance", "transition", "Transition")
        case .underwaterDiving: return item("endurance", "underwater_diving", "Underwater Diving")
        case .other: return item("mobility", "other", "Apple Health Workout")
        @unknown default: return item("mobility", "unknown", "Apple Health Workout")
        }
    }
}

enum HealthWorkoutMetrics {
    static var distanceIdentifiers: [HKQuantityTypeIdentifier] {
        var identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .distanceWheelchair,
            .distanceDownhillSnowSports,
        ]
        if #available(iOS 18.0, watchOS 11.0, *) {
            identifiers += [
                .distanceCrossCountrySkiing,
                .distancePaddleSports,
                .distanceRowing,
                .distanceSkatingSports,
            ]
        }
        return identifiers
    }
}

enum HealthObserverDelivery {
    @MainActor
    static func process<Value>(
        load: () async -> Value?,
        consume: (Value) async -> Void,
        completion: () -> Void
    ) async {
        defer { completion() }
        guard let value = await load() else { return }
        await consume(value)
    }
}

private final class HealthObserverCompletion: @unchecked Sendable {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        callback()
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
    private static let dietaryWaterAnchorKey = "apex.hk.dietary-water.anchor.v1"
    private static let workoutAnchorKeyPrefix = "apex.hk.workouts.anchor.v1"

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

    /// Existing users may have approved Health access before APEX started
    /// reading Apple's Activity Summary. HealthKit decides whether another
    /// system sheet is required, so this never manufactures an authorization
    /// state or repeatedly prompts after the user has answered.
    func requestNewReadAccessIfNeeded() async {
        guard isAvailable else { return }
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: Set(writeTypes),
                read: Set(readTypes)
            )
            guard status == .shouldRequest else { return }
            try await store.requestAuthorization(
                toShare: Set(writeTypes),
                read: Set(readTypes)
            )
            isAuthorized = true
            refreshWaterWriteState()
        } catch {
            message = error.localizedDescription
        }
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
                try await resolvedActiveEnergyKcal(start: start, end: end)
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
                let observerCompletion = HealthObserverCompletion(completion)
                Task { @MainActor [weak self] in
                    await HealthObserverDelivery.process(
                        load: { [weak self] in
                            guard let self else { return nil }
                            return try? await self.readToday()
                        },
                        consume: { [weak self] (snapshot: HealthSnapshot) in
                            guard let self else { return }
                            self.lastSnapshot = snapshot
                            if let importHandler = self.importHandler {
                                await importHandler(snapshot)
                            }
                        },
                        completion: { observerCompletion.call() }
                    )
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    @discardableResult
    func saveWater(
        liters: Double,
        date: Date = .now,
        eventID: UUID = UUID(),
        ownerID: UUID,
        kind: HydrationKind = .water,
        paletteToken: String = "aqua",
        iconToken: String = "drop.fill"
    ) async throws -> UUID {
        guard liters.isFinite, liters > 0 else { return eventID }
        let type = try await authorizedWaterType()
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .liter(), doubleValue: liters),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyExternalUUID: eventID.uuidString,
                HKMetadataKeySyncIdentifier: "apex.hydration.event.\(eventID.uuidString.lowercased())",
                HKMetadataKeySyncVersion: 1,
                HydrationReconciliation.eventIDMetadataKey: eventID.uuidString.lowercased(),
                HydrationMetadata.ownerID: ownerID.uuidString.lowercased(),
                HydrationReconciliation.foodMetadataKey: kind.rawValue,
                HydrationReconciliation.paletteMetadataKey: paletteToken,
                HydrationReconciliation.iconMetadataKey: iconToken,
            ]
        )
        try await store.save(sample)
        return sample.uuid
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
            let authored = try await waterSamples(
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
                    HydrationMetadata.ownerID: accountID.uuidString.lowercased(),
                ]
            )
            try await store.save(sample)
        }
        defaults.set(nextVersion, forKey: versionKey)
        defaults.set(normalized, forKey: amountKey)
    }

    func deleteWater(eventID: UUID, date: Date) async throws {
        let type = try await authorizedWaterType()
        let syncIdentifier = "apex.hydration.event.\(eventID.uuidString.lowercased())"
        let authored = try await waterSamples(
            type: type,
            syncIdentifier: syncIdentifier,
            date: date
        )
        if !authored.isEmpty { try await store.delete(authored) }
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

    func startWatchWorkout(_ kind: WatchWorkoutKind) async -> Bool {
        guard isAvailable else {
            message = "Apple Watch workout handoff is unavailable."
            return false
        }
        let configuration = HKWorkoutConfiguration()
        switch kind {
        case .traditionalStrength:
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
        case .yoga:
            configuration.activityType = .yoga
            configuration.locationType = .indoor
        case .hiit:
            configuration.activityType = .highIntensityIntervalTraining
            configuration.locationType = .indoor
        case .running:
            configuration.activityType = .running
            configuration.locationType = .outdoor
        case .cycling:
            configuration.activityType = .cycling
            configuration.locationType = .outdoor
        case .walking:
            configuration.activityType = .walking
            configuration.locationType = .outdoor
        }
        let result: (started: Bool, error: String?) = await withCheckedContinuation { continuation in
            store.startWatchApp(with: configuration) { started, error in
                continuation.resume(returning: (started, error?.localizedDescription))
            }
        }
        if let error = result.error { message = error }
        return result.started
    }

    private var readTypes: [HKObjectType] {
        let coreTypes: [HKObjectType?] = [
            quantity(.bodyMass), quantity(.vo2Max), quantity(.restingHeartRate),
            quantity(.dietaryWater), quantity(.stepCount), quantity(.activeEnergyBurned),
            quantity(.appleExerciseTime), quantity(.heartRateVariabilitySDNN),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.workoutType(), HKObjectType.activitySummaryType()
        ]
        let workoutMetricTypes = HealthWorkoutMetrics.distanceIdentifiers.map(quantity)
        return (coreTypes + workoutMetricTypes).compactMap { $0 }
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

    private func resolvedActiveEnergyKcal(start: Date, end: Date) async throws -> Double? {
        async let summaryRead = HealthMetricRead<Double?>.capture { [self] in
            try await activitySummaryEnergyKcal(on: end)
        }
        async let cumulativeRead = HealthMetricRead<Double?>.capture { [self] in
            try await cumulativeQuantity(
                .activeEnergyBurned,
                unit: .kilocalorie(),
                start: start,
                end: end
            )
        }
        let (summary, cumulative) = try await (summaryRead, cumulativeRead)
        guard summary.completed || cumulative.completed else {
            throw HealthActivityEnergyReadError.unavailable
        }
        return HealthActivityEnergyResolver.resolve(
            activitySummaryKcal: summary.resolved(or: nil),
            cumulativeSampleKcal: cumulative.resolved(or: nil)
        )
    }

    private func activitySummaryEnergyKcal(on date: Date) async throws -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = HealthActivitySummaryQueryDay.components(for: date, calendar: calendar)
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let calories = summaries?
                    .map { $0.activeEnergyBurned.doubleValue(for: .kilocalorie()) }
                    .filter(\.isFinite)
                    .max()
                continuation.resume(returning: calories)
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
        async let deletedSampleIDs = dietaryWaterDeletionIDs(type: type)
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
        let deleted = try await deletedSampleIDs
        guard !samples.isEmpty else {
            return HealthWaterTotals(
                total: 0,
                importableDrink: 0,
                deletedSampleIDs: deleted
            )
        }

        var classified: [HydrationReconciliation.Sample] = []
        var detailed: [HealthHydrationSample] = []
        var total = 0.0
        for sample in samples {
            let liters = sample.quantity.doubleValue(for: .liter())
            guard liters.isFinite, liters > 0 else { continue }
            total += liters
            let bundle = sample.sourceRevision.source.bundleIdentifier
            let syncIdentifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String
            let isFood = sample.metadata?[HydrationReconciliation.foodMetadataKey] as? String
                == HydrationReconciliation.foodMetadataValue
            let source: HydrationReconciliation.Source
            if isFood {
                source = .apexFood
            } else if syncIdentifier?.hasPrefix("apex.hydration.watch.") == true {
                source = .apexWatch
            } else if bundle == HydrationReconciliation.phoneBundleIdentifier {
                source = .apexPhone
            } else if bundle == HydrationReconciliation.watchBundleIdentifier {
                source = .apexWatch
            } else {
                source = .external
            }
            classified.append(.init(liters: liters, source: source))
            let rawKind = sample.metadata?[HydrationReconciliation.foodMetadataKey] as? String
            let kind = rawKind.flatMap(HydrationKind.init(rawValue:))
                ?? (source == .external ? .external : .water)
            detailed.append(HealthHydrationSample(
                id: sample.uuid,
                liters: liters,
                occurredAt: sample.startDate,
                source: source,
                kind: kind,
                paletteToken: sample.metadata?[HydrationReconciliation.paletteMetadataKey] as? String
                    ?? (source == .external ? "external" : "aqua"),
                iconToken: sample.metadata?[HydrationReconciliation.iconMetadataKey] as? String
                    ?? (source == .external ? "heart.fill" : "drop.fill"),
                ownerID: (sample.metadata?[HydrationMetadata.ownerID] as? String)
                    .flatMap(UUID.init(uuidString:))
            ))
        }
        return HealthWaterTotals(
            total: total,
            importableDrink: HydrationReconciliation.importableDrinkLiters(classified),
            samples: detailed,
            deletedSampleIDs: deleted
        )
    }

    private func dietaryWaterDeletionIDs(type: HKQuantityType) async throws -> Set<UUID> {
        let defaults = UserDefaults.standard
        let previousAnchor: HKQueryAnchor? = defaults.data(forKey: Self.dietaryWaterAnchorKey)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let result: (ids: Set<UUID>, anchorData: Data?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: previousAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, _, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let anchorData = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(
                        withRootObject: $0,
                        requiringSecureCoding: true
                    )
                }
                continuation.resume(returning: (
                    Set((deletedObjects ?? []).map(\.uuid)),
                    anchorData
                ))
            }
            store.execute(query)
        }
        if let anchorData = result.anchorData {
            defaults.set(anchorData, forKey: Self.dietaryWaterAnchorKey)
        }
        return result.ids
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

    private func waterSamples(
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
                let workouts = (samples as? [HKWorkout] ?? []).map(Self.snapshot)
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    func workoutChanges(ownerID: UUID) async throws -> HealthWorkoutChangeSet {
        let key = Self.workoutAnchorKey(ownerID: ownerID)
        let storedAnchorData = UserDefaults.standard.data(forKey: key)
        let anchor = storedAnchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map(Self.snapshot)
                let deletedIDs = Set((deleted ?? []).map(\.uuid))
                let shouldAdvance = storedAnchorData != nil || workouts.isEmpty == false || deletedIDs.isEmpty == false
                let newAnchorData = shouldAdvance
                    ? newAnchor.flatMap {
                        try? NSKeyedArchiver.archivedData(
                            withRootObject: $0,
                            requiringSecureCoding: true
                        )
                    }
                    : nil
                continuation.resume(returning: HealthWorkoutChangeSet(
                    workouts: workouts,
                    deletedWorkoutIDs: deletedIDs,
                    anchorData: newAnchorData
                ))
            }
            store.execute(query)
        }
    }

    func commitWorkoutAnchor(_ data: Data, ownerID: UUID) {
        UserDefaults.standard.set(data, forKey: Self.workoutAnchorKey(ownerID: ownerID))
    }

    private static func workoutAnchorKey(ownerID: UUID) -> String {
        "\(workoutAnchorKeyPrefix).\(ownerID.uuidString.lowercased())"
    }

    nonisolated private static func snapshot(_ workout: HKWorkout) -> HealthWorkoutSnapshot {
        let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
        let identity = HealthWorkoutCatalog.identity(
            for: workout.workoutActivityType,
            isIndoor: indoor
        )
        let distanceMeters = HealthWorkoutMetrics.distanceIdentifiers.compactMap { identifier -> Double? in
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
        }.reduce(0, +)
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let energy = energyType.flatMap {
            workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        let source = workout.sourceRevision.source
        let apexSessionID = (
            workout.metadata?["ch.apexperformance.apex.workout-session-id"] as? String
            ?? workout.metadata?[HKMetadataKeyExternalUUID] as? String
        ).flatMap(UUID.init(uuidString:))

        return HealthWorkoutSnapshot(
            id: workout.uuid,
            date: workout.startDate.apexDateKey,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            kind: identity.kind,
            activityName: identity.fallbackName,
            activityNameKey: identity.nameKey,
            durationMinutes: Int((workout.duration / 60).rounded()),
            distanceKM: distanceMeters > 0 ? distanceMeters / 1_000 : nil,
            activeEnergyKcal: energy,
            sourceName: source.name,
            sourceBundleIdentifier: source.bundleIdentifier,
            activityTypeRaw: Int(workout.workoutActivityType.rawValue),
            apexSessionID: apexSessionID
        )
    }

    private func enableBackgroundDelivery() async {
        let workoutType = HKObjectType.workoutType()
        for type in [
            quantity(.bodyMass), quantity(.dietaryWater), quantity(.vo2Max),
            quantity(.restingHeartRate), quantity(.stepCount), quantity(.activeEnergyBurned),
            quantity(.appleExerciseTime), quantity(.heartRateVariabilitySDNN),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ].compactMap({ $0 }) {
            try? await store.enableBackgroundDelivery(for: type, frequency: .hourly)
        }
        try? await store.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
    }
}
