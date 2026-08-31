import Foundation

struct WatchHydrationFillState: Equatable, Sendable {
    let liters: Double
    let targetLiters: Double

    var progress: Double {
        guard targetLiters.isFinite, targetLiters > 0, liters.isFinite else { return 0 }
        return min(1, max(0, liters / targetLiters))
    }

    var baseWaterline: Double { 1 - progress }

    var primaryAmount: String {
        "\(liters.formatted(.number.precision(.fractionLength(2)))) L"
    }

    static func waterline(
        progress rawProgress: Double,
        normalizedX rawX: Double,
        phase: Double
    ) -> Double {
        let progress = min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
        let x = min(1, max(0, rawX.isFinite ? rawX : 0))
        let amplitude = min(0.018, progress * 0.08, (1 - progress) * 0.08)
        let wave = sin((x * .pi * 2) + phase) * amplitude
        return min(1, max(0, (1 - progress) + wave))
    }
}

enum HydrationComplicationReadingSource: Equatable, Sendable {
    case sharedState
    case healthKit
    case empty
}

enum HydrationComplicationDelivery: Equatable, Sendable {
    case snapshot
    case timeline(isPreview: Bool)
}

enum HydrationComplicationDeliveryPolicy {
    static func acknowledgedSignature(
        _ signature: String,
        delivery: HydrationComplicationDelivery
    ) -> String? {
        switch delivery {
        case .snapshot, .timeline(isPreview: true): nil
        case .timeline(isPreview: false): signature
        }
    }
}

enum HydrationObserverDelivery {
    @MainActor
    static func process(
        operation: () async throws -> Void,
        completion: () -> Void
    ) async {
        defer { completion() }
        try? await operation()
    }
}

enum HydrationHealthSampleOwnershipPolicy {
    static func belongs(
        explicitOwnerID: UUID?,
        sharedClaimOwnerID: UUID?,
        activeOwnerID: UUID?
    ) -> Bool {
        guard let activeOwnerID else { return false }
        if let explicitOwnerID { return explicitOwnerID == activeOwnerID }
        return sharedClaimOwnerID == activeOwnerID
    }
}

enum HydrationPendingPreferencePolicy {
    static func acknowledges(
        pending: WatchHydrationPreferences,
        incoming: WatchHydrationPreferences
    ) -> Bool {
        guard pending.effectiveTargetMode == .automatic,
              incoming.effectiveTargetMode == .automatic
        else { return pending == incoming }

        var normalizedIncoming = incoming
        normalizedIncoming.targetLiters = pending.targetLiters
        normalizedIncoming.targetMode = pending.targetMode
        return pending == normalizedIncoming
    }
}

enum HydrationComplicationRefreshPolicy {
    static func readingSource(
        hasSharedState: Bool,
        hasHealthData: Bool
    ) -> HydrationComplicationReadingSource {
        guard hasSharedState else { return .empty }
        return .sharedState
    }

    static func shouldAcceptSnapshot(
        currentRevision: String?,
        incomingRevision: String
    ) -> Bool {
        guard let currentRevision else { return true }

        if let currentDate = revisionDate(currentRevision),
           let incomingDate = revisionDate(incomingRevision) {
            return incomingDate >= currentDate
        }
        return incomingRevision >= currentRevision
    }

    static func shouldAcceptCompanionRevision(
        acceptedCompanionRevision: String?,
        localWidgetRevision: String?,
        incomingRevision: String,
        protectsLocalWidgetRevision: Bool = false
    ) -> Bool {
        guard shouldAcceptSnapshot(
            currentRevision: acceptedCompanionRevision,
            incomingRevision: incomingRevision
        ) else { return false }
        guard protectsLocalWidgetRevision else { return true }
        return shouldAcceptSnapshot(
            currentRevision: localWidgetRevision,
            incomingRevision: incomingRevision
        )
    }

    static func revision(at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func shouldRequestImmediateTransfer(
        complicationEnabled: Bool,
        remainingTransfers: Int,
        previousVisibleSignature: String?,
        newVisibleSignature: String
    ) -> Bool {
        complicationEnabled
            && remainingTransfers > 0
            && previousVisibleSignature != newVisibleSignature
    }

    static func visibleSignature(
        ownerID: UUID,
        localDate: String,
        totalML: Int,
        targetML: Int,
        composition: [HydrationCompositionBand]
    ) -> String {
        let bands = composition
            .filter { $0.milliliters > 0 }
            .map {
                "\($0.kind.rawValue):\($0.paletteToken):\($0.iconToken):\($0.milliliters)"
            }
            .joined(separator: ",")
        return [
            ownerID.uuidString.lowercased(),
            localDate,
            String(max(0, totalML)),
            String(max(250, targetML)),
            bands,
        ].joined(separator: "|")
    }

    static func visibleSignature(for state: HydrationWidgetState) -> String {
        visibleSignature(
            ownerID: state.ownerID,
            localDate: state.localDate,
            totalML: state.totalML,
            targetML: state.targetML,
            composition: state.composition
        )
    }

    static func shouldReloadTimeline(
        renderedVisibleSignature: String?,
        requestedVisibleSignature: String?,
        newVisibleSignature: String,
        retryUnrenderedRequest: Bool
    ) -> Bool {
        guard renderedVisibleSignature != newVisibleSignature else { return false }
        return requestedVisibleSignature != newVisibleSignature || retryUnrenderedRequest
    }

    static func nextTimelineRefresh(
        after date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let routineRefresh = date.addingTimeInterval(30 * 60)
        let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? routineRefresh
        return min(routineRefresh, midnight)
    }

    private static func revisionDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct HydrationComplicationMidnightReset: Equatable, Sendable {
    let date: Date
    let totalML: Int
    let composition: [HydrationCompositionBand]
}

struct HydrationComplicationTimelineSchedule: Equatable, Sendable {
    let midnightReset: HydrationComplicationMidnightReset
    let refreshAfter: Date
}

enum HydrationComplicationDayRollover {
    static func state(
        _ stored: HydrationWidgetState,
        for currentDate: String
    ) -> HydrationWidgetState? {
        if stored.localDate == currentDate { return stored }
        guard stored.localDate < currentDate else { return nil }

        return HydrationWidgetState(
            ownerID: stored.ownerID,
            localDate: currentDate,
            totalML: 0,
            targetML: stored.targetML,
            composition: [],
            revision: stored.revision,
            healthAnchor: nil,
            healthQueryAnchorData: nil,
            canonicalSampleIDs: nil,
            healthOverlay: nil
        )
    }
}

enum HydrationComplicationTimelinePolicy {
    static func schedule(
        after date: Date,
        calendar: Calendar = .current
    ) -> HydrationComplicationTimelineSchedule {
        let routineRefresh = date.addingTimeInterval(30 * 60)
        let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? routineRefresh
        /* The explicit zero entry clears yesterday at midnight. Ask for a
           fresh canonical snapshot one minute later so that zero cannot
           become the long-lived face value when WidgetKit defers its normal
           half-hour refresh. */
        let postMidnightRecovery = midnight.addingTimeInterval(60)
        let refreshAfter = min(routineRefresh, postMidnightRecovery)
        return HydrationComplicationTimelineSchedule(
            midnightReset: HydrationComplicationMidnightReset(
                date: midnight,
                totalML: 0,
                composition: []
            ),
            refreshAfter: refreshAfter
        )
    }
}

struct HydrationHealthSampleAnchor: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let milliliters: Int
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String

    init(
        id: UUID,
        milliliters: Int,
        kind: HydrationKind,
        paletteToken: String,
        iconToken: String
    ) {
        self.id = id
        self.milliliters = max(0, milliliters)
        self.kind = kind
        self.paletteToken = paletteToken
        self.iconToken = iconToken
    }
}

enum HydrationPendingMutationAction: String, Codable, Sendable {
    case upsert
    case delete
}

struct HydrationPendingMutation: Codable, Equatable, Sendable {
    let ownerID: UUID
    let localDate: String
    let action: HydrationPendingMutationAction
    let sample: HydrationHealthSampleAnchor
}

struct HydrationDeferredDelete: Codable, Equatable, Sendable {
    let ownerID: UUID
    let eventID: UUID
    let localDate: String
}

struct HydrationDeferredDeleteReconciliation: Equatable, Sendable {
    let remaining: [HydrationDeferredDelete]
    let toReplay: [HydrationDeferredDelete]
}

enum HydrationDeferredDeleteReconciler {
    static func reconcile(
        _ queued: [HydrationDeferredDelete],
        snapshotOwnerID: UUID,
        snapshotLocalDate: String,
        snapshotEventIDs: Set<UUID>,
        acknowledgedDeleteIDs: Set<UUID>
    ) -> HydrationDeferredDeleteReconciliation {
        var remaining: [HydrationDeferredDelete] = []
        var toReplay: [HydrationDeferredDelete] = []
        for deletion in queued {
            guard deletion.ownerID == snapshotOwnerID else {
                remaining.append(deletion)
                continue
            }
            if acknowledgedDeleteIDs.contains(deletion.eventID) {
                continue
            }
            if deletion.localDate == snapshotLocalDate,
               !snapshotEventIDs.contains(deletion.eventID) {
                continue
            }
            remaining.append(deletion)
            toReplay.append(deletion)
        }
        return HydrationDeferredDeleteReconciliation(
            remaining: remaining,
            toReplay: toReplay
        )
    }
}

struct HydrationReconciledState: Equatable, Sendable {
    let totalML: Int
    let composition: [HydrationCompositionBand]
}

struct HydrationHealthOverlayUpdate: Equatable, Sendable {
    let mutations: [HydrationPendingMutation]
    let nextAnchor: [HydrationHealthSampleAnchor]
}

actor HydrationHealthSidecarStore {
    static let shared = HydrationHealthSidecarStore()

    private let suiteName: String

    init(suiteName: String = HydrationWidgetStorage.suiteName) {
        self.suiteName = suiteName
    }

    @discardableResult
    func persist(
        shared: HydrationWidgetState,
        healthQueryAnchorData: Data?,
        update: HydrationHealthOverlayUpdate,
        reconciled: HydrationReconciledState,
        observationRevision: String
    ) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let latestData = defaults.data(forKey: HydrationWidgetStorage.stateKey),
              let latest = try? HydrationWidgetState.decode(latestData),
              latest.ownerID == shared.ownerID,
              latest.localDate == shared.localDate,
              latest.revision == shared.revision
        else { return false }

        let updated = HydrationWidgetHealthState(
            ownerID: latest.ownerID,
            localDate: latest.localDate,
            baseRevision: latest.revision,
            observationRevision: observationRevision,
            totalML: reconciled.totalML,
            composition: reconciled.composition,
            healthAnchor: update.nextAnchor,
            healthQueryAnchorData: healthQueryAnchorData ?? latest.healthQueryAnchorData,
            healthOverlay: update.mutations
        )
        let existing = defaults.data(forKey: HydrationWidgetStorage.healthStateKey)
            .flatMap { try? HydrationWidgetHealthState.decode($0) }
        guard HydrationHealthSidecarWritePolicy.shouldPersist(
            existing: existing,
            incoming: updated,
            canonical: latest
        ), let data = try? updated.encoded() else { return false }

        defaults.set(data, forKey: HydrationWidgetStorage.healthStateKey)
        return true
    }
}

struct HydrationWatchOperationScope: Equatable, Sendable {
    let ownerID: UUID
    let localDate: String
    let generation: Int

    func matches(ownerID: UUID?, localDate: String, generation: Int) -> Bool {
        self.ownerID == ownerID
            && self.localDate == localDate
            && self.generation == generation
    }
}

enum HydrationWatchScopePolicy {
    static func shouldRebase(storedLocalDate: String?, currentLocalDate: String) -> Bool {
        guard let storedLocalDate else { return false }
        return storedLocalDate != currentLocalDate
    }

    static func persistenceLocalDate(
        storedLocalDate: String?,
        currentLocalDate: String
    ) -> String {
        storedLocalDate ?? currentLocalDate
    }
}

enum HydrationHealthReconciler {
    static func applying(
        _ pending: [HydrationPendingMutation],
        toTotalML totalML: Int,
        composition: [HydrationCompositionBand]
    ) -> HydrationReconciledState {
        applyingAdjustments(
            pending.map {
                ($0.sample, $0.action == .upsert ? $0.sample.milliliters : -$0.sample.milliliters)
            },
            toTotalML: totalML,
            composition: composition
        )
    }

    static func unacknowledged(
        _ pending: [HydrationPendingMutation],
        snapshotOwnerID: UUID,
        snapshotLocalDate: String,
        snapshotEventIDs: Set<UUID>
    ) -> [HydrationPendingMutation] {
        pending.filter {
            $0.ownerID == snapshotOwnerID && $0.localDate == snapshotLocalDate
        }.filter { mutation in
            switch mutation.action {
            case .upsert:
                return !snapshotEventIDs.contains(mutation.sample.id)
            case .delete:
                return snapshotEventIDs.contains(mutation.sample.id)
            }
        }
    }

    static func updatedHealthOverlay(
        _ existing: [HydrationPendingMutation],
        ownerID: UUID,
        localDate: String,
        canonicalSampleIDs: Set<UUID>,
        anchor: [HydrationHealthSampleAnchor]?,
        current: [HydrationHealthSampleAnchor],
        deletedSampleIDs: Set<UUID> = []
    ) -> HydrationHealthOverlayUpdate {
        let acknowledged = unacknowledged(
            existing,
            snapshotOwnerID: ownerID,
            snapshotLocalDate: localDate,
            snapshotEventIDs: canonicalSampleIDs
        )
        guard let anchor else {
            return HydrationHealthOverlayUpdate(
                mutations: acknowledged,
                nextAnchor: current
                    .filter { !deletedSampleIDs.contains($0.id) }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
            )
        }

        var mutationsByID = Dictionary(
            uniqueKeysWithValues: acknowledged.map { ($0.sample.id, $0) }
        )
        let anchorByID = Dictionary(uniqueKeysWithValues: anchor.map { ($0.id, $0) })
        var nextAnchorByID = anchorByID
        for sample in current {
            nextAnchorByID[sample.id] = sample
        }
        for deletedSampleID in deletedSampleIDs {
            nextAnchorByID.removeValue(forKey: deletedSampleID)
        }

        func merge(_ action: HydrationPendingMutationAction, sample: HydrationHealthSampleAnchor) {
            if let existing = mutationsByID[sample.id], existing.action != action {
                mutationsByID.removeValue(forKey: sample.id)
            } else {
                mutationsByID[sample.id] = HydrationPendingMutation(
                    ownerID: ownerID,
                    localDate: localDate,
                    action: action,
                    sample: sample
                )
            }
        }

        for sample in current where anchorByID[sample.id] == nil {
            if canonicalSampleIDs.contains(sample.id) {
                if mutationsByID[sample.id]?.action == .delete {
                    mutationsByID.removeValue(forKey: sample.id)
                }
            } else {
                merge(.upsert, sample: sample)
            }
        }
        for deletedSampleID in deletedSampleIDs {
            guard let sample = anchorByID[deletedSampleID]
                ?? mutationsByID[deletedSampleID]?.sample
            else { continue }

            if canonicalSampleIDs.contains(deletedSampleID) {
                merge(.delete, sample: sample)
            } else if mutationsByID[deletedSampleID]?.action == .upsert {
                mutationsByID.removeValue(forKey: deletedSampleID)
            }
        }

        return HydrationHealthOverlayUpdate(
            mutations: mutationsByID.values.sorted {
                $0.sample.id.uuidString < $1.sample.id.uuidString
            },
            nextAnchor: nextAnchorByID.values.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    static func replacingOverlay(
        _ previous: [HydrationPendingMutation],
        with updated: [HydrationPendingMutation],
        inTotalML totalML: Int,
        composition: [HydrationCompositionBand]
    ) -> HydrationReconciledState {
        let reversed = previous.map {
            HydrationPendingMutation(
                ownerID: $0.ownerID,
                localDate: $0.localDate,
                action: $0.action == .upsert ? .delete : .upsert,
                sample: $0.sample
            )
        }
        let withoutPrevious = applying(
            reversed,
            toTotalML: totalML,
            composition: composition
        )
        return applying(
            updated,
            toTotalML: withoutPrevious.totalML,
            composition: withoutPrevious.composition
        )
    }

    private static func applyingAdjustments(
        _ adjustments: [(sample: HydrationHealthSampleAnchor, deltaML: Int)],
        toTotalML totalML: Int,
        composition: [HydrationCompositionBand]
    ) -> HydrationReconciledState {
        guard !adjustments.isEmpty else {
            return HydrationReconciledState(totalML: max(0, totalML), composition: composition)
        }

        var resolvedComposition = composition
        for adjustment in adjustments where adjustment.deltaML != 0 {
            let sample = adjustment.sample
            if let index = resolvedComposition.firstIndex(where: {
                $0.kind == sample.kind
                    && $0.paletteToken == sample.paletteToken
                    && $0.iconToken == sample.iconToken
            }) {
                let amount = resolvedComposition[index].milliliters + adjustment.deltaML
                if amount > 0 {
                    resolvedComposition[index] = HydrationCompositionBand(
                        kind: sample.kind,
                        paletteToken: sample.paletteToken,
                        iconToken: sample.iconToken,
                        milliliters: amount
                    )
                } else {
                    resolvedComposition.remove(at: index)
                }
            } else if adjustment.deltaML > 0 {
                resolvedComposition.insert(
                    HydrationCompositionBand(
                        kind: sample.kind,
                        paletteToken: sample.paletteToken,
                        iconToken: sample.iconToken,
                        milliliters: adjustment.deltaML
                    ),
                    at: 0
                )
            }
        }
        return HydrationReconciledState(
            totalML: max(0, totalML + adjustments.reduce(0) { $0 + $1.deltaML }),
            composition: resolvedComposition
        )
    }
}

struct HydrationCompositionStop: Equatable, Sendable {
    let paletteToken: String
    let location: Double
}

enum HydrationCompositionLayout {
    private static let maximumTransitionHalfWidth = 0.0023

    /// Hydration composition is newest-first so the silhouette's zero offset
    /// paints the latest addition at its top. A chronological horizontal
    /// timeline needs the inverse order: morning on the left, latest on the
    /// right.
    static func timelineStops(
        for bands: [HydrationCompositionBand],
        mappedInto range: ClosedRange<Double> = 0 ... 1
    ) -> [HydrationCompositionStop] {
        stops(for: Array(bands.reversed()), mappedInto: range)
    }

    static func stops(
        for bands: [HydrationCompositionBand],
        mappedInto range: ClosedRange<Double> = 0 ... 1
    ) -> [HydrationCompositionStop] {
        let populated = bands.filter { $0.milliliters > 0 }
        guard !populated.isEmpty else { return [] }

        let lower = min(1, max(0, range.lowerBound.isFinite ? range.lowerBound : 0))
        let upper = min(1, max(lower, range.upperBound.isFinite ? range.upperBound : 1))
        let span = upper - lower

        let coalesced = populated.reduce(into: [(paletteToken: String, milliliters: Int)]()) {
            result, band in
            if result.last?.paletteToken == band.paletteToken {
                result[result.count - 1].milliliters += band.milliliters
            } else {
                result.append((band.paletteToken, band.milliliters))
            }
        }
        guard let first = coalesced.first, let last = coalesced.last else { return [] }
        guard coalesced.count > 1 else {
            return [
                HydrationCompositionStop(paletteToken: first.paletteToken, location: lower),
                HydrationCompositionStop(paletteToken: first.paletteToken, location: upper),
            ]
        }

        let total = Double(coalesced.reduce(0) { $0 + $1.milliliters })
        var stops = [HydrationCompositionStop(paletteToken: first.paletteToken, location: lower)]
        var cumulative = 0.0

        for index in 0 ..< (coalesced.count - 1) {
            let current = coalesced[index]
            let next = coalesced[index + 1]
            cumulative += Double(current.milliliters)

            let boundary = cumulative / total
            let currentShare = Double(current.milliliters) / total
            let nextShare = Double(next.milliliters) / total
            let transitionHalfWidth = min(
                maximumTransitionHalfWidth,
                currentShare * 0.092,
                nextShare * 0.092
            )

            stops.append(
                HydrationCompositionStop(
                    paletteToken: current.paletteToken,
                    location: lower + ((boundary - transitionHalfWidth) * span)
                )
            )
            stops.append(
                HydrationCompositionStop(
                    paletteToken: next.paletteToken,
                    location: lower + ((boundary + transitionHalfWidth) * span)
                )
            )
        }

        stops.append(HydrationCompositionStop(paletteToken: last.paletteToken, location: upper))
        return stops
    }
}

enum WatchHydrationAnimationPolicy {
    static func shouldAnimate(
        sceneIsActive: Bool,
        luminanceIsReduced: Bool,
        reduceMotion: Bool
    ) -> Bool {
        sceneIsActive && !luminanceIsReduced && !reduceMotion
    }
}

enum WatchHydrationAuthorship {
    static let phoneBundleIdentifier = "ch.apexperformance.APEX"
    static let watchBundleIdentifier = "ch.apexperformance.APEX.watchkitapp"
    static let watchSyncIdentifierPrefix = "apex.hydration.watch."

    static func canDelete(
        sourceBundleIdentifier: String,
        syncIdentifier: String? = nil
    ) -> Bool {
        if sourceBundleIdentifier == watchBundleIdentifier { return true }
        return sourceBundleIdentifier == phoneBundleIdentifier
            && syncIdentifier?.hasPrefix(watchSyncIdentifierPrefix) == true
    }
}

enum WatchHydrationDisplayMode: String, CaseIterable, Sendable {
    case percent
    case liters
    case gallons

    func shortValue(for state: WatchHydrationFillState) -> String {
        switch self {
        case .percent:
            return "\(Int((state.progress * 100).rounded()))%"
        case .liters:
            return "\(state.liters.formatted(.number.precision(.fractionLength(2))))L"
        case .gallons:
            let gallons = state.liters * 0.264_172_052
            return "\(gallons.formatted(.number.precision(.fractionLength(2))))gal"
        }
    }
}
