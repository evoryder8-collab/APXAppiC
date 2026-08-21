import XCTest
@testable import APEX

final class MealComposerTests: XCTestCase {
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

    func testPermanentPoisonOperationDoesNotBlockTheFollowingValidOperation() async throws {
        let poison = OfflineOperation.delete(table: "poison", id: UUID())
        let valid = OfflineOperation.delete(table: "valid", id: UUID())
        let harness = OfflineReplayHarness(poisonID: poison.id)

        let report = await OfflineQueueDrainer.drain(
            [poison, valid],
            replay: { try await harness.replay($0) },
            remove: { try await harness.remove($0) },
            quarantine: { try await harness.quarantine($0, reason: $1) },
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
