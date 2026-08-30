import XCTest
@testable import APEX

private struct WorkoutSyncFixture: Codable, Sendable {
    let id: UUID
}

private struct WorkoutLogFailureFixture: Codable, Sendable {
    let id: UUID
    let sessionID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
    }
}

final class SyncRepairTests: XCTestCase {
    func testDashboardCacheRoundTripPreservesAndMigratesLegacyMeasuredBMR() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXLegacyBMRMigrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let store = OfflineStore(rootURL: rootURL)
        var dashboard = APEXDebugFixture.dashboard(userID: ownerID)
        dashboard.profile?.customBMR = 1_683
        dashboard.settings?.addons.removeValue(forKey: "custom_bmr")

        try await store.saveDashboard(dashboard, for: ownerID)
        let loaded = try await store.loadDashboard(for: ownerID)
        let restored = try XCTUnwrap(loaded)

        XCTAssertEqual(restored.profile?.customBMR, 1_683)
        XCTAssertEqual(restored.settings?.userID, ownerID)
        XCTAssertEqual(restored.settings?.addons["custom_bmr"]?.numberValue, 1_683)
    }

    func testUITestFixturesCannotUseRemotePersistence() {
        XCTAssertTrue(
            APEXRuntimeEnvironment.usesLocalUITestFixture(
                arguments: ["APEX", "-apex-ui-test"]
            )
        )
        XCTAssertTrue(
            APEXRuntimeEnvironment.usesLocalUITestFixture(
                arguments: ["APEX", "-apex-preview", "induction", "-apex-ui-test-first-run"]
            )
        )
        XCTAssertFalse(
            APEXRuntimeEnvironment.usesLocalUITestFixture(
                arguments: ["APEX", "-apex-preview", "induction"]
            )
        )
        XCTAssertFalse(APEXRuntimeEnvironment.usesLocalUITestFixture(arguments: ["APEX"]))
    }

    func testReplayRefreshPlanReloadsAfterDrainAndPreservesCacheWhilePaused() {
        let repairedID = UUID()
        XCTAssertEqual(
            OfflineFailureReplayRefreshPlan.make(
                requeuedOperationIDs: [repairedID],
                pendingOperationIDs: [],
                failedOperationIDs: [],
                hasCachedDashboard: true
            ),
            .reloadRemote
        )
        XCTAssertEqual(
            OfflineFailureReplayRefreshPlan.make(
                requeuedOperationIDs: [repairedID],
                pendingOperationIDs: [repairedID],
                failedOperationIDs: [],
                hasCachedDashboard: true
            ),
            .preserveCached
        )
        XCTAssertEqual(
            OfflineFailureReplayRefreshPlan.make(
                requeuedOperationIDs: [repairedID],
                pendingOperationIDs: [],
                failedOperationIDs: [repairedID],
                hasCachedDashboard: true
            ),
            .preserveCached
        )
        XCTAssertEqual(
            OfflineFailureReplayRefreshPlan.make(
                requeuedOperationIDs: [repairedID],
                pendingOperationIDs: nil,
                failedOperationIDs: nil,
                hasCachedDashboard: true
            ),
            .preserveCached
        )
        XCTAssertEqual(
            OfflineFailureReplayRefreshPlan.make(
                requeuedOperationIDs: [],
                pendingOperationIDs: [],
                failedOperationIDs: [],
                hasCachedDashboard: true
            ),
            .useRemote
        )
    }

    func testWorkoutBundleQueuesParentBeforeDependentLogs() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("apex-workout-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = OfflineStore(rootURL: rootURL)
        let userID = UUID()
        let child = try OfflineOperation.upsert(
            WorkoutSyncFixture(id: UUID()),
            table: "workout_logs",
            onConflict: nil
        )
        try await Task.sleep(for: .seconds(1.1))
        let parent = try OfflineOperation.upsert(
            WorkoutSyncFixture(id: UUID()),
            table: "workout_sessions",
            onConflict: nil
        )

        try await store.enqueue(parent: parent, dependents: [child], for: userID)

        let queued = try await store.pendingOperations(for: userID)
        XCTAssertEqual(queued.map(\.id), [parent.id, child.id])
    }

    func testPersistedJWTReasonStillRequiresAuthenticationRecovery() {
        XCTAssertEqual(
            SyncFailurePolicy.classify(persistedReason: "JWT issued at future"),
            .authenticationRequired
        )
        XCTAssertEqual(
            SyncFailurePolicy.category(persistedReason: "permission denied for table logged_meals"),
            .permission
        )
        XCTAssertEqual(
            SyncFailurePolicy.category(persistedReason: "workout_logs_session_id_fkey"),
            .missingDependency
        )
    }

    func testMealTimeEditBuildsAnAtomicReplacementDraft() {
        let mealID = UUID()
        let originalTime = Date(timeIntervalSince1970: 1_777_777_777)
        let correctedTime = originalTime.addingTimeInterval(90 * 60)
        let original = MealComposerDraft(
            id: mealID,
            localDate: "2026-08-27",
            mealSlot: "breakfast",
            displayName: "Breakfast",
            finishedAt: originalTime,
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            replaceMealID: nil,
            loggedAs: "custom",
            items: []
        )

        let replacement = MealFinishedAtReplacement.retime(original, to: correctedTime)

        XCTAssertEqual(replacement.id, mealID)
        XCTAssertEqual(replacement.replaceMealID, mealID)
        XCTAssertEqual(replacement.finishedAt, correctedTime)
        XCTAssertEqual(replacement.localDate, original.localDate)
        XCTAssertEqual(replacement.mealSlot, original.mealSlot)
        XCTAssertEqual(replacement.displayName, original.displayName)
        XCTAssertEqual(replacement.loggedAs, original.loggedAs)
        XCTAssertEqual(replacement.items.count, original.items.count)
    }

    func testJWTClaimValidationFailuresRequireAuthenticationRecovery() {
        XCTAssertEqual(
            SyncFailurePolicy.classify(
                statusCode: nil,
                databaseCode: "PGRST303",
                isNetworkFailure: false
            ),
            .authenticationRequired
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(JWTIssuedAtFutureError()),
            .authenticationRequired
        )
    }

    func testAnonymousRLSFailureRequiresRefreshWithoutReclassifyingRealPermissionDenial() {
        XCTAssertEqual(
            SyncFailurePolicy.classify(
                statusCode: nil,
                databaseCode: "42501",
                databaseMessage: "new row violates row-level security policy for table workout_logs",
                isNetworkFailure: false
            ),
            .authenticationRequired
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(
                statusCode: nil,
                databaseCode: "42501",
                databaseMessage: "permission denied for table workout_logs",
                isNetworkFailure: false
            ),
            .permanent
        )
    }

    func testAuthenticationFailuresRequeueWithoutLosingPermanentFailures() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let userID = UUID()
        let authenticationFailure = OfflineOperation.delete(table: "health_metrics", id: UUID())
        let permanentFailure = OfflineOperation.delete(table: "meal_logs", id: UUID())
        let store = OfflineStore(rootURL: rootURL)

        try await store.recordFailure(
            authenticationFailure,
            reason: "JWT issued at future",
            for: userID
        )
        try await store.recordFailure(
            permanentFailure,
            reason: "permission denied for table meal_logs",
            for: userID
        )

        let restored = try await store.requeueAuthenticationFailures(for: userID)
        let pendingIDs = try await store.pendingOperations(for: userID).map(\.id)
        let failedIDs = try await store.failedOperations(for: userID).map(\.id)

        XCTAssertEqual(restored, 1)
        XCTAssertEqual(pendingIDs, [authenticationFailure.id])
        XCTAssertEqual(failedIDs, [permanentFailure.id])
    }

    func testReconciliationRepairsAnInvalidMealButKeepsAnAmbiguousDuplicate() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let failedMealID = UUID()
        let currentMealID = UUID()
        let entryID = UUID()
        let payload = makeStructuredMealPayload(mealID: failedMealID, entryID: entryID, loggedAs: "actual")
        let invalid = try OfflineOperation.rpc("log_structured_meal", params: payload)
        let duplicate = try OfflineOperation.rpc("log_structured_meal", params: payload)
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            invalid,
            reason: "new row for relation logged_meals violates check constraint logged_meal_kind",
            for: ownerID
        )
        try await store.recordFailure(
            duplicate,
            reason: "duplicate key value violates unique constraint logged_food_entries_pkey",
            for: ownerID
        )

        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [makeLoggedMeal(id: currentMealID, ownerID: ownerID, key: "new-key")]
        dashboard.loggedFoodEntries = [makeLoggedFoodEntry(id: entryID, mealID: currentMealID, ownerID: ownerID)]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let failures = try await store.failedOperations(for: ownerID)
        let pending = try await store.pendingOperations(for: ownerID)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(
                resolved: 0,
                requeued: 1,
                remaining: 1,
                requeuedOperationIDs: [invalid.id]
            )
        )
        XCTAssertEqual(failures.map(\.id), [duplicate.id])
        XCTAssertEqual(pending.map(\.id), [invalid.id])
    }

    func testReconciliationRepairsAnUnsupersededLegacyMealKindBeforeRetry() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let operation = try OfflineOperation.rpc(
            "log_structured_meal",
            params: makeStructuredMealPayload(mealID: UUID(), entryID: UUID(), loggedAs: "actual")
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            operation,
            reason: "new row for relation logged_meals violates check constraint logged_meal_kind",
            for: ownerID
        )

        let report = try await store.reconcileFailures(for: ownerID, dashboard: DashboardData.empty)
        let pending = try await store.pendingOperations(for: ownerID)
        let encodedPayload = try XCTUnwrap(pending.first?.payload)
        let repaired = try JSONDecoder().decode(StructuredMealRPCPayload.self, from: encodedPayload)
        let failures = try await store.failedOperations(for: ownerID)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(
                resolved: 0,
                requeued: 1,
                remaining: 0,
                requeuedOperationIDs: [operation.id]
            )
        )
        XCTAssertEqual(pending.map(\.id), [operation.id])
        XCTAssertEqual(repaired.pMeal.loggedAs, "custom")
        XCTAssertTrue(failures.isEmpty)
    }

    func testReconciliationKeepsAmbiguousLegacyWritesAndAbsentWorkouts() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let mealID = UUID()
        let entryID = UUID()
        let failedMeal = makeLoggedMeal(id: mealID, ownerID: ownerID, key: "legacy-key")
        let directMealWrite = try OfflineOperation.upsert(failedMeal, table: "logged_meals", onConflict: nil)
        let failedMetric = try OfflineOperation.upsert(
            HealthMetric(
                id: UUID(),
                userID: ownerID,
                date: "2026-08-24",
                weightKG: 68,
                vo2Max: 36.5,
                restingHeartRate: 51
            ),
            table: "health_metrics",
            onConflict: "user_id,date"
        )
        let orphanedLog = try OfflineOperation.upsert(
            WorkoutLogFailureFixture(id: UUID(), sessionID: UUID()),
            table: "workout_logs",
            onConflict: nil
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            directMealWrite,
            reason: "permission denied for table logged_meals",
            for: ownerID
        )
        try await store.recordFailure(
            failedMetric,
            reason: "duplicate key value violates unique constraint health_metrics_pkey",
            for: ownerID
        )
        try await store.recordFailure(
            orphanedLog,
            reason: "workout_logs_session_id_fkey",
            for: ownerID
        )
        try await store.saveDashboard(.empty, for: ownerID)

        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [makeLoggedMeal(id: mealID, ownerID: ownerID, key: "replacement-key")]
        dashboard.loggedFoodEntries = [makeLoggedFoodEntry(id: entryID, mealID: mealID, ownerID: ownerID)]
        dashboard.healthMetrics = [
            HealthMetric(
                id: UUID(),
                userID: ownerID,
                date: "2026-08-24",
                weightKG: 68,
                vo2Max: 36.5,
                restingHeartRate: 54
            ),
        ]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let failures = try await store.failedOperations(for: ownerID)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(resolved: 0, requeued: 0, remaining: 3)
        )
        XCTAssertEqual(failures.count, 3)
    }

    func testReconciliationKeepsAnOrphanedWorkoutStillPresentInTheLocalCache() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let sessionID = UUID()
        let operation = try OfflineOperation.upsert(
            WorkoutLogFailureFixture(id: UUID(), sessionID: sessionID),
            table: "workout_logs",
            onConflict: nil
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(operation, reason: "workout_logs_session_id_fkey", for: ownerID)
        var cached = DashboardData.empty
        cached.workoutSessions = [makeWorkoutSession(id: sessionID, ownerID: ownerID)]
        try await store.saveDashboard(cached, for: ownerID)

        let report = try await store.reconcileFailures(for: ownerID, dashboard: .empty)
        let failureIDs = try await store.failedOperations(for: ownerID).map(\.id)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(resolved: 0, requeued: 0, remaining: 1)
        )
        XCTAssertEqual(failureIDs, [operation.id])
    }

    func testReconciliationRetriesAWorkoutLogOnceItsParentExists() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let sessionID = UUID()
        let operation = try OfflineOperation.upsert(
            WorkoutLogFailureFixture(id: UUID(), sessionID: sessionID),
            table: "workout_logs",
            onConflict: nil
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(operation, reason: "workout_logs_session_id_fkey", for: ownerID)
        var dashboard = DashboardData.empty
        dashboard.workoutSessions = [makeWorkoutSession(id: sessionID, ownerID: ownerID)]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let pendingIDs = try await store.pendingOperations(for: ownerID).map(\.id)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(
                resolved: 0,
                requeued: 1,
                remaining: 0,
                requeuedOperationIDs: [operation.id]
            )
        )
        XCTAssertEqual(pendingIDs, [operation.id])
    }

    func testReconciliationDoesNotRetryANonSessionWorkoutForeignKeyFailure() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let sessionID = UUID()
        let operation = try OfflineOperation.upsert(
            WorkoutLogFailureFixture(id: UUID(), sessionID: sessionID),
            table: "workout_logs",
            onConflict: nil
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            operation,
            reason: "workout_logs_exercise_id_fkey",
            for: ownerID
        )
        var dashboard = DashboardData.empty
        dashboard.workoutSessions = [makeWorkoutSession(id: sessionID, ownerID: ownerID)]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let failures = try await store.failedOperations(for: ownerID)
        let pending = try await store.pendingOperations(for: ownerID)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(resolved: 0, requeued: 0, remaining: 1)
        )
        XCTAssertEqual(failures.map(\.id), [operation.id])
        XCTAssertTrue(pending.isEmpty)
    }

    func testReconciliationClearsALegacyMealWriteWhenTheExactRowAlreadyExists() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let mealID = UUID()
        let meal = makeLoggedMeal(id: mealID, ownerID: ownerID, key: "same-key")
        let operation = try OfflineOperation.upsert(meal, table: "logged_meals", onConflict: nil)
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            operation,
            reason: "permission denied for table logged_meals",
            for: ownerID
        )
        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [meal]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let failureIDs = try await store.failedOperations(for: ownerID).map(\.id)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(resolved: 1, requeued: 0, remaining: 0)
        )
        XCTAssertTrue(failureIDs.isEmpty)
    }

    func testReconciliationClearsAHealthMetricOnlyWhenTheExactRowAlreadyExists() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let metric = HealthMetric(
            id: UUID(),
            userID: ownerID,
            date: "2026-08-24",
            weightKG: 68,
            vo2Max: 36.5,
            restingHeartRate: 51
        )
        let operation = try OfflineOperation.upsert(
            metric,
            table: "health_metrics",
            onConflict: "user_id,date"
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            operation,
            reason: "duplicate key value violates unique constraint health_metrics_pkey",
            for: ownerID
        )
        var dashboard = DashboardData.empty
        dashboard.healthMetrics = [metric]

        let report = try await store.reconcileFailures(for: ownerID, dashboard: dashboard)
        let failures = try await store.failedOperations(for: ownerID)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(resolved: 1, requeued: 0, remaining: 0)
        )
        XCTAssertTrue(failures.isEmpty)
    }

    func testReconciliationInsertsARepairedFailureBeforeNewerPendingWork() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXSyncRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ownerID = UUID()
        let failed = try OfflineOperation.rpc(
            "log_structured_meal",
            params: makeStructuredMealPayload(mealID: UUID(), entryID: UUID(), loggedAs: "actual")
        )
        let generatedNewer = try OfflineOperation.rpc("newer_mutation", params: WorkoutSyncFixture(id: UUID()))
        let newer = OfflineOperation(
            id: generatedNewer.id,
            kind: generatedNewer.kind,
            table: generatedNewer.table,
            payload: generatedNewer.payload,
            recordID: generatedNewer.recordID,
            onConflict: generatedNewer.onConflict,
            rpcFunction: generatedNewer.rpcFunction,
            createdAt: failed.createdAt.addingTimeInterval(60)
        )
        let store = OfflineStore(rootURL: rootURL)
        try await store.recordFailure(
            failed,
            reason: "new row for relation logged_meals violates check constraint logged_meal_kind",
            for: ownerID
        )
        try await store.enqueue(newer, for: ownerID)

        let report = try await store.reconcileFailures(for: ownerID, dashboard: .empty)
        let pendingIDs = try await store.pendingOperations(for: ownerID).map(\.id)

        XCTAssertEqual(
            report,
            OfflineFailureReconciliationReport(
                resolved: 0,
                requeued: 1,
                remaining: 0,
                requeuedOperationIDs: [failed.id]
            )
        )
        XCTAssertEqual(pendingIDs, [failed.id, newer.id])
    }

    private func makeStructuredMealPayload(
        mealID: UUID,
        entryID: UUID,
        loggedAs: String
    ) -> StructuredMealRPCPayload {
        StructuredMealRPCPayload(
            pMeal: StructuredMealRequest(
                id: mealID,
                localDate: "2026-08-21",
                mealSlot: "breakfast",
                displayName: "Breakfast",
                sourcePresetID: nil,
                sourcePlannedMealID: nil,
                loggedAt: "2026-08-21T06:00:00Z",
                clientIdempotencyKey: "meal-\(mealID.uuidString.lowercased())",
                loggedAs: loggedAs,
                replaceMealID: nil
            ),
            pEntries: [
                StructuredFoodEntryRequest(
                    id: entryID,
                    foodID: nil,
                    sortOrder: 0,
                    snapshotName: "Oats",
                    snapshotBrand: nil,
                    snapshotPreparationState: "as_sold",
                    snapshotNutritionBasis: "per_100g",
                    snapshotKcal100: 100,
                    snapshotProtein100: 10,
                    snapshotCarbs100: 10,
                    snapshotFat100: 2,
                    snapshotFibre100: nil,
                    snapshotSugar100: nil,
                    snapshotSaturatedFat100: nil,
                    snapshotSalt100: nil,
                    snapshotWaterML100: nil,
                    quantity: 100,
                    unit: "g",
                    equivalentAmount: 100
                ),
            ]
        )
    }

    private func makeLoggedMeal(id: UUID, ownerID: UUID, key: String) -> LoggedMeal {
        LoggedMeal(
            id: id,
            userID: ownerID,
            localDate: "2026-08-27",
            mealSlot: "breakfast",
            displayName: "Breakfast",
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            loggedAt: "2026-08-27T06:30:00Z",
            clientIdempotencyKey: key,
            loggedAs: "custom",
            totalKcal: 100,
            totalProteinG: 10,
            totalCarbsG: 10,
            totalFatG: 2
        )
    }

    private func makeLoggedFoodEntry(id: UUID, mealID: UUID, ownerID: UUID) -> LoggedFoodEntry {
        LoggedFoodEntry(
            id: id,
            mealID: mealID,
            userID: ownerID,
            foodID: nil,
            sortOrder: 0,
            snapshotName: "Oats",
            snapshotBrand: nil,
            snapshotPreparationState: "as_sold",
            snapshotNutritionBasis: "per_100g",
            snapshotKcal100: 100,
            snapshotProtein100: 10,
            snapshotCarbs100: 10,
            snapshotFat100: 2,
            quantity: 100,
            unit: "g",
            equivalentAmount: 100,
            kcal: 100,
            proteinG: 10,
            carbsG: 10,
            fatG: 2
        )
    }

    private func makeWorkoutSession(id: UUID, ownerID: UUID) -> WorkoutSession {
        WorkoutSession(
            id: id,
            userID: ownerID,
            date: "2026-08-27",
            programDayID: UUID(),
            isLite: false,
            isDeload: false,
            isEventRecovery: false,
            completed: true,
            qualityScore: 1,
            startedAt: nil,
            completedAt: nil,
            notes: ""
        )
    }
}

private struct JWTIssuedAtFutureError: LocalizedError {
    var errorDescription: String? { "JWT issued at future" }
}
