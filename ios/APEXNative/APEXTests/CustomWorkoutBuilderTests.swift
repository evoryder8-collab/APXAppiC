import XCTest
import Testing
@testable import APEX

@MainActor
struct CustomWorkoutPersistenceTests {
    enum Failure: Swift.Error { case disk }

    @MainActor
    final class Fixture {
        let owner = UUID()
        let otherOwner = UUID()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: OfflineStore
        var current = DashboardData.empty
        var revision: UInt64 = 0
        var leaseIsCurrent = true
        let day: ProgramDay
        let merge: @MainActor (DashboardData) -> DashboardData
        let operation: OfflineOperation

        init(archive: Bool) throws {
            store = OfflineStore(rootURL: root)
            let program = Program(id: UUID(), userID: owner, slug: "custom", name: "A", description: "")
            var base = DashboardData.empty
            base.programs = [program]
            let saved = try CustomWorkoutLifecycle.prepareSave(
                in: base, ownerID: owner,
                request: .init(name: "Workout", weekday: 1, estimatedMinutes: 20,
                               sessionMode: .guided, picks: [], editingDayID: nil,
                               confirmedReplacementDayIDs: [])
            )
            if archive {
                current = saved.dashboard
                let change = try CustomWorkoutLifecycle.prepareArchive(dayID: saved.day.id, in: current, ownerID: owner)
                day = change.day
                merge = { change.merging(into: $0) }
            } else {
                current = base
                day = saved.day
                merge = { saved.merging(into: $0) }
            }
            operation = try .upsert(day, table: "program_days", onConflict: nil)
        }

        func initialize() async throws {
            try await store.saveDashboard(current, for: owner)
            var other = DashboardData.empty
            other.programs = [Program(id: UUID(), userID: otherOwner, slug: "custom", name: "B", description: "")]
            try await store.saveDashboard(other, for: otherOwner)
        }

        func requireCurrent() throws {
            if !leaseIsCurrent { throw CancellationError() }
        }

        func mutateUnrelated() {
            current.programs.append(Program(id: UUID(), userID: owner, slug: "unrelated", name: "Later", description: ""))
            revision += 1
        }

        func switchOwner() async throws {
            leaseIsCurrent = false
            current = try #require(await store.loadDashboard(for: otherOwner))
            revision += 1
        }

        func drain() async throws -> [ProgramDay] {
            let remote = OfflineStore(rootURL: root.appendingPathComponent("remote"))
            let owner = owner
            let store = store
            let queued = try await store.pendingOperations(for: owner)
            let report = await OfflineQueueDrainer.drain(
                queued,
                replay: { operation in
                    let row = try JSONDecoder().decode(ProgramDay.self, from: #require(operation.payload))
                    var data = DashboardData.empty
                    data.programDays = [row]
                    try await remote.saveDashboard(data, for: owner)
                },
                remove: { try await store.removeOperation($0.id, for: owner) },
                quarantine: { try await store.quarantine($0, reason: $1, for: owner) },
                refreshAuthentication: {}, classify: { _ in .permanent }
            )
            #expect(report.succeeded == queued.count)
            #expect(report.quarantined == 0)
            return try await remote.loadDashboard(for: owner)?.programDays ?? []
        }
    }

    @Test(arguments: [false, true], [false, true])
    func accountSwitchNeverCopiesAnotherOwnersDashboard(archive: Bool, duringEnqueue: Bool) async throws {
        let fixture = try Fixture(archive: archive)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.initialize()
        do {
            _ = try await CustomWorkoutLifecycle.persistMutation(
                snapshot: { (fixture.revision, fixture.current) }, merge: fixture.merge,
                requireCurrent: fixture.requireCurrent,
                saveDashboard: { data in
                    try await fixture.store.saveDashboard(data, for: fixture.owner)
                    if !duringEnqueue { try await fixture.switchOwner() }
                },
                enqueue: {
                    try await fixture.store.enqueue(fixture.operation, for: fixture.owner)
                    if duringEnqueue { try await fixture.switchOwner() }
                }
            )
            Issue.record("An expired lease must cancel publication")
        } catch is CancellationError {} catch { Issue.record(error) }
        let a = try #require(await fixture.store.loadDashboard(for: fixture.owner))
        let b = try #require(await fixture.store.loadDashboard(for: fixture.otherOwner))
        #expect(a.programs.allSatisfy { $0.userID == fixture.owner })
        #expect(b.programs.allSatisfy { $0.userID == fixture.otherOwner })
        #expect(b.programs.map(\.name) == ["B"])
        if !duringEnqueue {
            #expect(try await fixture.store.pendingOperations(for: fixture.owner).isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func failedCacheStabilizationLeavesNothingReplayable(archive: Bool) async throws {
        let fixture = try Fixture(archive: archive)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.initialize()
        var writes = 0
        do {
            _ = try await CustomWorkoutLifecycle.persistMutation(
                snapshot: { (fixture.revision, fixture.current) }, merge: fixture.merge,
                requireCurrent: fixture.requireCurrent,
                saveDashboard: { data in
                    writes += 1
                    if writes == 2 { throw Failure.disk }
                    try await fixture.store.saveDashboard(data, for: fixture.owner)
                    if writes == 1 { fixture.mutateUnrelated() }
                },
                enqueue: { try await fixture.store.enqueue(fixture.operation, for: fixture.owner) }
            )
            Issue.record("Expected pre-commit disk failure")
        } catch Failure.disk {} catch { Issue.record(error) }
        #expect(try await fixture.store.pendingOperations(for: fixture.owner).isEmpty)
        #expect(try await fixture.drain().isEmpty)
        let cached = try #require(await fixture.store.loadDashboard(for: fixture.owner))
        #expect(cached.programDays == fixture.current.programDays)
        #expect(cached.programs.map(\.slug).contains("unrelated"))
    }

    @Test(arguments: [false, true])
    func committedOutboxSurvivesFailedCacheRebaseWithoutReportingUnsaved(archive: Bool) async throws {
        let fixture = try Fixture(archive: archive)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.initialize()
        var writes = 0
        let committed = try await CustomWorkoutLifecycle.persistMutation(
            snapshot: { (fixture.revision, fixture.current) }, merge: fixture.merge,
            requireCurrent: fixture.requireCurrent,
            saveDashboard: { data in
                writes += 1
                if writes > 1 { throw Failure.disk }
                try await fixture.store.saveDashboard(data, for: fixture.owner)
            },
            enqueue: {
                try await fixture.store.enqueue(fixture.operation, for: fixture.owner)
                fixture.mutateUnrelated()
            }
        )
        #expect(committed.programDays.first { $0.id == fixture.day.id } == fixture.day)
        #expect(committed.programs.map(\.slug).contains("unrelated"))
        let cached = try #require(await fixture.store.loadDashboard(for: fixture.owner))
        #expect(cached.programDays.first { $0.id == fixture.day.id } == fixture.day)
        #expect(try await fixture.drain() == [fixture.day])
    }

    @Test(arguments: [false, true])
    func rollbackRebasesWhenAnotherOwnerScopedMutationArrives(archive: Bool) async throws {
        let fixture = try Fixture(archive: archive)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.initialize()
        var writes = 0
        do {
            _ = try await CustomWorkoutLifecycle.persistMutation(
                snapshot: { (fixture.revision, fixture.current) }, merge: fixture.merge,
                requireCurrent: fixture.requireCurrent,
                saveDashboard: { data in
                    writes += 1
                    try await fixture.store.saveDashboard(data, for: fixture.owner)
                    if writes == 2 { fixture.mutateUnrelated() }
                }, enqueue: { throw Failure.disk }
            )
            Issue.record("Expected outbox failure")
        } catch Failure.disk {} catch { Issue.record(error) }
        let cached = try #require(await fixture.store.loadDashboard(for: fixture.owner))
        #expect(cached.programs.map(\.slug).contains("unrelated"))
        #expect(cached.programDays == fixture.current.programDays)
        #expect(try await fixture.store.pendingOperations(for: fixture.owner).isEmpty)
    }
}

/*
 * The custom builder has to agree with the web builder, otherwise the same
 * session reads as a different length depending on which device opened it.
 */
@MainActor
final class CustomWorkoutBuilderTests: XCTestCase {
    private let ownerID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let customProgramID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!

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

    private func customProgram() -> Program {
        Program(
            id: customProgramID,
            userID: ownerID,
            slug: "custom",
            name: "Custom workouts",
            description: "Owned sessions"
        )
    }

    private func customDay(
        id: UUID,
        weekday: Int,
        name: String = "Monday strength",
        sessionMode: WorkoutSessionMode = .guided
    ) -> ProgramDay {
        ProgramDay(
            id: id,
            userID: ownerID,
            programID: customProgramID,
            weekday: weekday,
            name: name,
            dayType: "custom",
            estimatedMinutes: 32,
            warmupNote: "Move pain-free",
            sortOrder: weekday,
            sessionMode: sessionMode.rawValue
        )
    }

    private func exercise(
        id: UUID = UUID(),
        dayID: UUID,
        movementID: String,
        name: String,
        order: Int,
        groupID: UUID? = nil,
        groupPosition: Int? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            userID: ownerID,
            programDayID: dayID,
            name: name,
            movementID: movementID,
            workGroupID: groupID,
            workGroupPosition: groupPosition,
            sets: 4,
            repMin: 8,
            repMax: 8,
            repUnit: "reps",
            perSide: false,
            restSeconds: 75,
            tempoUp: 1,
            tempoDown: 2,
            tempoPause: 0,
            tempoNote: "",
            notes: "Barbell · legs",
            incrementKG: 2.5,
            isLite: false,
            optional: false,
            sortOrder: order
        )
    }

    private func request(
        weekday: Int,
        editingDayID: UUID? = nil,
        confirmedReplacementDayIDs: Set<UUID> = [],
        name: String = "New strength"
    ) -> CustomWorkoutLifecycle.SaveRequest {
        CustomWorkoutLifecycle.SaveRequest(
            name: name,
            weekday: weekday,
            estimatedMinutes: 28,
            sessionMode: .tracked,
            picks: [
                CustomWorkoutBuilder.Pick(
                    item: item(id: "barbell_back_squat", category: "weights"),
                    sets: 3,
                    reps: 10,
                    rest: 90
                ),
            ],
            editingDayID: editingDayID,
            confirmedReplacementDayIDs: confirmedReplacementDayIDs
        )
    }

    func testReopeningCustomDayPrefillsEveryEditableFieldAndOrderedRoundMembership() throws {
        let dayID = UUID(uuidString: "10000000-0000-4000-8000-000000000010")!
        let groupID = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
        let day = customDay(
            id: dayID,
            weekday: 4,
            name: "Thursday circuit",
            sessionMode: .tracked
        )
        let data = DashboardData(
            programs: [customProgram()],
            programDays: [day],
            exercises: [
                exercise(
                    dayID: dayID,
                    movementID: "power_snatch",
                    name: "Power Snatch",
                    order: 0,
                    groupID: groupID,
                    groupPosition: 1
                ),
                exercise(
                    dayID: dayID,
                    movementID: "barbell_back_squat",
                    name: "Barbell Back Squat",
                    order: 1,
                    groupID: groupID,
                    groupPosition: 2
                ),
            ]
        )

        let draft = try XCTUnwrap(CustomWorkoutLifecycle.editorDraft(for: day, in: data))

        XCTAssertEqual(draft.name, "Thursday circuit")
        XCTAssertEqual(draft.weekday, 4)
        XCTAssertEqual(draft.sessionMode, .tracked)
        XCTAssertEqual(draft.picks.map(\.item.movementID), ["power_snatch", "barbell_back_squat"])
        XCTAssertEqual(draft.picks.map(\.sets), [4, 4])
        XCTAssertEqual(draft.picks.map(\.reps), [8, 8])
        XCTAssertEqual(draft.picks.map(\.rest), [75, 75])
        XCTAssertEqual(draft.picks.map(\.linkedToNext), [true, false])
    }

    func testFreshSaveCannotReplaceSameWeekdayUntilEveryConflictIsExplicitlyConfirmed() throws {
        let firstID = UUID(uuidString: "10000000-0000-4000-8000-000000000020")!
        let duplicateID = UUID(uuidString: "10000000-0000-4000-8000-000000000021")!
        let oldExerciseID = UUID(uuidString: "10000000-0000-4000-8000-000000000022")!
        let oldSessionID = UUID(uuidString: "10000000-0000-4000-8000-000000000023")!
        let data = DashboardData(
            programs: [customProgram()],
            programDays: [
                customDay(id: firstID, weekday: 2, name: "First Tuesday"),
                customDay(id: duplicateID, weekday: 2, name: "Duplicate Tuesday"),
            ],
            exercises: [
                exercise(
                    id: oldExerciseID,
                    dayID: firstID,
                    movementID: "old",
                    name: "Old movement",
                    order: 0
                ),
            ],
            workoutSessions: [
                WorkoutSession(
                    id: oldSessionID,
                    userID: ownerID,
                    date: "2026-08-26",
                    programDayID: firstID,
                    isLite: false,
                    isDeload: false,
                    isEventRecovery: false,
                    completed: true,
                    qualityScore: 1,
                    startedAt: "2026-08-26T08:00:00Z",
                    completedAt: "2026-08-26T08:30:00Z",
                    notes: ""
                ),
            ]
        )

        XCTAssertThrowsError(
            try CustomWorkoutLifecycle.prepareSave(
                in: data,
                ownerID: ownerID,
                request: request(weekday: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? CustomWorkoutLifecycle.Error,
                .replacementConfirmationRequired([firstID, duplicateID])
            )
        }

        let change = try CustomWorkoutLifecycle.prepareSave(
            in: data,
            ownerID: ownerID,
            request: request(
                weekday: 2,
                confirmedReplacementDayIDs: [firstID, duplicateID]
            )
        )

        let activeTuesdays = change.dashboard.programDays.filter {
            $0.userID == ownerID && $0.programID == customProgramID && $0.weekday == 2 && $0.isActive
        }
        XCTAssertEqual(activeTuesdays.count, 1)
        XCTAssertEqual(activeTuesdays.first?.name, "New strength")
        XCTAssertNotEqual(activeTuesdays.first?.id, firstID)
        XCTAssertNotEqual(activeTuesdays.first?.id, duplicateID)
        XCTAssertEqual(change.dashboard.programDays.first { $0.id == firstID }?.name, "First Tuesday")
        XCTAssertEqual(change.dashboard.programDays.first { $0.id == firstID }?.isActive, false)
        XCTAssertEqual(change.dashboard.programDays.first { $0.id == duplicateID }?.isActive, false)
        XCTAssertTrue(change.dashboard.exercises.contains { $0.id == oldExerciseID })
        XCTAssertEqual(
            change.dashboard.workoutSessions.first { $0.id == oldSessionID }?.programDayID,
            firstID
        )
        XCTAssertEqual(
            change.dashboard.exercises.filter { $0.programDayID == activeTuesdays.first?.id }.map(\.movementID),
            ["barbell_back_squat"]
        )
    }

    func testEditingReusesTheDayIdentityWithoutNeedingReplacementConfirmation() throws {
        let dayID = UUID(uuidString: "10000000-0000-4000-8000-000000000030")!
        let oldExerciseID = UUID(uuidString: "10000000-0000-4000-8000-000000000031")!
        let data = DashboardData(
            programs: [customProgram()],
            programDays: [customDay(id: dayID, weekday: 5)],
            exercises: [
                exercise(
                    id: oldExerciseID,
                    dayID: dayID,
                    movementID: "old",
                    name: "Old movement",
                    order: 0
                ),
            ]
        )

        let change = try CustomWorkoutLifecycle.prepareSave(
            in: data,
            ownerID: ownerID,
            request: request(weekday: 5, editingDayID: dayID, name: "Edited Friday")
        )

        XCTAssertEqual(change.day.id, dayID)
        XCTAssertEqual(change.dashboard.programDays.filter { $0.id == dayID }.map(\.name), ["Edited Friday"])
        XCTAssertFalse(change.dashboard.exercises.contains { $0.id == oldExerciseID })
        XCTAssertEqual(change.dashboard.exercises.filter { $0.programDayID == dayID }.count, 1)
    }

    func testMovingAnEditOntoAnotherWorkoutRequiresDeliberateReplacement() throws {
        let editedID = UUID(uuidString: "10000000-0000-4000-8000-000000000040")!
        let occupiedID = UUID(uuidString: "10000000-0000-4000-8000-000000000041")!
        let data = DashboardData(
            programs: [customProgram()],
            programDays: [
                customDay(id: editedID, weekday: 3, name: "Wednesday"),
                customDay(id: occupiedID, weekday: 6, name: "Saturday"),
            ]
        )

        XCTAssertThrowsError(
            try CustomWorkoutLifecycle.prepareSave(
                in: data,
                ownerID: ownerID,
                request: request(weekday: 6, editingDayID: editedID)
            )
        ) { error in
            XCTAssertEqual(
                error as? CustomWorkoutLifecycle.Error,
                .replacementConfirmationRequired([occupiedID])
            )
        }

        let change = try CustomWorkoutLifecycle.prepareSave(
            in: data,
            ownerID: ownerID,
            request: request(
                weekday: 6,
                editingDayID: editedID,
                confirmedReplacementDayIDs: [occupiedID]
            )
        )

        XCTAssertEqual(change.day.id, editedID)
        XCTAssertEqual(change.day.weekday, 6)
        XCTAssertEqual(change.dashboard.programDays.first { $0.id == occupiedID }?.isActive, false)
        XCTAssertEqual(
            change.dashboard.programDays.filter { $0.weekday == 6 && $0.isActive }.map(\.id),
            [editedID]
        )
    }

    func testDeletingCustomWorkoutArchivesItsPlanRowButKeepsReceiptEvidence() throws {
        let dayID = UUID(uuidString: "10000000-0000-4000-8000-000000000050")!
        let exerciseID = UUID(uuidString: "10000000-0000-4000-8000-000000000051")!
        let sessionID = UUID(uuidString: "10000000-0000-4000-8000-000000000052")!
        let day = customDay(id: dayID, weekday: 7)
        let workout = WorkoutSession(
            id: sessionID,
            userID: ownerID,
            date: "2026-09-01",
            programDayID: dayID,
            isLite: false,
            isDeload: false,
            isEventRecovery: false,
            completed: true,
            qualityScore: 1,
            startedAt: "2026-09-01T08:00:00Z",
            completedAt: "2026-09-01T08:30:00Z",
            notes: ""
        )
        let data = DashboardData(
            programs: [customProgram()],
            programDays: [day],
            exercises: [
                exercise(
                    id: exerciseID,
                    dayID: dayID,
                    movementID: "power_snatch",
                    name: "Power Snatch",
                    order: 0
                ),
            ],
            workoutSessions: [workout]
        )

        let change = try CustomWorkoutLifecycle.prepareArchive(
            dayID: dayID,
            in: data,
            ownerID: ownerID
        )

        XCTAssertEqual(change.day.id, dayID)
        XCTAssertFalse(change.day.isActive)
        XCTAssertEqual(change.dashboard.exercises.map(\.id), [exerciseID])
        XCTAssertEqual(change.dashboard.workoutSessions.map(\.id), [sessionID])
        XCTAssertTrue(TrainingInduction.visibleProgramDays(in: change.dashboard, slug: "custom").isEmpty)
    }

    func testFailedDurablePersistenceCannotPublishTheProposedWorkout() async throws {
        enum ExpectedFailure: Swift.Error { case diskFull }
        let original = DashboardData(programs: [customProgram()])
        let proposed = try CustomWorkoutLifecycle.prepareSave(
            in: original,
            ownerID: ownerID,
            request: request(weekday: 1, name: "Must not appear")
        ).dashboard
        var published = original

        do {
            published = try await CustomWorkoutLifecycle.persistBeforePublishing(proposed) { _ in
                throw ExpectedFailure.diskFull
            }
            XCTFail("A failed durable write must not return a publishable dashboard")
        } catch ExpectedFailure.diskFull {
            // Exact expected branch.
        }

        XCTAssertTrue(published.programDays.isEmpty)
    }

    func testDurableSaveRebasesWorkoutDeltaWithoutDroppingConcurrentDashboardChanges() async throws {
        let original = DashboardData(programs: [customProgram()])
        let change = try CustomWorkoutLifecycle.prepareSave(
            in: original,
            ownerID: ownerID,
            request: request(weekday: 1, name: "Concurrent-safe strength")
        )
        let nutritionLog = DailyLog(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000090")!,
            userID: ownerID,
            date: "2026-09-03",
            kcal: 2_100,
            proteinG: 155,
            fatG: 70,
            carbsG: 215,
            waterL: 2.4,
            estimatedTDEE: 2_300,
            computedPAL: 1.55,
            activityMode: "quick",
            weightKG: 78
        )
        var current = original
        var revision: UInt64 = 0
        var persistAttempts = 0

        let committed = try await CustomWorkoutLifecycle.persistMergedBeforePublishing(
            snapshot: { (revision, current) },
            merge: { change.merging(into: $0) },
            persist: { _ in
                persistAttempts += 1
                if persistAttempts == 1 {
                    current.dailyLogs.append(nutritionLog)
                    revision &+= 1
                }
            }
        )

        XCTAssertEqual(persistAttempts, 2, "the merged latest dashboard must itself be durable")
        XCTAssertEqual(committed.dailyLogs.map(\.id), [nutritionLog.id])
        XCTAssertEqual(committed.programDays.map(\.id), [change.day.id])
        XCTAssertEqual(
            Set(committed.exercises.map(\.programDayID)),
            [change.day.id]
        )
    }

    func testCustomWorkoutMutationGateRejectsRapidSaveOrDeleteUntilTheFirstFinishes() throws {
        var gate = CustomWorkoutMutationGate()
        let first = try XCTUnwrap(gate.begin())

        XCTAssertTrue(gate.isActive)
        XCTAssertNil(gate.begin(), "a second save or delete must not overlap the first")
        gate.finish(UUID())
        XCTAssertTrue(gate.isActive, "a stale completion cannot unlock another mutation")
        gate.finish(first)
        XCTAssertFalse(gate.isActive)
        XCTAssertNotNil(gate.begin())
    }

    func testBuilderCapturesTheAccountLeaseBeforeSaveAndGatesDismissal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("APEX/Features/Training/CustomWorkoutBuilder.swift")
        )
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(compact.contains("guardletoperation=session.accountOperationLease()else{return}"))
        XCTAssertTrue(compact.contains("letoutcome=tryawaitsession.saveCustomWorkout("))
        XCTAssertTrue(compact.contains("operation:operation"))
        XCTAssertTrue(compact.contains(
            "guardsession.accountOperationIsCurrent(operation)else{return}switchoutcome{case.saved:didSave=truedismiss()"
        ))
        XCTAssertTrue(compact.contains(
            "case.replacementConfirmationRequired(letdayIDs):pendingReplacementDayIDs=dayIDs"
        ))
        XCTAssertTrue(compact.contains("case.denied:break"))
        XCTAssertTrue(compact.contains("catchisCancellationError{return}"))
        XCTAssertTrue(compact.contains(
            "catch{guardsession.accountOperationIsCurrent(operation)else{return}session.alertMessage=error.localizedDescription}"
        ))
    }

    func testAppSessionCommitsCustomWorkoutBeforePublishingAndGatesEveryMutation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("APEX/App/AppSession.swift")
        )
        let saveStart = try XCTUnwrap(source.range(of: "    func saveCustomWorkout("))
        let archiveStart = try XCTUnwrap(
            source.range(of: "    func archiveCustomWorkout(", range: saveStart.upperBound..<source.endIndex)
        )
        let manualStart = try XCTUnwrap(
            source.range(of: "    func saveManualWorkout(", range: archiveStart.upperBound..<source.endIndex)
        )
        let saveBody = String(source[saveStart.lowerBound..<archiveStart.lowerBound])
        let archiveBody = String(source[archiveStart.lowerBound..<manualStart.lowerBound])
        let manualTail = source[manualStart.lowerBound...]
        let manualEnd = manualTail.range(of: "    func installInductionPlan(")?.lowerBound
        let manualBody = manualEnd.map { String(manualTail[..<$0]) } ?? String(manualTail)

        XCTAssertTrue(saveBody.contains("guard coachClientPolicy.canCreateCustomWorkouts else"))
        XCTAssertTrue(saveBody.contains("CustomWorkoutLifecycle.prepareSave"))
        XCTAssertTrue(saveBody.contains("guard let mutationToken = beginCustomWorkoutMutation()"))
        XCTAssertTrue(saveBody.contains("CustomWorkoutLifecycle.persistMutation"))
        XCTAssertTrue(saveBody.contains("merge: { change.merging(into: $0) }"))
        let durableCommit = try XCTUnwrap(saveBody.range(of: "persistMutation"))
        let durableOutbox = try XCTUnwrap(saveBody.range(of: "offlineStore.enqueue("))
        let publication = try XCTUnwrap(saveBody.range(of: "data = committed"))
        XCTAssertLessThan(durableCommit.lowerBound, publication.lowerBound)
        XCTAssertLessThan(durableOutbox.lowerBound, publication.lowerBound)
        XCTAssertTrue(saveBody.contains("await self.flushPendingChanges(for: userID)"))
        XCTAssertTrue(archiveBody.contains("guard coachClientPolicy.canCreateCustomWorkouts else"))
        XCTAssertTrue(archiveBody.contains("CustomWorkoutLifecycle.prepareArchive"))
        XCTAssertTrue(archiveBody.contains("guard let mutationToken = beginCustomWorkoutMutation()"))
        XCTAssertTrue(archiveBody.contains("persistMutation"))
        XCTAssertTrue(archiveBody.contains("merge: { change.merging(into: $0) }"))
        let archiveOutbox = try XCTUnwrap(archiveBody.range(of: "offlineStore.enqueue("))
        let archivePublication = try XCTUnwrap(archiveBody.range(of: "data = committed"))
        XCTAssertLessThan(archiveOutbox.lowerBound, archivePublication.lowerBound)
        XCTAssertTrue(archiveBody.contains("await self.flushPendingChanges(for: operation.ownerID)"))
        XCTAssertTrue(archiveBody.contains("data = committed"))
        XCTAssertTrue(manualBody.contains("guard coachClientPolicy.canCreateCustomWorkouts else"))
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
