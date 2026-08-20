import XCTest
@testable import APEX

final class MealSlotDefaultTests: XCTestCase {

    func testTheClockPicksTheObviousMeal() {
        XCTAssertEqual(MealSlotDefault.slot(hour: 8, adaptiveLateDinner: false), "breakfast")
        XCTAssertEqual(MealSlotDefault.slot(hour: 13, adaptiveLateDinner: false), "lunch")
        XCTAssertEqual(MealSlotDefault.slot(hour: 19, adaptiveLateDinner: false), "dinner")
    }

    func testLateEveningIsASnackUnlessTheUserSaysOtherwise() {
        // The setting promises exactly this, and until now nothing read it.
        XCTAssertEqual(MealSlotDefault.slot(hour: 22, adaptiveLateDinner: false), "snack")
        XCTAssertEqual(MealSlotDefault.slot(hour: 22, adaptiveLateDinner: true), "dinner")
    }

    func testTheAdaptiveRuleDoesNotReachBackIntoTheAfternoon() {
        // On is not a licence to call a 3pm entry dinner.
        XCTAssertEqual(MealSlotDefault.slot(hour: 15, adaptiveLateDinner: true), "lunch")
    }
}
