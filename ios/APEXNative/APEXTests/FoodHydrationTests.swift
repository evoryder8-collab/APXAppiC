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
}
