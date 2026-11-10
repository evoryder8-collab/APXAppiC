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
}
