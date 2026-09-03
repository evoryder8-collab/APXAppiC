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

    func testCoachRosterRequestGateOnlyAcceptsTheLatestSameAccountSearch() {
        var gate = CoachRosterRequestGate()

        let older = gate.begin(query: "ju")
        let newer = gate.begin(query: "june")

        XCTAssertEqual(older.query, "ju")
        XCTAssertEqual(newer.query, "june")
        XCTAssertFalse(gate.accepts(older))
        XCTAssertTrue(gate.accepts(newer))
    }

    /// AppSession currently hard-wires its remote coach service, so a suspended
    /// request cannot be driven deterministically from this target. Keep the
    /// mutation boundary explicit until that service becomes injectable: the
    /// response must be validated against both the initiating owner and account
    /// generation before it is published into observable state.
    func testCoachContextMutationsRejectLateResultsFromAnotherAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        func body(_ start: String, before end: String) throws -> String {
            let lower = try XCTUnwrap(source.range(of: start))
            let upper = try XCTUnwrap(source.range(of: end, range: lower.upperBound..<source.endIndex))
            return String(source[lower.lowerBound..<upper.lowerBound])
        }
        func assertGuardedMutation(
            _ mutation: String,
            remoteCall: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let leaseArgument = try XCTUnwrap(
                mutation.range(of: "operation: AccountOperationLease"),
                "require the account lease captured synchronously by the coach action",
                file: file,
                line: line
            )
            let request = try XCTUnwrap(
                mutation.range(of: "context = try await service.\(remoteCall)"),
                "hold the remote result locally until ownership is revalidated",
                file: file,
                line: line
            )
            let revalidation = try XCTUnwrap(
                mutation.range(
                    of: "try requireCurrentAccountOperation(operation)",
                    range: request.upperBound..<mutation.endIndex
                ),
                "reject a completion whose owner or account generation changed",
                file: file,
                line: line
            )
            let publication = try XCTUnwrap(
                mutation.range(of: "coachContext = context"),
                "publish only the revalidated coach context",
                file: file,
                line: line
            )

            XCTAssertLessThan(leaseArgument.lowerBound, request.lowerBound, file: file, line: line)
            XCTAssertLessThan(request.lowerBound, revalidation.lowerBound, file: file, line: line)
            XCTAssertLessThan(revalidation.lowerBound, publication.lowerBound, file: file, line: line)
            XCTAssertTrue(
                mutation.contains("catch {\n                try requireCurrentAccountOperation(operation)"),
                "a late service failure must be converted to cancellation after an account switch",
                file: file,
                line: line
            )
        }

        let accept = try body(
            "func acceptCoachInvitation(",
            before: "func loadCoachClientOverview("
        )
        try assertGuardedMutation(accept, remoteCall: "acceptCoachInvitation(")
        let entitlementResolution = try XCTUnwrap(
            accept.range(of: "refreshAccountAccess(expectedUserID: operation.ownerID)")
        )
        let acceptedContext = try XCTUnwrap(accept.range(of: "coachContext = context"))
        XCTAssertLessThan(acceptedContext.lowerBound, entitlementResolution.lowerBound)

        let update = try body(
            "func updateCoachScopes(",
            before: "func endCoachRelationship("
        )
        try assertGuardedMutation(update, remoteCall: "updateCoachScopes(")

        let view = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Coach/CoachPlanView.swift")
        )
        XCTAssertGreaterThanOrEqual(
            view.components(separatedBy: "guard let operation = session.accountOperationLease() else { return }").count - 1,
            6,
            "every coach action must capture its owner and generation before creating an unstructured Task"
        )
        XCTAssertTrue(view.contains("catch is CancellationError"))
        XCTAssertTrue(view.contains("session.accountOperationIsCurrent(operation)"))
    }

    func testCoachWorkspaceRequestsCannotOutliveTheirInitiatingAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let view = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Coach/CoachWorkspaceView.swift")
        )

        func body(_ start: String, before end: String) throws -> String {
            let lower = try XCTUnwrap(session.range(of: start))
            let upper = try XCTUnwrap(
                session.range(of: end, range: lower.upperBound..<session.endIndex)
            )
            return String(session[lower.lowerBound..<upper.lowerBound])
        }

        let requests = [
            ("func loadCoachRoster(", "func createCoachInvitation(", "service.loadCoachRoster"),
            ("func createCoachInvitation(", "func previewCoachInvitation(", "service.createCoachInvitation"),
            ("func loadCoachClientOverview(", "func saveCoachPlan(", "service.loadCoachClientOverview"),
            ("func saveCoachPlan(", "func publishCoachPlan(", "service.saveCoachPlan"),
            ("func publishCoachPlan(", "func acknowledgeCoachPlan(", "service.saveCoachPlan"),
        ]
        for (start, end, remoteCall) in requests {
            let request = try body(start, before: end)
            let lease = try XCTUnwrap(request.range(of: "operation: AccountOperationLease"))
            let preflight = try XCTUnwrap(request.range(of: "try requireCurrentAccountOperation(operation)"))
            let remote = try XCTUnwrap(request.range(of: remoteCall))
            let revalidation = try XCTUnwrap(
                request.range(
                    of: "try requireCurrentAccountOperation(operation)",
                    range: remote.upperBound..<request.endIndex
                )
            )
            XCTAssertLessThan(lease.lowerBound, preflight.lowerBound)
            XCTAssertLessThan(preflight.lowerBound, remote.lowerBound)
            XCTAssertLessThan(remote.lowerBound, revalidation.lowerBound)
            XCTAssertTrue(
                request.contains("catch {\n            try requireCurrentAccountOperation(operation)"),
                "late failures from \(remoteCall) must become cancellation after an account switch"
            )
        }

        XCTAssertGreaterThanOrEqual(
            view.components(separatedBy: "guard let operation = session.accountOperationLease() else { return }").count - 1,
            7,
            "search, refresh, initial load, invitation creation, client load, draft save and publish must capture a lease before work starts"
        )
        for call in [
            "reload(operation: operation)",
            "createInvite(operation: operation)",
            "load(operation: operation)",
            "save(publish: false, operation: operation)",
            "save(publish: true, operation: operation)",
        ] {
            XCTAssertTrue(view.contains(call), "missing account-bound coach action: \(call)")
        }
        XCTAssertTrue(view.contains("catch is CancellationError"))
        XCTAssertTrue(view.contains("session.accountOperationIsCurrent(operation)"))
    }
}
