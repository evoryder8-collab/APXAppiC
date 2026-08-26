import XCTest
@testable import APEX

final class TrainingCalendarDayTests: XCTestCase {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let foreignOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private let mainID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private let mondayID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

    private func mainProgram(userID: UUID? = nil) -> Program {
        Program(
            id: mainID,
            userID: userID ?? owner,
            slug: "main",
            name: "Main Phase",
            description: ""
        )
    }

    private func monday(
        userID: UUID? = nil,
        programID: UUID? = nil,
        name: String = "Push",
        dayType: String = "push",
        sortOrder: Int = 0
    ) -> ProgramDay {
        ProgramDay(
            id: mondayID,
            userID: userID ?? owner,
            programID: programID ?? mainID,
            weekday: 1,
            name: name,
            dayType: dayType,
            estimatedMinutes: 45,
            warmupNote: "",
            sortOrder: sortOrder
        )
    }

    private func session(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
        userID: UUID? = nil,
        date: String = "2026-08-24",
        programDayID: UUID? = nil,
        completed: Bool,
        startedAt: String? = "2026-08-24T08:00:00Z",
        isDeload: Bool = false,
        notes: String = ""
    ) -> WorkoutSession {
        WorkoutSession(
            id: id,
            userID: userID ?? owner,
            date: date,
            programDayID: programDayID ?? mondayID,
            isLite: false,
            isDeload: isDeload,
            isEventRecovery: false,
            completed: completed,
            qualityScore: completed ? 1 : 0.4,
            startedAt: startedAt,
            completedAt: completed ? "2026-08-24T09:00:00Z" : nil,
            notes: notes
        )
    }

    private func baseData(day: ProgramDay? = nil) -> DashboardData {
        var data = DashboardData.empty
        data.programs = [mainProgram()]
        data.programDays = day.map { [$0] } ?? []
        return data
    }

    private func resolve(
        _ data: DashboardData,
        date: String = "2026-08-24",
        today: String = "2026-08-22"
    ) -> TrainingCalendarDay {
        TrainingCalendarDay.resolve(
            data,
            slug: "main",
            date: date,
            today: today,
            userID: owner
        )
    }

    func testScheduledMissedRestAndNoPrescriptionRemainDistinct() {
        XCTAssertEqual(resolve(baseData(day: monday())).state, .scheduled)
        XCTAssertEqual(
            resolve(baseData(day: monday()), date: "2026-08-17").state,
            .missed
        )
        XCTAssertEqual(
            resolve(baseData(day: monday(name: "Recovery", dayType: "rest"))).state,
            .rest
        )

        let empty = resolve(baseData())
        XCTAssertEqual(empty.state, .noPrescription)
        XCTAssertEqual(empty.title, "No workout prescribed")
    }

    func testCompletedPartialAndDeloadStatesUseRecordedFacts() {
        var completedData = baseData(day: monday())
        completedData.workoutSessions = [session(completed: true)]
        XCTAssertEqual(resolve(completedData).state, .completed)

        var partialData = baseData(day: monday())
        partialData.workoutSessions = [session(completed: false)]
        XCTAssertEqual(resolve(partialData).state, .partiallyCompleted)

        var deloadData = baseData(day: monday())
        deloadData.deloadMarks = [
            DeloadMark(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
                userID: owner,
                date: "2026-08-24"
            )
        ]
        XCTAssertEqual(resolve(deloadData).state, .deload)

        completedData.workoutSessions = [session(completed: true, isDeload: true)]
        let completedDeload = resolve(completedData)
        XCTAssertEqual(completedDeload.state, .completed)
        XCTAssertTrue(completedDeload.isDeload)
    }

    func testArchivedGeneratedDayStillResolvesCompletedHistory() {
        var data = baseData(day: monday(name: "Archived foundation"))
        data.settings = UserSettings(
            userID: owner,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [
                TrainingInduction.archivedMarkerKey: .array([
                    .string(mondayID.uuidString.lowercased())
                ])
            ]
        )
        data.workoutSessions = [session(completed: true)]

        let result = resolve(data)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.title, "Archived foundation")
        XCTAssertEqual(result.programDayID, mondayID)
    }

    func testRecordedSessionKeepsItsAuthoredDayWhenCompletedOffSchedule() {
        let actualDayID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let actualDay = ProgramDay(
            id: actualDayID,
            userID: owner,
            programID: mainID,
            weekday: 2,
            name: "Recorded pull",
            dayType: "pull",
            estimatedMinutes: 45,
            warmupNote: "",
            sortOrder: 1
        )
        var data = baseData(day: monday(name: "Monday push"))
        data.programDays.append(actualDay)
        data.workoutSessions = [session(programDayID: actualDayID, completed: true)]

        let result = resolve(data)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.title, "Recorded pull")
        XCTAssertEqual(result.dayType, "pull")
        XCTAssertEqual(result.programDayID, actualDayID)
    }

    func testAnIncompleteRowRequiresProgressBeforeItBecomesPartial() {
        var data = baseData(day: monday())
        let untouched = session(completed: false, startedAt: nil)
        data.workoutSessions = [untouched]
        XCTAssertEqual(resolve(data).state, .scheduled)

        data.workoutLogs = [
            WorkoutLog(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
                userID: owner,
                sessionID: untouched.id,
                exerciseID: nil,
                exerciseName: "Push-up",
                setNumber: 1,
                weightKG: nil,
                reps: 8,
                rir: 2,
                skipped: false,
                overrideFlag: false,
                createdAt: "2026-08-24T08:10:00Z"
            )
        ]
        XCTAssertEqual(resolve(data).state, .partiallyCompleted)
    }

    func testManualAndAuthoredCustomSessionsDoNotDisappearFromMainCalendar() {
        let customID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
        let customDayID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
        let customProgram = Program(
            id: customID,
            userID: owner,
            slug: "custom",
            name: "Custom workouts",
            description: ""
        )
        let customDay = ProgramDay(
            id: customDayID,
            userID: owner,
            programID: customID,
            weekday: 1,
            name: "Own session",
            dayType: "custom",
            estimatedMinutes: 35,
            warmupNote: "",
            sortOrder: 0
        )

        var manualData = baseData(day: monday())
        manualData.programs.append(customProgram)
        manualData.programDays.append(customDay)
        manualData.workoutSessions = [
            session(
                programDayID: customDayID,
                completed: true,
                notes: ManualWorkout.notes(title: "Evening run")
            )
        ]
        let manual = resolve(manualData)
        XCTAssertEqual(manual.state, .manuallyLogged)
        XCTAssertEqual(manual.title, "Evening run")

        var customData = manualData
        customData.workoutSessions = [session(programDayID: customDayID, completed: true)]
        let custom = resolve(customData)
        XCTAssertEqual(custom.state, .custom)
        XCTAssertEqual(custom.title, "Own session")
    }

    func testSparseGeneratedPlanUsesRestOnlyInsideItsRealWindow() {
        var data = baseData(day: monday())
        data.settings = UserSettings(
            userID: owner,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [
                "training_induction": .object([
                    "start_date": .string("2026-05-01"),
                    "main_start_date": .string("2026-08-01"),
                    "main_day_ids": .array([.string(mondayID.uuidString.lowercased())])
                ])
            ]
        )

        XCTAssertEqual(resolve(data, date: "2026-08-25").state, .rest)
        XCTAssertEqual(resolve(data, date: "2026-07-28").state, .noPrescription)
    }

    func testMalformedInductionBoundaryCannotEraseEveryTransitionDay() {
        var data = baseData(day: monday())
        data.settings = UserSettings(
            userID: owner,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [
                "training_induction": .object([
                    "start_date": .string("2026-05-01"),
                    "transition_day_ids": .array([.string(mondayID.uuidString.lowercased())])
                ])
            ]
        )

        XCTAssertTrue(
            TrainingPlanEngine.isInsideInductionWindow(
                data,
                slug: "transition",
                date: "2026-08-24"
            )
        )
    }

    func testGeneratedPlanEndDateStopsBothPhases() {
        var data = baseData(day: monday())
        data.settings = UserSettings(
            userID: owner,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [
                "training_induction": .object([
                    "start_date": .string("2026-05-01"),
                    "main_start_date": .string("2026-08-01"),
                    "end_date": .string("2026-11-01")
                ])
            ]
        )

        XCTAssertTrue(TrainingPlanEngine.isInsideInductionWindow(data, slug: "transition", date: "2026-07-31"))
        XCTAssertTrue(TrainingPlanEngine.isInsideInductionWindow(data, slug: "main", date: "2026-08-01"))
        XCTAssertFalse(TrainingPlanEngine.isInsideInductionWindow(data, slug: "main", date: "2026-11-01"))
        XCTAssertFalse(TrainingPlanEngine.isInsideInductionWindow(data, slug: "transition", date: "2026-11-01"))
    }

    func testSlugAndOwnershipAreResolvedBeforeWeekday() {
        let foreignProgramID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let foreignDayID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let foreignProgram = Program(
            id: foreignProgramID,
            userID: foreignOwner,
            slug: "main",
            name: "Wrong account",
            description: ""
        )
        let foreignDay = ProgramDay(
            id: foreignDayID,
            userID: foreignOwner,
            programID: foreignProgramID,
            weekday: 1,
            name: "Foreign rest",
            dayType: "rest",
            estimatedMinutes: 0,
            warmupNote: "",
            sortOrder: 0
        )
        var data = baseData(day: monday(name: "My push"))
        data.programs.insert(foreignProgram, at: 0)
        data.programDays.insert(foreignDay, at: 0)
        data.workoutSessions = [
            session(
                userID: foreignOwner,
                programDayID: foreignDayID,
                completed: true
            )
        ]

        let result = resolve(data)
        XCTAssertEqual(result.state, .scheduled)
        XCTAssertEqual(result.title, "My push")
    }

    func testDuplicateWeekdaysResolveByAuthoredOrderDeterministically() {
        var data = baseData(day: monday(name: "Later", sortOrder: 4))
        data.programDays.append(
            ProgramDay(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
                userID: owner,
                programID: mainID,
                weekday: 1,
                name: "First authored",
                dayType: "pull",
                estimatedMinutes: 40,
                warmupNote: "",
                sortOrder: 1
            )
        )

        let result = resolve(data)
        XCTAssertEqual(result.title, "First authored")
        XCTAssertEqual(result.dayType, "pull")
    }

    func testCurrentDayCueSurvivesSelectingAnotherCalendarDay() {
        let today = APEXDateMath.calendarDayState(
            date: "2026-08-26",
            selectedDate: "2026-08-01",
            today: "2026-08-26"
        )
        XCTAssertTrue(today.isToday)
        XCTAssertFalse(today.isSelected)

        let selectedPastDay = APEXDateMath.calendarDayState(
            date: "2026-08-01",
            selectedDate: "2026-08-01",
            today: "2026-08-26"
        )
        XCTAssertFalse(selectedPastDay.isToday)
        XCTAssertTrue(selectedPastDay.isSelected)
    }
}
