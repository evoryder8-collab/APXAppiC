/*
 * The Swift hydration estimator must agree with src/lib/hydration.ts, and must
 * never invent water a food cannot physically hold.
 */
import XCTest
@testable import APEX

final class FoodHydrationTests: XCTestCase {
    private let hydrationOwner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let hydrationOtherOwner = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

    private func hydrationEvent(
        id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        ownerID: UUID? = nil,
        key: String = "iphone:event-1",
        date: String = "2026-08-25",
        amountML: Int = 250,
        kind: HydrationKind = .water,
        palette: String = "aqua",
        source: HydrationSource = .iPhone,
        updatedAt: String = "2026-08-25T08:00:00Z"
    ) -> HydrationEvent {
        HydrationEvent(
            id: id,
            userID: ownerID ?? hydrationOwner,
            clientIdempotencyKey: key,
            localDate: date,
            occurredAt: "2026-08-25T08:00:00Z",
            amountML: amountML,
            kind: kind,
            paletteToken: palette,
            iconToken: "drop.fill",
            source: source,
            healthKitSampleID: nil,
            createdAt: "2026-08-25T08:00:00Z",
            updatedAt: updatedAt
        )
    }

    func testHydrationLedgerExcludesForeignAccountsAndDates() {
        let resolved = HydrationLedger.resolve(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [
                hydrationEvent(),
                hydrationEvent(ownerID: hydrationOtherOwner, key: "watch:foreign", amountML: 900),
                hydrationEvent(key: "iphone:tomorrow", date: "2026-08-26", amountML: 700),
            ],
            legacyDrinkLiters: 4
        )

        XCTAssertEqual(resolved.drinkML, 250)
        XCTAssertEqual(resolved.totalML, 250)
        XCTAssertEqual(resolved.composition.map(\.kind), [.water])
    }

    func testHydrationFactsReplaceLegacyAggregateWithoutFabricatingEvents() {
        let factual = HydrationLedger.resolve(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [hydrationEvent(amountML: 190, kind: .coffee, palette: "espresso")],
            legacyDrinkLiters: 2.5
        )
        XCTAssertEqual(factual.drinkML, 190)
        XCTAssertFalse(factual.usesLegacyAggregate)

        let legacy = HydrationLedger.resolve(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [],
            legacyDrinkLiters: 2.5
        )
        XCTAssertEqual(legacy.drinkML, 2_500)
        XCTAssertTrue(legacy.usesLegacyAggregate)
        XCTAssertEqual(legacy.composition.first?.kind, .legacy)
    }

    func testHydrationCompositionPreservesDrinkFoodAndExternalFacts() {
        let events = [
            hydrationEvent(),
            hydrationEvent(key: "watch:coffee", amountML: 190, kind: .coffee, palette: "espresso"),
            hydrationEvent(key: "food:2026-08-25", amountML: 420, kind: .food, palette: "food", source: .food),
            hydrationEvent(key: "healthkit:sample-1", amountML: 180, kind: .external, palette: "external", source: .healthKitExternal),
        ]
        let resolved = HydrationLedger.resolve(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: events,
            legacyDrinkLiters: 0
        )

        XCTAssertEqual(resolved.drinkML, 620)
        XCTAssertEqual(resolved.foodML, 420)
        XCTAssertEqual(resolved.totalML, 1_040)
        XCTAssertEqual(resolved.composition.map(\.kind), [.water, .coffee, .external, .food])
    }

    func testHydrationMergeIsIdempotentPerAccountAndKey() {
        let first = hydrationEvent(updatedAt: "2026-08-25T08:00:00Z")
        let revised = hydrationEvent(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            amountML: 300,
            updatedAt: "2026-08-25T08:01:00Z"
        )
        let foreign = hydrationEvent(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            ownerID: hydrationOtherOwner,
            amountML: 600,
            updatedAt: "2026-08-25T08:02:00Z"
        )
        let merged = HydrationLedger.merge(current: [first], incoming: [revised, foreign])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.userID == hydrationOwner }?.amountML, 300)
        XCTAssertEqual(merged.first { $0.userID == hydrationOtherOwner }?.amountML, 600)
    }

    func testHydrationDefaultPresetsHaveStableUsefulOrdering() {
        let presets = HydrationLedger.defaultPresetTemplates
        XCTAssertEqual(presets.map(\.kind), [.water, .water, .coffee, .tea, .juice, .shake])
        XCTAssertEqual(presets.map(\.sortOrder), Array(0...5))
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    }

    func testWatchCompanionSnapshotCannotCarryAnotherAccountsRows() throws {
        let ownPreset = HydrationPreset(
            id: UUID(), userID: hydrationOwner, name: "Coffee", amountML: 190,
            kind: .coffee, paletteToken: "espresso", iconToken: "cup.and.saucer.fill",
            sortOrder: 0, enabled: true,
            createdAt: "2026-08-25T08:00:00Z", updatedAt: "2026-08-25T08:00:00Z"
        )
        var foreignPreset = ownPreset
        foreignPreset = HydrationPreset(
            id: UUID(), userID: hydrationOtherOwner, name: "Foreign", amountML: 900,
            kind: .other, paletteToken: "violet", iconToken: "xmark",
            sortOrder: 0, enabled: true,
            createdAt: ownPreset.createdAt, updatedAt: ownPreset.updatedAt
        )
        let snapshot = HydrationCompanionSnapshot.make(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [hydrationEvent(), hydrationEvent(ownerID: hydrationOtherOwner, key: "foreign")],
            presets: [ownPreset, foreignPreset],
            preferences: .default,
            legacyDrinkLiters: 4,
            revision: "2026-08-25T08:00:00Z"
        )

        XCTAssertEqual(snapshot.events.map(\.userID), [hydrationOwner])
        XCTAssertEqual(snapshot.presets.map(\.userID), [hydrationOwner])
        XCTAssertEqual(snapshot.totalML, 250)
        XCTAssertEqual(try HydrationCompanionSnapshot.decode(snapshot.encoded()), snapshot)
    }

    func testWatchMutationMustBelongToTheActiveAccount() throws {
        let own = HydrationCompanionMutation.upserting(hydrationEvent())
        let foreign = HydrationCompanionMutation.upserting(
            hydrationEvent(ownerID: hydrationOtherOwner, key: "foreign")
        )
        XCTAssertTrue(own.belongs(to: hydrationOwner))
        XCTAssertFalse(foreign.belongs(to: hydrationOwner))
        XCTAssertEqual(try HydrationCompanionMutation.decode(own.encoded()), own)
    }

    func testLegacyHydrationMigrationNeverCollapsesTheExistingTotal() {
        let anchor = Date(timeIntervalSince1970: 1_777_000_000)
        let firstLedgerSync = HydrationLedger.legacyMigration(
            legacyDrinkLiters: 2,
            previouslyImportedLiters: nil,
            anchor: anchor
        )
        XCTAssertEqual(firstLedgerSync.baselineML, 2_000)
        XCTAssertEqual(firstLedgerSync.importCutoff, anchor)

        let priorHealthKitImport = HydrationLedger.legacyMigration(
            legacyDrinkLiters: 2,
            previouslyImportedLiters: 0.3,
            anchor: anchor
        )
        XCTAssertEqual(priorHealthKitImport.baselineML, 1_700)
        XCTAssertNil(priorHealthKitImport.importCutoff)
        XCTAssertEqual(priorHealthKitImport.baselineML + 300, 2_000)
    }

    func testLegacyAnchorImportsOnlySamplesRecordedAfterTheMigration() {
        let anchor = hydrationEvent(
            key: "legacy:2026-08-25",
            amountML: 2_000,
            kind: .legacy,
            palette: HydrationLedger.legacyAnchorPalette,
            source: .legacy
        )
        let anchorDate = ISO8601DateFormatter().date(from: anchor.occurredAt)!
        XCTAssertFalse(HydrationLedger.shouldImportHealthSample(
            occurredAt: anchorDate,
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [anchor]
        ))
        XCTAssertTrue(HydrationLedger.shouldImportHealthSample(
            occurredAt: anchorDate.addingTimeInterval(1),
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [anchor]
        ))
    }

    func testEmptyHealthKitReadNeverDeletesPersistedHydration() {
        let sampleID = UUID(uuidString: "00000000-0000-4000-8000-000000000099")!
        var imported = hydrationEvent(key: "healthkit:\(sampleID)", source: .healthKitExternal)
        imported.healthKitSampleID = sampleID

        XCTAssertTrue(HydrationLedger.eventsDeletedByHealthKit(
            events: [imported],
            ownerID: hydrationOwner,
            deletedSampleIDs: []
        ).isEmpty)
        XCTAssertEqual(HydrationLedger.eventsDeletedByHealthKit(
            events: [imported],
            ownerID: hydrationOwner,
            deletedSampleIDs: [sampleID]
        ).map(\.id), [imported.id])
    }

    func testDelayedWatchMutationCannotResurrectADeletedEntryOrPreferences() {
        let event = hydrationEvent(updatedAt: "2026-08-25T08:00:00Z")
        XCTAssertFalse(HydrationMutationOrdering.accepts(
            event: event,
            afterTombstoneRevision: "2026-08-25T08:01:00Z"
        ))
        XCTAssertTrue(HydrationMutationOrdering.accepts(
            event: event,
            afterTombstoneRevision: "2026-08-25T07:59:00Z"
        ))
        XCTAssertFalse(HydrationMutationOrdering.acceptsPreference(
            incomingRevision: "2026-08-25T08:00:00Z",
            currentRevision: "2026-08-25T08:01:00Z"
        ))
    }

    func testWatchWorkoutHandoffUsesTheClosestSensorPreset() {
        XCTAssertEqual(
            WatchWorkoutHandoff.resolve(
                dayType: "strength", name: "Upper hypertrophy", exerciseNames: ["Bench press"]
            ),
            .traditionalStrength
        )
        XCTAssertEqual(
            WatchWorkoutHandoff.resolve(
                dayType: "mobility", name: "Prehab", exerciseNames: ["Hip flow"]
            ),
            .yoga
        )
        XCTAssertEqual(
            WatchWorkoutHandoff.resolve(
                dayType: "conditioning", name: "Intervals", exerciseNames: ["Burpee"]
            ),
            .hiit
        )
        XCTAssertEqual(
            WatchWorkoutHandoff.resolve(
                dayType: "endurance", name: "Outdoor run", exerciseNames: ["Running"]
            ),
            .running
        )
    }

    func testComplicationStateUsesTheAccountTargetAndCompositionSnapshot() throws {
        let snapshot = HydrationCompanionSnapshot.make(
            ownerID: hydrationOwner,
            date: "2026-08-25",
            events: [
                hydrationEvent(amountML: 250),
                hydrationEvent(key: "watch:coffee", amountML: 190, kind: .coffee, palette: "espresso"),
            ],
            presets: [],
            preferences: WatchHydrationPreferences(
                targetLiters: 3.8,
                unit: .liters,
                showsPresetNames: true,
                confirmationHaptics: true,
                motionIntensity: .subtle,
                remindersEnabled: false,
                reminderIntervalMinutes: 90,
                quietHoursStartMinutes: 1_320,
                quietHoursEndMinutes: 420
            ),
            legacyDrinkLiters: 0,
            revision: "2026-08-25T08:00:00Z"
        )

        let state = HydrationWidgetState(snapshot: snapshot)
        XCTAssertEqual(state.localDate, "2026-08-25")
        XCTAssertEqual(state.totalML, 440)
        XCTAssertEqual(state.targetML, 3_800)
        XCTAssertEqual(state.composition.map(\.kind), [.water, .coffee])
        XCTAssertEqual(try HydrationWidgetState.decode(state.encoded()), state)
    }

    func testDenseAndLeanFoodsDeriveSensibleWater() {
        let oil = FoodHydration.waterByDifference(.init(protein100: 0, carbs100: 0, fat100: 100))
        XCTAssertEqual(oil, 0, "an oil holds no water")
        let cucumber = FoodHydration.waterByDifference(.init(protein100: 0.7, carbs100: 3.6, fat100: 0.1))
        XCTAssertNotNil(cucumber)
        XCTAssertGreaterThan(cucumber ?? 0, 90)
    }

    func testNamedWholeFoodsBeatDerivation() {
        XCTAssertEqual(FoodHydration.estimate(.init(name: "Cucumber, raw"))?.basis, .name)
        XCTAssertEqual(FoodHydration.estimate(.init(name: "Watermelon"))?.waterML100, 91.5)
    }

    /// The bug the web tests caught: a water-dense word inside another food.
    func testWaterInTheNameNeverOverridesTheComposition() {
        let tuna = FoodHydration.estimate(.init(
            name: "Tuna in water, drained",
            protein100: 23.6, carbs100: 0, fat100: 2.7, salt100: 0.9
        ))
        XCTAssertEqual(tuna?.basis, .difference, "the name must not win over the macros")
        XCTAssertLessThan(tuna?.waterML100 ?? 100, 80)
        let powder = FoodHydration.estimate(.init(
            name: "Milk protein powder", protein100: 80, carbs100: 6, fat100: 1.5
        ))
        XCTAssertEqual(powder?.basis, .difference)
        XCTAssertLessThan(powder?.waterML100 ?? 100, 15)
    }

    /// An oil measured per 100 ml is short of 100 g by density, not by water.
    func testFattyLiquidsAreNotTreatedAsHydrating() {
        let oliveOil = FoodHydration.waterByDifference(.init(
            nutritionBasis: "per_100ml", protein100: 0, carbs100: 0, fat100: 92
        ))
        XCTAssertEqual(oliveOil, 0)
        let cream = FoodHydration.waterByDifference(.init(
            nutritionBasis: "per_100ml", protein100: 2.3, carbs100: 3.1, fat100: 35
        ))
        XCTAssertNil(cream, "a fatty liquid cannot be resolved by difference alone")
    }

    func testMeasuredValueAlwaysWins() {
        let estimate = FoodHydration.estimate(
            .init(name: "Cucumber", protein100: 0.7, carbs100: 3.6, fat100: 0.1),
            measured: 95.2
        )
        XCTAssertEqual(estimate?.waterML100, 95.2)
        XCTAssertEqual(estimate?.basis, .measured)
    }

    func testOnlyMeasuredWaterIsPresentedAsExact() {
        XCTAssertFalse(FoodHydration.disclosure(for: "measured").isEstimated)
        XCTAssertEqual(FoodHydration.disclosure(for: "measured").prefix, "")

        for basis in ["provider_reported", "reference", "name", "difference", "legacy", nil] {
            let disclosure = FoodHydration.disclosure(for: basis)
            XCTAssertTrue(disclosure.isEstimated, "\(basis ?? "missing") must not look measured")
            XCTAssertEqual(disclosure.prefix, "≈")
        }
    }

    func testPortionWaterScalesWithTheAmountEaten() {
        XCTAssertEqual(FoodHydration.portionWater(90.4, equivalentAmount: 200), 180.8)
        XCTAssertNil(FoodHydration.portionWater(nil, equivalentAmount: 200))
        XCTAssertEqual(FoodHydration.portionWater(90.4, equivalentAmount: 0), 0)
    }

    func testFoodWaterIsReportedBesideDrinksNeverInsideThem() {
        let breakdown = FoodHydration.breakdown(drinkL: 1.5, foodML: 620)
        XCTAssertEqual(breakdown.drinkL, 1.5, "the drink figure must not absorb food water")
        XCTAssertEqual(breakdown.foodL, 0.62)
        XCTAssertEqual(breakdown.totalL, 2.12)
    }

    func testHealthKitFoodAndPhoneMirrorsNeverBecomeNewDrinkWater() {
        let samples = [
            HydrationReconciliation.Sample(liters: 0.42, source: .apexFood),
            HydrationReconciliation.Sample(liters: 0.25, source: .apexPhone),
            HydrationReconciliation.Sample(liters: 0.30, source: .apexWatch),
            HydrationReconciliation.Sample(liters: 0.18, source: .external),
        ]

        XCTAssertEqual(
            HydrationReconciliation.importableDrinkLiters(samples),
            0.48,
            accuracy: 0.0001,
            "food is displayed in the combined total and an iPhone mirror is already local"
        )
    }

    func testExternalEditsAndDeletesReconcileInBothDirections() {
        XCTAssertEqual(
            HydrationReconciliation.mergedDrinkLiters(
                localDrinkLiters: 1.8,
                previousImportableLiters: 0.5,
                currentImportableLiters: 0.8
            ),
            2.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HydrationReconciliation.mergedDrinkLiters(
                localDrinkLiters: 2.1,
                previousImportableLiters: 0.8,
                currentImportableLiters: 0.55
            ),
            1.85,
            accuracy: 0.0001,
            "removing a mistaken Watch or third-party entry must remove it from APEX"
        )
    }

    func testFoodSyncIdentifierIsStablePerAccountAndDay() {
        let account = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = HydrationReconciliation.foodSyncIdentifier(accountID: account, dateKey: "2026-08-24")
        XCTAssertEqual(first, HydrationReconciliation.foodSyncIdentifier(accountID: account, dateKey: "2026-08-24"))
        XCTAssertNotEqual(first, HydrationReconciliation.foodSyncIdentifier(accountID: account, dateKey: "2026-08-25"))
        XCTAssertNotEqual(
            first,
            HydrationReconciliation.foodSyncIdentifier(accountID: UUID(), dateKey: "2026-08-24"),
            "food samples must remain account-scoped on a shared device"
        )
    }

    func testWatchHistoryOnlyDeletesWaterAuthoredByThisWatchApp() {
        XCTAssertTrue(HydrationReconciliation.canDeleteOnWatch(sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"))
        XCTAssertFalse(HydrationReconciliation.canDeleteOnWatch(sourceBundleIdentifier: "ch.apexperformance.APEX"))
        XCTAssertFalse(HydrationReconciliation.canDeleteOnWatch(sourceBundleIdentifier: "com.thirdparty.water"))

        XCTAssertTrue(
            HydrationReconciliation.canDeleteOnWatch(
                sourceBundleIdentifier: "ch.apexperformance.APEX",
                syncIdentifier: "apex.hydration.watch.1234"
            ),
            "HealthKit can report a Watch-written sample under the parent APEX source"
        )
        XCTAssertFalse(
            HydrationReconciliation.canDeleteOnWatch(
                sourceBundleIdentifier: "ch.apexperformance.APEX",
                syncIdentifier: "apex.hydration.food.account.2026-08-25"
            )
        )
        XCTAssertFalse(
            HydrationReconciliation.canDeleteOnWatch(
                sourceBundleIdentifier: "com.thirdparty.water",
                syncIdentifier: "apex.hydration.watch.spoofed"
            )
        )
    }
}
