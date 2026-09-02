import XCTest
@testable import APEX

final class OrbitPrivacyArchiveTests: XCTestCase {
    func testArchiveFiltersEveryCollectionToTheRequestedOwner() throws {
        let owner = UUID()
        let other = UUID()
        let data = DashboardData(
            orbitShoes: [shoe(userID: owner, name: "Owner pair"), shoe(userID: other, name: "Other pair")]
        )

        let archive = OrbitPrivateArchive.ownerScoped(
            from: data,
            userID: owner,
            exportedAt: "2026-08-17T00:00:00Z"
        )

        XCTAssertEqual(archive.userID, owner)
        XCTAssertEqual(archive.shoes.map(\.name), ["Owner pair"])
        XCTAssertTrue(archive.routes.isEmpty)
        XCTAssertTrue(archive.runs.isEmpty)
    }

    func testArchiveUsesWebCompatibleSnakeCaseKeys() throws {
        let owner = UUID()
        let archive = OrbitPrivateArchive.ownerScoped(
            from: DashboardData(orbitShoes: [shoe(userID: owner, name: "Pair")]),
            userID: owner,
            exportedAt: "2026-08-17T00:00:00Z"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any]
        )

        XCTAssertEqual(object["user_id"] as? String, owner.uuidString.uppercased())
        XCTAssertNotNil(object["exported_at"])
        XCTAssertNotNil(object["campaign_sessions"])
    }

    private func shoe(userID: UUID, name: String) -> OrbitShoe {
        OrbitShoe(
            id: UUID(),
            userID: userID,
            name: name,
            brand: "APEX",
            firstUseDate: "2026-08-17",
            preferredSurfaces: ["road"],
            notes: "",
            archived: false,
            createdAt: "2026-08-17T00:00:00Z",
            updatedAt: "2026-08-17T00:00:00Z"
        )
    }
}

@MainActor
final class OrbitRunRecoveryOwnershipTests: XCTestCase {
    func testPausedDraftIsRecoverableOnlyForItsOwner() throws {
        let owner = UUID()
        let other = UUID()
        let manager = try makeManager()
        seedRecoverableRun(in: manager, ownerID: owner, state: .paused)

        XCTAssertTrue(manager.hasRecoverableRun(for: owner))
        XCTAssertFalse(manager.hasRecoverableRun(for: other))
        XCTAssertFalse(manager.hasRecoverableRun(for: nil))
    }

    func testRunningDraftCannotBeClaimedByAnotherAccount() throws {
        let owner = UUID()
        let other = UUID()
        let manager = try makeManager()
        seedRecoverableRun(in: manager, ownerID: owner, state: .running)

        manager.prepare(ownerID: other, mission: "Other account", routeID: nil)

        XCTAssertEqual(manager.draftOwnerID, owner)
        XCTAssertEqual(manager.draftMission, "Owner run")
        XCTAssertNil(manager.finish(for: other))
        XCTAssertNotNil(manager.finish(for: owner))
    }

    func testAccountBoundaryClearsMemoryButRetainsOwnersDraftForLaterRestore() throws {
        let owner = UUID()
        let other = UUID()
        let manager = try makeManager()
        seedRecoverableRun(in: manager, ownerID: owner, state: .paused)
        manager.persistForAppTransition()

        manager.releaseForAccountBoundary()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.draftOwnerID)
        XCTAssertTrue(manager.samples.isEmpty)
        manager.restoreDraft(for: other)
        XCTAssertFalse(manager.hasRecoverableRun(for: other))
        manager.restoreDraft(for: owner)
        XCTAssertTrue(manager.hasRecoverableRun(for: owner))
        XCTAssertEqual(manager.samples.count, 1)
    }

    func testDifferentOwnersKeepIndependentInterruptedDrafts() throws {
        let first = UUID()
        let second = UUID()
        let directory = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = OrbitLocationManager(draftDirectory: directory)

        seedRecoverableRun(in: manager, ownerID: first, state: .paused)
        manager.persistForAppTransition()
        manager.releaseForAccountBoundary()
        seedRecoverableRun(in: manager, ownerID: second, state: .paused)
        manager.persistForAppTransition()
        manager.releaseForAccountBoundary()

        manager.restoreDraft(for: first)
        XCTAssertTrue(manager.hasRecoverableRun(for: first))
        XCTAssertEqual(manager.draftMission, "Owner run")
        manager.releaseForAccountBoundary()
        manager.restoreDraft(for: second)
        XCTAssertTrue(manager.hasRecoverableRun(for: second))
    }

    func testAccountBoundaryCancelsPendingCountdownBeforeLocationTrackingStarts() async throws {
        let owner = UUID()
        let manager = try makeManager()
        manager.prepare(ownerID: owner, mission: "Owner run", routeID: nil)

        manager.beginCountdown(for: owner)
        manager.releaseForAccountBoundary()
        try await Task.sleep(for: .milliseconds(3_250))

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.draftOwnerID)
        XCTAssertNil(manager.startedAt)
        XCTAssertTrue(manager.samples.isEmpty)
    }

    private func makeManager() throws -> OrbitLocationManager {
        let directory = uniqueTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return OrbitLocationManager(draftDirectory: directory)
    }

    private func uniqueTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "apex-orbit-owner-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func seedRecoverableRun(
        in manager: OrbitLocationManager,
        ownerID: UUID,
        state: OrbitLocationManager.RunState
    ) {
        manager.draftOwnerID = ownerID
        manager.draftMission = "Owner run"
        manager.startedAt = Date(timeIntervalSince1970: 1_788_225_200)
        manager.samples = [
            OrbitLocationSample(
                latitude: 47.3769,
                longitude: 8.5417,
                altitude: 408,
                horizontalAccuracy: 4,
                timestamp: Date(timeIntervalSince1970: 1_788_225_205)
            )
        ]
        manager.distanceM = 125
        manager.movingSeconds = 58
        manager.state = state
    }
}

final class OrbitAccountOperationLeaseSourceTests: XCTestCase {
    func testOrbitMutationPipelineCarriesTheInitiatingAccountLeaseAcrossEverySuspension() throws {
        let source = try nativeSource("APEX/App/AppSession.swift")
        let methods = try [
            method(in: source, from: "func deleteAllOrbitData(", to: "func saveOrbitRun("),
            method(in: source, from: "func saveOrbitRun(", to: "func updateOrbitRunCheckIn("),
            method(in: source, from: "func updateOrbitRunCheckIn(", to: "func applyOrbitNutritionAdjustment("),
            method(in: source, from: "func applyOrbitNutritionAdjustment(", to: "func saveOrbitInduction("),
            method(in: source, from: "private func adaptCampaignAfterRun(", to: "private func integrateOrbitRun("),
            method(in: source, from: "private func integrateOrbitRun(", to: "private func saveCampaignBundle("),
            method(in: source, from: "private func saveCampaignBundle(", to: "func installRecoveryPlan(")
        ]

        for body in methods {
            XCTAssertTrue(
                body.contains("operation: AccountOperationLease"),
                "every Orbit mutation helper must carry the lease captured by the initiating account"
            )
            XCTAssertTrue(
                body.contains("requireCurrentAccountOperation(operation)")
                    || body.contains("accountOperationIsCurrent(operation)"),
                "every Orbit mutation helper must reject an expired account lease"
            )
        }

        let save = methods[1]
        let checkIn = methods[2]
        let nutrition = methods[3]
        let adapt = methods[4]

        XCTAssertTrue(save.contains("integrateOrbitRun(run, operation: operation)"))
        XCTAssertTrue(checkIn.contains("adaptCampaignAfterRun(updated, operation: operation)"))
        XCTAssertTrue(nutrition.contains("saveStructuredMeal(draft, operation: operation)"))
        XCTAssertTrue(adapt.contains("saveCampaignBundle(") && adapt.contains("operation: operation"))
    }

    func testEveryOrbitPersistenceCallUsesTheLeaseOwnerAndGeneration() throws {
        let source = try nativeSource("APEX/App/AppSession.swift")
        let persistedMethods = try [
            method(in: source, from: "func deleteAllOrbitData(", to: "func saveOrbitRun("),
            method(in: source, from: "func saveOrbitRun(", to: "func updateOrbitRunCheckIn("),
            method(in: source, from: "func updateOrbitRunCheckIn(", to: "func applyOrbitNutritionAdjustment("),
            method(in: source, from: "func applyOrbitNutritionAdjustment(", to: "func saveOrbitInduction("),
            method(in: source, from: "private func integrateOrbitRun(", to: "private func saveCampaignBundle("),
            method(in: source, from: "private func saveCampaignBundle(", to: "func installRecoveryPlan(")
        ]

        for body in persistedMethods {
            XCTAssertTrue(
                body.contains("ownerID: operation.ownerID"),
                "Orbit persistence must never infer the owner after an await"
            )
            XCTAssertTrue(
                body.contains("expectedAccountToken: operation.generation"),
                "Orbit persistence must reject a completion from an expired account generation"
            )
        }
    }

    func testOrbitEnergyAndDeloadInputsAreFilteredToTheLeaseOwner() throws {
        let source = try nativeSource("APEX/App/AppSession.swift")
        let integration = try method(
            in: source,
            from: "private func integrateOrbitRun(",
            to: "private func saveCampaignBundle("
        )
        XCTAssertTrue(integration.contains(
            "$0.userID == operation.ownerID && $0.date == run.localDate"
        ))

        let completion = try method(
            in: source,
            from: "func completeWorkout(",
            to: "func toggleDeload("
        )
        XCTAssertTrue(completion.contains(
            ".filter { $0.userID == ownerID }"
        ))
    }

    func testOrbitHomeCapturesTheLeaseBeforeLaunchingPermanentDeletion() throws {
        let source = try nativeSource("APEX/Features/Orbit/OrbitHomeView.swift")
        let action = try method(
            in: source,
            from: "Button(language.text(\"Delete permanently\")",
            to: "Button(language.text(\"Cancel\")"
        )

        try assertLeaseIsCapturedBeforeTask(in: action)
        XCTAssertTrue(action.contains("deleteAllOrbitData(operation: operation)"))
    }

    func testLiveRunCapturesTheLeaseBeforeLaunchingRunPersistence() throws {
        let source = try nativeSource("APEX/Features/Orbit/LiveRunView.swift")
        let action = try method(
            in: source,
            from: "Button(language.text(\"Finish and save\"))",
            to: "Button(language.text(\"Keep running\")"
        )

        try assertLeaseIsCapturedBeforeTask(in: action)
        XCTAssertTrue(action.contains("saveOrbitRun("))
        XCTAssertTrue(action.contains("operation: operation"))
    }

    func testRunDebriefCapturesSeparateLeasesBeforeLaunchingEitherMutation() throws {
        let source = try nativeSource("APEX/Features/Orbit/RunDebriefView.swift")
        let nutritionAction = try method(
            in: source,
            from: "if nutritionAdjustment.kcal > 0",
            to: ".disabled(nutritionApplied || isApplyingNutrition)"
        )
        let finishAction = try method(
            in: source,
            from: "TextField(language.text(\"Optional private note\")",
            to: ".disabled(isSaving)"
        )

        try assertLeaseIsCapturedBeforeTask(in: nutritionAction)
        try assertLeaseIsCapturedBeforeTask(in: finishAction)
        XCTAssertTrue(nutritionAction.contains("applyNutrition(operation: operation)"))
        XCTAssertTrue(finishAction.contains("saveAndFinish(operation: operation)"))
    }

    func testEveryRemainingOrbitMutationCarriesOwnerAndGenerationAcrossPersistence() throws {
        let source = try nativeSource("APEX/App/AppSession.swift")
        let methods = try [
            method(in: source, from: "func saveOrbitInduction(", to: "func completeOrbitInduction("),
            method(in: source, from: "func completeOrbitInduction(", to: "func markOrbitCampaignSessionMissed("),
            method(in: source, from: "func markOrbitCampaignSessionMissed(", to: "func chooseOrbitCampaignVersion("),
            method(in: source, from: "func chooseOrbitCampaignVersion(", to: "func saveOrbitRoute("),
            method(in: source, from: "func saveOrbitRoute(", to: "func updateOrbitRoute("),
            method(in: source, from: "func updateOrbitRoute(", to: "func duplicateOrbitRoute("),
            method(in: source, from: "func duplicateOrbitRoute(", to: "func saveOrbitShoe("),
            method(in: source, from: "func saveOrbitShoe(", to: "func archiveOrbitShoe("),
            method(in: source, from: "func archiveOrbitShoe(", to: "func saveOrbitSegment("),
            method(in: source, from: "func saveOrbitSegment(", to: "func saveOrbitPosterMetadata("),
            method(in: source, from: "func saveOrbitPosterMetadata(", to: "private func adaptCampaignAfterRun(")
        ]

        for body in methods {
            XCTAssertTrue(body.contains("operation: AccountOperationLease"))
            XCTAssertTrue(body.contains("requireCurrentAccountOperation(operation)"))
            XCTAssertTrue(
                body.contains("ownerID: operation.ownerID")
                    || body.contains("operation: operation"),
                "nested mutations must forward the initiating owner instead of resolving the active profile later"
            )
            XCTAssertTrue(
                body.contains("expectedAccountToken: operation.generation")
                    || body.contains("operation: operation"),
                "nested mutations must forward the initiating generation instead of accepting a delayed completion"
            )
        }
    }

    func testRemainingOrbitViewsCaptureLeaseBeforeLaunchingMutationTasks() throws {
        let expectations: [(String, Int, Int)] = [
            ("APEX/Features/Orbit/MarathonInductionView.swift", 1, 2),
            ("APEX/Features/Orbit/MarathonCampaignView.swift", 3, 3),
            ("APEX/Features/Orbit/ManualRouteEditorView.swift", 1, 1),
            ("APEX/Features/Orbit/RoutePlannerView.swift", 3, 3),
            ("APEX/Features/Orbit/OrbitLibraryView.swift", 5, 5),
            ("APEX/Features/Orbit/RunningShoesView.swift", 2, 2),
            ("APEX/Features/Orbit/OrbitRoutePosterView.swift", 1, 1)
        ]

        for (path, captureCount, forwardCount) in expectations {
            let source = try nativeSource(path)
            XCTAssertGreaterThanOrEqual(
                source.components(separatedBy: "guard let operation = session.accountOperationLease()").count - 1,
                captureCount,
                "\(path) must capture each mutation lease synchronously before starting its Task"
            )
            XCTAssertGreaterThanOrEqual(
                source.components(separatedBy: "operation: operation").count - 1,
                forwardCount,
                "\(path) must forward each captured lease to the mutation"
            )
        }
    }

    func testRouteGenerationRetainsItsInitiatingAccountAcrossTheAsyncEngineCall() throws {
        let source = try nativeSource("APEX/Features/Orbit/RoutePlannerView.swift")
        let action = try method(
            in: source,
            from: "Toggle(language.text(\"Prefer simpler navigation\")",
            to: "HStack(spacing: 10)"
        )
        let generation = try method(
            in: source,
            from: "private func generate(",
            to: "private func save("
        )

        try assertLeaseIsCapturedBeforeTask(in: action)
        XCTAssertTrue(action.contains("generate(operation: operation)"))
        XCTAssertTrue(generation.contains("operation: AccountOperationLease"))
        XCTAssertGreaterThanOrEqual(
            generation.components(separatedBy: "session.accountOperationIsCurrent(operation)").count - 1,
            3,
            "generation must reject an expired lease before work, after the route engine returns, and before publishing an error"
        )
        XCTAssertTrue(generation.contains("catch is CancellationError"))
        XCTAssertFalse(generation.contains("defer { isGenerating = false }"))
    }

    func testMarathonInductionReloadsOnlyTheCurrentOwnersDraftAndProgramme() throws {
        let source = try nativeSource("APEX/Features/Orbit/MarathonInductionView.swift")
        let load = try method(
            in: source,
            from: "private func loadExisting(",
            to: "private func next("
        )

        XCTAssertTrue(source.contains(".task(id: session.profile?.userID)"))
        XCTAssertTrue(load.contains("guard loadedOwnerID != ownerID else { return }"))
        XCTAssertTrue(load.contains("resetDraft()"))
        XCTAssertTrue(load.contains("$0.userID == ownerID"))
        XCTAssertTrue(load.contains("activeProgramDays(in: session.data, userID: ownerID)"))
    }

    func testOrbitCountdownIsCancelledAndOwnerValidatedAtAnAccountBoundary() throws {
        let source = try nativeSource("APEX/Features/Orbit/OrbitLocationManager.swift")
        let countdown = try method(in: source, from: "func beginCountdown(", to: "func startRun(")
        let boundary = try method(in: source, from: "func releaseForAccountBoundary(", to: "func persistForAppTransition(")

        XCTAssertTrue(countdown.contains("countdownTask"))
        XCTAssertTrue(countdown.contains("Task.checkCancellation()"))
        XCTAssertTrue(countdown.contains("draftOwnerID == ownerID"))
        XCTAssertTrue(boundary.contains("countdownTask?.cancel()"))
    }

    private func nativeSource(_ relativePath: String) throws -> String {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: nativeRoot.appending(path: relativePath))
    }

    private func method(
        in source: String,
        from startToken: String,
        to endToken: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startToken))
        let end = try XCTUnwrap(source.range(of: endToken, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func assertLeaseIsCapturedBeforeTask(
        in action: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let lease = try XCTUnwrap(
            action.range(of: "guard let operation = session.accountOperationLease()"),
            file: file,
            line: line
        )
        let task = try XCTUnwrap(action.range(of: "Task {"), file: file, line: line)
        XCTAssertLessThan(
            action.distance(from: action.startIndex, to: lease.lowerBound),
            action.distance(from: action.startIndex, to: task.lowerBound),
            "the account lease must be captured synchronously before the unstructured task can adopt another account",
            file: file,
            line: line
        )
    }
}

final class SupabaseServiceReliabilityTests: XCTestCase {
    func testRealtimeSubscriptionsAreTableScopedAndIsolatedToCurrentUser() {
        let currentUser = UUID()
        let otherUser = UUID()
        let subscriptions = SupabaseService.realtimeSubscriptions(userID: currentUser)

        XCTAssertFalse(subscriptions.isEmpty)
        XCTAssertEqual(Set(subscriptions.map(\.table)).count, subscriptions.count)
        XCTAssertTrue(subscriptions.allSatisfy { !$0.table.isEmpty })
        XCTAssertTrue(subscriptions.allSatisfy { $0.filterColumn == "user_id" })
        XCTAssertTrue(subscriptions.allSatisfy { $0.filterValue == currentUser })
        XCTAssertFalse(subscriptions.contains { $0.filterValue == otherUser })
        XCTAssertTrue(subscriptions.contains { $0.table == "daily_logs" })
        XCTAssertFalse(subscriptions.contains { $0.table == "activity_types" })
        XCTAssertFalse(subscriptions.contains { $0.table == "foods" })
    }
}
