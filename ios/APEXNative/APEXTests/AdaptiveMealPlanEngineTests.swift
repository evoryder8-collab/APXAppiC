import XCTest
@testable import APEX

final class AdaptiveMealPlanEngineTests: XCTestCase {
    func testAllocationReturnsExactTargetTotals() {
        let plan = AdaptiveMealPlanEngine.build(
            meals: meals,
            targets: targets(calories: 2_137, protein: 154, fat: 49, carbs: 270),
            dayLabel: "Moderately active"
        )

        XCTAssertEqual(plan.reduce(0) { $0 + $1.kcal }, 2_137)
        XCTAssertEqual(plan.reduce(0) { $0 + $1.proteinG }, 154)
        XCTAssertEqual(plan.reduce(0) { $0 + $1.fatG }, 49)
        XCTAssertEqual(plan.reduce(0) { $0 + $1.carbsG }, 270)
    }

    func testChangingCaloriesKeepsPinnedProteinTotalAndMovesCarbs() {
        let low = AdaptiveMealPlanEngine.build(
            meals: meals,
            targets: targets(calories: 1_800, protein: 154, fat: 49, carbs: 186),
            dayLabel: "Sedentary"
        )
        let high = AdaptiveMealPlanEngine.build(
            meals: meals,
            targets: targets(calories: 2_500, protein: 154, fat: 49, carbs: 361),
            dayLabel: "Very active"
        )

        XCTAssertEqual(low.reduce(0) { $0 + $1.proteinG }, high.reduce(0) { $0 + $1.proteinG })
        XCTAssertGreaterThan(high.reduce(0) { $0 + $1.carbsG }, low.reduce(0) { $0 + $1.carbsG })
        XCTAssertTrue(low.first?.portionNote.contains("oats") == true)
    }

    private var meals: [Meal] {
        let user = UUID()
        return [
            Meal(id: UUID(), userID: user, time: "07:00", name: "Oat Jar", foods: "80 g oats + milk", kcal: 700, proteinG: 45, fatG: 15, carbsG: 95, fullDaysOnly: false, sortOrder: 1),
            Meal(id: UUID(), userID: user, time: "13:00", name: "Bulgur Snack", foods: "70 g dry bulgur + cottage cheese", kcal: 620, proteinG: 40, fatG: 10, carbsG: 86, fullDaysOnly: false, sortOrder: 2),
            Meal(id: UUID(), userID: user, time: "19:00", name: "Dinner", foods: "300 g sweet potato + chicken", kcal: 880, proteinG: 60, fatG: 28, carbsG: 104, fullDaysOnly: false, sortOrder: 3)
        ]
    }

    private func targets(calories: Int, protein: Int, fat: Int, carbs: Int) -> NutritionTargets {
        NutritionTargets(
            bmr: 1_600, tdee: 2_200, targetCalories: calories,
            proteinG: protein, fatG: fat, carbsG: carbs,
            pal: 1.5, level: .moderate, safetyFloorApplied: false
        )
    }
}
