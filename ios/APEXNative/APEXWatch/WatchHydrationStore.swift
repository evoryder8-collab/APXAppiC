import Foundation
import HealthKit
import WidgetKit

@MainActor
final class WatchHydrationStore: ObservableObject {
    @Published private(set) var liters = 0.0
    @Published private(set) var isAuthorized = false
    @Published private(set) var isSaving = false
    @Published var message: String?

    let targetLiters = 2.75

    private let healthStore = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    var progress: Double {
        WatchHydrationFillState(liters: liters, targetLiters: targetLiters).progress
    }

    func start() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else {
            message = "Apple Health is unavailable."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [waterType], read: [waterType])
            isAuthorized = true
            await refresh()
            beginObserving(waterType)
        } catch {
            message = "Allow Water access in Health settings."
        }
    }

    func add(milliliters: Double) async {
        guard milliliters > 0,
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return }

        isSaving = true
        defer { isSaving = false }

        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())

        do {
            try await healthStore.save(sample)
            liters += milliliters / 1_000
            message = "+\(Int(milliliters)) mL"
            try? await Task.sleep(for: .seconds(1.2))
            message = nil
        } catch {
            message = "Water was not saved."
        }
    }

    func refresh() async {
        guard let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        do {
            let total: Double = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Double, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: waterType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let value = statistics?.sumQuantity()?.doubleValue(for: .liter()) ?? 0
                    continuation.resume(returning: value)
                }
                healthStore.execute(query)
            }
            liters = max(0, total)
            /* Keep the watch face ring honest the moment the total moves,
               instead of waiting for the next scheduled timeline refresh. */
            WidgetCenter.shared.reloadTimelines(ofKind: "ch.apexperformance.APEX.water")
        } catch {
            if !(error is CancellationError) {
                message = "Using the last water total."
            }
        }
    }

    private func beginObserving(_ waterType: HKQuantityType) {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { [weak self] _, completion, _ in
            completion()
            Task { @MainActor in
                await self?.refresh()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }
}
