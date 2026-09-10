import XCTest
import SwiftUI
@testable import APEX

private enum InjectedMealDeletionFailure: Error {
    case local
    case remote
    case outbox
}

final class MealComposerTests: XCTestCase {
    func testYesterdayCopyUsesPreviousCalendarDayOwnerAndFreshItems() throws {
        let owner = UUID(), mealID = UUID()
        let meal = loggedMeal(id: mealID, ownerID: owner, localDate: "2026-08-31")
        let entry = loggedFoodEntry(id: UUID(), mealID: mealID, ownerID: owner)
        let date = try XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: "2026-09-01"))
        let copied = MealYesterdayCopy.items(date: date, slot: "lunch", ownerID: owner, meals: [meal], entries: [entry])
        XCTAssertEqual(copied.count, 1)
        XCTAssertNotEqual(copied.first?.id, entry.id)
        XCTAssertEqual(copied.first?.quantity, entry.quantity)
        XCTAssertEqual(copied.first?.equivalentAmount, entry.equivalentAmount)
        var portion = try XCTUnwrap(copied.first)
        portion.unit = "serving"
        let previousCalories = portion.nutrients.kcal
        portion.setQuantity(entry.quantity * 2)
        XCTAssertEqual(portion.equivalentAmount, entry.equivalentAmount * 2)
        XCTAssertEqual(portion.nutrients.kcal, previousCalories * 2)
        XCTAssertTrue(MealYesterdayCopy.items(date: date, slot: "breakfast", ownerID: owner, meals: [meal], entries: [entry]).isEmpty)
        XCTAssertTrue(MealYesterdayCopy.items(date: date, slot: "lunch", ownerID: UUID(), meals: [meal], entries: [entry]).isEmpty)
    }

    func testEmptySavedMealRequiresRemovalConfirmation() {
        XCTAssertEqual(
            MealComposerCommitPolicy.intent(itemCount: 0, existingMealID: UUID()),
            .confirmRemoval
        )
    }

    func testEmptyNewMealCannotBeCommitted() {
        XCTAssertEqual(
            MealComposerCommitPolicy.intent(itemCount: 0, existingMealID: nil),
            .unavailable
        )
    }

    func testNonemptyMealRetainsNormalSaveBehavior() {
        XCTAssertEqual(
            MealComposerCommitPolicy.intent(itemCount: 1, existingMealID: UUID()),
            .save
        )
        XCTAssertEqual(
            MealComposerCommitPolicy.intent(itemCount: 1, existingMealID: nil),
            .save
        )
    }

    func testConfirmedMealRemovalIsScopedToOwnerMealAndDate() throws {
        let owner = UUID()
        let anotherOwner = UUID()
        let mealID = UUID()
        let anotherMealID = UUID()
        let target = loggedMeal(
            id: mealID,
            ownerID: owner,
            localDate: "2026-08-29"
        )
        let otherDay = loggedMeal(
            id: anotherMealID,
            ownerID: owner,
            localDate: "2026-08-30"
        )
        let collidingOtherOwner = loggedMeal(
            id: mealID,
            ownerID: anotherOwner,
            localDate: "2026-08-29"
        )
        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [target, otherDay, collidingOtherOwner]
        dashboard.loggedFoodEntries = [
            loggedFoodEntry(id: UUID(), mealID: mealID, ownerID: owner),
            loggedFoodEntry(id: UUID(), mealID: anotherMealID, ownerID: owner),
            loggedFoodEntry(id: UUID(), mealID: mealID, ownerID: anotherOwner),
        ]

        let scope = try XCTUnwrap(StructuredMealDeletionScope(meal: target, ownerID: owner))
        try scope.removeConfirmedMeal(from: &dashboard)

        XCTAssertEqual(scope.localDate, "2026-08-29")
        XCTAssertEqual(dashboard.loggedMeals.map(\.id), [anotherMealID, mealID])
        XCTAssertEqual(dashboard.loggedMeals.map(\.userID), [owner, anotherOwner])
        XCTAssertEqual(dashboard.loggedFoodEntries.map(\.mealID), [anotherMealID, mealID])
        XCTAssertEqual(dashboard.loggedFoodEntries.map(\.userID), [owner, anotherOwner])
    }

    func testMealRemovalRejectsAnotherAccountsMeal() {
        let meal = loggedMeal(
            id: UUID(),
            ownerID: UUID(),
            localDate: "2026-08-29"
        )

        XCTAssertNil(StructuredMealDeletionScope(meal: meal, ownerID: UUID()))
    }

    func testMealRemovalRejectsSameOwnerAndIDWhenCapturedDateIsStale() throws {
        let owner = UUID()
        let mealID = UUID()
        let staleTarget = loggedMeal(
            id: mealID,
            ownerID: owner,
            localDate: "2026-08-29"
        )
        let currentMeal = loggedMeal(
            id: mealID,
            ownerID: owner,
            localDate: "2026-08-30"
        )
        let currentEntry = loggedFoodEntry(id: UUID(), mealID: mealID, ownerID: owner)
        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [currentMeal]
        dashboard.loggedFoodEntries = [currentEntry]

        let scope = try XCTUnwrap(
            StructuredMealDeletionScope(meal: staleTarget, ownerID: owner)
        )

        XCTAssertThrowsError(try scope.removeConfirmedMeal(from: &dashboard)) { error in
            XCTAssertEqual(error as? StructuredMealDeletionError, .targetChanged)
        }
        XCTAssertEqual(dashboard.loggedMeals.map(\.localDate), ["2026-08-30"])
        XCTAssertEqual(dashboard.loggedFoodEntries.map(\.id), [currentEntry.id])
    }

    @MainActor
    func testConfirmedMealDeletionRequiresDurableLocalSnapshotBeforeSync() async {
        var calls: [String] = []

        do {
            _ = try await ConfirmedMealDeletionPersistence.persist(
                local: {
                    calls.append("local")
                    throw InjectedMealDeletionFailure.local
                },
                remote: {
                    calls.append("remote")
                },
                enqueue: {
                    calls.append("enqueue")
                }
            )
            XCTFail("Expected local durability failure")
        } catch {
            XCTAssertEqual(error as? StructuredMealDeletionError, .durabilityUnavailable)
        }

        XCTAssertEqual(calls, ["local"])
    }

    @MainActor
    func testConfirmedMealDeletionThrowsWhenRemoteAndOutboxBothFail() async {
        var calls: [String] = []

        do {
            _ = try await ConfirmedMealDeletionPersistence.persist(
                local: {
                    calls.append("local")
                },
                remote: {
                    calls.append("remote")
                    throw InjectedMealDeletionFailure.remote
                },
                enqueue: {
                    calls.append("enqueue")
                    throw InjectedMealDeletionFailure.outbox
                }
            )
            XCTFail("Expected sync durability failure")
        } catch {
            XCTAssertEqual(error as? StructuredMealDeletionError, .durabilityUnavailable)
        }

        XCTAssertEqual(calls, ["local", "remote", "enqueue"])
    }

    @MainActor
    func testConfirmedMealDeletionCanCompleteThroughDurableOutbox() async throws {
        var calls: [String] = []

        let outcome = try await ConfirmedMealDeletionPersistence.persist(
            local: {
                calls.append("local")
            },
            remote: {
                calls.append("remote")
                throw InjectedMealDeletionFailure.remote
            },
            enqueue: {
                calls.append("enqueue")
            }
        )

        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(calls, ["local", "remote", "enqueue"])
    }

    @MainActor
    func testMergedMealDeletionPreservesConcurrentNutritionChanges() async throws {
        let owner = UUID()
        let target = loggedMeal(
            id: UUID(),
            ownerID: owner,
            localDate: "2026-08-29"
        )
        let concurrentMeal = loggedMeal(
            id: UUID(),
            ownerID: owner,
            localDate: "2026-08-29"
        )
        var dashboard = DashboardData.empty
        dashboard.loggedMeals = [target]
        dashboard.loggedFoodEntries = [
            loggedFoodEntry(id: UUID(), mealID: target.id, ownerID: owner),
        ]
        var revision: UInt64 = 0
        var persistenceAttempts = 0
        let scope = try XCTUnwrap(
            StructuredMealDeletionScope(meal: target, ownerID: owner)
        )
        let change = try StructuredMealDeletionChange(scope: scope, data: dashboard)

        let committed = try await ConfirmedMealDeletionPersistence
            .persistMergedBeforePublishing(
                snapshot: { (revision, dashboard) },
                merge: { try change.deleting(from: $0) },
                persist: { _ in
                    persistenceAttempts += 1
                    if persistenceAttempts == 1 {
                        dashboard.loggedMeals.append(concurrentMeal)
                        revision &+= 1
                    }
                }
            )

        XCTAssertEqual(persistenceAttempts, 2)
        XCTAssertFalse(committed.loggedMeals.contains { $0.id == target.id })
        XCTAssertTrue(committed.loggedMeals.contains { $0.id == concurrentMeal.id })
        XCTAssertEqual(
            committed.dailyLogs.first {
                $0.userID == owner && $0.date == "2026-08-29"
            }?.kcal,
            420
        )
    }

    func testMealDeletionRollbackRestoresOnlyItsOwnRows() throws {
        let owner = UUID()
        let target = loggedMeal(
            id: UUID(),
            ownerID: owner,
            localDate: "2026-08-29"
        )
        let concurrentMeal = loggedMeal(
            id: UUID(),
            ownerID: owner,
            localDate: "2026-08-30"
        )
        var original = DashboardData.empty
        original.loggedMeals = [target]
        original.loggedFoodEntries = [
            loggedFoodEntry(id: UUID(), mealID: target.id, ownerID: owner),
        ]
        let scope = try XCTUnwrap(
            StructuredMealDeletionScope(meal: target, ownerID: owner)
        )
        let change = try StructuredMealDeletionChange(scope: scope, data: original)
        var latest = try change.deleting(from: original)
        latest.loggedMeals.append(concurrentMeal)

        let restored = change.restoring(in: latest)

        XCTAssertTrue(restored.loggedMeals.contains { $0.id == target.id })
        XCTAssertTrue(restored.loggedMeals.contains { $0.id == concurrentMeal.id })
        XCTAssertTrue(restored.loggedFoodEntries.contains { $0.mealID == target.id })
    }

    func testAPEXPopoverCardWidthPreservesSixteenPointGuttersOnCompactNotchedPhone() {
        let safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        let cardWidth = APEXPopoverGeometry.cardWidth(
            containerWidth: 375,
            safeAreaInsets: safeAreaInsets
        )

        XCTAssertEqual(cardWidth, 343, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual((375 - cardWidth) / 2, 16)
    }

    func testAPEXPopoverCardWidthCapsAtThreeHundredSeventyTwoOnWideNotchedPhone() {
        let safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        let cardWidth = APEXPopoverGeometry.cardWidth(
            containerWidth: 430,
            safeAreaInsets: safeAreaInsets
        )

        XCTAssertEqual(cardWidth, 372, accuracy: 0.001)
        XCTAssertLessThanOrEqual(cardWidth, 372)
        XCTAssertGreaterThanOrEqual((430 - cardWidth) / 2, 16)
    }

    func testAPEXPopoverCardWidthKeepsGuttersInsideHorizontalSafeAreaInsets() {
        let safeAreaInsets = EdgeInsets(top: 0, leading: 21, bottom: 0, trailing: 21)

        let cardWidth = APEXPopoverGeometry.cardWidth(
            containerWidth: 430,
            safeAreaInsets: safeAreaInsets
        )

        XCTAssertEqual(cardWidth, 356, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual((430 - cardWidth) / 2, safeAreaInsets.leading + 16)
        XCTAssertGreaterThanOrEqual((430 - cardWidth) / 2, safeAreaInsets.trailing + 16)
    }

    func testAPEXPopoverGeometryRejectsInvalidKeyboardTransitionDimensions() {
        let invalidSize = APEXPopoverGeometry.containerSize(
            CGSize(width: .nan, height: -.infinity)
        )

        XCTAssertEqual(invalidSize, .zero)
        XCTAssertEqual(
            APEXPopoverGeometry.maximumHeight(
                containerHeight: -.infinity,
                fraction: .nan
            ),
            0
        )
        XCTAssertEqual(
            APEXPopoverGeometry.cardHeight(
                contentHeight: .infinity,
                maximumHeight: -40
            ),
            0
        )
    }

    func testAPEXPopoverGeometryClampsValidDimensionsWithoutChangingNormalLayout() {
        XCTAssertEqual(
            APEXPopoverGeometry.maximumHeight(
                containerHeight: 874,
                fraction: 0.78
            ),
            681.72,
            accuracy: 0.001
        )
        XCTAssertEqual(
            APEXPopoverGeometry.cardHeight(
                contentHeight: 720,
                maximumHeight: 681.72
            ),
            681.72,
            accuracy: 0.001
        )
        XCTAssertEqual(
            APEXPopoverGeometry.cardHeight(
                contentHeight: 440,
                maximumHeight: 681.72
            ),
            440,
            accuracy: 0.001
        )
    }

    func testNewMealLogKindNormalizesToDatabaseAcceptedCustomValue() {
        XCTAssertEqual(MealLogKind.normalized(nil), "custom")
        XCTAssertEqual(MealLogKind.normalized("actual"), "custom")
        XCTAssertEqual(MealLogKind.normalized(" manual "), "custom")
        XCTAssertEqual(MealLogKind.normalized("planned"), "planned")
        XCTAssertEqual(MealLogKind.normalized("CHANGED"), "changed")
        XCTAssertEqual(MealLogKind.normalized("custom"), "custom")
    }

    func testSettingsRebindToTheAuthenticatedProfileWithoutLosingPreferences() {
        let staleUserID = UUID()
        let authenticatedUserID = UUID()
        let settings = UserSettings(
            userID: staleUserID,
            voiceOn: false,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.75,
            addons: ["uiMode": .string("simple"), "newbie_mode": .bool(true)]
        )

        let rebound = settings.rebound(to: authenticatedUserID)

        XCTAssertEqual(rebound.userID, authenticatedUserID)
        XCTAssertEqual(rebound.voiceOn, settings.voiceOn)
        XCTAssertEqual(rebound.ticksOn, settings.ticksOn)
        XCTAssertEqual(rebound.notificationsOn, settings.notificationsOn)
        XCTAssertEqual(rebound.guardianFactor, settings.guardianFactor)
        XCTAssertEqual(rebound.addons, settings.addons)
    }

    func testPermanentSyncFailuresAreNeverClassifiedAsOfflineRetryWork() {
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: 400, databaseCode: nil, isNetworkFailure: false),
            .permanent
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: 403, databaseCode: nil, isNetworkFailure: false),
            .permanent
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: nil, databaseCode: "23514", isNetworkFailure: false),
            .permanent
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: nil, databaseCode: "42501", isNetworkFailure: false),
            .permanent
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: 429, databaseCode: nil, isNetworkFailure: false),
            .transient
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: nil, databaseCode: nil, isNetworkFailure: true),
            .transient
        )
    }

    func testUnauthorizedSyncFailuresRequireAuthenticationRecoveryInsteadOfQuarantine() {
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: 401, databaseCode: nil, isNetworkFailure: false),
            .authenticationRequired
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(statusCode: nil, databaseCode: "PGRST301", isNetworkFailure: false),
            .authenticationRequired
        )
        XCTAssertEqual(
            SyncFailurePolicy.classify(OfflineAuthenticationReplayHarness.UnauthorizedReplayError()),
            .authenticationRequired
        )
    }

    func testUnauthorizedOfflineWriteRefreshesAuthenticationAndRetriesExactlyOnce() async {
        let operation = OfflineOperation.delete(table: "hydration_events", id: UUID())
        let harness = OfflineAuthenticationReplayHarness()

        let report = await OfflineQueueDrainer.drain(
            [operation],
            replay: { try await harness.replay($0) },
            remove: { await harness.remove($0) },
            quarantine: { await harness.quarantine($0, reason: $1) },
            refreshAuthentication: { try await harness.refreshAuthentication() },
            classify: SyncFailurePolicy.classify
        )

        XCTAssertEqual(report, OfflineQueueDrainReport(succeeded: 1, quarantined: 0, paused: false))
        let snapshot = await harness.snapshot()
        XCTAssertEqual(snapshot.replayed, [operation.id, operation.id])
        XCTAssertEqual(snapshot.removed, [operation.id])
        XCTAssertEqual(snapshot.quarantined, [])
        XCTAssertEqual(snapshot.authenticationRefreshes, 1)
    }

    func testFailedAuthenticationRefreshPausesWithoutQuarantiningTheWrite() async {
        let operation = OfflineOperation.delete(table: "hydration_events", id: UUID())
        let harness = OfflineAuthenticationReplayHarness(refreshFails: true)

        let report = await OfflineQueueDrainer.drain(
            [operation],
            replay: { try await harness.replay($0) },
            remove: { await harness.remove($0) },
            quarantine: { await harness.quarantine($0, reason: $1) },
            refreshAuthentication: { try await harness.refreshAuthentication() },
            classify: SyncFailurePolicy.classify
        )

        XCTAssertEqual(report, OfflineQueueDrainReport(succeeded: 0, quarantined: 0, paused: true))
        let snapshot = await harness.snapshot()
        XCTAssertEqual(snapshot.replayed, [operation.id])
        XCTAssertEqual(snapshot.removed, [])
        XCTAssertEqual(snapshot.quarantined, [])
        XCTAssertEqual(snapshot.authenticationRefreshes, 1)
    }

    func testPermanentPoisonOperationDoesNotBlockTheFollowingValidOperation() async throws {
        let poison = OfflineOperation.delete(table: "poison", id: UUID())
        let valid = OfflineOperation.delete(table: "valid", id: UUID())
        let harness = OfflineReplayHarness(poisonID: poison.id)

        let report = await OfflineQueueDrainer.drain(
            [poison, valid],
            replay: { try await harness.replay($0) },
            remove: { try await harness.remove($0) },
            quarantine: { try await harness.quarantine($0, reason: $1) },
            refreshAuthentication: {},
            classify: { error in
                error is OfflineReplayHarness.PermanentReplayError ? .permanent : .transient
            }
        )

        XCTAssertEqual(report, OfflineQueueDrainReport(succeeded: 1, quarantined: 1, paused: false))
        let snapshot = await harness.snapshot()
        XCTAssertEqual(snapshot.replayed, [poison.id, valid.id])
        XCTAssertEqual(snapshot.removed, [valid.id])
        XCTAssertEqual(snapshot.quarantined, [poison.id])
    }

    func testDiskBackedOutboxQuarantinesPoisonAndFullyDrainsValidWork() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXOfflineStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let userID = UUID()
        let poison = OfflineOperation.delete(table: "poison", id: UUID())
        let valid = OfflineOperation.delete(table: "valid", id: UUID())
        let store = OfflineStore(rootURL: rootURL)
        let harness = OfflineReplayHarness(poisonID: poison.id)

        try await store.enqueue(poison, for: userID)
        try await store.enqueue(valid, for: userID)

        let queued = try await store.pendingOperations(for: userID)
        XCTAssertEqual(queued.map(\.id), [poison.id, valid.id])

        let report = await OfflineQueueDrainer.drain(
            queued,
            replay: { try await harness.replay($0) },
            remove: { try await store.removeOperation($0.id, for: userID) },
            quarantine: { try await store.quarantine($0, reason: $1, for: userID) },
            refreshAuthentication: {},
            classify: { error in
                error is OfflineReplayHarness.PermanentReplayError ? .permanent : .transient
            }
        )

        XCTAssertEqual(report, OfflineQueueDrainReport(succeeded: 1, quarantined: 1, paused: false))
        let remaining = try await store.pendingOperations(for: userID)
        XCTAssertTrue(remaining.isEmpty)

        let failures = try await store.failedOperations(for: userID)
        XCTAssertEqual(failures.map(\.operation.id), [poison.id])
        XCTAssertEqual(failures.first?.reason, OfflineReplayHarness.PermanentReplayError().localizedDescription)

        let replaySnapshot = await harness.snapshot()
        XCTAssertEqual(replaySnapshot.replayed, [poison.id, valid.id])
    }

    func testDraftTotalsFollowEditedQuantities() {
        let oats = food(
            name: "Oats",
            kcal100: 370,
            protein100: 13,
            carbs100: 60,
            fat100: 7
        )
        let whey = food(
            name: "Whey isolate",
            kcal100: 360,
            protein100: 86,
            carbs100: 2,
            fat100: 1
        )
        var oatItem = MealComposerItem(food: oats, quantity: 60, unit: "g")
        let wheyItem = MealComposerItem(food: whey, quantity: 30, unit: "g")

        oatItem.setQuantity(80, food: oats)
        let draft = MealComposerDraft(
            id: UUID(),
            localDate: "2026-08-17",
            mealSlot: "breakfast",
            displayName: "Breakfast",
            finishedAt: Date(timeIntervalSince1970: 0),
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            replaceMealID: nil,
            loggedAs: "actual",
            items: [oatItem, wheyItem]
        )

        XCTAssertEqual(draft.totals.kcal, 404, accuracy: 0.001)
        XCTAssertEqual(draft.totals.proteinG, 36.2, accuracy: 0.001)
        XCTAssertEqual(draft.totals.carbsG, 48.6, accuracy: 0.001)
        XCTAssertEqual(draft.totals.fatG, 5.9, accuracy: 0.001)
    }

    func testComposerHydrationSumsTheActualPortionsShownInTheMeal() {
        var milk = food(
            name: "High protein milk",
            kcal100: 54,
            protein100: 8,
            carbs100: 5.2,
            fat100: 0.2
        )
        milk.waterML100 = 86.4
        milk.waterBasis = "measured"
        var walnuts = food(
            name: "Walnuts",
            kcal100: 654,
            protein100: 15.2,
            carbs100: 13.7,
            fat100: 65.2
        )
        walnuts.waterML100 = 4
        walnuts.waterBasis = "difference"

        let milkItem = MealComposerItem(food: milk, quantity: 251, unit: "g")
        let walnutItem = MealComposerItem(food: walnuts, quantity: 27, unit: "g")

        XCTAssertEqual(MealComposerHydration.itemWaterML(milkItem), 216.864, accuracy: 0.001)
        XCTAssertEqual(MealComposerHydration.itemWaterML(walnutItem), 1.08, accuracy: 0.001)
        XCTAssertFalse(MealComposerHydration.itemWaterIsEstimated(milkItem))
        XCTAssertTrue(MealComposerHydration.itemWaterIsEstimated(walnutItem))
        XCTAssertTrue(MealComposerHydration.totalWaterIsEstimated(in: [milkItem, walnutItem]))
        XCTAssertEqual(
            MealComposerHydration.totalWaterML(in: [milkItem, walnutItem]),
            217.944,
            accuracy: 0.001
        )
    }

    func testDisplayedMealWaterEqualsTheSumOfDisplayedItemWater() {
        var food = food(
            name: "Low-water test food",
            kcal100: 100,
            protein100: 1,
            carbs100: 1,
            fat100: 1
        )
        food.waterML100 = 1
        let first = MealComposerItem(food: food, quantity: 60, unit: "g")
        let second = MealComposerItem(food: food, quantity: 60, unit: "g")

        XCTAssertEqual(MealComposerHydration.displayedItemWaterML(first), 1)
        XCTAssertEqual(MealComposerHydration.displayedItemWaterML(second), 1)
        XCTAssertEqual(MealComposerHydration.displayedTotalWaterML(in: [first, second]), 2)
    }

    func testUndoRestoresTheRemovedFoodAtItsExactPosition() {
        let first = MealComposerItem(
            food: food(name: "Milk", kcal100: 54, protein100: 8, carbs100: 5, fat100: 0.2),
            quantity: 250,
            unit: "g"
        )
        let removed = MealComposerItem(
            food: food(name: "Oats", kcal100: 370, protein100: 13, carbs100: 60, fat100: 7),
            quantity: 75,
            unit: "g"
        )
        let last = MealComposerItem(
            food: food(name: "Walnuts", kcal100: 654, protein100: 15.2, carbs100: 13.7, fat100: 65.2),
            quantity: 27,
            unit: "g"
        )
        var items = [first, removed, last]
        var undo = MealComposerUndoBuffer()

        XCTAssertTrue(undo.remove(removed.id, from: &items))
        XCTAssertEqual(items.map(\.id), [first.id, last.id])
        XCTAssertEqual(undo.removedName, "Oats")

        XCTAssertTrue(undo.restore(into: &items))
        XCTAssertEqual(items.map(\.id), [first.id, removed.id, last.id])
        XCTAssertNil(undo.removedName)
    }

    func testUndoExpiresAfterFiveSecondsAndReportsTheVisibleCountdown() {
        let first = MealComposerItem(
            food: food(name: "Milk", kcal100: 54, protein100: 8, carbs100: 5, fat100: 0.2),
            quantity: 250,
            unit: "g"
        )
        let removed = MealComposerItem(
            food: food(name: "Oats", kcal100: 370, protein100: 13, carbs100: 60, fat100: 7),
            quantity: 75,
            unit: "g"
        )
        let last = MealComposerItem(
            food: food(name: "Walnuts", kcal100: 654, protein100: 15.2, carbs100: 13.7, fat100: 65.2),
            quantity: 27,
            unit: "g"
        )
        let start = Date(timeIntervalSince1970: 10_000)
        var items = [first, removed, last]
        var undo = MealComposerUndoBuffer()

        XCTAssertTrue(undo.remove(removed.id, from: &items, at: start))
        XCTAssertEqual(undo.secondsRemaining(at: start), 5)
        XCTAssertEqual(undo.secondsRemaining(at: start.addingTimeInterval(4.001)), 1)
        XCTAssertFalse(undo.restore(into: &items, at: start.addingTimeInterval(5)))
        XCTAssertEqual(items.map(\.id), [first.id, last.id])
        XCTAssertNil(undo.removedName)
    }

    func testUndoBarOwnsItsFiveSecondTaskAndVisibleCountdown() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Nutrition/MealComposerView.swift"))

        XCTAssertTrue(source.contains("TimelineView(.periodic"))
        XCTAssertTrue(source.contains(".task(id: undoBuffer.removalToken)"))
        XCTAssertTrue(source.contains("undoBuffer.secondsRemaining(at: context.date)"))
    }

    func testCompactUnitControlReservesOneLineForMillilitresAndServingLabels() {
        XCTAssertEqual(MealComposerCompactLayout.unitControlWidth, 72)
        XCTAssertEqual(MealComposerCompactLayout.controlHeight, 40)
    }

    func testPieceAndServingUnitsUseFoodEquivalents() {
        var egg = food(name: "Egg", kcal100: 143, protein100: 13, carbs100: 1, fat100: 10)
        egg.pieceGramsOrML = 50
        egg.servingGramsOrML = 100

        var item = MealComposerItem(food: egg, quantity: 2, unit: "piece")
        XCTAssertEqual(item.equivalentAmount, 100)
        XCTAssertEqual(item.nutrients.kcal, 143, accuracy: 0.001)

        item.setUnit("serving", food: egg)
        XCTAssertEqual(item.equivalentAmount, 200)
        XCTAssertEqual(item.nutrients.proteinG, 26, accuracy: 0.001)
    }

    func testApplyingAPresetCreatesFreshLoggedFoodEntryIDsEveryTime() {
        let food = food(name: "Oats", kcal100: 370, protein100: 13, carbs100: 60, fat100: 7)
        let presetItem = MealPresetItem(
            id: UUID(),
            presetID: UUID(),
            userID: UUID(),
            foodID: UUID(uuidString: food.id)!,
            sortOrder: 0,
            quantity: 60,
            unit: "g",
            optional: false,
            locked: false,
            adjustable: true,
            minimumAmount: nil,
            maximumAmount: nil,
            stepAmount: nil,
            adjustmentRole: "carb"
        )

        let firstApplication = MealComposerItem(food: food, preset: presetItem)
        let secondApplication = MealComposerItem(food: food, preset: presetItem)

        XCTAssertNotEqual(firstApplication.id, presetItem.id)
        XCTAssertNotEqual(secondApplication.id, presetItem.id)
        XCTAssertNotEqual(firstApplication.id, secondApplication.id)
    }

    func testEachComposerSessionGetsANewSaveOperationKeyForTheSameMeal() {
        let mealID = UUID()
        let firstDraft = draft(id: mealID)
        let reopenedDraft = draft(id: mealID)

        XCTAssertEqual(firstDraft.clientIdempotencyKey, firstDraft.clientIdempotencyKey)
        XCTAssertNotEqual(firstDraft.clientIdempotencyKey, reopenedDraft.clientIdempotencyKey)
    }

    func testPresetPayloadKeepsSupabaseRPCContract() throws {
        let foodID = UUID()
        let payload = MealPresetRPCPayload(
            pPreset: MealPresetRequest(
                id: UUID(),
                name: "Fast breakfast",
                mealSlot: "breakfast",
                sourcePlannedMealID: nil,
                archived: false
            ),
            pItems: [
                MealPresetItemRequest(
                    id: UUID(),
                    foodID: foodID,
                    sortOrder: 0,
                    quantity: 60,
                    unit: "g",
                    optional: false,
                    locked: true,
                    adjustable: false,
                    minimumAmount: nil,
                    maximumAmount: nil,
                    stepAmount: nil,
                    adjustmentRole: "fixed"
                )
            ],
            pExpectedVersion: 3
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertNotNil(object["p_preset"])
        XCTAssertNotNil(object["p_items"])
        XCTAssertEqual(object["p_expected_version"] as? Int, 3)

        let items = try XCTUnwrap(object["p_items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["food_id"] as? String, foodID.uuidString)
        XCTAssertEqual(items.first?["adjustment_role"] as? String, "fixed")
    }

    private func draft(id: UUID) -> MealComposerDraft {
        MealComposerDraft(
            id: id,
            localDate: "2026-08-21",
            mealSlot: "breakfast",
            displayName: "Breakfast",
            finishedAt: Date(timeIntervalSince1970: 0),
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            replaceMealID: id,
            loggedAs: "custom",
            items: []
        )
    }

    private func loggedMeal(id: UUID, ownerID: UUID, localDate: String) -> LoggedMeal {
        LoggedMeal(
            id: id,
            userID: ownerID,
            localDate: localDate,
            mealSlot: "lunch",
            displayName: "Lunch",
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            loggedAt: "\(localDate)T12:00:00Z",
            clientIdempotencyKey: UUID().uuidString,
            loggedAs: "custom",
            totalKcal: 420,
            totalProteinG: 30,
            totalCarbsG: 45,
            totalFatG: 12
        )
    }

    private func loggedFoodEntry(id: UUID, mealID: UUID, ownerID: UUID) -> LoggedFoodEntry {
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

    private func food(
        name: String,
        kcal100: Double,
        protein100: Double,
        carbs100: Double,
        fat100: Double
    ) -> Food {
        Food(
            id: UUID().uuidString,
            ownerUserID: nil,
            name: name,
            namesI18n: [:],
            brand: nil,
            barcode: nil,
            source: "test",
            providerProductID: nil,
            externalImageURL: nil,
            packageQuantity: nil,
            nutritionBasis: "per_100g",
            preparationState: "as_sold",
            kcal100: kcal100,
            protein100: protein100,
            carbs100: carbs100,
            fat100: fat100,
            fibre100: nil,
            sugar100: nil,
            saturatedFat100: nil,
            salt100: nil,
            servingAmount: nil,
            servingUnit: nil,
            servingGramsOrML: nil,
            pieceGramsOrML: nil,
            confidence: "verified"
        )
    }
}

private actor OfflineReplayHarness {
    struct PermanentReplayError: Error, Sendable {}

    private let poisonID: UUID
    private var replayed: [UUID] = []
    private var removed: [UUID] = []
    private var quarantined: [UUID] = []

    init(poisonID: UUID) {
        self.poisonID = poisonID
    }

    func replay(_ operation: OfflineOperation) throws {
        replayed.append(operation.id)
        if operation.id == poisonID {
            throw PermanentReplayError()
        }
    }

    func remove(_ operation: OfflineOperation) {
        removed.append(operation.id)
    }

    func quarantine(_ operation: OfflineOperation, reason: String) {
        quarantined.append(operation.id)
    }

    func snapshot() -> (replayed: [UUID], removed: [UUID], quarantined: [UUID]) {
        (replayed, removed, quarantined)
    }
}

private actor OfflineAuthenticationReplayHarness {
    struct UnauthorizedReplayError: LocalizedError, Sendable {
        var errorDescription: String? { "request failed with status code 401" }
    }

    struct RefreshError: Error, Sendable {}

    private let refreshFails: Bool
    private var replayed: [UUID] = []
    private var removed: [UUID] = []
    private var quarantined: [UUID] = []
    private var authenticationRefreshes = 0

    init(refreshFails: Bool = false) {
        self.refreshFails = refreshFails
    }

    func replay(_ operation: OfflineOperation) throws {
        replayed.append(operation.id)
        if replayed.count == 1 {
            throw UnauthorizedReplayError()
        }
    }

    func remove(_ operation: OfflineOperation) {
        removed.append(operation.id)
    }

    func quarantine(_ operation: OfflineOperation, reason: String) {
        quarantined.append(operation.id)
    }

    func refreshAuthentication() throws {
        authenticationRefreshes += 1
        if refreshFails { throw RefreshError() }
    }

    func snapshot() -> (
        replayed: [UUID],
        removed: [UUID],
        quarantined: [UUID],
        authenticationRefreshes: Int
    ) {
        (replayed, removed, quarantined, authenticationRefreshes)
    }
}
