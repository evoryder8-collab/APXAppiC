import XCTest
@testable import APEX

final class RecoveryEvidenceTests: XCTestCase {
    private let owner = UUID(uuidString: "33333333-4444-4555-8666-777777777777")!

    private func day(_ dayType: String) -> ProgramDay {
        ProgramDay(id: UUID(), userID: owner, programID: UUID(), weekday: 4, name: "Day",
                   dayType: dayType, estimatedMinutes: 20, warmupNote: "", sortOrder: 0)
    }

    private func session(_ day: ProgramDay, date: String) -> WorkoutSession {
        WorkoutSession(id: UUID(), userID: owner, date: date, programDayID: day.id, isLite: false,
                       isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
                       startedAt: "\(date)T08:00:00Z", completedAt: "\(date)T08:20:00Z", notes: "")
    }

    private func row(_ name: String, in session: WorkoutSession, movementID: String? = nil,
                     weight: Double? = nil, reps: Int? = 1, skipped: Bool = false) -> WorkoutLog {
        WorkoutLog(id: UUID(), userID: owner, sessionID: session.id, exerciseID: nil, exerciseName: name,
                   setNumber: 1, weightKG: weight, reps: skipped ? nil : reps, rir: nil, movementID: movementID,
                   skipped: skipped, overrideFlag: false, createdAt: "\(session.date)T08:10:00Z")
    }

    func testCompletedRecoveryDayCountsAsMobilityInTheNinetyDayProfile() {
        var data = DashboardData.empty
        let fix = day("fix"), push = day("push")
        let circuit = session(fix, date: "2026-11-05")
        let skippedCircuit = session(fix, date: "2026-11-04")
        let liftsOnAFixDay = session(fix, date: "2026-11-03")
        let unnamedLift = session(push, date: "2026-11-02")
        data.programDays = [fix, push]
        data.workoutSessions = [circuit, skippedCircuit, liftsOnAFixDay, unnamedLift]
        data.workoutLogs = [
            row("Posture and Wrist Circuit", in: circuit),
            row("Posture and Wrist Circuit", in: skippedCircuit, skipped: true),
            row("Barbell Back Squat", in: liftsOnAFixDay, movementID: "barbell_back_squat", weight: 60, reps: 8),
            row("Garage complex", in: unnamedLift, reps: 12),
        ]

        let profile = TrainingProfile90.summarize(ownerID: owner, data: data, through: "2026-11-06")

        XCTAssertEqual(profile.counts[.mobility], 1, "the finished circuit is the recovery day it was planned as")
        XCTAssertEqual(profile.counts[.resistance], 2, "identified lifts keep their own kind; unnamed work takes its day's")
        XCTAssertEqual(profile.classifiedWorkouts, 3, "a session where everything was skipped is not a workout")
    }
}
