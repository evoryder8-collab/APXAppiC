import XCTest
@testable import APEX

final class AvatarScoreInputTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    private let dayID = UUID(uuidString: "22222222-3333-4444-8555-666666666666")!

    private func dashboard(dayType: String = "legs_a", baseline: String = "2026-10-01") -> DashboardData {
        var data = APEXDebugFixture.dashboard(userID: owner)
        data.profile?.baselineDate = baseline
        data.programDays = [ProgramDay(id: dayID, userID: owner, programID: UUID(), weekday: 1, name: "Day",
                                       dayType: dayType, estimatedMinutes: 45, warmupNote: "", sortOrder: 0)]
        data.exercises = []
        data.workoutSessions = []
        data.workoutLogs = []
        data.dailyLogs = []
        data.healthMetrics = []
        data.importedActivities = []
        data.fitnessEvidence = []
        return data
    }

    private func workout(date: String = "2026-10-05", completedAt: String = "2026-10-05T09:00:00Z") -> WorkoutSession {
        WorkoutSession(id: UUID(), userID: owner, date: date, programDayID: dayID, isLite: false,
                       isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
                       startedAt: "\(date)T08:00:00Z", completedAt: completedAt, notes: "Completed in tracked mode")
    }

    private func set(_ movementID: String?, session: UUID, weight: Double? = 60, reps: Int? = 10,
                     exercise: UUID? = nil) -> WorkoutLog {
        WorkoutLog(id: UUID(), userID: owner, sessionID: session, exerciseID: exercise,
                   exerciseName: movementID ?? "Unlisted lift", setNumber: 1, weightKG: weight, reps: reps, rir: 2,
                   movementID: movementID, skipped: false, overrideFlag: false, createdAt: "2026-10-05T08:10:00Z")
    }

    private func evidence(_ metric: FitnessEvidenceMetric, value: Double, measuredAt: String,
                          protocolName: String = "apex_baseline_calibration_v1",
                          lowerBound: Double? = nil) -> FitnessEvidenceRecord {
        var metadata: [String: JSONValue] = ["answered_count": .number(3)]
        if let lowerBound { metadata["lower_bound"] = .number(lowerBound) }
        return FitnessEvidenceRecord(
            id: UUID(), userID: owner, metric: metric, value: value, unit: "score_0_100",
            source: .structuredSelfReport, protocol: protocolName, device: nil, measuredAt: measuredAt,
            importedAt: measuredAt, confidence: .low, metadata: metadata, supersedesID: nil,
            clientIdempotencyKey: UUID().uuidString)
    }

    private func result(_ data: DashboardData, through: String = "2026-10-06") throws -> FBEngineResult {
        FitnessBrainEngine.compute(try XCTUnwrap(FitnessBrainService.engineInput(from: data)), throughDate: through)
    }

    private func latest(_ data: DashboardData, through: String = "2026-10-06") throws -> FBSnapshot {
        try XCTUnwrap(result(data, through: through).snapshots.last)
    }

    private func engineInput(dayType: String, startingPoints: [String: Int]? = nil) throws -> FBEngineInput {
        var data = dashboard(dayType: dayType)
        data.profile?.avatarStartingPoints = startingPoints
        return try XCTUnwrap(FitnessBrainService.engineInput(from: data))
    }

    private func fbSession(_ id: String, date: String = "2026-10-05", deload: Bool = false) -> FBWorkoutSession {
        FBWorkoutSession(id: id, date: date, programDayID: dayID.uuidString.lowercased(), isDeload: deload,
                         isEventRecovery: false, completed: true, qualityScore: 1)
    }

    private func fbSet(_ movementID: String?, session: String, weight: Double? = 60, reps: Int? = 10,
                       duration: Int? = nil, exercise: String? = nil) -> FBWorkoutLog {
        var log = FBWorkoutLog(
            id: UUID().uuidString, sessionID: session, exerciseID: exercise,
            exerciseName: movementID ?? "Unlisted lift", weightKG: weight, skipped: false, overrideFlag: false,
            movementID: movementID, reps: reps, durationSeconds: duration)
        log.performedTypes = MovementTiming.performedWorkoutTypes(for: log)
        return log
    }

    private func scores(_ input: FBEngineInput, through: String = "2026-10-06") throws -> FBSnapshot {
        try XCTUnwrap(FitnessBrainEngine.compute(input, throughDate: through).snapshots.last)
    }

    func testCoachPlanWorkoutMovesTheAvatar() throws {
        var data = dashboard(dayType: "coach")
        let rested = try latest(data)
        let session = workout()
        data.workoutSessions = [session]
        data.workoutLogs = [set("barbell_back_squat", session: session.id)]
        XCTAssertGreaterThan(try latest(data).strengthLower, rested.strengthLower)
    }

    func testReplayedReceiptEarnsItsPointsOnce() throws {
        var data = dashboard()
        let first = workout()
        data.workoutSessions = [first]
        data.workoutLogs = [set("barbell_back_squat", session: first.id)]
        let once = try latest(data)
        let replay = workout(completedAt: "2026-10-05T09:00:07Z")
        data.workoutSessions.append(replay)
        data.workoutLogs.append(set("barbell_back_squat", session: replay.id))
        XCTAssertEqual(try latest(data), once)
        let evening = WorkoutSession(
            id: UUID(), userID: owner, date: first.date, programDayID: dayID, isLite: false, isDeload: false,
            isEventRecovery: false, completed: true, qualityScore: 1, startedAt: "2026-10-05T18:00:00Z",
            completedAt: "2026-10-05T19:00:00Z", notes: "Completed in tracked mode")
        data.workoutSessions.append(evening)
        data.workoutLogs.append(set("barbell_back_squat", session: evening.id))
        XCTAssertGreaterThan(try latest(data).strengthLower, once.strengthLower)
    }

    func testUnlinkedWatchRecordingOfAnAppWorkoutIsNotASecondWorkout() throws {
        var data = dashboard()
        let session = workout()
        data.workoutSessions = [session]
        data.workoutLogs = [set("barbell_back_squat", session: session.id)]
        func watch(_ start: String, _ end: String) -> ImportedActivity {
            ImportedActivity(
                id: UUID(), userID: owner, date: session.date, kind: "strength",
                activity: "Traditional Strength Training", durationMinutes: 56, source: "Apple Watch",
                healthKitWorkoutID: UUID(), startedAt: start, endedAt: end,
                sourceBundleIdentifier: "com.apple.health")
        }
        data.importedActivities = [watch("2026-10-05T08:02:00Z", "2026-10-05T08:58:00Z")]
        XCTAssertTrue(try XCTUnwrap(FitnessBrainService.engineInput(from: data)).importedActivities.isEmpty)
        data.importedActivities = [watch("2026-10-05T18:00:00Z", "2026-10-05T18:56:00Z")]
        XCTAssertEqual(try XCTUnwrap(FitnessBrainService.engineInput(from: data)).importedActivities.count, 1)
    }

    func testOneVO2ReadingStampedOnManyDaysAnchorsEnduranceOnce() throws {
        func metric(_ day: Int, _ vo2: Double) -> HealthMetric {
            HealthMetric(id: UUID(), userID: owner, date: String(format: "2026-10-%02d", day),
                         weightKG: nil, vo2Max: vo2, restingHeartRate: nil)
        }
        var once = dashboard()
        once.healthMetrics = [metric(2, 40)]
        var restamped = once
        restamped.healthMetrics += (3...6).map { metric($0, 40) }
        XCTAssertEqual(try latest(once).endurance, 52)
        XCTAssertEqual(try latest(restamped).endurance, 52)
        restamped.healthMetrics[4] = metric(6, 44)
        XCTAssertEqual(try latest(restamped).endurance, 55.7)
    }

    func testHealthReadingIsStoredOnTheDayItWasSampled() async throws {
        let plan = HealthTodayQueryPlan(
            weightKG: { nil },
            vo2Max: { HealthDatedValue(value: 40, day: "2026-10-01") },
            restingHeartRate: { HealthDatedValue(value: 52, day: "2026-10-06") },
            dietaryWater: { .unavailable }, steps: { nil }, activeEnergyKcal: { nil },
            exerciseMinutes: { nil }, sleepDurationHours: { nil }, heartRateVariabilityMS: { nil },
            workouts: { [] })
        let rows = try await plan.snapshot(date: "2026-10-06").metricRows(ownerID: owner, existing: [])
        XCTAssertEqual(rows.map(\.date), ["2026-10-01", "2026-10-06"])
        XCTAssertEqual(rows.map(\.vo2Max), [40, nil])
        XCTAssertEqual(rows.map(\.restingHeartRate), [nil, 52])
        let nextDay = try await plan.snapshot(date: "2026-10-07")
        XCTAssertTrue(nextDay.metricRows(ownerID: owner, existing: rows).isEmpty)
    }

    func testEveningCalibrationWestOfGreenwichBelongsToTheLocalDay() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let record = evidence(.cardioCapacityScore, value: 62, measuredAt: "2026-11-10T02:30:00Z")
        let anchors = FitnessBrainService.capacityCalibrationEvidence(
            from: [record], ownerID: owner, timeZone: losAngeles)
        XCTAssertEqual(anchors.map(\.measuredOn), ["2026-11-09"])
    }

    func testOnboardingAnswersOnSignupEveningDoNotAlterChosenStartingPoints() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var data = dashboard(baseline: "2026-11-09")
        data.profile?.avatarStartingPoints = AvatarStartingPoints.balanced
        data.fitnessEvidence = [evidence(.cardioCapacityScore, value: 30, measuredAt: "2026-11-10T02:30:00Z",
                                         protocolName: "apex_onboarding_pulse_v1")]
        let input = try XCTUnwrap(FitnessBrainService.engineInput(from: data, timeZone: losAngeles))
        XCTAssertTrue(input.capacityCalibrationEvidence.isEmpty)
    }

    func testScoresShowOnSignupDayWhenTheStoredBaselineIsAheadOfTheDeviceDate() throws {
        var data = dashboard(baseline: "2026-11-10")
        data.profile?.avatarStartingPoints = AvatarStartingPoints.balanced
        XCTAssertEqual(try result(data, through: "2026-11-09").publishableSnapshots.last?.overall, 50)
    }

    func testCalibrationDatedAheadOfTheDeviceDateAppliesToday() throws {
        var data = dashboard(baseline: "2026-11-01")
        data.profile?.avatarStartingPoints = AvatarStartingPoints.balanced
        var input = try XCTUnwrap(FitnessBrainService.engineInput(from: data))
        input.capacityCalibrationEvidence = [FBCapacityCalibrationEvidence(
            id: "ahead", userID: owner.uuidString.lowercased(), metric: .cardiorespiratory, value: 62,
            measuredOn: "2026-11-10", importedAt: "2026-11-10T01:00:00Z", coverage: 0.55, supersedesID: nil)]
        XCTAssertEqual(FitnessBrainEngine.compute(input, throughDate: "2026-11-09").snapshots.last?.endurance, 56.6)
    }

    func testNewProfileCarriesTheDeviceDateAsItsBaseline() throws {
        let body = try JSONEncoder().encode(ProfileCreationRequest(userID: owner, goal: "maintain"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["baseline_date"] as? String, Date().apexDateKey)
    }

    func testEasingAssistanceCountsAsProgress() throws {
        var input = try engineInput(dayType: "pull")
        input.exercises = [FBExerciseRef(id: "pull-up", programDayID: dayID.uuidString.lowercased())]
        input.workoutSessions = [fbSession("first", date: "2026-10-02"), fbSession("second")]
        input.workoutLogs = [fbSet(nil, session: "first", weight: -30, exercise: "pull-up"),
                             fbSet(nil, session: "second", weight: -30, exercise: "pull-up")]
        let level = try scores(input).strengthUpper
        input.workoutLogs[1].weightKG = -20
        XCTAssertGreaterThan(try scores(input).strengthUpper, level)
    }

    func testDeloadDayBanksItsJointCreditOnce() throws {
        var input = try engineInput(dayType: "push")
        input.workoutSessions = [fbSession("morning", deload: true)]
        let one = FitnessBrainEngine.compute(input, throughDate: "2026-10-06")
        input.workoutSessions.append(fbSession("evening", deload: true))
        let two = FitnessBrainEngine.compute(input, throughDate: "2026-10-06")
        XCTAssertEqual(two.synergies.filter { $0.kind == .deloadHonored }.count, 1)
        XCTAssertEqual(two.snapshots.last?.joint, one.snapshots.last?.joint)
    }

    func testWorkoutInAScheduledDeloadWeekEarnsTheDeloadCredit() throws {
        var data = dashboard(dayType: "push")
        let main = try XCTUnwrap(data.programs.first { $0.slug == "main" })
        data.programDays = [ProgramDay(id: dayID, userID: owner, programID: main.id, weekday: 1, name: "Day",
                                       dayType: "push", estimatedMinutes: 45, warmupNote: "", sortOrder: 0)]
        data.settings?.addons["training_protocol"] = .object(["start_date": .string("2026-09-07")])
        data.workoutSessions = [workout(date: "2026-09-30", completedAt: "2026-09-30T09:00:00Z"),
                                workout(date: "2026-10-07", completedAt: "2026-10-07T09:00:00Z")]
        let input = try XCTUnwrap(FitnessBrainService.engineInput(from: data))
        XCTAssertEqual(input.workoutSessions.map(\.isDeload), [true, false])
    }

    func testFullBodyDayCreditsEachBodyAreaItsMovementsTrained() throws {
        var input = try engineInput(dayType: "upper")
        let rested = try scores(input)
        input.workoutSessions = [fbSession("full")]
        input.workoutLogs = [fbSet("leg_press", session: "full"), fbSet("machine_chest_press", session: "full")]
        let trained = try scores(input)
        XCTAssertGreaterThan(trained.strengthLower, rested.strengthLower)
        XCTAssertGreaterThan(trained.strengthUpper, rested.strengthUpper)
    }

    func testLegPressIncreaseRaisesLowerBodyStrengthOnAnUpperTypedDay() throws {
        var input = try engineInput(dayType: "upper")
        input.exercises = [FBExerciseRef(id: "leg-press", programDayID: dayID.uuidString.lowercased())]
        input.workoutSessions = [fbSession("first", date: "2026-10-02"), fbSession("second")]
        input.workoutLogs = [fbSet("leg_press", session: "first", weight: 100, exercise: "leg-press"),
                             fbSet("leg_press", session: "second", weight: 100, exercise: "leg-press")]
        let level = try scores(input)
        input.workoutLogs[1].weightKG = 110
        let heavier = try scores(input)
        XCTAssertGreaterThan(heavier.strengthLower, level.strengthLower)
        XCTAssertEqual(heavier.strengthUpper, level.strengthUpper)
    }

    func testStrengthOnlyRecoveryTypedDayEarnsNoFlexibility() throws {
        var input = try engineInput(dayType: "fix")
        let rested = try scores(input)
        input.workoutSessions = [fbSession("capacity")]
        input.workoutLogs = [fbSet("lat_pulldown", session: "capacity"), fbSet("dead_bug", session: "capacity", weight: nil)]
        let trained = try scores(input)
        XCTAssertGreaterThan(trained.strengthUpper, rested.strengthUpper)
        XCTAssertEqual(trained.flexibility, rested.flexibility)
        XCTAssertEqual(trained.joint, rested.joint)
    }

    func testPlannedDayKeepsItsLabelForWorkTheAppCannotIdentify() throws {
        var input = try engineInput(dayType: "legs_a")
        let rested = try scores(input)
        input.workoutSessions = [fbSession("legs")]
        input.workoutLogs = [fbSet(nil, session: "legs"), fbSet("cat_cow", session: "legs", weight: nil, reps: nil, duration: 120)]
        let trained = try scores(input)
        XCTAssertGreaterThan(trained.strengthLower, rested.strengthLower)
        XCTAssertGreaterThan(trained.flexibility, rested.flexibility)
        input.workoutLogs = []
        XCTAssertGreaterThan(try scores(input).strengthLower, rested.strengthLower)
    }
}
