import XCTest
@testable import APEX

/*
 * The custom builder has to agree with the web builder, otherwise the same
 * session reads as a different length depending on which device opened it.
 */
@MainActor
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
            movementID: id,
            name: "Push-Up",
            category: category,
            categories: [category],
            equipment: "Bodyweight",
            muscles: muscles,
            dayType: "push",
            sets: 3,
            reps: 12,
            rest: 90,
            unit: unit,
            perSide: false,
            loadable: category == "weights" || category == "machine",
            incrementKG: category == "weights" || category == "machine" ? 2.5 : 0,
            names: names,
            aliases: aliases
        )
    }

    func testBuilderCapturesTheAccountLeaseBeforeSaveAndGatesDismissal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("APEX/Features/Training/CustomWorkoutBuilder.swift")
        )
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(compact.contains(
            "guardletoperation=session.accountOperationLease()else{return}Task{do{tryawaitsession.saveCustomWorkout("
        ))
        XCTAssertTrue(compact.contains("operation:operation"))
        XCTAssertTrue(compact.contains(
            "guardsession.accountOperationIsCurrent(operation)else{return}didSave=truedismiss()"
        ))
        XCTAssertTrue(compact.contains("catchisCancellationError{return}"))
        XCTAssertTrue(compact.contains(
            "catch{guardsession.accountOperationIsCurrent(operation)else{return}session.alertMessage=error.localizedDescription}"
        ))
    }

    func testCatalogueShipsEntireCanonicalLibraryInsideTheBundle() {
        XCTAssertEqual(ExerciseCatalog.all.count, 549)
        XCTAssertEqual(Set(ExerciseCatalog.all.map(\.id)).count, 549)
        XCTAssertEqual(
            Set(ExerciseCatalog.all.map(\.id)),
            Set(MovementTiming.cataloguedMovements.map(\.id))
        )
        XCTAssertEqual(ExerciseCatalog.categories.first?.id, "all")
    }

    func testSportAndTrainingFiltersAreActuallySelectable() {
        let offered = Set(ExerciseCatalog.categories.map(\.id))
        for category in [
            "hyrox", "crossfit", "olympic_weightlifting", "powerlifting",
            "kettlebell_sport", "strongman", "mobility",
        ] {
            XCTAssertTrue(offered.contains(category), "\(category) is missing from the workout studio")
        }

        let expectedCounts = [
            "hyrox": 8,
            "crossfit": 40,
            "olympic_weightlifting": 7,
            "powerlifting": 4,
            "kettlebell_sport": 6,
            "strongman": 9,
            "mobility": 54,
        ]
        for (category, count) in expectedCounts {
            XCTAssertEqual(
                ExerciseCatalog.search("", category: category, language: .english).count,
                count,
                category
            )
        }

        XCTAssertEqual(
            ExerciseCatalog.search("", category: "hyrox", language: .english).map(\.id),
            [
                "ski_erg", "sled_push", "sled_pull", "burpee_broad_jump",
                "row_erg", "kettlebell_farmers_walk", "sandbag_lunge", "wall_ball",
            ],
            "the HYROX shelf follows the official station order from SkiErg to Wall Balls"
        )
        XCTAssertEqual(
            Set(ExerciseCatalog.search("", category: "olympic_weightlifting", language: .english).map(\.id)),
            Set([
                "power_clean", "power_snatch", "clean_and_jerk",
                "snatch_grip_romanian_deadlift", "barbell_split_jerk",
                "barbell_push_jerk", "barbell_power_jerk",
            ])
        )
        XCTAssertEqual(
            Set(ExerciseCatalog.search("", category: "powerlifting", language: .english).map(\.id)),
            Set(["barbell_back_squat", "barbell_bench_press", "conventional_deadlift", "barbell_rack_pull"])
        )

        let mace = ExerciseCatalog.search("mace", category: "street", language: .english)
        XCTAssertEqual(mace.count, 8)
        XCTAssertTrue(mace.allSatisfy { $0.categories.contains("street") })
    }

    func testEveryCataloguedCategoryIsSelectable() {
        let offered = Set(ExerciseCatalog.categories.map(\.id))
        for exercise in ExerciseCatalog.all {
            XCTAssertFalse(exercise.categories.isEmpty, "\(exercise.id) has no browse category")
            for category in exercise.categories {
                XCTAssertTrue(offered.contains(category), "\(exercise.id) sits in unreachable category \(category)")
            }
        }
    }

    func testCategoryFilterNarrowsTheResults() {
        let all = ExerciseCatalog.search("", category: "all", language: .english)
        let weights = ExerciseCatalog.search("", category: "weights", language: .english)
        XCTAssertEqual(all.count, ExerciseCatalog.all.count)
        XCTAssertLessThan(weights.count, all.count)
        XCTAssertTrue(weights.allSatisfy { $0.categories.contains("weights") })
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
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "metres"), "DISTANCE M")
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "steps"), "STEPS")
        XCTAssertEqual(CustomWorkoutBuilder.workLabel(for: "rounds"), "ROUNDS")
    }

    func testSelectedMovementsCanBeReorderedWithoutRecreatingThem() {
        let picks = [
            CustomWorkoutBuilder.Pick(item: item(id: "first"), sets: 3, reps: 8, rest: 60),
            CustomWorkoutBuilder.Pick(item: item(id: "second"), sets: 3, reps: 10, rest: 75),
            CustomWorkoutBuilder.Pick(item: item(id: "third"), sets: 2, reps: 12, rest: 90),
        ]

        let moved = CustomWorkoutBuilder.moving(picks, at: 2, by: -1)

        XCTAssertEqual(moved.map(\.id), ["first", "third", "second"])
        XCTAssertEqual(moved.map(\.sets), [3, 2, 3])
        XCTAssertEqual(CustomWorkoutBuilder.moving(moved, at: 0, by: -1), moved)
    }

    func testAdjacentLinksResolveToOneRoundGroupWithStableMemberPositions() {
        let groupID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        var first = CustomWorkoutBuilder.Pick(item: item(id: "first"), sets: 3, reps: 8, rest: 60)
        var second = CustomWorkoutBuilder.Pick(item: item(id: "second"), sets: 3, reps: 10, rest: 75)
        let third = CustomWorkoutBuilder.Pick(item: item(id: "third"), sets: 2, reps: 12, rest: 90)
        first.linkedToNext = true
        second.linkedToNext = false

        let assignments = CustomWorkoutBuilder.workGroupAssignments(
            for: [first, second, third],
            makeID: { groupID }
        )

        XCTAssertEqual(assignments.map(\.workGroupID), [groupID, groupID, nil])
        XCTAssertEqual(assignments.map(\.workGroupPosition), [1, 2, nil])
        XCTAssertEqual(CustomWorkoutBuilder.groupLabels(for: [first, second, third]), ["A1", "A2", nil])
    }

    func testPersistedRowsKeepOrderPrescriptionAndReusableRoundMembership() {
        let userID = UUID()
        let dayID = UUID()
        let groupID = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!
        var first = CustomWorkoutBuilder.Pick(item: item(id: "first"), sets: 4, reps: 8, rest: 75)
        let carry = CustomWorkoutBuilder.Pick(
            item: item(id: "carry", unit: "metres"), sets: 3, reps: 40, rest: 90
        )
        first.linkedToNext = true

        let rows = CustomWorkoutBuilder.exerciseRows(
            userID: userID,
            programDayID: dayID,
            picks: [first, carry],
            makeGroupID: { groupID }
        )

        XCTAssertEqual(rows.map(\.movementID), ["first", "carry"])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1])
        XCTAssertEqual(rows.map(\.sets), [4, 3])
        XCTAssertEqual(rows.map(\.repMax), [8, 40])
        XCTAssertEqual(rows.map(\.repUnit), ["reps", "metres"])
        XCTAssertEqual(rows.map(\.restSeconds), [75, 90])
        XCTAssertEqual(rows.map(\.workGroupID), [groupID, groupID])
        XCTAssertEqual(rows.map(\.workGroupPosition), [1, 2])
    }

    func testGuidedDistanceTargetPersistsDistanceInsteadOfFabricatingDuration() {
        let carry = Exercise(
            id: UUID(), userID: UUID(), programDayID: UUID(),
            name: "Kettlebell Farmer's Walk", movementID: "kettlebell_farmers_walk",
            sets: 3, repMin: 40, repMax: 40, repUnit: "metres", perSide: false,
            restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 2.5, isLite: false,
            optional: false, sortOrder: 0
        )

        let input = GuidedWorkout.setInput(
            for: carry, setNumber: 1, measuredWork: 40,
            signedLoadKG: 24, skipped: false
        )

        XCTAssertFalse(GuidedWorkout.usesAutomaticCadence(for: carry))
        XCTAssertEqual(input.distanceMeters, 40)
        XCTAssertNil(input.durationSeconds)
        XCTAssertEqual(input.weightKG, 24)
    }

    func testGuidedRoundTargetPersistsAsTheStrengthMovementCount() {
        let wristRoller = Exercise(
            id: UUID(), userID: UUID(), programDayID: UUID(),
            name: "Wrist Roller", movementID: "wrist_roller",
            sets: 3, repMin: 3, repMax: 3, repUnit: "rounds", perSide: false,
            restSeconds: 60, tempoUp: 1, tempoDown: 2, tempoPause: 0,
            tempoNote: "", notes: "", incrementKG: 1.25, isLite: false,
            optional: false, sortOrder: 0
        )

        let input = GuidedWorkout.setInput(
            for: wristRoller, setNumber: 1, measuredWork: 3,
            signedLoadKG: 10, skipped: false
        )

        XCTAssertFalse(GuidedWorkout.usesAutomaticCadence(for: wristRoller))
        XCTAssertEqual(input.reps, 3)
        XCTAssertNil(input.rounds)
        XCTAssertNil(input.durationSeconds)
    }
}
