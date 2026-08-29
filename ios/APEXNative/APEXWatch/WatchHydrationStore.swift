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
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String

    var id: UUID { sample.uuid }
    var date: Date { sample.startDate }
}

private struct WatchHydrationHealthChanges: Sendable {
    let deletedSampleIDs: Set<UUID>
    let queryAnchorData: Data?
}

private final class WatchHealthObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (() -> Void)?

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        lock.lock()
        let callback = callback
        self.callback = nil
        lock.unlock()
        callback?()
    }
}

@MainActor
final class WatchHydrationStore: ObservableObject {
    @Published private(set) var liters = 0.0
    @Published private(set) var isAuthorized = false
    @Published private(set) var isSaving = false
    @Published private(set) var entries: [WatchHydrationEntry] = []
    @Published private(set) var presets: [HydrationPreset] = []
    @Published private(set) var composition: [HydrationCompositionBand] = []
    @Published private(set) var activeOwnerID: UUID?
    @Published private(set) var preferences: WatchHydrationPreferences
    @Published var message: String?

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let widgetDefaults = UserDefaults(suiteName: HydrationWidgetStorage.suiteName)
    private let connectivity: WatchHydrationConnectivity
    private var observerQuery: HKObserverQuery?
    private var latestWidgetLocalDate: String?
    private var latestWidgetRevision: String?
    private var acceptedCompanionRevision: String?
    private var pendingPreferenceOwnerID: UUID?
    private var pendingPreferenceRevision: String?
    private var healthAnchor: [HydrationHealthSampleAnchor]?
    private var healthQueryAnchorData: Data?
    private var pendingMutations: [HydrationPendingMutation] = []
    private var deferredDeletes: [HydrationDeferredDelete] = []
    private var healthMutationsInFlight: Set<UUID> = []
    private var canonicalSampleIDs: Set<UUID> = []
    private var healthOverlay: [HydrationPendingMutation] = []
    private var stateGeneration = 0
    private static let preferencesKey = "ch.apexperformance.APEX.watch.hydration.preferences.v1"
    private static let pendingMutationsKey =
        "ch.apexperformance.APEX.watch.hydration.pending-mutations.v1"
    private static let deferredDeletesKey =
        "ch.apexperformance.APEX.watch.hydration.deferred-deletes.v1"
    private static let acceptedCompanionRevisionKey =
        "ch.apexperformance.APEX.watch.hydration.accepted-companion-revision.v1"
    private static let pendingPreferenceOwnerKey =
        "ch.apexperformance.APEX.watch.hydration.pending-preference-owner.v1"
    private static let pendingPreferenceRevisionKey =
        "ch.apexperformance.APEX.watch.hydration.pending-preference-revision.v1"
    private static let reminderIdentifierPrefix = "ch.apexperformance.APEX.hydration.reminder."
    private static let reminderCountDayKey = "ch.apexperformance.APEX.watch.hydration.reminder.day"
    private static let reminderCountKey = "ch.apexperformance.APEX.watch.hydration.reminder.count"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        connectivity = WatchHydrationConnectivity()
        acceptedCompanionRevision = defaults.string(forKey: Self.acceptedCompanionRevisionKey)
        if let ownerValue = defaults.string(forKey: Self.pendingPreferenceOwnerKey),
           let ownerID = UUID(uuidString: ownerValue),
           let revision = defaults.string(forKey: Self.pendingPreferenceRevisionKey) {
            pendingPreferenceOwnerID = ownerID
            pendingPreferenceRevision = revision
        }
        if let data = defaults.data(forKey: Self.pendingMutationsKey),
           let restored = try? JSONDecoder().decode([HydrationPendingMutation].self, from: data) {
            pendingMutations = restored
        }
        if let data = defaults.data(forKey: Self.deferredDeletesKey),
           let restored = try? JSONDecoder().decode([HydrationDeferredDelete].self, from: data) {
            deferredDeletes = restored
        }
        if let data = defaults.data(forKey: Self.preferencesKey),
           let restored = try? JSONDecoder().decode(WatchHydrationPreferences.self, from: data) {
            preferences = restored
        } else {
            preferences = .default
        }
        if let data = widgetDefaults?.data(forKey: HydrationWidgetStorage.stateKey),
           let state = try? HydrationWidgetState.decode(data),
           state.localDate == Date().apexDateKey {
            let widgetHealthState = widgetDefaults?
                .data(forKey: HydrationWidgetStorage.healthStateKey)
                .flatMap { try? HydrationWidgetHealthState.decode($0) }
                .flatMap { $0.matches(state) ? $0 : nil }
            let resolved = HydrationWidgetStateResolver.resolve(
                canonical: state,
                healthState: widgetHealthState
            )
            activeOwnerID = state.ownerID
            liters = Double(resolved.totalML) / 1_000
            composition = resolved.composition
            preferences.targetLiters = Double(state.targetML) / 1_000
            latestWidgetLocalDate = state.localDate
            latestWidgetRevision = state.revision
            healthAnchor = resolved.healthAnchor
            healthQueryAnchorData = resolved.healthQueryAnchorData
            canonicalSampleIDs = Set(state.canonicalSampleIDs ?? [])
            healthOverlay = resolved.healthOverlay
        }
        connectivity.snapshotHandler = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        connectivity.disconnectHandler = { [weak self] revision in
            self?.disconnectAccount(revision: revision)
        }
        connectivity.workoutCommandHandler = { [weak self] command in
            guard self?.activeOwnerID == command.ownerID, command.action == .stop else { return }
            Task { @MainActor in await WatchWorkoutSessionController.shared.stop() }
        }
    }

    var targetLiters: Double { preferences.targetLiters }

    var progress: Double {
        WatchHydrationFillState(liters: liters, targetLiters: targetLiters).progress
    }

    func updatePreferences(_ value: WatchHydrationPreferences) async throws {
        let localDate = Date().apexDateKey
        ensureCurrentDay(localDate)
        absorbWidgetHealthStateIfCurrent()
        let operationScope = activeOwnerID.map {
            HydrationWatchOperationScope(
                ownerID: $0,
                localDate: localDate,
                generation: stateGeneration
            )
        }
        let remindersWereEnabled = preferences.remindersEnabled
        var validated = value
        if value.effectiveTargetMode == .custom {
            validated.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(value.targetLiters)
        }
        validated.reminderIntervalMinutes = [60, 90, 120].contains(value.reminderIntervalMinutes)
            ? value.reminderIntervalMinutes
            : 90
        validated.quietHoursStartMinutes = min(1_439, max(0, value.quietHoursStartMinutes))
        validated.quietHoursEndMinutes = min(1_439, max(0, value.quietHoursEndMinutes))

        let data = try JSONEncoder().encode(validated)
        defaults.set(data, forKey: Self.preferencesKey)
        preferences = validated
        persistWidgetState()
        if let activeOwnerID, let latestWidgetRevision {
            pendingPreferenceOwnerID = activeOwnerID
            pendingPreferenceRevision = latestWidgetRevision
            persistPendingPreferenceRevision()
        }
        requestComplicationReload()

        if validated.remindersEnabled, !remindersWereEnabled {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            )) ?? false
            if !granted {
                message = "Watch notifications are off. Enable APEX in Notification settings."
            }
        }
        guard operationScope?.matches(
            ownerID: activeOwnerID,
            localDate: Date().apexDateKey,
            generation: stateGeneration
        ) ?? (activeOwnerID == nil) else { return }
        await synchronizeReminderSchedule()
        guard operationScope?.matches(
            ownerID: activeOwnerID,
            localDate: Date().apexDateKey,
            generation: stateGeneration
        ) ?? (activeOwnerID == nil) else { return }
        if let operationScope {
            connectivity.send(.updating(validated, ownerID: operationScope.ownerID))
        }
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
            await refresh(retryComplicationIfStale: true)
            beginObserving(waterType)
        } catch {
            refreshAuthorizationStatus(waterType)
            message = permissionMessage
        }
    }

    func reconnect() async {
        await start()
    }

    func add(
        milliliters: Double,
        kind: HydrationKind = .water,
        paletteToken: String = "aqua",
        iconToken: String = "drop.fill"
    ) async {
        guard milliliters > 0,
              let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
        else { return }
        guard let activeOwnerID else {
            message = "Open APEX on iPhone once to connect this Watch."
            return
        }
        let localDate = Date().apexDateKey
        ensureCurrentDay(localDate)
        absorbWidgetHealthStateIfCurrent()
        let operationScope = HydrationWatchOperationScope(
            ownerID: activeOwnerID,
            localDate: localDate,
            generation: stateGeneration
        )

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
                HydrationMetadata.eventID: identifier.uuidString.lowercased(),
                HydrationMetadata.ownerID: activeOwnerID.uuidString.lowercased(),
                HydrationMetadata.kind: kind.rawValue,
                HydrationMetadata.palette: paletteToken,
                HydrationMetadata.icon: iconToken,
            ]
        )
        healthMutationsInFlight.insert(sample.uuid)

        do {
            try await healthStore.save(sample)
            guard operationScope.matches(
                ownerID: self.activeOwnerID,
                localDate: Date().apexDateKey,
                generation: stateGeneration
            ) else {
                healthMutationsInFlight.remove(sample.uuid)
                try? await healthStore.delete(sample)
                return
            }
            let now = Date().ISO8601Format()
            let event = HydrationEvent(
                id: sample.uuid,
                userID: activeOwnerID,
                clientIdempotencyKey: "healthkit:\(sample.uuid.uuidString.lowercased())",
                localDate: localDate,
                occurredAt: sample.startDate.ISO8601Format(),
                amountML: Int(milliliters.rounded()),
                kind: kind,
                paletteToken: paletteToken,
                iconToken: iconToken,
                source: .watch,
                healthKitSampleID: sample.uuid,
                createdAt: now,
                updatedAt: now
            )
            connectivity.send(.upserting(event))
            healthMutationsInFlight.remove(sample.uuid)
            recordPendingMutation(HydrationPendingMutation(
                ownerID: activeOwnerID,
                localDate: localDate,
                action: .upsert,
                sample: HydrationHealthSampleAnchor(
                    id: sample.uuid,
                    milliliters: Int(milliliters.rounded()),
                    kind: kind,
                    paletteToken: paletteToken,
                    iconToken: iconToken
                )
            ))
            applyLocalHydrationDelta(
                Int(milliliters.rounded()),
                kind: kind,
                paletteToken: paletteToken,
                iconToken: iconToken
            )
            await refresh()
            if preferences.confirmationHaptics {
                WKInterfaceDevice.current().play(.success)
            }
            message = "+\(Int(milliliters)) mL"
            try? await Task.sleep(for: .seconds(1.2))
            message = nil
        } catch {
            healthMutationsInFlight.remove(sample.uuid)
            refreshAuthorizationStatus(waterType)
            message = isAuthorized ? error.localizedDescription : permissionMessage
        }
    }

    func delete(_ entry: WatchHydrationEntry) async {
        guard entry.canDelete else {
            message = "Only water added by APEX on this Watch can be removed here."
            return
        }
        guard let activeOwnerID else {
            message = "Open APEX on iPhone once to connect this Watch."
            return
        }
        let localDate = Date().apexDateKey
        ensureCurrentDay(localDate)
        absorbWidgetHealthStateIfCurrent()
        let operationScope = HydrationWatchOperationScope(
            ownerID: activeOwnerID,
            localDate: localDate,
            generation: stateGeneration
        )
        healthMutationsInFlight.insert(entry.id)
        do {
            try await healthStore.delete(entry.sample)
            healthMutationsInFlight.remove(entry.id)
            recordDeferredDelete(HydrationDeferredDelete(
                ownerID: activeOwnerID,
                eventID: entry.id,
                localDate: localDate
            ))
            guard operationScope.matches(
                ownerID: self.activeOwnerID,
                localDate: Date().apexDateKey,
                generation: stateGeneration
            ) else {
                /* The delete already committed under the captured owner. Keep
                   its companion ledger consistent without touching new state. */
                connectivity.send(.deleting(eventID: entry.id, ownerID: activeOwnerID))
                return
            }
            connectivity.send(.deleting(eventID: entry.id, ownerID: activeOwnerID))
            recordPendingMutation(HydrationPendingMutation(
                ownerID: activeOwnerID,
                localDate: localDate,
                action: .delete,
                sample: HydrationHealthSampleAnchor(
                    id: entry.id,
                    milliliters: Int(entry.milliliters.rounded()),
                    kind: entry.kind,
                    paletteToken: entry.paletteToken,
                    iconToken: entry.iconToken
                )
            ))
            applyLocalHydrationDelta(
                -Int(entry.milliliters.rounded()),
                kind: entry.kind,
                paletteToken: entry.paletteToken,
                iconToken: entry.iconToken
            )
            await refresh()
            if preferences.confirmationHaptics {
                WKInterfaceDevice.current().play(.click)
            }
            message = "Entry removed"
        } catch {
            healthMutationsInFlight.remove(entry.id)
            message = error.localizedDescription
        }
    }

    func refresh(retryComplicationIfStale: Bool = false) async {
        guard let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return }
        guard let activeOwnerID else {
            liters = 0
            entries = []
            composition = []
            message = "Open APEX on iPhone once to connect this Watch."
            return
        }
        defer {
            requestComplicationReload(
                retryIfUnrendered: retryComplicationIfStale
            )
        }
        let localDate = Date().apexDateKey
        ensureCurrentDay(localDate)
        absorbWidgetHealthStateIfCurrent()
        let operationScope = HydrationWatchOperationScope(
            ownerID: activeOwnerID,
            localDate: localDate,
            generation: stateGeneration
        )
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
            guard operationScope.matches(
                ownerID: self.activeOwnerID,
                localDate: Date().apexDateKey,
                generation: stateGeneration
            ) else { return }
            let previousHealthQueryAnchorData = healthQueryAnchorData
            let healthChanges = try await anchoredHealthChanges(
                waterType: waterType,
                predicate: predicate,
                anchorData: previousHealthQueryAnchorData
            )
            guard operationScope.matches(
                ownerID: self.activeOwnerID,
                localDate: Date().apexDateKey,
                generation: stateGeneration
            ) else { return }
            healthQueryAnchorData = healthChanges.queryAnchorData
                ?? previousHealthQueryAnchorData
            let accountSamples = samples.filter(watchSampleBelongsToActiveOwner)
            entries = accountSamples.map { sample in
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
                    canDelete: canDelete,
                    kind: (sample.metadata?[HydrationMetadata.kind] as? String)
                        .flatMap(HydrationKind.init(rawValue:))
                        ?? (canDelete ? .water : .external),
                    paletteToken: sample.metadata?[HydrationMetadata.palette] as? String
                        ?? (canDelete ? "aqua" : "external"),
                    iconToken: sample.metadata?[HydrationMetadata.icon] as? String
                        ?? (canDelete ? "drop.fill" : "heart.fill")
                )
            }
            let currentHealthAnchor = entries.map {
                HydrationHealthSampleAnchor(
                    id: $0.id,
                    milliliters: Int($0.milliliters.rounded()),
                    kind: $0.kind,
                    paletteToken: $0.paletteToken,
                    iconToken: $0.iconToken
                )
            }
            let previousHealthAnchor = healthAnchor
            let comparisonAnchor = previousHealthAnchor?.filter {
                !healthMutationsInFlight.contains($0.id)
            }
            let comparisonCurrent = currentHealthAnchor.filter {
                !healthMutationsInFlight.contains($0.id)
            }
            let previousTotalML = Int((liters * 1_000).rounded())
            let previousComposition = composition
            let previousHealthOverlay = healthOverlay
            let overlayUpdate = HydrationHealthReconciler.updatedHealthOverlay(
                previousHealthOverlay,
                ownerID: activeOwnerID,
                localDate: localDate,
                canonicalSampleIDs: canonicalSampleIDs,
                anchor: comparisonAnchor,
                current: comparisonCurrent,
                deletedSampleIDs: healthChanges.deletedSampleIDs
            )
            let reconciled = HydrationHealthReconciler.replacingOverlay(
                previousHealthOverlay,
                with: overlayUpdate.mutations,
                inTotalML: previousTotalML,
                composition: previousComposition
            )
            healthOverlay = overlayUpdate.mutations
            let protectedAnchor = previousHealthAnchor?.filter {
                healthMutationsInFlight.contains($0.id)
            } ?? []
            healthAnchor = overlayUpdate.nextAnchor + protectedAnchor
            liters = Double(reconciled.totalML) / 1_000
            composition = reconciled.composition
            let visibleStateChanged = reconciled.totalML != previousTotalML
                || reconciled.composition != previousComposition
            if visibleStateChanged {
                persistWidgetState(absorbSidecar: false)
            } else if healthAnchor != previousHealthAnchor
                || healthOverlay != previousHealthOverlay
                || healthQueryAnchorData != previousHealthQueryAnchorData {
                persistWidgetState(
                    revision: latestWidgetRevision,
                    absorbSidecar: false
                )
            }
            await synchronizeReminderSchedule()
        } catch {
            if !(error is CancellationError) {
                message = "Using the last water total."
            }
        }
    }

    private func beginObserving(_ waterType: HKQuantityType) {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { completion(); return }
            let observerCompletion = WatchHealthObserverCompletion(completion)
            Task { @MainActor in
                await HydrationObserverDelivery.process(
                    operation: { [weak self] in await self?.refresh() },
                    completion: { observerCompletion.call() }
                )
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    private func anchoredHealthChanges(
        waterType: HKQuantityType,
        predicate: NSPredicate,
        anchorData: Data?
    ) async throws -> WatchHydrationHealthChanges {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<WatchHydrationHealthChanges, Error>) in
            let query = HKAnchoredObjectQuery(
                type: waterType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, _, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let encodedAnchor = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(
                        withRootObject: $0,
                        requiringSecureCoding: true
                    )
                }
                continuation.resume(returning: WatchHydrationHealthChanges(
                    deletedSampleIDs: Set((deletedObjects ?? []).map(\.uuid)),
                    queryAnchorData: encodedAnchor
                ))
            }
            healthStore.execute(query)
        }
    }

    private func apply(_ snapshot: HydrationCompanionSnapshot) {
        guard snapshot.localDate == Date().apexDateKey else { return }
        let protectsPendingPreference = pendingPreferenceOwnerID == snapshot.ownerID
            && pendingPreferenceRevision != nil
        if protectsPendingPreference,
           !HydrationPendingPreferencePolicy.acknowledges(
               pending: preferences,
               incoming: snapshot.preferences
           ) {
            return
        }
        guard HydrationComplicationRefreshPolicy.shouldAcceptCompanionRevision(
            acceptedCompanionRevision: acceptedCompanionRevision,
            localWidgetRevision: protectsPendingPreference
                ? pendingPreferenceRevision
                : latestWidgetRevision,
            incomingRevision: snapshot.revision,
            protectsLocalWidgetRevision: protectsPendingPreference
        ) else { return }
        if protectsPendingPreference || pendingPreferenceOwnerID != snapshot.ownerID {
            clearPendingPreferenceRevision()
        }
        absorbWidgetHealthStateIfCurrent()
        if activeOwnerID != snapshot.ownerID || latestWidgetLocalDate != snapshot.localDate {
            stateGeneration &+= 1
            healthAnchor = nil
            healthQueryAnchorData = nil
            healthOverlay = []
        }
        let snapshotEventIDs = snapshot.events.reduce(into: Set<UUID>()) { result, event in
            result.insert(event.id)
            if let healthKitSampleID = event.healthKitSampleID {
                result.insert(healthKitSampleID)
            }
        }
        let deferredDeleteUpdate = HydrationDeferredDeleteReconciler.reconcile(
            deferredDeletes,
            snapshotOwnerID: snapshot.ownerID,
            snapshotLocalDate: snapshot.localDate,
            snapshotEventIDs: snapshotEventIDs,
            acknowledgedDeleteIDs: Set(snapshot.acknowledgedDeleteIDs ?? [])
        )
        deferredDeletes = deferredDeleteUpdate.remaining
        persistDeferredDeletes()
        for deletion in deferredDeleteUpdate.toReplay {
            connectivity.send(.deleting(
                eventID: deletion.eventID,
                ownerID: deletion.ownerID
            ))
        }
        let acknowledgedDeleteIDs = Set(snapshot.acknowledgedDeleteIDs ?? [])
        pendingMutations.removeAll {
            $0.action == .delete && acknowledgedDeleteIDs.contains($0.sample.id)
        }
        pendingMutations = HydrationHealthReconciler.unacknowledged(
            pendingMutations,
            snapshotOwnerID: snapshot.ownerID,
            snapshotLocalDate: snapshot.localDate,
            snapshotEventIDs: snapshotEventIDs
        )
        persistPendingMutations()
        canonicalSampleIDs = snapshotEventIDs
        healthOverlay = HydrationHealthReconciler.unacknowledged(
            healthOverlay,
            snapshotOwnerID: snapshot.ownerID,
            snapshotLocalDate: snapshot.localDate,
            snapshotEventIDs: snapshotEventIDs
        )
        let healthOverlaid = HydrationHealthReconciler.applying(
            healthOverlay,
            toTotalML: snapshot.totalML,
            composition: snapshot.composition
        )
        let overlaid = HydrationHealthReconciler.applying(
            pendingMutations,
            toTotalML: healthOverlaid.totalML,
            composition: healthOverlaid.composition
        )
        activeOwnerID = snapshot.ownerID
        presets = snapshot.presets
        composition = overlaid.composition
        liters = Double(overlaid.totalML) / 1_000
        preferences = snapshot.preferences
        if let data = try? JSONEncoder().encode(snapshot.preferences) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
        latestWidgetLocalDate = snapshot.localDate
        latestWidgetRevision = snapshot.revision
        acceptedCompanionRevision = snapshot.revision
        defaults.set(snapshot.revision, forKey: Self.acceptedCompanionRevisionKey)
        persistWidgetState(revision: snapshot.revision, absorbSidecar: false)
        requestComplicationReload()
        if isAuthorized {
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    private func disconnectAccount(revision: String) {
        guard HydrationComplicationRefreshPolicy.shouldAcceptCompanionRevision(
            acceptedCompanionRevision: acceptedCompanionRevision,
            localWidgetRevision: latestWidgetRevision,
            incomingRevision: revision
        ) else { return }
        stateGeneration &+= 1
        activeOwnerID = nil
        liters = 0
        entries = []
        presets = []
        composition = []
        preferences = .default
        healthAnchor = nil
        healthQueryAnchorData = nil
        canonicalSampleIDs = []
        healthOverlay = []
        pendingMutations = []
        persistPendingMutations()
        clearPendingPreferenceRevision()
        latestWidgetLocalDate = Date().apexDateKey
        latestWidgetRevision = revision
        acceptedCompanionRevision = revision
        defaults.set(revision, forKey: Self.acceptedCompanionRevisionKey)
        defaults.removeObject(forKey: Self.preferencesKey)
        widgetDefaults?.removeObject(forKey: HydrationWidgetStorage.stateKey)
        widgetDefaults?.removeObject(forKey: HydrationWidgetStorage.healthStateKey)
        widgetDefaults?.set(
            "disconnected|\(revision)",
            forKey: HydrationWidgetStorage.requestedVisibleSignatureKey
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "ch.apexperformance.APEX.water")
        Task { @MainActor [weak self] in
            await self?.removeHydrationReminders()
            await WatchWorkoutSessionController.shared.stop()
        }
    }

    private func watchSampleBelongsToActiveOwner(_ sample: HKQuantitySample) -> Bool {
        guard let activeOwnerID else { return false }
        let explicitOwnerID = (sample.metadata?[HydrationMetadata.ownerID] as? String)
            .flatMap(UUID.init(uuidString:))
        if explicitOwnerID != nil {
            return HydrationHealthSampleOwnershipPolicy.belongs(
                explicitOwnerID: explicitOwnerID,
                sharedClaimOwnerID: nil,
                activeOwnerID: activeOwnerID
            )
        }

        let sharedKey = HydrationWidgetStorage.healthSampleOwnerClaimKey(for: sample.uuid)
        let legacyKey = "apex.hk.hydration.claim.\(sample.uuid.uuidString.lowercased())"
        var sharedClaimOwnerID = widgetDefaults?.string(forKey: sharedKey)
            .flatMap(UUID.init(uuidString:))
        if sharedClaimOwnerID == nil,
           let legacyClaimOwnerID = defaults.string(forKey: legacyKey).flatMap(UUID.init(uuidString:)) {
            widgetDefaults?.set(legacyClaimOwnerID.uuidString.lowercased(), forKey: sharedKey)
            sharedClaimOwnerID = legacyClaimOwnerID
        }
        if sharedClaimOwnerID == nil, widgetDefaults != nil {
            widgetDefaults?.set(activeOwnerID.uuidString.lowercased(), forKey: sharedKey)
            sharedClaimOwnerID = activeOwnerID
        }
        return HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: nil,
            sharedClaimOwnerID: sharedClaimOwnerID,
            activeOwnerID: activeOwnerID
        )
    }

    private func persistWidgetState(
        revision explicitRevision: String? = nil,
        absorbSidecar: Bool = true
    ) {
        if absorbSidecar {
            absorbWidgetHealthStateIfCurrent()
        }
        guard let activeOwnerID else { return }
        let revision = explicitRevision ?? HydrationComplicationRefreshPolicy.revision()
        let state = HydrationWidgetState(
            ownerID: activeOwnerID,
            localDate: HydrationWatchScopePolicy.persistenceLocalDate(
                storedLocalDate: latestWidgetLocalDate,
                currentLocalDate: Date().apexDateKey
            ),
            totalML: Int((liters * 1_000).rounded()),
            targetML: Int((preferences.targetLiters * 1_000).rounded()),
            composition: composition,
            revision: revision,
            healthAnchor: healthAnchor,
            healthQueryAnchorData: healthQueryAnchorData,
            canonicalSampleIDs: canonicalSampleIDs.sorted { $0.uuidString < $1.uuidString },
            healthOverlay: healthOverlay
        )
        if let data = try? state.encoded() {
            widgetDefaults?.set(data, forKey: HydrationWidgetStorage.stateKey)
        }
        latestWidgetLocalDate = state.localDate
        latestWidgetRevision = state.revision
    }

    private func requestComplicationReload(retryIfUnrendered: Bool = false) {
        guard let activeOwnerID,
              let localDate = latestWidgetLocalDate,
              let widgetDefaults
        else { return }
        let signature = HydrationComplicationRefreshPolicy.visibleSignature(
            ownerID: activeOwnerID,
            localDate: localDate,
            totalML: Int((liters * 1_000).rounded()),
            targetML: Int((preferences.targetLiters * 1_000).rounded()),
            composition: composition
        )
        guard HydrationComplicationRefreshPolicy.shouldReloadTimeline(
            renderedVisibleSignature: widgetDefaults.string(
                forKey: HydrationWidgetStorage.renderedVisibleSignatureKey
            ),
            requestedVisibleSignature: widgetDefaults.string(
                forKey: HydrationWidgetStorage.requestedVisibleSignatureKey
            ),
            newVisibleSignature: signature,
            retryUnrenderedRequest: retryIfUnrendered
        ) else { return }
        widgetDefaults.set(
            signature,
            forKey: HydrationWidgetStorage.requestedVisibleSignatureKey
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "ch.apexperformance.APEX.water")
    }

    private func rebaseForNewDay(_ localDate: String) {
        stateGeneration &+= 1
        liters = 0
        entries = []
        composition = []
        healthAnchor = []
        healthQueryAnchorData = nil
        canonicalSampleIDs = []
        healthOverlay = []
        pendingMutations = []
        persistPendingMutations()
        latestWidgetLocalDate = localDate
        persistWidgetState(absorbSidecar: false)
        requestComplicationReload()
    }

    private func ensureCurrentDay(_ localDate: String) {
        guard activeOwnerID != nil,
              HydrationWatchScopePolicy.shouldRebase(
                  storedLocalDate: latestWidgetLocalDate,
                  currentLocalDate: localDate
              )
        else { return }
        rebaseForNewDay(localDate)
    }

    private func absorbWidgetHealthStateIfCurrent() {
        guard let activeOwnerID,
              let canonicalData = widgetDefaults?.data(forKey: HydrationWidgetStorage.stateKey),
              let canonical = try? HydrationWidgetState.decode(canonicalData),
              canonical.ownerID == activeOwnerID,
              canonical.localDate == latestWidgetLocalDate,
              canonical.revision == latestWidgetRevision,
              let healthData = widgetDefaults?.data(forKey: HydrationWidgetStorage.healthStateKey),
              let healthState = try? HydrationWidgetHealthState.decode(healthData),
              healthState.matches(canonical)
        else { return }

        let resolved = HydrationWidgetStateResolver.resolve(
            canonical: canonical,
            healthState: healthState
        )
        liters = Double(resolved.totalML) / 1_000
        composition = resolved.composition
        healthAnchor = resolved.healthAnchor
        healthQueryAnchorData = resolved.healthQueryAnchorData
        healthOverlay = resolved.healthOverlay
    }

    private func recordPendingMutation(_ mutation: HydrationPendingMutation) {
        pendingMutations.removeAll { $0.sample.id == mutation.sample.id }
        pendingMutations.append(mutation)
        if var anchor = healthAnchor {
            anchor.removeAll { $0.id == mutation.sample.id }
            if mutation.action == .upsert {
                anchor.append(mutation.sample)
            }
            healthAnchor = anchor
        }
        persistPendingMutations()
    }

    private func persistPendingMutations() {
        if pendingMutations.isEmpty {
            defaults.removeObject(forKey: Self.pendingMutationsKey)
        } else if let data = try? JSONEncoder().encode(pendingMutations) {
            defaults.set(data, forKey: Self.pendingMutationsKey)
        }
    }

    private func persistPendingPreferenceRevision() {
        guard let pendingPreferenceOwnerID, let pendingPreferenceRevision else {
            defaults.removeObject(forKey: Self.pendingPreferenceOwnerKey)
            defaults.removeObject(forKey: Self.pendingPreferenceRevisionKey)
            return
        }
        defaults.set(
            pendingPreferenceOwnerID.uuidString.lowercased(),
            forKey: Self.pendingPreferenceOwnerKey
        )
        defaults.set(pendingPreferenceRevision, forKey: Self.pendingPreferenceRevisionKey)
    }

    private func clearPendingPreferenceRevision() {
        pendingPreferenceOwnerID = nil
        pendingPreferenceRevision = nil
        persistPendingPreferenceRevision()
    }

    private func recordDeferredDelete(_ deletion: HydrationDeferredDelete) {
        deferredDeletes.removeAll {
            $0.ownerID == deletion.ownerID && $0.eventID == deletion.eventID
        }
        deferredDeletes.append(deletion)
        persistDeferredDeletes()
    }

    private func persistDeferredDeletes() {
        if deferredDeletes.isEmpty {
            defaults.removeObject(forKey: Self.deferredDeletesKey)
        } else if let data = try? JSONEncoder().encode(deferredDeletes) {
            defaults.set(data, forKey: Self.deferredDeletesKey)
        }
    }

    private func applyLocalHydrationDelta(
        _ deltaML: Int,
        kind: HydrationKind,
        paletteToken: String,
        iconToken: String
    ) {
        guard deltaML != 0 else { return }
        liters = max(0, liters + (Double(deltaML) / 1_000))

        let matchingAmount = composition
            .filter {
                $0.kind == kind
                    && $0.paletteToken == paletteToken
                    && $0.iconToken == iconToken
            }
            .reduce(0) { $0 + $1.milliliters }
        var adjusted = composition.filter {
            $0.kind != kind
                || $0.paletteToken != paletteToken
                || $0.iconToken != iconToken
        }
        let updatedAmount = max(0, matchingAmount + deltaML)
        if updatedAmount > 0 {
            adjusted.append(HydrationCompositionBand(
                kind: kind,
                paletteToken: paletteToken,
                iconToken: iconToken,
                milliliters: updatedAmount
            ))
        }
        composition = Self.sortedComposition(adjusted)
        persistWidgetState(absorbSidecar: false)
        requestComplicationReload()
    }

    private static func compositionBands(from entries: [WatchHydrationEntry]) -> [HydrationCompositionBand] {
        struct Key: Hashable {
            let kind: HydrationKind
            let palette: String
            let icon: String
        }
        var totals: [Key: Int] = [:]
        for entry in entries {
            let key = Key(kind: entry.kind, palette: entry.paletteToken, icon: entry.iconToken)
            totals[key, default: 0] += Int(entry.milliliters.rounded())
        }
        return sortedComposition(totals.map {
            HydrationCompositionBand(
                kind: $0.key.kind,
                paletteToken: $0.key.palette,
                iconToken: $0.key.icon,
                milliliters: $0.value
            )
        })
    }

    private static func sortedComposition(
        _ bands: [HydrationCompositionBand]
    ) -> [HydrationCompositionBand] {
        let order: [HydrationKind: Int] = [
            .water: 0, .coffee: 1, .tea: 2, .juice: 3, .shake: 4,
            .other: 5, .external: 6, .food: 7, .legacy: 8,
        ]
        return bands.sorted {
            let lhs = (order[$0.kind] ?? 99, $0.paletteToken, $0.iconToken)
            let rhs = (order[$1.kind] ?? 99, $1.paletteToken, $1.iconToken)
            return lhs < rhs
        }
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

    private func removeHydrationReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending
                .filter { $0.identifier.hasPrefix(Self.reminderIdentifierPrefix) }
                .map(\.identifier)
        )
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
