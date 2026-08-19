import Foundation
import HealthKit

/*
 * Historical backfill from HealthKit.
 *
 * The web imports years of Apple Health by stream-parsing an export.xml that
 * can approach a gigabyte. On iOS that file is unnecessary: the same history
 * is already on device and can be queried directly, so this reads it into the
 * shape HealthImport expects and the shared merge policy does the rest.
 *
 * Everything here is a read. Nothing is written back to HealthKit, and a
 * category the user has not authorised simply yields nothing rather than
 * failing the whole import.
 */
@MainActor
extension HealthKitManager {
    /// Reads history into the same shape the web parser produces.
    func readHistory(from start: Date, to end: Date = .now) async -> HealthImport.Parsed {
        var parsed = HealthImport.Parsed()
        guard HKHealthStore.isHealthDataAvailable() else { return parsed }

        /* Each read is independent: a denied category costs its own data and
           nothing else, which keeps a partial authorisation useful. */
        parsed.nutrition = await dailyNutrition(start: start, end: end)
        parsed.water = await dailySum(.dietaryWater, unit: .liter(), start: start, end: end)
        parsed.weight = await dailyLatest(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: end)
        parsed.vo2Max = await dailyLatest(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: start, end: end)
        parsed.restingHeartRate = await dailyLatest(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: start, end: end
        )
        parsed.workouts = await historicalWorkouts(start: start, end: end)
        return parsed
    }

    private func dailyNutrition(start: Date, end: Date) async -> [String: HealthImport.Nutrition] {
        async let kcal = dailySum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)
        async let protein = dailySum(.dietaryProtein, unit: .gram(), start: start, end: end)
        async let fat = dailySum(.dietaryFatTotal, unit: .gram(), start: start, end: end)
        async let carbs = dailySum(.dietaryCarbohydrates, unit: .gram(), start: start, end: end)
        let (energy, proteins, fats, carbohydrates) = await (kcal, protein, fat, carbs)

        var out: [String: HealthImport.Nutrition] = [:]
        for date in Set(energy.keys).union(proteins.keys).union(fats.keys).union(carbohydrates.keys) {
            out[date] = HealthImport.Nutrition(
                kcal: energy[date] ?? 0,
                protein: proteins[date] ?? 0,
                fat: fats[date] ?? 0,
                carbs: carbohydrates[date] ?? 0
            )
        }
        return out
    }

    private func samples(
        _ identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date
    ) async -> [HKQuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    /// Totals per day, matching how the web sums repeated entries.
    private func dailySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [String: Double] {
        var out: [String: Double] = [:]
        for sample in await samples(identifier, start: start, end: end) {
            let key = sample.startDate.apexDateKey
            out[key, default: 0] += sample.quantity.doubleValue(for: unit)
        }
        return out
    }

    /// Last reading of the day, matching the web's handling of body mass.
    private func dailyLatest(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [String: Double] {
        var out: [String: Double] = [:]
        for sample in await samples(identifier, start: start, end: end) {
            out[sample.startDate.apexDateKey] = sample.quantity.doubleValue(for: unit)
        }
        return out
    }

    private func historicalWorkouts(start: Date, end: Date) async -> [HealthImport.Workout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        return workouts.compactMap { workout in
            let raw = Self.exportName(workout.workoutActivityType)
            /* An unmapped activity is skipped rather than guessed at, exactly
               as the web skips a type it has no opinion about. */
            guard let kind = HealthImport.activityKind[raw] else { return nil }
            let minutes = Int((workout.duration / 60).rounded())
            guard minutes >= HealthImport.minimumWorkoutMinutes else { return nil }
            return HealthImport.Workout(
                date: workout.startDate.apexDateKey,
                activity: raw,
                kind: kind,
                durationMinutes: minutes,
                source: workout.sourceRevision.source.name
            )
        }
    }

    /// The names Apple writes into export.xml, so a workout imported from the
    /// file and the same workout read from HealthKit agree.
    nonisolated static func exportName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "TraditionalStrengthTraining"
        case .functionalStrengthTraining: "FunctionalStrengthTraining"
        case .coreTraining: "CoreTraining"
        case .highIntensityIntervalTraining: "HighIntensityIntervalTraining"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing: "StairClimbing"
        case .jumpRope: "JumpRope"
        case .crossTraining: "CrossTraining"
        case .mixedCardio: "MixedCardio"
        case .hiking: "Hiking"
        case .waterSports: "WaterSports"
        case .yoga: "Yoga"
        case .flexibility: "Flexibility"
        case .mindAndBody: "MindAndBody"
        case .pilates: "Pilates"
        default: "Other"
        }
    }
}
