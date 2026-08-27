import XCTest
@testable import APEX

private struct WorkoutSyncFixture: Codable, Sendable {
    let id: UUID
}

final class SyncRepairTests: XCTestCase {
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
}

private struct JWTIssuedAtFutureError: LocalizedError {
    var errorDescription: String? { "JWT issued at future" }
}
