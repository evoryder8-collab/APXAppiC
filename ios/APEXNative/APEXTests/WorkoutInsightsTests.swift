import XCTest
@testable import APEX

final class WorkoutInsightsTests: XCTestCase {
    private let ownerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func session(
        id: UUID = UUID(),
        ownerID: UUID? = nil,
        date: String = "2026-08-29",
        completed: Bool = true,
        startedAt: String? = "2026-08-29T10:00:00.000Z",
        completedAt: String? = "2026-08-29T11:00:00.000Z"
    ) -> WorkoutSession {
        WorkoutSession(
            id: id,
            userID: ownerID ?? self.ownerID,
            date: date,
            programDayID: UUID(),
            isLite: false,
            isDeload: false,
            isEventRecovery: false,
            completed: completed,
            qualityScore: 1,
            startedAt: startedAt,
            completedAt: completedAt,
            notes: ""
        )
    }

    private func log(
        sessionID: UUID,
        ownerID: UUID? = nil,
        set: Int = 1,
        weight: Double? = 50,
        reps: Int? = 10,
        duration: Int? = nil,
        skipped: Bool = false
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            userID: ownerID ?? self.ownerID,
            sessionID: sessionID,
            exerciseID: nil,
            exerciseName: "Squat",
            setNumber: set,
            weightKG: weight,
            reps: reps,
            rir: nil,
            durationSeconds: duration,
            skipped: skipped,
            overrideFlag: false,
            createdAt: "2026-08-29T10:15:00.000Z"
        )
    }

    private func activity(
        id: UUID = UUID(),
        ownerID: UUID? = nil,
        date: String = "2026-08-29",
        duration: Int = 58,
        energy: Double? = nil,
        distance: Double? = nil,
        bundleID: String = "com.apple.health",
        linkedSessionID: UUID? = nil,
        hiddenAt: String? = nil
    ) -> ImportedActivity {
        ImportedActivity(
            id: id,
            userID: ownerID ?? self.ownerID,
            date: date,
            kind: "strength",
            activity: "Traditional Strength Training",
            durationMinutes: duration,
            source: "Apple Watch",
            distanceKM: distance,
            activeEnergyKcal: energy,
            sourceBundleIdentifier: bundleID,
            apexWorkoutSessionID: linkedSessionID,
            hiddenAt: hiddenAt
        )
    }

    func testLinkedWearableEvidenceReplacesDurationWithoutBecomingASecondWorkout() {
        let sessionID = UUID()
        let summary = WorkoutInsights.summarize(
            ownerID: ownerID,
            from: "2026-08-23",
            to: "2026-08-29",
            sessions: [session(id: sessionID)],
            logs: [
                log(sessionID: sessionID),
                log(sessionID: sessionID, set: 2, weight: 60, reps: 5),
            ],
            importedActivities: [activity(energy: 420, distance: 1.2, linkedSessionID: sessionID)]
        )

        XCTAssertEqual(summary.workouts, 1)
        XCTAssertEqual(summary.activeDays, 1)
        XCTAssertEqual(summary.durationMinutes, 58)
        XCTAssertEqual(summary.activeEnergyKcal, 420)
        XCTAssertEqual(summary.sets, 2)
        XCTAssertEqual(summary.reps, 15)
        XCTAssertEqual(summary.volumeKG, 800)
        XCTAssertEqual(summary.distanceKM, 1.2)
    }

    func testOnlyOwnedVisibleRangeFactsContribute() {
        let sessionID = UUID()
        let summary = WorkoutInsights.summarize(
            ownerID: ownerID,
            from: "2026-08-23",
            to: "2026-08-29",
            sessions: [
                session(id: sessionID),
                session(ownerID: otherID),
                session(completed: false),
            ],
            logs: [
                log(sessionID: sessionID),
                log(sessionID: sessionID, skipped: true),
                log(sessionID: sessionID, ownerID: otherID),
            ],
            importedActivities: [
                activity(energy: 200),
                activity(energy: 900, hiddenAt: "2026-08-29T12:00:00.000Z"),
                activity(energy: 900, bundleID: "ch.apexperformance.APEX.watchkitapp"),
                activity(ownerID: otherID, energy: 900),
                activity(date: "2026-08-22", energy: 900),
            ]
        )

        XCTAssertEqual(summary.workouts, 2)
        XCTAssertEqual(summary.activeEnergyKcal, 200)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.reps, 10)
        XCTAssertEqual(summary.volumeKG, 500)
    }

    func testMissingFactsRemainNilAndTimedEffortProvidesOnlyRecordedDuration() {
        let sessionID = UUID()
        let summary = WorkoutInsights.summarize(
            ownerID: ownerID,
            from: "2026-08-29",
            to: "2026-08-29",
            sessions: [session(id: sessionID, startedAt: nil, completedAt: nil)],
            logs: [log(sessionID: sessionID, weight: nil, reps: nil, duration: 90)],
            importedActivities: []
        )

        XCTAssertNil(summary.activeEnergyKcal)
        XCTAssertNil(summary.distanceKM)
        XCTAssertNil(summary.volumeKG)
        XCTAssertEqual(summary.durationMinutes, 2)
    }

    func testAnniversaryNeedsSelectedRangeAndActualEvidenceTenure() {
        XCTAssertEqual(WorkoutInsights.anniversaryYears(oldestEvidenceDate: "2016-08-29", from: "2016-08-29", to: "2026-08-29"), 10)
        XCTAssertEqual(WorkoutInsights.anniversaryYears(oldestEvidenceDate: "2021-08-29", from: "2021-08-29", to: "2026-08-29"), 5)
        XCTAssertEqual(WorkoutInsights.anniversaryYears(oldestEvidenceDate: "2025-08-29", from: "2025-08-29", to: "2026-08-29"), 1)
        XCTAssertNil(WorkoutInsights.anniversaryYears(oldestEvidenceDate: "2016-08-29", from: "2026-08-22", to: "2026-08-29"))
        XCTAssertNil(WorkoutInsights.anniversaryYears(oldestEvidenceDate: "2026-01-01", from: "2025-08-29", to: "2026-08-29"))
    }
}
