import XCTest
@testable import APEX

/*
 * The custom builder has to agree with the web builder, otherwise the same
 * session reads as a different length depending on which device opened it.
 */
final class CustomWorkoutBuilderTests: XCTestCase {
    private func item(
        id: String = "test",
        category: String = "calisthenics",
        unit: String = "reps",
        names: [String: String] = [:],
        aliases: [String: [String]] = [:],
        muscles: [String] = ["chest"]
    ) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: id,
            name: "Push-Up",
            category: category,
            equipment: "Bodyweight",
            muscles: muscles,
            dayType: "push",
            sets: 3,
            reps: 12,
            rest: 90,
            unit: unit,
            perSide: false,
            names: names,
            aliases: aliases
        )
    }

    func testCatalogueShipsInsideTheBundle() {
        XCTAssertEqual(ExerciseCatalog.all.count, 96)
        XCTAssertEqual(ExerciseCatalog.categories.count, 8)
        XCTAssertEqual(ExerciseCatalog.categories.first?.id, "all")
    }

    func testEveryCataloguedCategoryIsSelectable() {
        let offered = Set(ExerciseCatalog.categories.map(\.id))
        for exercise in ExerciseCatalog.all {
            XCTAssertTrue(offered.contains(exercise.category), "\(exercise.id) sits in an unreachable category")
        }
    }

    func testCategoryFilterNarrowsTheResults() {
        let all = ExerciseCatalog.search("", category: "all", language: .english)
        let weights = ExerciseCatalog.search("", category: "weights", language: .english)
        XCTAssertEqual(all.count, ExerciseCatalog.all.count)
        XCTAssertLessThan(weights.count, all.count)
        XCTAssertTrue(weights.allSatisfy { $0.category == "weights" })
    }

    func testSearchFindsAMovementThroughAnAliasInAnotherLanguage() {
        let push = item(names: ["ro": "Flotări"], aliases: ["ro": ["flotari"]])
        XCTAssertTrue(push.matches("flotari", language: .english))
        XCTAssertTrue(push.matches("Flotări", language: .english))
        XCTAssertFalse(push.matches("deadlift", language: .english))
    }

    func testSearchIgnoresCaseAndDiacritics() {
        let push = item(names: ["ro": "Flotări"])
        XCTAssertTrue(push.matches("FLOTARI", language: .romanian))
        XCTAssertTrue(push.matches("push", language: .english))
    }

    func testEmptyQueryKeepsEverything() {
        XCTAssertTrue(item().matches("", language: .english))
    }

    func testRepBasedEstimateMatchesTheWebArithmetic() {
        // 3 sets x (12 reps x 3s + 90s rest) = 378s, rounds to 6, floors to 8.
        let picks = [CustomWorkoutBuilder.Pick(item: item(), sets: 3, reps: 12, rest: 90)]
        XCTAssertEqual(CustomWorkoutBuilder.estimatedMinutes(for: picks), 8)
    }

    func testShortRepsStillCostTwentySecondsOfWork() {
        // 10 sets x (max(20, 3 x 3) + 60) = 800s = 13 minutes.
        let picks = [CustomWorkoutBuilder.Pick(item: item(), sets: 10, reps: 3, rest: 60)]
        XCTAssertEqual(CustomWorkoutBuilder.estimatedMinutes(for: picks), 13)
    }

    func testTimedWorkCountsItsOwnUnits() {
        let seconds = [CustomWorkoutBuilder.Pick(item: item(unit: "seconds"), sets: 4, reps: 45, rest: 15)]
        XCTAssertEqual(CustomWorkoutBuilder.estimatedMinutes(for: seconds), 8)

        let minutes = [CustomWorkoutBuilder.Pick(item: item(unit: "minutes"), sets: 2, reps: 12, rest: 60)]
        XCTAssertEqual(CustomWorkoutBuilder.estimatedMinutes(for: minutes), 26)
    }

    func testEmptySelectionStillReadsAsTheMinimumSession() {
        XCTAssertEqual(CustomWorkoutBuilder.estimatedMinutes(for: []), 8)
    }

    func testLoadedWorkProgressesInPlateJumpsAndBodyweightDoesNot() {
        XCTAssertEqual(item(category: "weights").incrementKG, 2.5)
        XCTAssertEqual(item(category: "machine").incrementKG, 2.5)
        XCTAssertEqual(item(category: "calisthenics").incrementKG, 0)
        XCTAssertEqual(item(category: "cardio").incrementKG, 0)
    }

    func testWorkLabelFollowsTheUnit() {
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "reps"), "REPS")
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "seconds"), "SEC")
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "minutes"), "MIN")
    }
}
