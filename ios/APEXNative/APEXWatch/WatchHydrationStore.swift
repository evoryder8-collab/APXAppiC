import Foundation
import HealthKit
import WidgetKit

struct WatchHydrationEntry: Identifiable {
    let sample: HKQuantitySample
    let milliliters: Double
    let sourceName: String
    let canDelete: Bool

    var id: UUID { sample.uuid }
    var date: Date { sample.startDate }
}

@MainActor
final class WatchHydrationStore: ObservableObject {
    @Published private(set) var liters = 0.0
    @Published private(set) var isAuthorized = false
    @Published private(set) var isSaving = false
    @Published private(set) var entries: [WatchHydrationEntry] = []
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
            refreshAuthorizationStatus(waterType)
            if !isAuthorized { message = permissionMessage }
            await refresh()
            beginObserving(waterType)
        } catch {
            refreshAuthorizationStatus(waterType)
            message = permissionMessage
        }
    }

    func reconnect() async {
        await start()
    }

    func add(milliliters: Double) async {
        guard milliliters > 0,
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return }

        refreshAuthorizationStatus(waterType)
        if !isAuthorized {
            await reconnect()
            guard isAuthorized else {
                message = permissionMessage
                return
            }
        }

        isSaving = true
        defer { isSaving = false }

        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters)
        let identifier = UUID()
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: Date(),
            end: Date(),
            metadata: [
                HKMetadataKeyExternalUUID: identifier.uuidString,
                HKMetadataKeySyncIdentifier: "apex.hydration.watch.\(identifier.uuidString.lowercased())",
                HKMetadataKeySyncVersion: 1,
            ]
        )

        do {
            try await healthStore.save(sample)
            await refresh()
            message = "+\(Int(milliliters)) mL"
            try? await Task.sleep(for: .seconds(1.2))
            message = nil
        } catch {
            refreshAuthorizationStatus(waterType)
            message = isAuthorized ? error.localizedDescription : permissionMessage
        }
    }

    func delete(_ entry: WatchHydrationEntry) async {
        guard entry.canDelete else {
            message = "Only water added by APEX on this Watch can be removed here."
            return
        }
        do {
            try await healthStore.delete(entry.sample)
            await refresh()
            message = "Entry removed"
        } catch {
            message = error.localizedDescription
        }
    }

    func refresh() async {
        guard let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: waterType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                ) { _, rawSamples, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: rawSamples as? [HKQuantitySample] ?? [])
                }
                healthStore.execute(query)
            }
            liters = samples.reduce(0) {
                $0 + max(0, $1.quantity.doubleValue(for: .liter()))
            }
            entries = samples.map { sample in
                let bundle = sample.sourceRevision.source.bundleIdentifier
                let isFood = sample.metadata?["ch.apexperformance.APEX.hydration.kind"] as? String == "food"
                let sourceName: String
                if isFood {
                    sourceName = "APEX food"
                } else if bundle == "ch.apexperformance.APEX.watchkitapp" {
                    sourceName = "APEX Watch"
                } else if bundle == "ch.apexperformance.APEX" {
                    sourceName = "APEX iPhone"
                } else {
                    sourceName = sample.sourceRevision.source.name
                }
                return WatchHydrationEntry(
                    sample: sample,
                    milliliters: sample.quantity.doubleValue(for: .literUnit(with: .milli)),
                    sourceName: sourceName,
                    canDelete: bundle == "ch.apexperformance.APEX.watchkitapp"
                )
            }
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

    private var permissionMessage: String {
        "Water access is off. On iPhone open Health > profile > Apps and Services > APEX, then enable Water."
    }

    private func refreshAuthorizationStatus(_ waterType: HKQuantityType) {
        isAuthorized = healthStore.authorizationStatus(for: waterType) == .sharingAuthorized
    }
}
