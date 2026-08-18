import XCTest
@testable import APEX

/*
 * The predefined list is a shopping list, a suggestion when the decision is the
 * hard part, and something a person can rewrite. All three depend on it showing
 * the right amounts for the goal they are actually on.
 */
final class MealProtocolGuideTests: XCTestCase {
    func testDinnerReadsFromThePersonasProtocol() {
        let lines = MealProtocolGuide.lines(
            persona: "constantine", slot: "dinner", goal: "recomp",
            language: "en", overrides: nil
        )
        XCTAssertEqual(lines.first, "300 g sweet potato, cooked")
        XCTAssertTrue(lines.contains("150 g chicken breast, cooked"))
        XCTAssertEqual(lines.count, 5)
    }

    func testEachSlotHasItsOwnList() {
        func first(_ slot: String) -> String? {
            MealProtocolGuide.lines(
                persona: "constantine", slot: slot, goal: "recomp",
                language: "en", overrides: nil
            ).first
        }
        XCTAssertEqual(first("breakfast"), "70 g organic whole-grain oats")
        XCTAssertEqual(first("lunch"), "70 g dry bulgur")
        XCTAssertEqual(first("snack"), "1 banana or another saved fruit")
        XCTAssertEqual(first("dinner"), "300 g sweet potato, cooked")
    }

    func testPersonasGetTheirOwnProtocol() {
        let june = MealProtocolGuide.lines(
            persona: "june", slot: "dinner", goal: "recomp", language: "en", overrides: nil
        )
        XCTAssertTrue(june.contains("110 g salmon fillet, cooked"))
        XCTAssertFalse(june.contains("150 g chicken breast, cooked"))
    }

    func testStaplesScaleWithTheGoalAndOtherFoodsDoNot() {
        let recomp = MealProtocolGuide.lines(
            persona: "constantine", slot: "breakfast", goal: "recomp", language: "en", overrides: nil
        )
        let bulk = MealProtocolGuide.lines(
            persona: "constantine", slot: "breakfast", goal: "bulk", language: "en", overrides: nil
        )
        /* 70 g oats at 1.1x rounds to 75; a kiwi stays a kiwi. */
        XCTAssertEqual(recomp.first, "70 g organic whole-grain oats")
        XCTAssertEqual(bulk.first, "75 g organic whole-grain oats")
        XCTAssertTrue(bulk.contains("1 kiwi"))
        XCTAssertTrue(bulk.contains("100 g berries"))
    }

    func testAGoalThatScalesDownReducesTheStaples() {
        let maintain = MealProtocolGuide.goalAdjusted(
            "65 g oats", persona: "june", goal: "recomp"
        )
        /* 65 x 0.85 = 55.25, rounded to the nearest five. */
        XCTAssertEqual(maintain, "55 g oats")
    }

    func testARangeStaysARange() {
        let scaled = MealProtocolGuide.goalAdjusted(
            "10-15 g seed blend", persona: "constantine", goal: "bulk"
        )
        XCTAssertEqual(scaled, "10-15 g seed blend")
    }

    func testARewrittenListReplacesTheDefault() {
        let key = MealProtocolGuide.overrideKey(
            persona: "constantine", slot: "dinner", goal: "recomp", language: "en"
        )
        let overrides: [String: JSONValue] = [
            key: .array([.string("Whatever I actually eat"), .string("A second thing")])
        ]
        let lines = MealProtocolGuide.lines(
            persona: "constantine", slot: "dinner", goal: "recomp",
            language: "en", overrides: overrides
        )
        XCTAssertEqual(lines, ["Whatever I actually eat", "A second thing"])
    }

    func testAnEditForOneGoalDoesNotLeakIntoAnother() {
        let key = MealProtocolGuide.overrideKey(
            persona: "constantine", slot: "dinner", goal: "recomp", language: "en"
        )
        let overrides: [String: JSONValue] = [key: .array([.string("Recomp only")])]
        let bulk = MealProtocolGuide.lines(
            persona: "constantine", slot: "dinner", goal: "bulk",
            language: "en", overrides: overrides
        )
        /* The bulk list is untouched by the recomp edit, and still carries the
           bulk scaling: 300 g of sweet potato becomes 330. */
        XCTAssertEqual(bulk.first, "330 g sweet potato, cooked")
        XCTAssertFalse(bulk.contains("Recomp only"))
    }

    func testAWeighedLineOpensTheSearchAtThatAmount() {
        let query = MealProtocolGuide.foodQuery("300 g sweet potato, cooked")
        XCTAssertEqual(query.query, "sweet potato, cooked")
        XCTAssertEqual(query.quantity, 300)
        XCTAssertEqual(query.unit, "g")
    }

    func testARangedLineOpensAtItsMidpoint() {
        let query = MealProtocolGuide.foodQuery("10-15 g seed blend")
        XCTAssertEqual(query.quantity, 13)
        XCTAssertEqual(query.query, "seed blend")
    }

    func testAConditionalTailIsNotSearchedFor() {
        let query = MealProtocolGuide.foodQuery("150 g saved protein or whey providing 35-40 g protein")
        /* Searching for the whole sentence finds nothing; the food does. */
        XCTAssertEqual(query.query, "saved protein")
        XCTAssertEqual(query.quantity, 150)
    }

    func testACountedItemOpensAsOnePiece() {
        let query = MealProtocolGuide.foodQuery("1 banana or another saved fruit")
        XCTAssertEqual(query.query, "banana")
        XCTAssertEqual(query.quantity, 1)
        XCTAssertEqual(query.unit, "piece")
    }

    func testAnUnmeasuredNudgeOpensAtARoundAmount() {
        let query = MealProtocolGuide.foodQuery("Optional boiled egg")
        XCTAssertEqual(query.query, "boiled egg")
        XCTAssertEqual(query.quantity, 100)
        XCTAssertEqual(query.unit, "g")
    }

    func testAPersonaWithNoProtocolShowsNothingRatherThanGuessing() {
        XCTAssertTrue(
            MealProtocolGuide.lines(
                persona: "matthew", slot: "dinner", goal: "recomp",
                language: "en", overrides: nil
            ).isEmpty
        )
    }
}
