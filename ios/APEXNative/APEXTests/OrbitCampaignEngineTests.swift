import XCTest
@testable import APEX

final class OrbitCampaignEngineTests: XCTestCase {
    func testBeginnerReceivesFoundationInsteadOfCompressedTwelveWeekPlan() {
        var answers = completeAnswers(raceDate: "2027-06-01")
        answers["running_frequency"] = .string("one")
        answers["weekly_distance"] = .string("under_10")
        answers["longest_run"] = .string("under_5")
        answers["consistency"] = .string("under_month")

        let result = OrbitCampaignEngine.assess(answers, today: date("2026-08-16"))

        XCTAssertEqual(result.outcome, "foundation")
        XCTAssertFalse(result.credibleBase)
        XCTAssertTrue(result.reason.contains("Foundation to First Marathon"))
    }

    func testCredibleBaseCanEnterSpecificCampaign() {
        let result = OrbitCampaignEngine.assess(
            completeAnswers(raceDate: "2027-02-01"),
            today: date("2026-08-16")
        )

        XCTAssertEqual(result.outcome, "ready")
        XCTAssertTrue(result.credibleBase)
    }

    func testConcerningCurrentResponseRecommendsProfessionalReviewWithoutDiagnosis() {
        var answers = completeAnswers(raceDate: "2027-02-01")
        answers["chest_discomfort"] = .bool(true)

        let result = OrbitCampaignEngine.assess(answers, today: date("2026-08-16"))

        XCTAssertEqual(result.outcome, "professional_review")
        XCTAssertTrue(result.reason.contains("professional review"))
        XCTAssertFalse(result.reason.lowercased().contains("diagnos"))
    }

    func testRaceTooCloseIsExplainedRatherThanCompressed() {
        let result = OrbitCampaignEngine.assess(
            completeAnswers(raceDate: "2026-09-15"),
            today: date("2026-08-16")
        )

        XCTAssertEqual(result.outcome, "more_information")
        XCTAssertFalse(result.timelineWarning.isEmpty)
    }

    func testGeneratedHybridCampaignCoordinatesDemandingRunsAroundLegDays() {
        let userID = UUID()
        let induction = OrbitInduction(
            id: UUID(), userID: userID,
            answers: completeAnswers(raceDate: "2027-02-01"),
            currentStep: 24, completed: true, outcome: "ready", outcomeReason: "",
            createdAt: "2026-08-16T00:00:00Z", updatedAt: "2026-08-16T00:00:00Z"
        )
        let programID = UUID()
        let legs = [
            programDay(userID: userID, programID: programID, weekday: 1, type: "legs_a"),
            programDay(userID: userID, programID: programID, weekday: 5, type: "legs_b")
        ]

        let result = OrbitCampaignEngine.createCampaign(
            induction: induction,
            programDays: legs,
            events: [],
            today: date("2026-08-16")
        )

        XCTAssertEqual(result.campaign.family, "hybrid")
        XCTAssertFalse(result.sessions.isEmpty)
        let demandingWeekdays = result.sessions
            .filter {
                $0.adapted["demanding"]?.boolValue == true
                    && $0.adapted["mission"]?.stringValue != "performance_test"
            }
            .compactMap { ISO8601DateFormatter.apexDateOnly.date(from: $0.date) }
            .map { Calendar.current.component(.weekday, from: $0) == 1 ? 0 : Calendar.current.component(.weekday, from: $0) - 1 }
        XCTAssertFalse(demandingWeekdays.contains(1))
        XCTAssertFalse(demandingWeekdays.contains(5))
    }

    private func completeAnswers(raceDate: String) -> [String: JSONValue] {
        var answers = OrbitCampaignEngine.emptyAnswers
        let values = [
            "race_name": "Zurich Marathon", "race_date": raceDate, "race_goal": "finish_comfortably",
            "course_profile": "rolling", "course_surface": "road", "climate_familiar": "yes",
            "running_frequency": "four", "weekly_distance": "20_35", "longest_run": "10_15",
            "consistency": "over_six_months", "race_experience": "half", "marathon_experience": "never",
            "structured_plan": "completed_one", "running_style": "continuous", "available_days": "four",
            "long_run_day": "sunday", "previous_issue": "none", "previous_surgery": "no",
            "issue_status": "resolved", "medication": "none"
        ]
        for (key, value) in values { answers[key] = .string(value) }
        answers["strength_days_per_week"] = .number(2)
        return answers
    }

    private func programDay(userID: UUID, programID: UUID, weekday: Int, type: String) -> ProgramDay {
        ProgramDay(
            id: UUID(), userID: userID, programID: programID,
            weekday: weekday, name: type, dayType: type,
            estimatedMinutes: 45, warmupNote: "", sortOrder: weekday
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter.apexDateOnly.date(from: value)!
    }
}
