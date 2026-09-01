import XCTest
@testable import APEX

final class RecoveryPlannerTests: XCTestCase {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let programID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    private func data() -> DashboardData {
        var data = DashboardData.empty
        data.programs = [
            Program(
                id: programID,
                userID: owner,
                slug: "main",
                name: "Main Phase",
                description: ""
            )
        ]
        return data
    }

    func testRecoveryDatesAreBoundedAcrossFourWeeksWithTwoSessionsPerWeek() {
        let dates = RecoveryPlanner.scheduledDates(
            startDate: "2026-09-02",
            existingDays: []
        )

        XCTAssertEqual(dates.count, 8)
        XCTAssertEqual(Set(dates).count, 8)
        XCTAssertTrue(dates.allSatisfy { $0 >= "2026-09-02" && $0 <= "2026-09-29" })

        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let parsed = dates.compactMap(formatter.date(from:))
        for pair in zip(parsed, parsed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                calendar.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0,
                2
            )
        }
    }

    func testGuidedPlanCreatesExactDatedMobilityRowsAndReviewedExercises() {
        var next = 300
        let result = RecoveryPlanner.build(
            data: data(),
            ownerID: owner,
            startDate: "2026-09-02",
            target: .joint,
            source: .guided,
            makeID: {
                defer { next += 1 }
                return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", next))!
            }
        )

        XCTAssertEqual(result.days.count, 8)
        XCTAssertEqual(result.exercises.count, 32)
        XCTAssertTrue(result.days.allSatisfy {
            $0.userID == owner &&
            $0.programID == programID &&
            $0.dayType == "mobility" &&
            $0.scheduledDate != nil &&
            $0.recoveryPlanID == result.planID &&
            $0.recoveryTarget == RecoveryPlanner.Target.joint.rawValue &&
            $0.recoverySource == RecoveryPlanner.Source.guided.rawValue
        })
        XCTAssertTrue(result.exercises.allSatisfy { exercise in
            result.days.contains(where: { $0.id == exercise.programDayID })
        })
    }

    func testExternalRoutineCreatesOneHonestCompletionRowPerSession() {
        let result = RecoveryPlanner.build(
            data: data(),
            ownerID: owner,
            startDate: "2026-09-02",
            target: .flexibility,
            source: .external
        )

        XCTAssertEqual(result.days.count, 8)
        XCTAssertEqual(result.exercises.count, 8)
        XCTAssertTrue(result.exercises.allSatisfy { $0.name == "Mobility Flow" })
    }

    func testScheduledRowMatchesOnlyItsExactCalendarDate() {
        let day = ProgramDay(
            id: UUID(),
            userID: owner,
            programID: programID,
            weekday: 3,
            name: "Joint care",
            dayType: "mobility",
            estimatedMinutes: 10,
            warmupNote: "",
            sortOrder: 0,
            scheduledDate: "2026-09-09",
            recoveryPlanID: UUID(),
            recoveryTarget: RecoveryPlanner.Target.joint.rawValue,
            recoverySource: RecoveryPlanner.Source.guided.rawValue
        )

        XCTAssertTrue(RecoveryPlanner.day(day, matches: "2026-09-09"))
        XCTAssertFalse(RecoveryPlanner.day(day, matches: "2026-09-16"))
    }

    func testReplacingFuturePlanNeverDeactivatesCompletedOrUnrelatedRows() {
        let protectedID = UUID()
        let oldPlan = UUID()
        let rows = [
            ProgramDay(
                id: protectedID,
                userID: owner,
                programID: programID,
                weekday: 3,
                name: "Completed joint care",
                dayType: "mobility",
                estimatedMinutes: 10,
                warmupNote: "",
                sortOrder: 0,
                scheduledDate: "2026-09-08",
                recoveryPlanID: oldPlan,
                recoveryTarget: RecoveryPlanner.Target.joint.rawValue,
                recoverySource: RecoveryPlanner.Source.guided.rawValue
            ),
            ProgramDay(
                id: UUID(),
                userID: owner,
                programID: programID,
                weekday: 5,
                name: "Future joint care",
                dayType: "mobility",
                estimatedMinutes: 10,
                warmupNote: "",
                sortOrder: 1,
                scheduledDate: "2026-09-10",
                recoveryPlanID: oldPlan,
                recoveryTarget: RecoveryPlanner.Target.joint.rawValue,
                recoverySource: RecoveryPlanner.Source.guided.rawValue
            ),
            ProgramDay(
                id: UUID(),
                userID: owner,
                programID: programID,
                weekday: 6,
                name: "Future flexibility",
                dayType: "mobility",
                estimatedMinutes: 10,
                warmupNote: "",
                sortOrder: 2,
                scheduledDate: "2026-09-11",
                recoveryPlanID: oldPlan,
                recoveryTarget: RecoveryPlanner.Target.flexibility.rawValue,
                recoverySource: RecoveryPlanner.Source.guided.rawValue
            )
        ]

        let deactivated = RecoveryPlanner.futureRowsToDeactivate(
            rows,
            ownerID: owner,
            target: .joint,
            today: "2026-09-01",
            protectedDayIDs: [protectedID]
        )

        XCTAssertEqual(deactivated.count, 1)
        XCTAssertEqual(deactivated.first?.name, "Future joint care")
        XCTAssertEqual(deactivated.first?.isActive, false)
    }
}
