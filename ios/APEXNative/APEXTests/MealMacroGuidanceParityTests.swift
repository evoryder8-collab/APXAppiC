/*
 * Golden parity for MealMacroGuidance against src/lib/mealMacroGuidance.ts,
 * across every macro, persona, goal and threshold boundary.
 */
import XCTest
@testable import APEX

private struct MacroFixture: Decodable {
    let cases: [MacroCase]
}

private struct MacroCase: Decodable {
    let macro: String
    let persona: String
    let goal: String
    let value: Double
    let target: Double
    let expected: Expected
}

private struct Expected: Decodable {
    let state: String
    let completion: Double
    let overBy: Double
    let upperGuide: Double
}

final class MealMacroGuidanceParityTests: XCTestCase {
    private static let fixture: MacroFixture = {
        guard let url = Bundle(for: MealMacroGuidanceParityTests.self)
            .url(forResource: "macro-guidance-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("macro-guidance-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(MacroFixture.self, from: data)
    }()

    func testEveryCaseMatchesTheWeb() {
        for scenario in Self.fixture.cases {
            guard let macro = MealMacroGuidance.Macro(rawValue: scenario.macro) else {
                return XCTFail("unknown macro \(scenario.macro)")
            }
            let status = MealMacroGuidance.status(
                value: scenario.value, target: scenario.target,
                macro: macro, persona: scenario.persona, goal: scenario.goal
            )
            let label = "\(scenario.persona)/\(scenario.goal)/\(scenario.macro) \(scenario.value) of \(scenario.target)"
            XCTAssertEqual(status.state.rawValue, scenario.expected.state, label)
            XCTAssertEqual(status.completion, scenario.expected.completion, accuracy: 0.0001, label)
            XCTAssertEqual(status.overBy, scenario.expected.overBy, accuracy: 0.0001, label)
            XCTAssertEqual(Double(status.upperGuide), scenario.expected.upperGuide, accuracy: 0.0001, label)
        }
    }

    /// A guide is a distribution hint, so the same meal reads differently
    /// depending on what the person is actually trying to do.
    func testTheSameMealReadsDifferentlyByGoal() {
        let recomp = MealMacroGuidance.status(
            value: 52, target: 40, macro: .carbs, persona: "constantine", goal: "recomp"
        )
        let bulk = MealMacroGuidance.status(
            value: 52, target: 40, macro: .carbs, persona: "june", goal: "bulk"
        )
        XCTAssertEqual(recomp.state, .high, "a tight recomp calls 52 g against a 40 g guide high")
        XCTAssertEqual(bulk.state, .above, "a deliberate bulk allows the same meal a wider range")
        XCTAssertGreaterThan(bulk.upperGuide, recomp.upperGuide)
    }

    /// Never over by a negative amount, and never divided by zero.
    func testDegenerateTargetsAreSafe() {
        let zero = MealMacroGuidance.status(value: 10, target: 0, macro: .fat, persona: "matthew", goal: "maintain")
        XCTAssertTrue(zero.completion.isFinite)
        XCTAssertGreaterThanOrEqual(zero.overBy, 0)
        let under = MealMacroGuidance.status(value: 0, target: 40, macro: .protein, persona: "matthew", goal: "maintain")
        XCTAssertEqual(under.overBy, 0)
        XCTAssertEqual(under.state, .below)
    }
}
