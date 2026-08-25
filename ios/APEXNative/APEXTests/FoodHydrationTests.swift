/*
 * The Swift hydration estimator must agree with src/lib/hydration.ts, and must
 * never invent water a food cannot physically hold.
 */
import XCTest
@testable import APEX

final class FoodHydrationTests: XCTestCase {
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
