import XCTest
@testable import APEX

final class DailyNudgesTests: XCTestCase {

    func testTheSingleSittingCapScalesWithBodyweight() {
        // Roughly 0.4 g per kg is where muscle protein synthesis saturates in
        // one meal, so 40 g is a sensible catch-up at 100 kg and far too much
        // of a day's target at 45 kg.
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 50), 20)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 60), 25)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 70), 30)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 80), 30)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 100), 40)
        // And it stays sane at both extremes rather than following the maths off a cliff.
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 35), 20)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 200), 60)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 0), 30)
    }

    func testProteinNudgeIsStricterWhenLosingWeight() {
        // 80% of target: fine when maintaining, worth saying on a cut, because
        // that is where protein is holding muscle rather than adding it.
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 120, targetG: 150, goal: "maintain", bodyweightKG: 80))
        XCTAssertNotNil(DailyNudges.proteinShortfall(
            consumedG: 120, targetG: 150, goal: "recomp", bodyweightKG: 80))
    }

    func testNoNudgeWhenTheDayWentFine() {
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 155, targetG: 150, goal: "cut", bodyweightKG: 80))
        // A reminder that fires most days is one people switch off.
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 140, targetG: 150, goal: "cut", bodyweightKG: 80))
    }

    func testTheProteinNudgeCarriesACeilingNotJustAShortfall() {
        let nudge = DailyNudges.proteinShortfall(
            consumedG: 40, targetG: 160, goal: "fat_loss", bodyweightKG: 70)
        guard let nudge else { return XCTFail("no nudge for a 120 g shortfall") }
        XCTAssertEqual(nudge.shortfallG, 120)
        // The predictable response to "you are short" is to drink the whole
        // deficit at once, so the number to have tonight is capped.
        XCTAssertEqual(nudge.capG, 30)
        XCTAssertEqual(nudge.tonightG, 30)
        XCTAssertTrue(nudge.losingWeight)
    }

    func testASmallShortfallIsNotInflatedToTheCap() {
        // Tonight is the shortfall or the ceiling, whichever is smaller. Being
        // 25 g under should not turn into an instruction to eat the full 30.
        let small = DailyNudges.proteinShortfall(
            consumedG: 75, targetG: 100, goal: "cut", bodyweightKG: 70)
        XCTAssertEqual(small?.capG, 30)
        XCTAssertEqual(small?.tonightG, 25)
        // And a large shortfall is held down to the ceiling rather than repeated whole.
        let large = DailyNudges.proteinShortfall(
            consumedG: 88, targetG: 160, goal: "cut", bodyweightKG: 70)
        XCTAssertEqual(large?.shortfallG, 72)
        XCTAssertEqual(large?.tonightG, 30)
        XCTAssertNil(
            DailyNudges.proteinShortfall(consumedG: 150, targetG: 160, goal: "cut", bodyweightKG: 70),
            "10 g under is not worth a notification"
        )
    }

    func testCreatineNudgeOnlyForPeopleWhoActuallyTakeIt() {
        XCTAssertNil(DailyNudges.creatineMissed(loggedToday: false, inStack: false))
        XCTAssertNil(DailyNudges.creatineMissed(loggedToday: true, inStack: true))
        XCTAssertNotNil(DailyNudges.creatineMissed(loggedToday: false, inStack: true))
    }

    func testTheEveningIsLateEnoughToJudgeAndEarlyEnoughToAct() {
        XCTAssertGreaterThanOrEqual(DailyNudges.eveningHour, 19)
        XCTAssertLessThanOrEqual(DailyNudges.eveningHour, 20)
    }
}
