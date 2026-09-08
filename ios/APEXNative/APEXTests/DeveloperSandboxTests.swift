import XCTest
@testable import APEX

@MainActor
final class DeveloperSandboxTests: XCTestCase {
    func testSandboxConstructionDoesNotReplaceRealEntitlementOwner() async throws {
        let entitlementOwner = EntitlementStore.shared.resolvedUserID
        let first = AppSession(developerSandboxRole: .individual)
        let second = AppSession(developerSandboxRole: .coach)
        XCTAssertTrue(first.isDeveloperSandbox)
        XCTAssertNotEqual(first.accountOperationLease()?.ownerID, second.accountOperationLease()?.ownerID)
        XCTAssertEqual(EntitlementStore.shared.resolvedUserID, entitlementOwner)
        XCTAssertFalse(first.canOpenDeveloperSandbox)
        XCTAssertFalse(first.developerSandboxHasExternalDependencies)
        let lease = try XCTUnwrap(first.accountOperationLease())
        await first.skipInduction(operation: lease)
        XCTAssertNil(first.data.profile)
        XCTAssertNotNil(first.data.settings)
        first.invalidateDeveloperSandbox()
        XCTAssertFalse(first.accountOperationIsCurrent(lease))
        XCTAssertEqual(EntitlementStore.shared.resolvedUserID, entitlementOwner)
    }

    func testSandboxEditsAndRoleReplacementDoNotShareDashboard() async throws {
        let first = AppSession(developerSandboxRole: .coach)
        let second = AppSession(developerSandboxRole: .invitedClient)
        let before = second.data.profile
        first.data.profile?.displayName = "Edited sample"
        first.navigationPath = [.settings]
        XCTAssertEqual(second.data.profile, before)
        XCTAssertFalse(second.coachClientPolicy.canRebuildFitnessPlan)
        XCTAssertTrue(second.navigationPath.isEmpty)
    }

    func testLocalHydrationFoodAndDeletionStayOutOfSyncAndHealth() async throws {
        let session = AppSession(developerSandboxRole: .coach, foodSearchProvider: { _ in
            XCTFail("Sandbox must not invoke the production food provider")
            throw CancellationError()
        })
        let operation = try XCTUnwrap(session.accountOperationLease())
        let healthConnected = await session.connectHealth(operation: operation)
        XCTAssertFalse(healthConnected)
        XCTAssertFalse(session.healthImportIsEnabledForCurrentAccount)
        try await session.logHydration(amountML: 250, operation: operation)
        let event = try XCTUnwrap(session.data.hydrationEvents?.first { $0.amountML == 250 })
        XCTAssertNil(event.healthKitSampleID)
        try await session.deleteHydrationEvent(event, on: .now, operation: operation)
        XCTAssertFalse(session.data.hydrationEvents?.contains { $0.id == event.id } ?? false)
        let foods = try await session.searchFoods(query: "Oats", operation: operation)
        let food = try XCTUnwrap(foods.first)
        try await session.logFood(food, amount: 100, unit: "g", mealSlot: "breakfast", date: .now, operation: operation)
        let meal = try XCTUnwrap(session.data.loggedMeals.first)
        XCTAssertEqual(meal.totalKcal, 370)
        try await session.deleteLoggedMeal(meal, operation: operation)
        XCTAssertTrue(session.data.loggedMeals.isEmpty)
        XCTAssertEqual(session.pendingSyncCount, 0)
        XCTAssertEqual(session.failedSyncCount, 0)
    }

    func testCoachPublishesLocallyAndClientActivatesRealWorkoutRows() async throws {
        let coach = AppSession(developerSandboxRole: .coach)
        let operation = try XCTUnwrap(coach.accountOperationLease())
        let roster = try await coach.loadCoachRoster(operation: operation)
        let relationship = try XCTUnwrap(roster.first)
        let overview = try await coach.loadCoachClientOverview(relationshipID: relationship.id, operation: operation)
        let current = try XCTUnwrap(overview.currentPlan)
        var draft = current.plan
        draft.title = "Edited plan"
        let receipt = try await coach.publishCoachPlan(relationshipID: relationship.id, plan: draft,
            expectedVersion: current.version, operation: operation)
        XCTAssertEqual(receipt.version, current.version + 1)
        let updated = try await coach.loadCoachClientOverview(relationshipID: relationship.id, operation: operation)
        XCTAssertEqual(updated.currentPlan?.title, "Edited plan")
        let invitation = try await coach.createCoachInvitation(email: "nobody@example.invalid", scopes: [.workouts],
            visualProgressRequested: false, operation: operation)
        XCTAssertTrue(invitation.token.hasPrefix("sample-only-"))

        let client = AppSession(developerSandboxRole: .invitedClient)
        let clientOperation = try XCTUnwrap(client.accountOperationLease())
        let plan = try XCTUnwrap(client.coachContext.currentPlan)
        try await client.acknowledgeCoachPlan(planVersionID: plan.id, operation: clientOperation)
        XCTAssertNotNil(client.coachContext.currentPlan?.acknowledgedAt)
        try await client.activateCoachPlan(planVersionID: plan.id, operation: clientOperation)
        XCTAssertNotNil(client.coachContext.currentPlan?.activatedAt)
        XCTAssertEqual(client.data.programs.first?.slug, "coach")
        XCTAssertFalse(client.data.exercises.isEmpty)
        XCTAssertFalse(client.coachClientPolicy.canCreateCustomWorkouts)
    }

    func testSkippedIndividualCanBuildAndRebuildAnActualPlan() async throws {
        let session = AppSession(developerSandboxRole: .individual)
        let operation = try XCTUnwrap(session.accountOperationLease())
        await session.skipInduction(operation: operation)
        var input = TrainingInduction.Input(startDate: Date().apexDateKey)
        input.availableMinutes = 30
        input.bodyBaseline = .init(sex: "female", weightKG: 65, heightCM: 168, birthdate: "1990-01-01")
        input.dataConsent = .init(termsVersion: TrainingInduction.currentTermsVersion,
            privacyVersion: TrainingInduction.currentPrivacyVersion, acceptedAt: Date().ISO8601Format())
        await session.installInductionPlan(input, operation: operation)
        XCTAssertFalse(session.data.programDays.isEmpty)
        XCTAssertFalse(session.data.exercises.isEmpty)
        let ready = await session.prepareCommittedPlanForPortal(operation: operation)
        XCTAssertTrue(ready)
        XCTAssertEqual(session.data.profile?.userID, operation.ownerID)
        let firstDays = Set(session.data.programDays.map(\.id))
        input.sessionsPerWeek = 4
        await session.installInductionPlan(input, operation: operation)
        XCTAssertNotEqual(Set(session.data.programDays.map(\.id)), firstDays)
        XCTAssertEqual(session.pendingSyncCount, 0)
        XCTAssertFalse(session.developerSandboxHasExternalDependencies)
    }

    func testMemoryOnlyStoreDoesNotCreateCacheOrOutbox() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let owner = UUID()
        let store = OfflineStore(rootURL: root, memoryOnly: true)
        let dashboard = DeveloperSandboxSamples.dashboard(ownerID: owner, name: "Sample")
        try await store.saveDashboard(dashboard, for: owner)
        try await store.enqueue(.delete(table: "meals", id: UUID()), for: owner)
        let pending = try await store.pendingOperations(for: owner)
        let cached = try await store.loadDashboard(for: owner)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
