import XCTest
@testable import APEX

final class CoachPlatformTests: XCTestCase {
    private func completePlan() -> CoachPlanDraft {
        CoachPlanDraft(
            title: "Foundation strength",
            objective: "Build pain-free strength and repeatable training rhythm.",
            coachNote: "Keep two good reps in reserve during the first week.",
            reviewDate: "2026-09-15",
            checklist: CoachPlanChecklist(
                nutrition: true,
                workouts: true,
                supplements: true,
                hydration: true,
                schedule: true,
                reviewDate: true
            ),
            sessions: [
                CoachSessionTemplate(
                    id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                    weekday: 1,
                    name: "Monday foundation",
                    sessionMode: .guided,
                    estimatedMinutes: 38,
                    warmupNote: "Five minutes of pain-free joint preparation.",
                    exercises: [
                        CoachExerciseTemplate(
                            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                            movementID: "bodyweight-squat",
                            name: "Bodyweight squat",
                            sets: 3,
                            targetMin: 10,
                            targetMax: 12,
                            unit: "reps",
                            perSide: false,
                            restSeconds: 75,
                            tempoUpSeconds: 1,
                            tempoDownSeconds: 2,
                            tempoPauseSeconds: 0,
                            notes: "Stop if knee pain appears.",
                            optional: false,
                            groupID: nil,
                            groupPosition: nil
                        )
                    ]
                )
            ]
        )
    }

    func testSponsoredPolicyLocksPlanCreationButKeepsConsentedSurfaces() {
        let policy = CoachClientPolicy.resolve(
            relationshipStatus: .active,
            seatState: .active,
            consentedScopes: [.nutrition, .workouts, .avatar],
            individualAccess: false
        )
        XCTAssertTrue(policy.canUseSponsoredApp)
        XCTAssertTrue(policy.canFollowCoachPlan)
        XCTAssertFalse(policy.canCreateCustomWorkouts)
        XCTAssertFalse(policy.canRebuildFitnessPlan)
        XCTAssertFalse(policy.canUseOrbit)
        XCTAssertTrue(policy.canUseNutrition)
        XCTAssertTrue(policy.canUseAvatar)
        XCTAssertFalse(policy.canViewVisualProgress)
    }

    func testGraceIsReadOnlyAndIndividualAccessSurvivesIt() {
        let grace = CoachClientPolicy.resolve(
            relationshipStatus: .grace,
            seatState: .grace,
            consentedScopes: [.workouts],
            individualAccess: false
        )
        XCTAssertFalse(grace.canUseSponsoredApp)
        XCTAssertFalse(grace.canFollowCoachPlan)
        XCTAssertTrue(grace.coachPlanReadOnly)

        let subscribed = CoachClientPolicy.resolve(
            relationshipStatus: .grace,
            seatState: .grace,
            consentedScopes: [.workouts],
            individualAccess: true
        )
        XCTAssertTrue(subscribed.canCreateCustomWorkouts)
        XCTAssertTrue(subscribed.canRebuildFitnessPlan)
    }

    func testTypedPlanValidationMatchesPublicationRules() {
        let valid = CoachPlanValidator.validate(
            completePlan(),
            publishing: true,
            knownMovementIDs: ["bodyweight-squat"]
        )
        XCTAssertTrue(valid.publishable)
        XCTAssertTrue(valid.issues.isEmpty)

        var invalid = completePlan()
        invalid.checklist.hydration = false
        invalid.sessions[0].weekday = 9
        invalid.sessions[0].exercises[0].sets = 99
        invalid.sessions[0].exercises[0].movementID = "invented-movement"
        invalid.sessions[0].exercises[0].targetMin = 20
        invalid.sessions[0].exercises[0].targetMax = 4
        let result = CoachPlanValidator.validate(
            invalid,
            publishing: true,
            knownMovementIDs: ["bodyweight-squat"]
        )
        XCTAssertFalse(result.publishable)
        XCTAssertTrue(result.issues.contains { $0.code == .checklist })
        XCTAssertTrue(result.issues.contains { $0.code == .weekday })
        XCTAssertTrue(result.issues.contains { $0.code == .sets })
        XCTAssertTrue(result.issues.contains { $0.code == .movement })
        XCTAssertTrue(result.issues.contains { $0.code == .targetOrder })
    }

    func testCoachContextDecodesAccountScopedServerShape() throws {
        let payload = Data("""
        {
          "coach":{"status":"development","display_name":"Constantine","seat_limit":10,"active_seats":2},
          "sponsorship":{"relationship_id":"33333333-3333-4333-8333-333333333333","coach_display_name":"Constantine","relationship_status":"active","seat_state":"active","offered_scopes":["nutrition","workouts","recovery","avatar"],"consented_scopes":["nutrition","workouts","avatar"],"grace_ends_at":null},
          "current_plan":{"id":"44444444-4444-4444-8444-444444444444","relationship_id":"33333333-3333-4333-8333-333333333333","version":2,"status":"published","title":"Foundation strength","objective":"Build rhythm.","coach_note":"","review_date":"2026-09-15","checklist":{"nutrition":true,"workouts":true,"supplements":true,"hydration":true,"schedule":true,"review_date":true},"plan":{"title":"Foundation strength","objective":"Build rhythm.","coach_note":"","review_date":"2026-09-15","checklist":{"nutrition":true,"workouts":true,"supplements":true,"hydration":true,"schedule":true,"review_date":true},"sessions":[]},"published_at":"2026-09-01T08:00:00Z","acknowledged_at":null,"activated_at":null},
          "capabilities":{"coach_workspace":true,"sponsored_client":true}
        }
        """.utf8)
        let context = try JSONDecoder().decode(CoachAccountContext.self, from: payload)
        XCTAssertEqual(context.coach?.status, .development)
        XCTAssertEqual(context.sponsorship?.offeredScopes, [.nutrition, .workouts, .recovery, .avatar])
        XCTAssertEqual(context.sponsorship?.consentedScopes, [.nutrition, .workouts, .avatar])
        XCTAssertEqual(context.currentPlan?.version, 2)
        XCTAssertTrue(context.capabilities.coachWorkspace)
        XCTAssertTrue(context.capabilities.sponsoredClient)
    }

    func testRosterAttentionNeverInventsHealthJudgements() {
        XCTAssertEqual(
            CoachRosterAttention.resolve(
                relationshipStatus: .active,
                planVersion: 4,
                planPublishedAt: "2026-08-30T08:00:00Z",
                acknowledgedAt: nil,
                reviewDate: "2026-09-05",
                today: "2026-09-01"
            ),
            [.reviewDue, .awaitingAcknowledgement]
        )
    }

    func testSimulatorCoachFixturesCoverBothSidesWithoutNetworkState() {
        let workspace = APEXDebugFixture.coachWorkspaceContext()
        XCTAssertTrue(workspace.capabilities.coachWorkspace)
        XCTAssertEqual(workspace.coach?.activeSeats, 2)

        let client = APEXDebugFixture.coachPlanContext()
        XCTAssertTrue(client.capabilities.sponsoredClient)
        XCTAssertEqual(client.currentPlan?.version, 2)
        XCTAssertEqual(client.currentPlan?.plan.sessions.first?.exercises.first?.movementID, "bodyweight-squat")
        XCTAssertTrue(client.sponsorship?.consentedScopes.contains(.nutrition) == true)
        XCTAssertFalse(client.sponsorship?.consentedScopes.contains(.visualProgress) == true)
        XCTAssertEqual(APEXDebugFixture.coachRoster().first?.displayName, "June")
        XCTAssertEqual(APEXDebugFixture.coachClientOverview()?.workouts?.completed30Days, 12)
    }
}
