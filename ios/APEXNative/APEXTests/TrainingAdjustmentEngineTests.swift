import XCTest
@testable import APEX

final class TrainingAdjustmentEngineTests: XCTestCase {
    func testDeloadLookupIsDateSpecific() {
        let mark = DeloadMark(id: UUID(), userID: UUID(), date: "2026-08-17")
        XCTAssertTrue(TrainingAdjustmentEngine.isDeload(on: "2026-08-17", marks: [mark]))
        XCTAssertFalse(TrainingAdjustmentEngine.isDeload(on: "2026-08-18", marks: [mark]))
    }

    func testDeloadRemovesOneSetWithoutDroppingBelowOne() {
        let threeSets = exercise(sets: 3)
        let oneSet = exercise(sets: 1)
        let adjusted = TrainingAdjustmentEngine.adjustedExercises(
            [threeSets, oneSet],
            isDeload: true
        )

        XCTAssertEqual(adjusted.map(\.sets), [2, 1])
        XCTAssertEqual(threeSets.sets, 3, "The Supabase-backed source prescription must stay unchanged.")
    }

    func testStandardDayLeavesPrescriptionUnchanged() {
        let source = exercise(sets: 4)
        XCTAssertEqual(
            TrainingAdjustmentEngine.adjustedExercises([source], isDeload: false).first?.sets,
            4
        )
    }

    private func exercise(sets: Int) -> Exercise {
        Exercise(
            id: UUID(),
            userID: UUID(),
            programDayID: UUID(),
            name: "Test movement",
            sets: sets,
            repMin: 8,
            repMax: 12,
            repUnit: "reps",
            perSide: false,
            restSeconds: 90,
            tempoUp: 1,
            tempoDown: 2,
            tempoPause: 0,
            tempoNote: "",
            notes: "",
            incrementKG: 1,
            isLite: false,
            optional: false,
            sortOrder: 1
        )
    }
}
