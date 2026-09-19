/*
 * Native must detect and deliver the V8.5 update to a native-only account.
 */
import XCTest
@testable import APEX

final class SeedVersionTests: XCTestCase {
    private func profile(seedVersion: Int) -> Profile {
        var value = APEXDebugFixture.dashboard().profile!
        value.seedVersion = seedVersion
        return value
    }

    func testCurrentVersionNeedsNothing() {
        let state = SeedVersion.state(of: profile(seedVersion: SeedVersion.current))
        XCTAssertEqual(state, .current)
        XCTAssertFalse(state.needsRepair)
        XCTAssertNil(SeedVersion.notice(for: state))
    }

    func testAnOlderAccountIsReportedAsBehind() {
        let state = SeedVersion.state(of: profile(seedVersion: 3))
        XCTAssertEqual(state, .behind(stored: 3))
        XCTAssertTrue(state.needsRepair)
        XCTAssertNotNil(SeedVersion.notice(for: state))
    }

    /// A newer account than this build knows about is not behind.
    func testAFutureVersionIsNotTreatedAsStale() {
        let state = SeedVersion.state(of: profile(seedVersion: SeedVersion.current + 1))
        XCTAssertEqual(state, .current)
        XCTAssertFalse(state.needsRepair)
    }

    func testNoProfileIsUnknownRatherThanCurrent() {
        let state = SeedVersion.state(of: nil)
        XCTAssertEqual(state, .unknown)
        XCTAssertTrue(state.needsRepair, "absence of a profile is not evidence of a current one")
    }

    func testVersionSevenCannotClaimTheUndeliveredV85ProgrammeIsCurrent() {
        XCTAssertEqual(SeedVersion.state(of: profile(seedVersion: 7)), .behind(stored: 7))
    }

    func testNativeCarriesTheAuthoredProgrammeWithoutRequiringAWebLogin() {
        XCTAssertNotNil(Bundle.main.url(forResource: "constantine-v85", withExtension: "json"))
    }
}

final class BespokeProgrammeUpgradeTests: XCTestCase {
    private let owner = UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!

    private func legacy() -> DashboardData {
        var data = APEXDebugFixture.dashboard(userID: owner)
        data.profile?.profileKind = .bespoke
        data.profile?.bespokeProtocolID = .constantineV85
        data.profile?.seedVersion = 7
        data.settings?.addons["training_protocol"] = .object([
            "version": .number(83), "start_date": .string("2026-09-07")
        ])
        data.events = []
        data.deloadMarks = []
        return data
    }

    func testInstallsSevenFiveSetMorningRotationsBeforeTheOfficialCards() throws {
        let result = try XCTUnwrap(BespokeProgrammeUpgrade.prepare(in: legacy(), authenticatedOwnerID: owner))
        let targets = [
            ["chest", "side delts"], ["side delts", "quads", "hamstrings", "calves"],
            ["chest", "side delts", "quads", "hamstrings", "calves"],
            ["chest", "side delts", "quads", "hamstrings", "calves"],
            ["chest", "side delts"], ["quads", "hamstrings", "calves"],
            ["chest", "side delts", "quads", "hamstrings", "calves"]
        ]
        for index in 0..<7 {
            let date = "2026-09-\(14 + index)"
            let plans = TrainingPlanEngine.programDays(result.dashboard, slug: "main", date: date, lite: false)
            let morning = try XCTUnwrap(plans.first)
            XCTAssertEqual(morning.programDay?.name, "AM · Morning circle")
            XCTAssertEqual(morning.exercises.map { $0.exercise.notes.replacingOccurrences(of: "Morning circle · ", with: "") }, targets[index])
            XCTAssertTrue(morning.exercises.allSatisfy { $0.plannedSets == 5 })
            let sequence = PlayerTimeline.workSequence(morning)
            XCTAssertEqual(sequence.count, targets[index].count * 5)
            XCTAssertEqual(sequence.prefix(targets[index].count).map(\.exerciseIndex), Array(0..<targets[index].count))
            XCTAssertTrue(sequence.prefix(targets[index].count).allSatisfy { $0.setNumber == 1 })
            let rest = PlayerTimeline.breakPlan(after: sequence[0], before: sequence[1], exercises: morning.exercises.map(\.exercise))
            XCTAssertEqual(rest.duration, morning.exercises[0].exercise.restSeconds)
        }
    }

    func testDeloadAndLightMorningKeepEveryEligibleTargetAtTwoSets() throws {
        let result = try XCTUnwrap(BespokeProgrammeUpgrade.prepare(in: legacy(), authenticatedOwnerID: owner))
        for (date, lite) in [("2026-09-28", false), ("2026-09-14", true)] {
            let morning = try XCTUnwrap(TrainingPlanEngine.programDays(result.dashboard, slug: "main", date: date, lite: lite).first)
            XCTAssertEqual(morning.exercises.count, 2)
            XCTAssertTrue(morning.exercises.allSatisfy { $0.plannedSets == 2 })
        }
    }

    func testHistoryAndUnrelatedDataSurviveAndRetryUsesTheSameIDs() throws {
        let original = legacy()
        let result = try XCTUnwrap(BespokeProgrammeUpgrade.prepare(in: original, authenticatedOwnerID: owner))
        XCTAssertEqual(result.dashboard.workoutSessions, original.workoutSessions)
        XCTAssertEqual(result.dashboard.workoutLogs, original.workoutLogs)
        XCTAssertEqual(result.dashboard.meals, original.meals)
        for row in original.exercises { XCTAssertTrue(result.dashboard.exercises.contains(row)) }
        let mainID = try XCTUnwrap(original.programs.first { $0.slug == "main" }?.id)
        for row in original.programDays where row.programID != mainID {
            XCTAssertTrue(result.dashboard.programDays.contains(row))
        }
        XCTAssertTrue(result.stagedDays.allSatisfy { !$0.isActive })
        XCTAssertEqual(result.dashboard.settings?.addons["training_protocol"]?.objectValue?["start_date"]?.stringValue, "2026-09-07")
        XCTAssertEqual(result.dashboard.profile?.seedVersion, 8)
        XCTAssertNil(try BespokeProgrammeUpgrade.prepare(in: result.dashboard, authenticatedOwnerID: owner))
        var interrupted = result.dashboard
        interrupted.profile?.seedVersion = 7
        let retry = try XCTUnwrap(BespokeProgrammeUpgrade.prepare(in: interrupted, authenticatedOwnerID: owner))
        XCTAssertTrue(retry.stagedDays.isEmpty, "Retry must never hide already activated replacement days")
        XCTAssertEqual(Set(retry.days.filter(\.isActive).map(\.id)), Set(result.stagedDays.map(\.id)))
        XCTAssertEqual(retry.dashboard.programDays.count, result.dashboard.programDays.count)
        XCTAssertEqual(retry.dashboard.exercises.count, result.dashboard.exercises.count)
    }

    func testStandardAccountsOtherOwnersAndActiveQuestionnairePlansAreNotChanged() throws {
        XCTAssertNil(try BespokeProgrammeUpgrade.prepare(in: legacy(), authenticatedOwnerID: UUID()))
        var standard = legacy()
        standard.profile?.profileKind = .standard
        XCTAssertNil(try BespokeProgrammeUpgrade.prepare(in: standard, authenticatedOwnerID: owner))
        var overlay = legacy()
        overlay.settings?.addons["training_induction"] = .object(["main_day_ids": .array([.string(UUID().uuidString)])])
        XCTAssertNil(try BespokeProgrammeUpgrade.prepare(in: overlay, authenticatedOwnerID: owner))
    }

    func testProtectedOriginalInLegacyArchiveIsRetiredWithoutDuplicateCards() throws {
        var data = legacy()
        let mainID = try XCTUnwrap(data.programs.first { $0.slug == "main" }?.id)
        let oldDay = try XCTUnwrap(data.programDays.first { $0.programID == mainID })
        let ids: JSONValue = .array([.string(oldDay.id.uuidString.lowercased())])
        data.settings?.addons[TrainingInduction.protectedOriginalDayIDsKey] = ids
        data.settings?.addons[TrainingInduction.archivedMarkerKey] = ids
        let result = try XCTUnwrap(BespokeProgrammeUpgrade.prepare(in: data, authenticatedOwnerID: owner))
        XCTAssertFalse(try XCTUnwrap(result.dashboard.programDays.first { $0.id == oldDay.id }).isActive)
        XCTAssertEqual(TrainingInduction.activeProgramDays(in: result.dashboard).filter { $0.programID == mainID }.count, 18)
    }

    func testFailedExerciseDeliveryCannotActivateCardsOrAdvanceVersion() async throws {
        enum Failure: Error { case offline }
        var writes: [BespokeProgrammeUpgrade.WritePhase] = []
        do {
            try await BespokeProgrammeUpgrade.deliver { phase in
                writes.append(phase)
                if phase == .exercises { throw Failure.offline }
            }
            XCTFail("Delivery must propagate the failed write")
        } catch Failure.offline { }
        XCTAssertEqual(writes, [.stagedDays, .exercises])
        writes = []
        try await BespokeProgrammeUpgrade.deliver { writes.append($0) }
        XCTAssertEqual(writes, [.stagedDays, .exercises, .activeDays, .program, .settings, .version])
    }
}
