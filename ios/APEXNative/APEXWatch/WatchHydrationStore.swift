import Foundation
import HealthKit
import UserNotifications
import WatchKit
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
    @Published private(set) var preferences: WatchHydrationPreferences
    @Published var message: String?

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private var observerQuery: HKObserverQuery?
    private static let preferencesKey = "ch.apexperformance.APEX.watch.hydration.preferences.v1"
    private static let reminderIdentifierPrefix = "ch.apexperformance.APEX.hydration.reminder."
    private static let reminderCountDayKey = "ch.apexperformance.APEX.watch.hydration.reminder.day"
    private static let reminderCountKey = "ch.apexperformance.APEX.watch.hydration.reminder.count"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey),
           let restored = try? JSONDecoder().decode(WatchHydrationPreferences.self, from: data) {
            preferences = restored
        } else {
            preferences = .default
        }
    }

    var targetLiters: Double { preferences.targetLiters }

    var progress: Double {
        WatchHydrationFillState(liters: liters, targetLiters: targetLiters).progress
    }

    func updatePreferences(_ value: WatchHydrationPreferences) async throws {
        let remindersWereEnabled = preferences.remindersEnabled
        var validated = value
        validated.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(value.targetLiters)
        validated.reminderIntervalMinutes = [60, 90, 120].contains(value.reminderIntervalMinutes)
            ? value.reminderIntervalMinutes
            : 90
        validated.quietHoursStartMinutes = min(1_439, max(0, value.quietHoursStartMinutes))
        validated.quietHoursEndMinutes = min(1_439, max(0, value.quietHoursEndMinutes))

        let data = try JSONEncoder().encode(validated)
        defaults.set(data, forKey: Self.preferencesKey)
        preferences = validated
        WidgetCenter.shared.reloadTimelines(ofKind: "ch.apexperformance.APEX.water")

        if validated.remindersEnabled, !remindersWereEnabled {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            )) ?? false
            if !granted {
                message = "Watch notifications are off. Enable APEX in Notification settings."
            }
        }
        await synchronizeReminderSchedule()
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
            if preferences.confirmationHaptics {
                WKInterfaceDevice.current().play(.success)
            }
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
            if preferences.confirmationHaptics {
                WKInterfaceDevice.current().play(.click)
            }
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
                let syncIdentifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String
                let isFood = sample.metadata?["ch.apexperformance.APEX.hydration.kind"] as? String == "food"
                let canDelete = WatchHydrationAuthorship.canDelete(
                    sourceBundleIdentifier: bundle,
                    syncIdentifier: syncIdentifier
                )
                let sourceName: String
                if isFood {
                    sourceName = "APEX food"
                } else if canDelete {
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
                    canDelete: canDelete
                )
            }
            /* Keep the watch face ring honest the moment the total moves,
               instead of waiting for the next scheduled timeline refresh. */
            WidgetCenter.shared.reloadTimelines(ofKind: "ch.apexperformance.APEX.water")
            await synchronizeReminderSchedule()
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

    private func synchronizeReminderSchedule(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existing = pending.filter { $0.identifier.hasPrefix(Self.reminderIdentifierPrefix) }

        guard preferences.remindersEnabled,
              let reminderDate = WatchHydrationReminderPolicy.nextReminderDate(
                now: now,
                liters: liters,
                lastDrinkAt: entries.first?.date,
                preferences: preferences
              )
        else {
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))
            return
        }

        let signature = reminderSignature(date: reminderDate)
        if existing.contains(where: { $0.content.userInfo["signature"] as? String == signature }) {
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))

        let status = await center.notificationSettings().authorizationStatus
        guard [.authorized, .provisional].contains(status) else { return }

        let day = reminderDayKey(now)
        let count = scheduledReminderCount(for: day)
        guard count < 3 else { return }

        let content = UNMutableNotificationContent()
        content.title = "A gentle hydration check"
        content.body = "You are behind your current hydration pace. A few sips can close the gap."
        content.sound = .default
        content.userInfo = ["signature": signature, "kind": "hydration"]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifierPrefix + day + ".\(count + 1)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
            defaults.set(day, forKey: Self.reminderCountDayKey)
            defaults.set(count + 1, forKey: Self.reminderCountKey)
        } catch {
            message = "Hydration reminder could not be scheduled."
        }
    }

    private func reminderSignature(date: Date) -> String {
        let milliliters = Int((liters * 1_000).rounded())
        let lastEntry = Int((entries.first?.date.timeIntervalSince1970 ?? 0).rounded())
        return "\(milliliters)|\(lastEntry)|\(Int(date.timeIntervalSince1970.rounded()))|\(preferences.targetLiters)"
    }

    private func reminderDayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func scheduledReminderCount(for day: String) -> Int {
        guard defaults.string(forKey: Self.reminderCountDayKey) == day else { return 0 }
        return defaults.integer(forKey: Self.reminderCountKey)
    }

    private var permissionMessage: String {
        "Water access is off. On iPhone open Health > profile > Apps and Services > APEX, then enable Water."
    }

    private func refreshAuthorizationStatus(_ waterType: HKQuantityType) {
        isAuthorized = healthStore.authorizationStatus(for: waterType) == .sharingAuthorized
    }
}
