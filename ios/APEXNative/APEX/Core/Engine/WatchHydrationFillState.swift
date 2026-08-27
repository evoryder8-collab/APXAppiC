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

enum HydrationComplicationRefreshPolicy {
    static func readingSource(
        hasSharedState: Bool,
        hasHealthData: Bool
    ) -> HydrationComplicationReadingSource {
        guard hasSharedState else { return hasHealthData ? .healthKit : .empty }
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
        localWidgetRevision _: String?,
        incomingRevision: String
    ) -> Bool {
        shouldAcceptSnapshot(
            currentRevision: acceptedCompanionRevision,
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
            .sorted()
            .joined(separator: ",")
        return [
            ownerID.uuidString.lowercased(),
            localDate,
            String(max(0, totalML)),
            String(max(250, targetML)),
            bands,
        ].joined(separator: "|")
    }

    private static func revisionDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
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
    private struct BandKey: Hashable {
        let kind: HydrationKind
        let paletteToken: String
        let iconToken: String
    }

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
        var bandTotals: [BandKey: Int] = [:]
        for band in composition where band.milliliters > 0 {
            let key = BandKey(
                kind: band.kind,
                paletteToken: band.paletteToken,
                iconToken: band.iconToken
            )
            bandTotals[key, default: 0] += band.milliliters
        }
        for adjustment in adjustments where adjustment.deltaML != 0 {
            let key = BandKey(
                kind: adjustment.sample.kind,
                paletteToken: adjustment.sample.paletteToken,
                iconToken: adjustment.sample.iconToken
            )
            bandTotals[key, default: 0] += adjustment.deltaML
        }

        let order: [HydrationKind: Int] = [
            .water: 0, .coffee: 1, .tea: 2, .juice: 3, .shake: 4,
            .other: 5, .external: 6, .food: 7, .legacy: 8,
        ]
        let resolvedComposition: [HydrationCompositionBand] = bandTotals.compactMap { element in
            let (key, amount) = element
            guard amount > 0 else { return nil }
            return HydrationCompositionBand(
                kind: key.kind,
                paletteToken: key.paletteToken,
                iconToken: key.iconToken,
                milliliters: amount
            )
        }.sorted {
            let lhs = (order[$0.kind] ?? 99, $0.paletteToken, $0.iconToken)
            let rhs = (order[$1.kind] ?? 99, $1.paletteToken, $1.iconToken)
            return lhs < rhs
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
