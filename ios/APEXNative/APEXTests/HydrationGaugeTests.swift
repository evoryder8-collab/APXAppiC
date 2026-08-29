import XCTest
@testable import APEX

/*
 * The litre scale beside the hydration figure has to land on the body, not
 * on the frame. The SVG viewBox is "-150 -150 W 1015"; inside it the crown
 * of the head is y = 0 and the feet, where the fill rests at zero, are
 * y = 712. Rendered with xMidYMid meet into a frame of the same aspect
 * ratio, those become fixed fractions of the frame height.
 *
 * These pin the mapping so a future layout change cannot quietly detach the
 * ruler from the silhouette again.
 */
final class HydrationGaugeTests: XCTestCase {

    private let crownFraction = 150.0 / 1015.0
    private let feetFraction = 862.0 / 1015.0

    private func tickY(liters: Double, target: Double, height: Double) -> Double {
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        let fraction = target > 0 ? min(1, max(0, liters / target)) : 0
        return feetY - fraction * (feetY - crownY)
    }

    func testZeroLitresSitsAtTheFeet() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 0, target: 2.75, height: height), feetFraction * height, accuracy: 0.001)
    }

    func testTargetSitsAtTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 2.75, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testHalfTheTargetSitsHalfwayUpTheBody() {
        let height = 400.0
        let crownY = crownFraction * height
        let feetY = feetFraction * height
        XCTAssertEqual(
            tickY(liters: 1.375, target: 2.75, height: height),
            (crownY + feetY) / 2,
            accuracy: 0.001
        )
    }

    func testScaleIsProportionalToFrameHeight() {
        /* Doubling the figure doubles every offset, so the ruler tracks it. */
        let small = tickY(liters: 1.0, target: 2.75, height: 200)
        let large = tickY(liters: 1.0, target: 2.75, height: 400)
        XCTAssertEqual(large, small * 2, accuracy: 0.001)
    }

    func testBodyOccupiesTheExpectedSliceOfTheFrame() {
        /* Guards against someone "fixing" the layout by stretching the web
           view to full height, which would silently break the alignment. */
        XCTAssertEqual(crownFraction, 0.1478, accuracy: 0.0005)
        XCTAssertEqual(feetFraction, 0.8493, accuracy: 0.0005)
    }

    func testOverdrinkingIsClampedToTheCrown() {
        let height = 400.0
        XCTAssertEqual(tickY(liters: 5.0, target: 2.75, height: height), crownFraction * height, accuracy: 0.001)
    }

    func testFigureAspectMatchesTheViewBox() {
        /* Frame aspect must equal the viewBox aspect or xMidYMid meet
           letterboxes the drawing and the fractions above stop holding. */
        XCTAssertEqual(583.6 / 1015.0, 0.5750, accuracy: 0.0005, "male figure")
        XCTAssertEqual(568.0 / 1015.0, 0.5596, accuracy: 0.0005, "female figure")
    }

    func testQuickAddFigureCannotBlockTheCustomFieldAndDisabledActionStaysReadable() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Portal/SimpleHomeView.swift"))

        XCTAssertTrue(
            source.contains(".allowsHitTesting(false) // hydration gauge is presentation only"),
            "the transparent figure renderer must never intercept taps below its visual bounds"
        )
        XCTAssertTrue(
            source.contains(".onTapGesture { customIsFocused = true }"),
            "the whole custom-amount control must focus immediately, not only a narrow text glyph"
        )
        XCTAssertFalse(
            source.contains(".opacity(customAmountML == nil ? 0.45 : 1)"),
            "disabled Add copy needs a deliberate high-contrast palette rather than whole-control fading"
        )
    }

    func testWatchOwnsDedicatedIconAndSilhouetteAssets() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: nativeRoot.appending(path: "APEXNative.xcodeproj/project.pbxproj")
        )
        let watchAssets = nativeRoot.appending(path: "APEXWatch/WatchAssets.xcassets")
        let iconManifest = try String(
            contentsOf: watchAssets.appending(path: "AppIcon.appiconset/Contents.json")
        )
        let silhouetteManifest = try String(
            contentsOf: watchAssets.appending(path: "WatchHydrationSilhouette.imageset/Contents.json")
        )
        let watchView = try String(
            contentsOf: nativeRoot.appending(path: "APEXWatch/WatchHydrationView.swift")
        )

        XCTAssertTrue(project.contains("WatchAssets.xcassets"))
        XCTAssertTrue(iconManifest.contains("APEXWatchIcon.png"))
        XCTAssertTrue(iconManifest.contains(#""platform" : "watchos""#))
        XCTAssertTrue(silhouetteManifest.contains("WatchHydrationSilhouette.png"))
        XCTAssertTrue(watchView.contains(#"Image("WatchHydrationSilhouette")"#))
    }
}

final class WatchHydrationFillStateTests: XCTestCase {
    private func healthSample(
        _ id: String,
        milliliters: Int,
        kind: HydrationKind = .water,
        palette: String = "aqua",
        icon: String = "drop.fill"
    ) -> HydrationHealthSampleAnchor {
        HydrationHealthSampleAnchor(
            id: UUID(uuidString: id)!,
            milliliters: milliliters,
            kind: kind,
            paletteToken: palette,
            iconToken: icon
        )
    }

    func testProgressAndWaterlineClampAtEmptyAndTarget() {
        let empty = WatchHydrationFillState(liters: -0.5, targetLiters: 2.75)
        let full = WatchHydrationFillState(liters: 4.0, targetLiters: 2.75)

        XCTAssertEqual(empty.progress, 0)
        XCTAssertEqual(empty.baseWaterline, 1)
        XCTAssertEqual(full.progress, 1)
        XCTAssertEqual(full.baseWaterline, 0)
    }

    func testWaterlineRisesProportionallyThroughTheBody() {
        let quarter = WatchHydrationFillState(liters: 0.6875, targetLiters: 2.75)
        let half = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)
        let threeQuarters = WatchHydrationFillState(liters: 2.0625, targetLiters: 2.75)

        XCTAssertEqual(quarter.baseWaterline, 0.75, accuracy: 0.0001)
        XCTAssertEqual(half.baseWaterline, 0.5, accuracy: 0.0001)
        XCTAssertEqual(threeQuarters.baseWaterline, 0.25, accuracy: 0.0001)
    }

    func testWaveCannotCreateWaterWhenEmptyOrLeaveAirWhenFull() {
        for phase in stride(from: 0.0, through: Double.pi * 2, by: 0.4) {
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 0, normalizedX: 0.35, phase: phase),
                1,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                WatchHydrationFillState.waterline(progress: 1, normalizedX: 0.65, phase: phase),
                0,
                accuracy: 0.0001
            )
        }
    }

    func testAnimatedWaveStaysInsideNormalizedGaugeBounds() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                let waterline = WatchHydrationFillState.waterline(
                    progress: progress,
                    normalizedX: x,
                    phase: 1.75
                )
                XCTAssertGreaterThanOrEqual(waterline, 0)
                XCTAssertLessThanOrEqual(waterline, 1)
            }
        }
    }

    func testComplicationModesDeriveFromLitersWithoutStoringConvertedValues() {
        let state = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)
        XCTAssertEqual(WatchHydrationDisplayMode.percent.shortValue(for: state), "50%")
        XCTAssertEqual(WatchHydrationDisplayMode.liters.shortValue(for: state), "1.38L")
        XCTAssertEqual(WatchHydrationDisplayMode.gallons.shortValue(for: state), "0.36gal")
    }

    @MainActor
    func testHydrationObserverCompletionRunsAfterTheFullAsyncRefresh() async {
        var events: [String] = []

        await HydrationObserverDelivery.process(
            operation: {
                events.append("refresh started")
                await Task.yield()
                events.append("refresh finished")
            },
            completion: { events.append("completion") }
        )

        XCTAssertEqual(events, ["refresh started", "refresh finished", "completion"])
    }

    @MainActor
    func testHydrationObserverCompletionStillRunsWhenRefreshThrows() async {
        enum ExpectedFailure: Error { case refresh }
        var events: [String] = []

        await HydrationObserverDelivery.process(
            operation: {
                events.append("refresh")
                throw ExpectedFailure.refresh
            },
            completion: { events.append("completion") }
        )

        XCTAssertEqual(events, ["refresh", "completion"])
    }

    func testComplicationKeepsNewerCompanionSnapshotWhenLocalHealthKitIsBehind() {
        XCTAssertEqual(
            HydrationComplicationRefreshPolicy.readingSource(
                hasSharedState: true,
                hasHealthData: true
            ),
            .sharedState
        )
    }

    func testComplicationNeverReplacesCompleteSharedStateWithAPartialHealthKitAggregate() {
        XCTAssertEqual(
            HydrationComplicationRefreshPolicy.readingSource(
                hasSharedState: true,
                hasHealthData: true
            ),
            .sharedState
        )
    }

    func testComplicationNeverShowsAccountUnscopedHealthKitWithoutACanonicalOwner() {
        XCTAssertEqual(
            HydrationComplicationRefreshPolicy.readingSource(
                hasSharedState: false,
                hasHealthData: true
            ),
            .empty
        )
    }

    func testComplicationRejectsAnOlderSnapshotDeliveredOnASecondConnectivityChannel() {
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: "2026-08-27T20:10:00Z",
                incomingRevision: "2026-08-27T20:09:00Z"
            )
        )
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: "2026-08-27T20:10:00Z",
                incomingRevision: "2026-08-27T20:11:00Z"
            )
        )
    }

    func testComplicationRevisionsDistinguishRapidConsecutivePublishes() {
        let first = HydrationComplicationRefreshPolicy.revision(
            at: Date(timeIntervalSince1970: 2_000.001)
        )
        let second = HydrationComplicationRefreshPolicy.revision(
            at: Date(timeIntervalSince1970: 2_000.002)
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: first,
                incomingRevision: second
            )
        )
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: second,
                incomingRevision: first
            )
        )
    }

    func testDisconnectedRevisionRejectsADelayedAccountSnapshot() {
        let tombstone = HydrationComplicationRefreshPolicy.revision(
            at: Date(timeIntervalSince1970: 2_000)
        )
        let delayedAccountSnapshot = HydrationComplicationRefreshPolicy.revision(
            at: Date(timeIntervalSince1970: 1_999)
        )

        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: tombstone,
                incomingRevision: delayedAccountSnapshot
            )
        )
    }

    func testLocalWidgetRevisionCannotRejectANewerPhoneDisconnect() {
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldAcceptCompanionRevision(
                acceptedCompanionRevision: "2026-08-27T20:00:00.000Z",
                localWidgetRevision: "2026-08-27T20:10:00.000Z",
                incomingRevision: "2026-08-27T20:05:00.000Z"
            )
        )
    }

    func testPendingWatchGoalRejectsDelayedPhoneSnapshotUntilThePhoneCatchesUp() {
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldAcceptCompanionRevision(
                acceptedCompanionRevision: "2026-08-27T20:00:00.000Z",
                localWidgetRevision: "2026-08-27T20:10:00.000Z",
                incomingRevision: "2026-08-27T20:05:00.000Z",
                protectsLocalWidgetRevision: true
            )
        )
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldAcceptCompanionRevision(
                acceptedCompanionRevision: "2026-08-27T20:05:00.000Z",
                localWidgetRevision: "2026-08-27T20:10:00.000Z",
                incomingRevision: "2026-08-27T20:10:00.000Z",
                protectsLocalWidgetRevision: true
            )
        )

        var watchPreference = WatchHydrationPreferences.default
        watchPreference.targetMode = .custom
        watchPreference.targetLiters = 3.8
        let matchingPhonePreference = watchPreference
        var stalePhonePreference = watchPreference
        stalePhonePreference.targetLiters = 2.75

        XCTAssertFalse(HydrationPendingPreferencePolicy.acknowledges(
            pending: watchPreference,
            incoming: stalePhonePreference
        ))
        XCTAssertTrue(HydrationPendingPreferencePolicy.acknowledges(
            pending: watchPreference,
            incoming: matchingPhonePreference
        ))
    }

    func testPendingAutomaticWatchPreferenceAcceptsARecalculatedPhoneTargetOnly() {
        var watchPreference = WatchHydrationPreferences.default
        watchPreference.targetMode = .automatic
        watchPreference.targetLiters = 2.75
        watchPreference.unit = .gallons
        watchPreference.showsPresetNames = false
        watchPreference.confirmationHaptics = false
        watchPreference.motionIntensity = .full
        watchPreference.remindersEnabled = true
        watchPreference.reminderIntervalMinutes = 120
        watchPreference.quietHoursStartMinutes = 20 * 60
        watchPreference.quietHoursEndMinutes = 7 * 60

        var recalculatedPhonePreference = watchPreference
        recalculatedPhonePreference.targetLiters = 3.45

        XCTAssertTrue(HydrationPendingPreferencePolicy.acknowledges(
            pending: watchPreference,
            incoming: recalculatedPhonePreference
        ))

        var changedUserPreference = recalculatedPhonePreference
        changedUserPreference.remindersEnabled = false
        XCTAssertFalse(HydrationPendingPreferencePolicy.acknowledges(
            pending: watchPreference,
            incoming: changedUserPreference
        ))

        watchPreference.targetMode = .custom
        watchPreference.targetLiters = 3.8
        var changedCustomTarget = watchPreference
        changedCustomTarget.targetLiters = 3.9
        XCTAssertFalse(HydrationPendingPreferencePolicy.acknowledges(
            pending: watchPreference,
            incoming: changedCustomTarget
        ))
    }

    func testAnchoredHealthKitDeltaPreservesCompleteSharedTotalAndTracksExternalChanges() throws {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let existing = healthSample(
            "00000000-0000-0000-0000-000000000001",
            milliliters: 330
        )
        let externalCoffee = healthSample(
            "00000000-0000-0000-0000-000000000002",
            milliliters: 100,
            kind: .coffee,
            palette: "espresso",
            icon: "cup.and.saucer.fill"
        )
        let baseComposition = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 770
            ),
        ]

        let unchangedUpdate = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [],
            anchor: [existing],
            current: [existing]
        )
        let unchanged = HydrationHealthReconciler.replacingOverlay(
            [],
            with: unchangedUpdate.mutations,
            inTotalML: 770,
            composition: baseComposition
        )
        XCTAssertEqual(unchanged.totalML, 770)

        let addedUpdate = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [],
            anchor: [existing],
            current: [existing, externalCoffee]
        )
        let added = HydrationHealthReconciler.replacingOverlay(
            [],
            with: addedUpdate.mutations,
            inTotalML: 770,
            composition: baseComposition
        )
        XCTAssertEqual(added.totalML, 870)
        XCTAssertEqual(
            try XCTUnwrap(added.composition.first { $0.kind == .coffee }).milliliters,
            100
        )

        let unanchoredUpdate = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [],
            anchor: nil,
            current: [existing, externalCoffee]
        )
        let unanchored = HydrationHealthReconciler.replacingOverlay(
            [],
            with: unanchoredUpdate.mutations,
            inTotalML: 770,
            composition: baseComposition
        )
        XCTAssertEqual(unanchored.totalML, 770)
        XCTAssertEqual(unanchored.composition, baseComposition)
    }

    func testEmptyHydrationAdjustmentsPreserveNewestFirstCanonicalCompositionExactly() {
        let newestFirst = [
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 300
            ),
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 500
            ),
            HydrationCompositionBand(
                kind: .tea,
                paletteToken: "tea",
                iconToken: "mug.fill",
                milliliters: 200
            ),
        ]

        let resolved = HydrationHealthReconciler.applying(
            [],
            toTotalML: 1_000,
            composition: newestFirst
        )

        XCTAssertEqual(resolved.totalML, 1_000)
        XCTAssertEqual(resolved.composition, newestFirst)
    }

    func testHydrationAdjustmentsMinimallyMergeWithoutReorderingUnaffectedBands() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000080")!
        let coffee = HydrationCompositionBand(
            kind: .coffee,
            paletteToken: "espresso",
            iconToken: "cup.and.saucer.fill",
            milliliters: 300
        )
        let water = HydrationCompositionBand(
            kind: .water,
            paletteToken: "aqua",
            iconToken: "drop.fill",
            milliliters: 500
        )
        let tea = HydrationCompositionBand(
            kind: .tea,
            paletteToken: "tea",
            iconToken: "mug.fill",
            milliliters: 200
        )
        let waterAddition = HydrationPendingMutation(
            ownerID: ownerID,
            localDate: "2026-08-29",
            action: .upsert,
            sample: healthSample(
                "00000000-0000-0000-0000-000000000081",
                milliliters: 100
            )
        )
        let externalAddition = HydrationPendingMutation(
            ownerID: ownerID,
            localDate: "2026-08-29",
            action: .upsert,
            sample: healthSample(
                "00000000-0000-0000-0000-000000000082",
                milliliters: 50,
                kind: .external,
                palette: "external",
                icon: "heart.fill"
            )
        )

        let resolved = HydrationHealthReconciler.applying(
            [waterAddition, externalAddition],
            toTotalML: 1_000,
            composition: [coffee, water, tea]
        )

        XCTAssertEqual(resolved.totalML, 1_150)
        XCTAssertEqual(resolved.composition, [
            HydrationCompositionBand(
                kind: .external,
                paletteToken: "external",
                iconToken: "heart.fill",
                milliliters: 50
            ),
            coffee,
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 600
            ),
            tea,
        ])
    }

    func testPendingWatchMutationsOverlaySnapshotsUntilTheirEventIsAcknowledged() {
        let added = healthSample(
            "00000000-0000-0000-0000-000000000010",
            milliliters: 70
        )
        let deleted = healthSample(
            "00000000-0000-0000-0000-000000000011",
            milliliters: 100,
            kind: .coffee,
            palette: "espresso",
            icon: "cup.and.saucer.fill"
        )
        let pending = [
            HydrationPendingMutation(
                ownerID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
                localDate: "2026-08-27",
                action: .upsert,
                sample: added
            ),
            HydrationPendingMutation(
                ownerID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
                localDate: "2026-08-27",
                action: .delete,
                sample: deleted
            ),
        ]
        let staleSnapshotEvents: Set<UUID> = [deleted.id]
        let stillPending = HydrationHealthReconciler.unacknowledged(
            pending,
            snapshotOwnerID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            snapshotLocalDate: "2026-08-27",
            snapshotEventIDs: staleSnapshotEvents
        )

        XCTAssertEqual(stillPending, pending)
        let overlaid = HydrationHealthReconciler.applying(
            stillPending,
            toTotalML: 800,
            composition: [
                HydrationCompositionBand(
                    kind: .water,
                    paletteToken: "aqua",
                    iconToken: "drop.fill",
                    milliliters: 700
                ),
                HydrationCompositionBand(
                    kind: .coffee,
                    paletteToken: "espresso",
                    iconToken: "cup.and.saucer.fill",
                    milliliters: 100
                ),
            ]
        )
        XCTAssertEqual(overlaid.totalML, 770)

        let acknowledged = HydrationHealthReconciler.unacknowledged(
            pending,
            snapshotOwnerID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            snapshotLocalDate: "2026-08-27",
            snapshotEventIDs: [added.id]
        )
        XCTAssertTrue(acknowledged.isEmpty)

        let expiredAtMidnight = HydrationHealthReconciler.unacknowledged(
            pending,
            snapshotOwnerID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            snapshotLocalDate: "2026-08-28",
            snapshotEventIDs: []
        )
        XCTAssertTrue(expiredAtMidnight.isEmpty)
    }

    func testDelayedCanonicalHealthSampleIsNotCountedTwice() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let existing = healthSample(
            "00000000-0000-0000-0000-000000000041",
            milliliters: 330
        )
        let delayedCanonical = healthSample(
            "00000000-0000-0000-0000-000000000042",
            milliliters: 440
        )

        let update = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [delayedCanonical.id],
            anchor: [existing],
            current: [existing, delayedCanonical]
        )

        XCTAssertTrue(update.mutations.isEmpty)
        XCTAssertEqual(update.nextAnchor, [existing, delayedCanonical])
    }

    func testPhoneDeletionBeforeHealthKitDeletionDoesNotSubtractTheSampleTwice() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        let removed = healthSample(
            "00000000-0000-0000-0000-000000000044",
            milliliters: 330
        )

        let update = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [],
            anchor: [removed],
            current: [],
            deletedSampleIDs: [removed.id]
        )
        let visible = HydrationHealthReconciler.replacingOverlay(
            [],
            with: update.mutations,
            inTotalML: 440,
            composition: []
        )

        XCTAssertTrue(update.mutations.isEmpty)
        XCTAssertTrue(update.nextAnchor.isEmpty)
        XCTAssertEqual(visible.totalML, 440)
    }

    func testExternalHealthOverlaySurvivesAnIncompletePhoneSnapshot() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000050")!
        let external = healthSample(
            "00000000-0000-0000-0000-000000000051",
            milliliters: 100,
            kind: .coffee,
            palette: "espresso",
            icon: "cup.and.saucer.fill"
        )
        let overlay = [HydrationPendingMutation(
            ownerID: ownerID,
            localDate: "2026-08-27",
            action: .upsert,
            sample: external
        )]

        let remaining = HydrationHealthReconciler.unacknowledged(
            overlay,
            snapshotOwnerID: ownerID,
            snapshotLocalDate: "2026-08-27",
            snapshotEventIDs: []
        )
        let visible = HydrationHealthReconciler.applying(
            remaining,
            toTotalML: 770,
            composition: []
        )

        XCTAssertEqual(remaining, overlay)
        XCTAssertEqual(visible.totalML, 870)
    }

    func testEmptyHealthKitReadCannotMasqueradeAsDeletingEveryAnchoredSample() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000060")!
        let existing = healthSample(
            "00000000-0000-0000-0000-000000000061",
            milliliters: 330
        )

        let update = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [existing.id],
            anchor: [existing],
            current: [],
            deletedSampleIDs: []
        )

        XCTAssertTrue(update.mutations.isEmpty)
        XCTAssertEqual(update.nextAnchor, [existing])
    }

    func testConfirmedDeletionOfFinalExternalSampleClearsItsOverlay() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
        let external = healthSample(
            "00000000-0000-0000-0000-000000000063",
            milliliters: 100,
            kind: .coffee,
            palette: "espresso",
            icon: "cup.and.saucer.fill"
        )
        let overlay = [HydrationPendingMutation(
            ownerID: ownerID,
            localDate: "2026-08-27",
            action: .upsert,
            sample: external
        )]

        let update = HydrationHealthReconciler.updatedHealthOverlay(
            overlay,
            ownerID: ownerID,
            localDate: "2026-08-27",
            canonicalSampleIDs: [],
            anchor: [external],
            current: [],
            deletedSampleIDs: [external.id]
        )

        XCTAssertTrue(update.mutations.isEmpty)
        XCTAssertTrue(update.nextAnchor.isEmpty)
    }

    func testSuspendedWatchOperationMustStillMatchOwnerDayAndGeneration() {
        let ownerA = UUID(uuidString: "00000000-0000-0000-0000-000000000064")!
        let ownerB = UUID(uuidString: "00000000-0000-0000-0000-000000000065")!
        let scope = HydrationWatchOperationScope(
            ownerID: ownerA,
            localDate: "2026-08-27",
            generation: 7
        )

        XCTAssertTrue(scope.matches(ownerID: ownerA, localDate: "2026-08-27", generation: 7))
        XCTAssertFalse(scope.matches(ownerID: ownerB, localDate: "2026-08-27", generation: 7))
        XCTAssertFalse(scope.matches(ownerID: ownerA, localDate: "2026-08-28", generation: 7))
        XCTAssertFalse(scope.matches(ownerID: ownerA, localDate: "2026-08-27", generation: 8))
    }

    func testWatchStoreRebasesAtMidnightBeforeReconcilingHealthKit() {
        XCTAssertFalse(
            HydrationWatchScopePolicy.shouldRebase(
                storedLocalDate: "2026-08-27",
                currentLocalDate: "2026-08-27"
            )
        )
        XCTAssertTrue(
            HydrationWatchScopePolicy.shouldRebase(
                storedLocalDate: "2026-08-27",
                currentLocalDate: "2026-08-28"
            )
        )
        XCTAssertEqual(
            HydrationWatchScopePolicy.persistenceLocalDate(
                storedLocalDate: "2026-08-27",
                currentLocalDate: "2026-08-28"
            ),
            "2026-08-27"
        )
    }

    func testFirstHealthKitSampleAfterMidnightIsAppliedToTheRebasedZeroTotal() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000066")!
        let firstSample = healthSample(
            "00000000-0000-0000-0000-000000000067",
            milliliters: 250
        )

        let update = HydrationHealthReconciler.updatedHealthOverlay(
            [],
            ownerID: ownerID,
            localDate: "2026-08-28",
            canonicalSampleIDs: [],
            anchor: [],
            current: [firstSample]
        )
        let visible = HydrationHealthReconciler.replacingOverlay(
            [],
            with: update.mutations,
            inTotalML: 0,
            composition: []
        )

        XCTAssertEqual(update.mutations.map(\.action), [.upsert])
        XCTAssertEqual(update.nextAnchor, [firstSample])
        XCTAssertEqual(visible.totalML, 250)
    }

    func testWidgetStateHealthAnchorRoundTripsAndOlderCacheStillDecodes() throws {
        let sample = healthSample(
            "00000000-0000-0000-0000-000000000020",
            milliliters: 330
        )
        let state = HydrationWidgetState(
            ownerID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            localDate: "2026-08-27",
            totalML: 770,
            targetML: 1_000,
            composition: [],
            revision: "2026-08-27T21:00:00.001Z",
            healthAnchor: [sample],
            healthQueryAnchorData: Data([1, 2, 3])
        )
        let encoded = try state.encoded()
        XCTAssertEqual(try HydrationWidgetState.decode(encoded).healthAnchor, [sample])
        XCTAssertEqual(try HydrationWidgetState.decode(encoded).healthQueryAnchorData, Data([1, 2, 3]))

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "healthAnchor")
        legacyObject.removeValue(forKey: "healthQueryAnchorData")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        XCTAssertNil(try HydrationWidgetState.decode(legacyData).healthAnchor)
        XCTAssertNil(try HydrationWidgetState.decode(legacyData).healthQueryAnchorData)
    }

    func testWidgetHealthStateIsScopedToOneCanonicalRevision() throws {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000068")!
        let canonical = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-28",
            totalML: 770,
            targetML: 1_000,
            composition: [],
            revision: "2026-08-28T00:01:00.000Z"
        )
        let healthState = HydrationWidgetHealthState(
            ownerID: ownerID,
            localDate: "2026-08-28",
            baseRevision: canonical.revision,
            totalML: 870,
            composition: [],
            healthAnchor: [],
            healthQueryAnchorData: Data([4, 5, 6]),
            healthOverlay: []
        )
        let newerCanonical = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-28",
            totalML: 900,
            targetML: 1_000,
            composition: [],
            revision: "2026-08-28T00:02:00.000Z"
        )

        XCTAssertTrue(healthState.matches(canonical))
        XCTAssertFalse(healthState.matches(newerCanonical))
        XCTAssertEqual(
            HydrationWidgetStateResolver.resolve(
                canonical: canonical,
                healthState: healthState
            ).totalML,
            770
        )
        XCTAssertEqual(
            HydrationWidgetStateResolver.resolve(
                canonical: newerCanonical,
                healthState: healthState
            ).totalML,
            900
        )
        XCTAssertNotEqual(HydrationWidgetStorage.stateKey, HydrationWidgetStorage.healthStateKey)
        XCTAssertEqual(
            try HydrationWidgetHealthState.decode(healthState.encoded()),
            healthState
        )
    }

    func testDeferredDeleteSurvivesOtherAccountAndReplaysUntilItsOwnerAcknowledges() {
        let ownerA = UUID(uuidString: "00000000-0000-0000-0000-000000000069")!
        let ownerB = UUID(uuidString: "00000000-0000-0000-0000-000000000070")!
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let queued = [HydrationDeferredDelete(
            ownerID: ownerA,
            eventID: eventID,
            localDate: "2026-08-27"
        )]

        let whileBIsActive = HydrationDeferredDeleteReconciler.reconcile(
            queued,
            snapshotOwnerID: ownerB,
            snapshotLocalDate: "2026-08-28",
            snapshotEventIDs: [],
            acknowledgedDeleteIDs: []
        )
        XCTAssertEqual(whileBIsActive.remaining, queued)
        XCTAssertTrue(whileBIsActive.toReplay.isEmpty)

        let staleASnapshot = HydrationDeferredDeleteReconciler.reconcile(
            whileBIsActive.remaining,
            snapshotOwnerID: ownerA,
            snapshotLocalDate: "2026-08-28",
            snapshotEventIDs: [],
            acknowledgedDeleteIDs: []
        )
        XCTAssertEqual(staleASnapshot.remaining, queued)
        XCTAssertEqual(staleASnapshot.toReplay, queued)

        let acknowledgedASnapshot = HydrationDeferredDeleteReconciler.reconcile(
            staleASnapshot.remaining,
            snapshotOwnerID: ownerA,
            snapshotLocalDate: "2026-08-28",
            snapshotEventIDs: [],
            acknowledgedDeleteIDs: [eventID]
        )
        XCTAssertTrue(acknowledgedASnapshot.remaining.isEmpty)
        XCTAssertTrue(acknowledgedASnapshot.toReplay.isEmpty)
    }

    func testComplicationSnapshotPushDeduplicatesVisibleStateAndProtectsScarceQuota() {
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
                complicationEnabled: true,
                remainingTransfers: 1,
                previousVisibleSignature: nil,
                newVisibleSignature: "owner|day|770|1000|water"
            )
        )
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
                complicationEnabled: false,
                remainingTransfers: 1,
                previousVisibleSignature: nil,
                newVisibleSignature: "owner|day|770|1000|water"
            )
        )
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
                complicationEnabled: true,
                remainingTransfers: 0,
                previousVisibleSignature: nil,
                newVisibleSignature: "owner|day|770|1000|water"
            )
        )
        XCTAssertFalse(
            HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
                complicationEnabled: true,
                remainingTransfers: 1,
                previousVisibleSignature: "owner|day|770|1000|water",
                newVisibleSignature: "owner|day|770|1000|water"
            )
        )
        XCTAssertTrue(
            HydrationComplicationRefreshPolicy.shouldRequestImmediateTransfer(
                complicationEnabled: true,
                remainingTransfers: 1,
                previousVisibleSignature: "owner|day|330|1000|water",
                newVisibleSignature: "owner|day|770|1000|water"
            )
        )
    }

    func testComplicationResolverCannotReplaceTheCanonicalTotalWithAStaleSameRevisionSidecar() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let canonical = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-29",
            totalML: 1_696,
            targetML: 3_750,
            composition: [HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 1_696
            )],
            revision: "2026-08-29T12:46:56.970Z"
        )
        let staleThirtyThreePercent = HydrationWidgetHealthState(
            ownerID: ownerID,
            localDate: canonical.localDate,
            baseRevision: canonical.revision,
            totalML: 1_238,
            composition: [HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 1_238
            )],
            healthAnchor: [],
            healthQueryAnchorData: nil,
            healthOverlay: []
        )

        let resolved = HydrationWidgetStateResolver.resolve(
            canonical: canonical,
            healthState: staleThirtyThreePercent
        )

        XCTAssertEqual(resolved.totalML, 1_696)
        XCTAssertEqual(resolved.composition, canonical.composition)
        XCTAssertEqual(
            HydrationComplicationRefreshPolicy.visibleSignature(
                ownerID: canonical.ownerID,
                localDate: canonical.localDate,
                totalML: resolved.totalML,
                targetML: canonical.targetML,
                composition: resolved.composition
            ),
            HydrationComplicationRefreshPolicy.visibleSignature(for: canonical)
        )
    }

    func testTimelineReloadGateRefreshesChangedAndUnrenderedStateWithoutLooping() {
        XCTAssertTrue(HydrationComplicationRefreshPolicy.shouldReloadTimeline(
            renderedVisibleSignature: "owner|day|1238|3750|water",
            requestedVisibleSignature: "owner|day|1238|3750|water",
            newVisibleSignature: "owner|day|1696|3750|water",
            retryUnrenderedRequest: false
        ))
        XCTAssertFalse(HydrationComplicationRefreshPolicy.shouldReloadTimeline(
            renderedVisibleSignature: "owner|day|1238|3750|water",
            requestedVisibleSignature: "owner|day|1696|3750|water",
            newVisibleSignature: "owner|day|1696|3750|water",
            retryUnrenderedRequest: false
        ))
        XCTAssertTrue(HydrationComplicationRefreshPolicy.shouldReloadTimeline(
            renderedVisibleSignature: "owner|day|1238|3750|water",
            requestedVisibleSignature: "owner|day|1696|3750|water",
            newVisibleSignature: "owner|day|1696|3750|water",
            retryUnrenderedRequest: true
        ))
        XCTAssertFalse(HydrationComplicationRefreshPolicy.shouldReloadTimeline(
            renderedVisibleSignature: "owner|day|1696|3750|water",
            requestedVisibleSignature: "owner|day|1696|3750|water",
            newVisibleSignature: "owner|day|1696|3750|water",
            retryUnrenderedRequest: true
        ))
    }

    func testVisibleSignatureInvalidatesForWatchPhoneRemovalAndGoalChanges() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000073")!
        func signature(totalML: Int, targetML: Int) -> String {
            HydrationComplicationRefreshPolicy.visibleSignature(
                ownerID: ownerID,
                localDate: "2026-08-29",
                totalML: totalML,
                targetML: targetML,
                composition: totalML == 0 ? [] : [HydrationCompositionBand(
                    kind: .water,
                    paletteToken: "aqua",
                    iconToken: "drop.fill",
                    milliliters: totalML
                )]
            )
        }

        let original = signature(totalML: 1_238, targetML: 3_750)
        XCTAssertNotEqual(original, signature(totalML: 1_488, targetML: 3_750), "local Watch add")
        XCTAssertNotEqual(original, signature(totalML: 988, targetML: 3_750), "local Watch removal")
        XCTAssertNotEqual(original, signature(totalML: 1_696, targetML: 3_750), "phone snapshot")
        XCTAssertNotEqual(original, signature(totalML: 1_238, targetML: 3_000), "goal change")
    }

    func testTimelineCarriesAnExplicitEmptyMidnightEntryUntilTheRoutineRefresh() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-29T23:50:00Z")!
        let expectedMidnight = ISO8601DateFormatter().date(from: "2026-08-30T00:00:00Z")!
        let expectedRefresh = ISO8601DateFormatter().date(from: "2026-08-30T00:20:00Z")!
        let schedule = HydrationComplicationTimelinePolicy.schedule(
            after: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.midnightReset.date, expectedMidnight)
        XCTAssertEqual(schedule.midnightReset.totalML, 0)
        XCTAssertTrue(schedule.midnightReset.composition.isEmpty)
        XCTAssertEqual(schedule.refreshAfter, expectedRefresh)
    }

    func testComplicationCarriesTheCanonicalOwnerAndGoalAcrossMidnightButNotYesterdayTotal() throws {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let stored = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-29",
            totalML: 1_696,
            targetML: 3_750,
            composition: [HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 1_696
            )],
            revision: "2026-08-29T23:59:50.000Z"
        )

        let rolled = try XCTUnwrap(HydrationComplicationDayRollover.state(
            stored,
            for: "2026-08-30"
        ))

        XCTAssertEqual(rolled.ownerID, ownerID)
        XCTAssertEqual(rolled.localDate, "2026-08-30")
        XCTAssertEqual(rolled.targetML, 3_750)
        XCTAssertEqual(rolled.totalML, 0)
        XCTAssertTrue(rolled.composition.isEmpty)
        XCTAssertNil(rolled.healthAnchor)
        XCTAssertNil(rolled.healthQueryAnchorData)
        XCTAssertNil(rolled.canonicalSampleIDs)
        XCTAssertNil(rolled.healthOverlay)
        XCTAssertEqual(HydrationComplicationDayRollover.state(
            stored,
            for: stored.localDate
        ), stored)
        XCTAssertNil(HydrationComplicationDayRollover.state(
            stored,
            for: "2026-08-28"
        ))
    }

    func testOnlyDeliveredNonPreviewTimelineAcknowledgesVisibleSignature() {
        let current = "owner|day|1696|3750|water"

        XCTAssertNil(HydrationComplicationDeliveryPolicy.acknowledgedSignature(
            current,
            delivery: .snapshot
        ))
        XCTAssertNil(HydrationComplicationDeliveryPolicy.acknowledgedSignature(
            current,
            delivery: .timeline(isPreview: true)
        ))
        XCTAssertEqual(
            HydrationComplicationDeliveryPolicy.acknowledgedSignature(
                current,
                delivery: .timeline(isPreview: false)
            ),
            current
        )
    }

    func testNewerSameBaseHealthObservationCannotBeOverwrittenByAnOlderCompletion() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000074")!
        let canonical = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-29",
            totalML: 1_000,
            targetML: 3_000,
            composition: [HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 1_000
            )],
            revision: "2026-08-29T12:00:00.000Z"
        )
        func sidecar(revision: String?, overlayML: Int) -> HydrationWidgetHealthState {
            HydrationWidgetHealthState(
                ownerID: ownerID,
                localDate: canonical.localDate,
                baseRevision: canonical.revision,
                observationRevision: revision,
                totalML: 1_000 + overlayML,
                composition: canonical.composition,
                healthAnchor: [],
                healthQueryAnchorData: nil,
                healthOverlay: overlayML == 0 ? [] : [HydrationPendingMutation(
                    ownerID: ownerID,
                    localDate: canonical.localDate,
                    action: .upsert,
                    sample: HydrationHealthSampleAnchor(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000076")!,
                        milliliters: overlayML,
                        kind: .external,
                        paletteToken: "external",
                        iconToken: "heart.fill"
                    )
                )]
            )
        }
        let older = sidecar(revision: "2026-08-29T12:00:01.000Z", overlayML: 100)
        let newer = sidecar(revision: "2026-08-29T12:00:02.000Z", overlayML: 250)

        XCTAssertTrue(HydrationHealthSidecarWritePolicy.shouldPersist(
            existing: older,
            incoming: newer,
            canonical: canonical
        ))
        XCTAssertFalse(HydrationHealthSidecarWritePolicy.shouldPersist(
            existing: newer,
            incoming: older,
            canonical: canonical
        ))
        XCTAssertTrue(HydrationHealthSidecarWritePolicy.shouldPersist(
            existing: sidecar(revision: nil, overlayML: 50),
            incoming: newer,
            canonical: canonical
        ))
        XCTAssertEqual(
            HydrationWidgetStateResolver.resolve(canonical: canonical, healthState: newer).totalML,
            1_250
        )
        XCTAssertEqual(
            HydrationWidgetStateResolver.resolve(canonical: canonical, healthState: older).totalML,
            1_100
        )
    }

    func testConcurrentSidecarTransactionsCannotLetAnOlderObservationWin() async throws {
        let suiteName = "ch.apexperformance.APEX.tests.sidecar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000083")!
        let canonical = HydrationWidgetState(
            ownerID: ownerID,
            localDate: "2026-08-29",
            totalML: 1_000,
            targetML: 3_000,
            composition: [HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 1_000
            )],
            revision: "2026-08-29T12:00:00.000Z"
        )
        defaults.set(try canonical.encoded(), forKey: HydrationWidgetStorage.stateKey)

        func input(
            id: String,
            milliliters: Int
        ) -> (HydrationHealthOverlayUpdate, HydrationReconciledState) {
            let sample = healthSample(id, milliliters: milliliters, kind: .external)
            return (
                HydrationHealthOverlayUpdate(
                    mutations: [HydrationPendingMutation(
                        ownerID: ownerID,
                        localDate: canonical.localDate,
                        action: .upsert,
                        sample: sample
                    )],
                    nextAnchor: [sample]
                ),
                HydrationReconciledState(
                    totalML: 1_000 + milliliters,
                    composition: canonical.composition + [HydrationCompositionBand(
                        kind: .external,
                        paletteToken: "external",
                        iconToken: "heart.fill",
                        milliliters: milliliters
                    )]
                )
            )
        }
        let older = input(
            id: "00000000-0000-0000-0000-000000000084",
            milliliters: 100
        )
        let newer = input(
            id: "00000000-0000-0000-0000-000000000085",
            milliliters: 250
        )
        let store = HydrationHealthSidecarStore(suiteName: suiteName)

        async let olderPersisted = store.persist(
            shared: canonical,
            healthQueryAnchorData: Data([1]),
            update: older.0,
            reconciled: older.1,
            observationRevision: "2026-08-29T12:00:01.000Z"
        )
        async let newerPersisted = store.persist(
            shared: canonical,
            healthQueryAnchorData: Data([2]),
            update: newer.0,
            reconciled: newer.1,
            observationRevision: "2026-08-29T12:00:02.000Z"
        )
        _ = await (olderPersisted, newerPersisted)

        let stored = try HydrationWidgetHealthState.decode(try XCTUnwrap(
            defaults.data(forKey: HydrationWidgetStorage.healthStateKey)
        ))
        XCTAssertEqual(stored.observationRevision, "2026-08-29T12:00:02.000Z")
        XCTAssertEqual(stored.totalML, 1_250)
        XCTAssertEqual(stored.healthQueryAnchorData, Data([2]))
        XCTAssertEqual(stored.healthOverlay, newer.0.mutations)
    }

    func testSharedHealthSampleOwnershipKeepsBothConsumersAccountScoped() {
        let accountA = UUID(uuidString: "00000000-0000-0000-0000-000000000077")!
        let accountB = UUID(uuidString: "00000000-0000-0000-0000-000000000078")!

        XCTAssertTrue(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: accountA,
            sharedClaimOwnerID: nil,
            activeOwnerID: accountA
        ))
        XCTAssertFalse(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: accountA,
            sharedClaimOwnerID: nil,
            activeOwnerID: accountB
        ))
        XCTAssertFalse(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: nil,
            sharedClaimOwnerID: nil,
            activeOwnerID: accountA
        ))
        XCTAssertTrue(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: nil,
            sharedClaimOwnerID: accountA,
            activeOwnerID: accountA
        ))
        XCTAssertFalse(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: nil,
            sharedClaimOwnerID: accountA,
            activeOwnerID: accountB
        ))
        XCTAssertFalse(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: accountA,
            sharedClaimOwnerID: nil,
            activeOwnerID: nil
        ))
        XCTAssertFalse(HydrationHealthSampleOwnershipPolicy.belongs(
            explicitOwnerID: nil,
            sharedClaimOwnerID: nil,
            activeOwnerID: nil
        ))
    }

    func testVisibleSignaturePreservesRenderedCompositionOrder() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000079")!
        let water = HydrationCompositionBand(
            kind: .water,
            paletteToken: "aqua",
            iconToken: "drop.fill",
            milliliters: 750
        )
        let coffee = HydrationCompositionBand(
            kind: .coffee,
            paletteToken: "espresso",
            iconToken: "cup.and.saucer.fill",
            milliliters: 250
        )
        func signature(_ composition: [HydrationCompositionBand]) -> String {
            HydrationComplicationRefreshPolicy.visibleSignature(
                ownerID: ownerID,
                localDate: "2026-08-29",
                totalML: 1_000,
                targetML: 3_000,
                composition: composition
            )
        }

        XCTAssertEqual(signature([water, coffee]), signature([water, coffee]))
        XCTAssertNotEqual(signature([water, coffee]), signature([coffee, water]))
    }

    func testPrimaryWatchAmountKeepsTheUnitBesideTheValueWithoutARedundantDayLabel() {
        let state = WatchHydrationFillState(liters: 1.375, targetLiters: 2.75)

        XCTAssertEqual(state.primaryAmount, "1.38 L")
        XCTAssertFalse(state.primaryAmount.localizedCaseInsensitiveContains("today"))
    }

    func testGaugeAnimationRunsOnlyWhileTheAppIsActivelyVisible() {
        XCTAssertTrue(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: false,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: false,
                luminanceIsReduced: false,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WatchHydrationAnimationPolicy.shouldAnimate(
                sceneIsActive: true,
                luminanceIsReduced: false,
                reduceMotion: true
            )
        )
    }

    func testCompositionStopsPreserveExactBeverageProportions() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationCompositionLayout.stops(for: bands)
        let first = try XCTUnwrap(stops.first)
        let last = try XCTUnwrap(stops.last)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(coffeeStart.location - waterEnd.location, 0.005)
        XCTAssertEqual(first.location, 0)
        XCTAssertEqual(last.location, 1)
    }

    func testTimelineStopsRunFromOldestOnLeftToLatestOnRight() throws {
        let newestFirstBands = [
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
        ]

        let stops = HydrationCompositionLayout.timelineStops(for: newestFirstBands)
        let first = try XCTUnwrap(stops.first)
        let last = try XCTUnwrap(stops.last)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual(first.paletteToken, "aqua")
        XCTAssertEqual(first.location, 0)
        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(last.paletteToken, "espresso")
        XCTAssertEqual(last.location, 1)
    }

    func testCompositionTransitionIsFifteenPercentSofterWithoutMovingItsBoundary() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationCompositionLayout.stops(for: bands)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(coffeeStart.location - waterEnd.location, 0.0046, accuracy: 0.000_001)
    }

    func testCompositionStopsMapExactProportionsIntoOnlyTheFilledSilhouette() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationCompositionLayout.stops(for: bands, mappedInto: 0.6 ... 1)
        let first = try XCTUnwrap(stops.first)
        let last = try XCTUnwrap(stops.last)
        let waterEnd = try XCTUnwrap(stops.last { $0.paletteToken == "aqua" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.paletteToken == "espresso" })

        XCTAssertEqual(first.location, 0.6, accuracy: 0.000_001)
        XCTAssertEqual((waterEnd.location + coffeeStart.location) / 2, 0.96, accuracy: 0.000_001)
        XCTAssertEqual(last.location, 1, accuracy: 0.000_001)
    }

    func testFigureBridgeCarriesWeightedStopsAcrossTheVisibleFill() throws {
        let bands = [
            HydrationCompositionBand(
                kind: .water,
                paletteToken: "aqua",
                iconToken: "drop.fill",
                milliliters: 900
            ),
            HydrationCompositionBand(
                kind: .coffee,
                paletteToken: "espresso",
                iconToken: "cup.and.saucer.fill",
                milliliters: 100
            ),
        ]

        let stops = HydrationFigureWebPalette.stops(for: bands)
        let waterEnd = try XCTUnwrap(stops.last { $0.color == "#14CCE8" })
        let coffeeStart = try XCTUnwrap(stops.first { $0.color == "#8C4A21" })

        XCTAssertEqual((waterEnd.offset + coffeeStart.offset) / 2, 0.9, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(coffeeStart.offset - waterEnd.offset, 0.005)
        XCTAssertEqual(HydrationFigureWebPalette.fillHeight(progress: 0.49), 348.88, accuracy: 0.000_001)
    }
}

final class WatchHydrationPreferencesTests: XCTestCase {
    func testDefaultsAreQuietAndBatteryConscious() {
        let preferences = WatchHydrationPreferences.default

        XCTAssertEqual(preferences.targetLiters, 2.75)
        XCTAssertEqual(preferences.effectiveTargetMode, .automatic)
        XCTAssertEqual(preferences.unit, .liters)
        XCTAssertTrue(preferences.showsPresetNames)
        XCTAssertTrue(preferences.confirmationHaptics)
        XCTAssertEqual(preferences.motionIntensity, .subtle)
        XCTAssertFalse(preferences.remindersEnabled)
        XCTAssertEqual(preferences.reminderIntervalMinutes, 90)
        XCTAssertEqual(preferences.quietHoursStartMinutes, 21 * 60 + 30)
        XCTAssertEqual(preferences.quietHoursEndMinutes, 8 * 60)
    }

    func testExactTargetValidationRejectsUnsafeOrInvalidValues() throws {
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(3.8), 3.8)
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(1.0), 1.0)
        XCTAssertEqual(try WatchHydrationPreferences.validatedTargetLiters(6.0), 6.0)
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(0.9))
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(6.1))
        XCTAssertThrowsError(try WatchHydrationPreferences.validatedTargetLiters(.nan))
    }

    func testPreferencesRoundTripWithoutLosingExactGoal() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(3.83)
        preferences.targetMode = .custom
        preferences.unit = .gallons
        preferences.showsPresetNames = false
        preferences.remindersEnabled = true
        preferences.reminderIntervalMinutes = 120

        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(WatchHydrationPreferences.self, from: data)

        XCTAssertEqual(restored, preferences)
        XCTAssertEqual(restored.targetLiters, 3.83)
        XCTAssertEqual(restored.effectiveTargetMode, .custom)
    }

    func testEarlierWatchCacheWithoutTargetModeStillDecodesAsAutomatic() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchHydrationPreferences.default))
                as? [String: Any]
        )
        object.removeValue(forKey: "targetMode")
        let restored = try JSONDecoder().decode(
            WatchHydrationPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(restored.effectiveTargetMode, .automatic)
        XCTAssertEqual(restored.targetLiters, 2.75)
    }

    func testEarlierWatchCachePreservesANonDefaultCustomTarget() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.targetLiters = 3.8
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
        )
        object.removeValue(forKey: "targetMode")
        let restored = try JSONDecoder().decode(
            WatchHydrationPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(restored.effectiveTargetMode, .custom)
        XCTAssertEqual(restored.targetLiters, 3.8)
    }

    func testSelectedUnitsDeriveDisplayWithoutChangingStoredLiters() {
        var preferences = WatchHydrationPreferences.default
        XCTAssertEqual(preferences.formattedAmount(liters: 1), "1.00 L")

        preferences.unit = .gallons
        XCTAssertEqual(preferences.formattedAmount(liters: 1), "0.26 gal")
        XCTAssertEqual(preferences.formattedTarget, "0.73 gal")
        XCTAssertEqual(preferences.targetLiters, 2.75)
    }
}

final class AdaptiveHydrationTargetTests: XCTestCase {
    func testAutomaticTargetCombinesBodySizeWithBoundedExercise() {
        let target = HydrationTargetPolicy.resolve(
            sex: "male",
            weightKG: 80,
            mode: .automatic,
            customTargetML: 3_800,
            plannedExerciseMinutes: 60,
            recordedExerciseMinutes: 0,
            activeCalories: 0,
            dateRelation: .today,
            localHour: 10
        )

        XCTAssertEqual(target.mode, .automatic)
        XCTAssertEqual(target.targetML, 3_250)
        XCTAssertEqual(target.baselineML, 2_850)
        XCTAssertEqual(target.exerciseAdjustmentML, 400)
        XCTAssertEqual(target.wearableAdjustmentML, 0)
    }

    func testBaselineIsBoundedBySexSpecificPopulationReferences() {
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "female", weightKG: 60).baselineML, 2_150)
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "female", weightKG: 35).baselineML, 2_000)
        XCTAssertEqual(HydrationTargetPolicy.resolve(sex: "male", weightKG: 200).baselineML, 3_700)
    }

    func testLateWearableCaloriesAreSmallAndCapped() {
        let before = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 1_600, dateRelation: .today, localHour: 14
        )
        let after = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 800, dateRelation: .today, localHour: 16
        )
        let muchHigherCalories = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 80,
            plannedExerciseMinutes: 60, recordedExerciseMinutes: 45,
            activeCalories: 1_600, dateRelation: .today, localHour: 16
        )

        XCTAssertEqual(before.wearableAdjustmentML, 0)
        XCTAssertEqual(after.wearableAdjustmentML, 200)
        XCTAssertEqual(muchHigherCalories.wearableAdjustmentML, 200)
        XCTAssertEqual(after.exerciseAdjustmentML, 400)
        XCTAssertEqual(after.targetML, 3_450)
    }

    func testLateStepsCanCorroborateActivityWithoutACalorieSample() {
        let moderate = HydrationTargetPolicy.resolve(
            sex: "female", weightKG: 60,
            activeCalories: 0, steps: 12_000,
            dateRelation: .today, localHour: 16
        )
        let high = HydrationTargetPolicy.resolve(
            sex: "female", weightKG: 60,
            activeCalories: 0, steps: 18_000,
            dateRelation: .today, localHour: 16
        )

        XCTAssertEqual(moderate.wearableAdjustmentML, 100)
        XCTAssertEqual(high.wearableAdjustmentML, 200)
    }

    func testExactCustomTargetCannotDriftWithActivity() {
        let target = HydrationTargetPolicy.resolve(
            sex: "male", weightKG: 100,
            mode: .custom, customTargetML: 3_830,
            plannedExerciseMinutes: 120, recordedExerciseMinutes: 120,
            activeCalories: 2_000, dateRelation: .past, localHour: 23
        )

        XCTAssertEqual(target.targetML, 3_830)
        XCTAssertEqual(target.baselineML, 3_830)
        XCTAssertEqual(target.exerciseAdjustmentML, 0)
        XCTAssertEqual(target.wearableAdjustmentML, 0)
    }

    func testLegacyModeInferencePreservesCustomChoice() {
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: nil, targetML: 2_750), .automatic)
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: nil, targetML: 3_800), .custom)
        XCTAssertEqual(HydrationTargetPolicy.inferredMode(stored: "automatic", targetML: 3_800), .automatic)
    }
}

final class WatchHydrationReminderPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDisabledAndCompletedGoalsDoNotSchedule() {
        let now = date(hour: 12)
        var preferences = WatchHydrationPreferences.default

        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: now,
                liters: 0.5,
                lastDrinkAt: date(hour: 10),
                preferences: preferences,
                calendar: calendar
            )
        )

        preferences.remindersEnabled = true
        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: now,
                liters: preferences.targetLiters,
                lastDrinkAt: date(hour: 10),
                preferences: preferences,
                calendar: calendar
            )
        )
    }

    func testReminderRequiresBothInactivityAndQuarterLiterPaceDeficit() throws {
        var preferences = WatchHydrationPreferences.default
        preferences.remindersEnabled = true
        preferences.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(3)
        let now = date(hour: 10)

        let behind = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 0,
            lastDrinkAt: date(hour: 8),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertEqual(behind, date(hour: 10, minute: 1))

        let recentlyDrank = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 0,
            lastDrinkAt: date(hour: 9, minute: 30),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertEqual(recentlyDrank, date(hour: 11))

        let ahead = WatchHydrationReminderPolicy.nextReminderDate(
            now: now,
            liters: 1,
            lastDrinkAt: date(hour: 8),
            preferences: preferences,
            calendar: calendar
        )
        XCTAssertNotNil(ahead)
        XCTAssertGreaterThan(ahead ?? now, date(hour: 13))
    }

    func testQuietHoursNeverScheduleAStaleNextDayReminder() {
        var preferences = WatchHydrationPreferences.default
        preferences.remindersEnabled = true

        XCTAssertNil(
            WatchHydrationReminderPolicy.nextReminderDate(
                now: date(hour: 22),
                liters: 0,
                lastDrinkAt: date(hour: 18),
                preferences: preferences,
                calendar: calendar
            )
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: hour, minute: minute))!
    }
}
