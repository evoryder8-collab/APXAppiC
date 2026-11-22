import XCTest
@testable import APEX

/*
 * Meals on the Watch. The ranking a block offers, the additions the Watch keeps
 * while it is away from the phone, and how the phone puts them on the dayline:
 * into the block's meal, once, without dropping anything already in it.
 */
@MainActor
final class WatchMealTests: XCTestCase {
    private let owner = UUID(uuidString: "6A1C2D3E-4F50-4A6B-8C7D-9E0F1A2B3C4D")!
    private let today = "2026-11-22"
    private let yesterday = "2026-11-21"

    // MARK: - Watch fixtures

    private func food(_ id: String, kcal: Double = 100, protein: Double = 10) -> WatchMealFood {
        WatchMealFood(id: id, name: id.capitalized, kcal100: kcal, protein100: protein, carbs100: 0, fat100: 0,
                      basis: "per_100g", preparation: "as_sold")
    }

    private func portion(_ id: String, _ quantity: Double, _ unit: String = "g", grams: Double = 1) -> WatchMealPortion {
        WatchMealPortion(foodID: id, quantity: quantity, unit: unit, gramsPerUnit: grams)
    }

    private func log(_ day: String, _ block: String, _ portion: WatchMealPortion, planned: Bool = false) -> WatchMealLog {
        WatchMealLog(day: day, block: block, portion: portion, kcal: portion.quantity, planned: planned)
    }

    private func snapshot(
        revision: UInt64 = 1,
        logs: [WatchMealLog] = [],
        favourites: [WatchMealPortion] = [],
        memory: [String: [WatchMealPortion]] = [:],
        acknowledged: [UUID] = [],
        ownerID: UUID? = nil
    ) -> WatchMealSnapshot {
        let ids = Set(logs.map(\.portion.foodID) + favourites.map(\.foodID) + memory.values.flatMap { $0.map(\.foodID) })
        return WatchMealSnapshot(
            ownerID: ownerID ?? owner, revision: revision,
            blocks: [
                WatchMealBlock(id: "breakfast", label: "Breakfast", time: "07:00"),
                WatchMealBlock(id: "lunch", label: "Lunch", time: "13:00"),
                WatchMealBlock(id: "snack", label: "Snack", time: "16:00"),
            ],
            foods: ids.sorted().map { food($0) },
            logs: logs, favourites: favourites, memory: memory, acknowledgedIDs: acknowledged
        )
    }

    private func state(_ snapshot: WatchMealSnapshot) -> WatchMealState {
        var state = WatchMealState()
        XCTAssertTrue(state.accept(snapshot, ownerID: owner))
        return state
    }

    // MARK: - Ranking

    func testYesterdaysSameMealComesFirstInItsOrderAndAmounts() {
        let state = state(snapshot(
            logs: [
                log(yesterday, "breakfast", portion("oats", 60)),
                log(yesterday, "breakfast", portion("skyr", 250)),
                log(yesterday, "breakfast", portion("berries", 100)),
                log(yesterday, "lunch", portion("rice", 200)),
            ],
            favourites: [portion("banana", 1, "piece", grams: 120), portion("skyr", 170)],
            memory: ["breakfast": [portion("coffee", 200, "ml"), portion("oats", 40)]]
        ))

        let offered = state.suggestions(day: today, block: "breakfast")
        XCTAssertEqual(offered.map(\.food.id), ["oats", "skyr", "berries", "banana", "coffee"])
        XCTAssertEqual(offered.map(\.reason), [.yesterday, .yesterday, .yesterday, .favourite, .recent])
        XCTAssertEqual(offered.prefix(3).map(\.portion.quantity), [60, 250, 100],
                       "Yesterday's amounts, not the favourite's or Food Memory's")
        XCTAssertFalse(offered.contains { $0.food.id == "rice" }, "Lunch's food stays in lunch")
    }

    func testFavouritesThisMealUsesComeFirstAtThisMealsAmount() {
        let state = state(snapshot(
            favourites: [portion("banana", 1, "piece", grams: 120), portion("whey", 30), portion("eggs", 2, "piece", grams: 55)],
            memory: ["breakfast": [portion("eggs", 3, "piece", grams: 55), portion("whey", 25)]]
        ))

        let offered = state.suggestions(day: today, block: "breakfast")
        XCTAssertEqual(offered.map(\.food.id), ["eggs", "whey", "banana"])
        XCTAssertEqual(offered.map(\.reason), [.favourite, .favourite, .favourite])
        XCTAssertEqual(offered.map(\.portion.quantity), [3, 25, 1])
    }

    func testEachMealOffersOnlyTheFavouritesSavedToIt() {
        var published = snapshot(favourites: [portion("oats", 60), portion("whey", 30), portion("potato", 200)])
        published.favouritesByBlock = ["breakfast": ["oats", "whey"], "lunch": ["whey", "potato"], "snack": []]
        let state = state(published)

        XCTAssertEqual(state.suggestions(day: today, block: "breakfast").map(\.food.id), ["oats", "whey"])
        XCTAssertEqual(state.suggestions(day: today, block: "lunch").map(\.food.id), ["whey", "potato"])
        XCTAssertTrue(state.suggestions(day: today, block: "snack").isEmpty, "Breakfast's oats stay out of the snack")
        let older = self.state(snapshot(favourites: [portion("oats", 60), portion("whey", 30)]))
        XCTAssertEqual(older.suggestions(day: today, block: "snack").count, 2,
                       "A phone older than favourites per meal: every favourite everywhere, as before")
    }

    func testAStarInsideAMealSavesTheFavouriteToThatMealOnly() throws {
        let plain = FoodPreference(
            id: UUID(), userID: owner, foodID: UUID(), personalName: nil, aliases: [], favourite: false,
            usualAmount: nil, usualUnit: nil, usageCount: 3, lastUsedAt: nil, hidden: false
        )
        let dinner = plain.starred(true, in: "dinner")
        XCTAssertTrue(dinner.isFavourite(in: "dinner"))
        XCTAssertFalse(dinner.isFavourite(in: "breakfast"))
        XCTAssertTrue(dinner.isFavourite(in: nil), "Still a favourite where no meal is asked about")
        let evening = dinner.starred(true, in: "post_workout")
        XCTAssertEqual(evening.favouriteMealBlocks, ["dinner", "post_workout"])
        let none = evening.starred(false, in: "dinner").starred(false, in: "post_workout")
        XCTAssertFalse(none.favourite)
        XCTAssertEqual(none.favouriteMealBlocks, [])

        var everywhere = plain
        everywhere.favourite = true
        XCTAssertTrue(["breakfast", "lunch", "dinner", "snack", "post_workout"].allSatisfy { everywhere.isFavourite(in: $0) },
                      "A favourite from before meals had their own is in every meal")
        XCTAssertEqual(Set(everywhere.starred(false, in: "dinner").favouriteMealBlocks ?? []),
                       ["breakfast", "lunch", "snack", "post_workout"], "Unstarred at dinner, kept everywhere else")
        XCTAssertEqual(everywhere.starred(true, in: "dinner"), everywhere)

        XCTAssertTrue(dinner.starred(true, in: nil).isFavourite(in: "breakfast"), "A star outside a meal is every meal")
        XCTAssertFalse(dinner.starred(false, in: nil).favourite)

        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(none)) as? [String: Any])
        XCTAssertEqual(sent["favourite_meal_blocks"] as? [String], [],
                       "The list always travels, so the upsert replaces what the server held")
        let legacy = try JSONEncoder().encode(plain)
        XCTAssertNil(try JSONDecoder().decode(FoodPreference.self, from: legacy).favouriteMealBlocks)
    }

    func testFoodsAlreadyInTodaysMealAndPlannedPrescriptionsAreNotOffered() {
        let state = state(snapshot(logs: [
            log(yesterday, "breakfast", portion("oats", 60)),
            log(yesterday, "breakfast", portion("plan", 1, "serving", grams: 300), planned: true),
            log(yesterday, "breakfast", portion("skyr", 250)),
            log(today, "breakfast", portion("oats", 70)),
        ]))

        XCTAssertEqual(state.suggestions(day: today, block: "breakfast").map(\.food.id), ["skyr"])
        XCTAssertEqual(state.logged(day: today, block: "breakfast").map(\.portion.quantity), [70])
    }

    func testAMealLoggedOnTheWatchYesterdayLeadsTodayBeforeThePhoneHasSeenIt() throws {
        var state = state(snapshot(favourites: [portion("banana", 1, "piece", grams: 120)]))
        _ = try XCTUnwrap(state.add([(food("oats"), portion("oats", 55))], block: "breakfast", day: yesterday))

        let offered = state.suggestions(day: today, block: "breakfast")
        XCTAssertEqual(offered.map(\.food.id), ["oats", "banana"])
        XCTAssertEqual(offered.first?.reason, .yesterday)
        XCTAssertEqual(offered.first?.portion.quantity, 55)
    }

    // MARK: - The Watch away from the phone

    func testAnAdditionWaitsOnTheWatchUntilThePhoneConfirmsIt() throws {
        var state = state(snapshot(revision: 1))
        let added = try XCTUnwrap(state.add([(food("oats", kcal: 372), portion("oats", 60))], block: "breakfast", day: today))
        XCTAssertEqual(state.logged(day: today, block: "breakfast").map(\.isPending), [true])
        XCTAssertEqual(state.kcal(day: today), 223, "372 kcal per 100 g, 60 g, rounded as the phone stores it")

        // A snapshot the phone sent before it saw the addition does not drop it.
        XCTAssertTrue(state.accept(snapshot(revision: 2), ownerID: owner))
        XCTAssertEqual(state.pending.map(\.id), [added.id])

        // Confirmed: the phone's record replaces the Watch's copy, so it is counted once.
        let saved = WatchMealLog(day: today, block: "breakfast", portion: portion("oats", 60), kcal: 223)
        XCTAssertTrue(state.accept(snapshot(revision: 3, logs: [saved], acknowledged: [added.id]), ownerID: owner))
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.logged(day: today, block: "breakfast").map(\.isPending), [false])
        XCTAssertEqual(state.kcal(day: today), 223)
    }

    func testASavedAdditionIsCountedOnceEvenBeforeThePhoneAcknowledgesIt() throws {
        var state = state(snapshot(revision: 1))
        let added = try XCTUnwrap(state.add([(food("oats", kcal: 372), portion("oats", 60))], block: "breakfast", day: today))
        var saved = portion("oats", 60)
        saved.entryID = try XCTUnwrap(added.items.first?.id)
        XCTAssertTrue(state.accept(snapshot(revision: 2, logs: [
            WatchMealLog(day: today, block: "breakfast", portion: saved, kcal: 223),
        ]), ownerID: owner))
        XCTAssertEqual(state.pending.map(\.id), [added.id], "Kept until acknowledged: the phone's copy may not be on the server yet")
        XCTAssertEqual(state.logged(day: today, block: "breakfast").map(\.isPending), [false])
        XCTAssertEqual(state.kcal(day: today), 223)
        XCTAssertEqual(state.logged(day: today, block: "breakfast").map(\.id), [saved.entryID?.uuidString],
                       "The row keeps its identity from pending to confirmed")
    }

    func testOlderAndOtherAccountsSnapshotsAreIgnored() {
        var state = state(snapshot(revision: 5, favourites: [portion("oats", 60)]))
        XCTAssertFalse(state.accept(snapshot(revision: 4), ownerID: owner))
        XCTAssertFalse(state.accept(snapshot(revision: 5), ownerID: owner))
        XCTAssertFalse(state.accept(snapshot(revision: 9, ownerID: UUID()), ownerID: owner))
        XCTAssertEqual(state.snapshot?.revision, 5)
    }

    func testNothingIsRecordedForAnUnknownBlockOrAnAmountThatCannotBeLogged() {
        var state = state(snapshot())
        XCTAssertNil(state.add([(food("oats"), portion("oats", 60))], block: "brunch", day: today))
        XCTAssertNil(state.add([(food("oats"), portion("oats", 0))], block: "breakfast", day: today))
        XCTAssertNil(state.add([(food("eggs"), portion("eggs", 2, "piece", grams: 0))], block: "breakfast", day: today))
        XCTAssertNil(state.add([], block: "breakfast", day: today))
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testUnconfirmedAdditionsSurviveTheWatchRestarting() throws {
        var state = state(snapshot())
        _ = try XCTUnwrap(state.add([(food("oats"), portion("oats", 60))], block: "breakfast", day: today))
        let restored = try JSONDecoder().decode(WatchMealState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.logged(day: today, block: "breakfast").count, 1)
    }

    // MARK: - Clock

    func testTheBlockNearestTheClockIsTheCurrentOne() {
        let blocks = snapshot().blocks
        XCTAssertEqual(WatchMealState.currentBlock(blocks, minute: 9 * 60 + 30), "breakfast")
        XCTAssertEqual(WatchMealState.currentBlock(blocks, minute: 11 * 60), "lunch")
        XCTAssertEqual(WatchMealState.currentBlock(blocks, minute: 14 * 60 + 30), "lunch", "A tie goes to the earlier block")
        XCTAssertEqual(WatchMealState.currentBlock(blocks, minute: 23 * 60), "snack")
        XCTAssertNil(WatchMealState.currentBlock([], minute: 0))
    }

    func testTheDayBeforeFollowsTheCalendar() {
        XCTAssertEqual(WatchMealState.previousDay("2026-03-01"), "2026-02-28")
        XCTAssertEqual(WatchMealState.previousDay("2024-03-01"), "2024-02-29")
        XCTAssertEqual(WatchMealState.previousDay("2027-01-01"), "2026-12-31")
        XCTAssertEqual(WatchMealState.previousDay("2026-03-30"), "2026-03-29", "The night the clocks go forward")
        XCTAssertEqual(WatchMealState.previousDay("2026-10-26"), "2026-10-25", "The night they go back")
        XCTAssertEqual(WatchMealState.previousDay("not a day"), "")
    }

    // MARK: - Phone fixtures

    private func catalogueFood(_ id: UUID, _ name: String, kcal: Double, piece: Double? = nil) -> Food {
        Food(
            id: id.uuidString.lowercased(), ownerUserID: nil, name: name, namesI18n: [:], brand: nil, barcode: nil,
            source: "test", providerProductID: nil, externalImageURL: nil, packageQuantity: nil,
            nutritionBasis: "per_100g", preparationState: "as_sold",
            kcal100: kcal, protein100: 10, carbs100: 10, fat100: 5,
            fibre100: nil, sugar100: nil, saturatedFat100: nil, salt100: nil,
            servingAmount: nil, servingUnit: nil, servingGramsOrML: nil, pieceGramsOrML: piece,
            confidence: "verified"
        )
    }

    private func meal(
        _ id: UUID = UUID(), day: String, slot: String, at time: String = "08:00", key: String? = nil, ownerID: UUID? = nil
    ) -> LoggedMeal {
        LoggedMeal(
            id: id, userID: ownerID ?? owner, localDate: day, mealSlot: slot, displayName: slot.capitalized,
            sourcePresetID: nil, sourcePlannedMealID: nil, loggedAt: "\(day)T\(time):00Z",
            clientIdempotencyKey: key ?? "ios-meal-op-\(id.uuidString.lowercased())", loggedAs: "custom",
            totalKcal: 0, totalProteinG: 0, totalCarbsG: 0, totalFatG: 0
        )
    }

    private func entry(
        _ id: UUID = UUID(), meal: UUID, food: UUID? = nil, name: String, kcal100: Double,
        quantity: Double, unit: String = "g", grams: Double? = nil, order: Int = 0, ownerID: UUID? = nil
    ) -> LoggedFoodEntry {
        let amount = grams ?? quantity
        return LoggedFoodEntry(
            id: id, mealID: meal, userID: ownerID ?? owner, foodID: food, sortOrder: order,
            snapshotName: name, snapshotBrand: nil, snapshotPreparationState: "as_sold",
            snapshotNutritionBasis: "per_100g", snapshotKcal100: kcal100, snapshotProtein100: 10,
            snapshotCarbs100: 10, snapshotFat100: 5, quantity: quantity, unit: unit, equivalentAmount: amount,
            kcal: (kcal100 * amount / 100).rounded(), proteinG: 0, carbsG: 0, fatG: 0
        )
    }

    // MARK: - What the phone publishes

    func testThePhonePublishesTheDaylineBlocksAndTwoDaysOfWhatTheyHeld() throws {
        let oats = UUID()
        let banana = UUID()
        let breakfastYesterday = UUID()
        let breakfastToday = UUID()
        let recovery = UUID()
        let old = UUID()
        let foreign = UUID()
        var data = DashboardData.empty
        data.foods = [catalogueFood(oats, "Oats", kcal: 372), catalogueFood(banana, "Banana", kcal: 89, piece: 120)]
        data.loggedMeals = [
            meal(breakfastYesterday, day: yesterday, slot: "breakfast"),
            meal(breakfastToday, day: today, slot: "breakfast", at: "07:30"),
            meal(recovery, day: today, slot: "snack", at: "21:10",
                 key: "ios-meal-op-x|apex-meal-block=post_workout"),
            meal(old, day: "2026-11-19", slot: "lunch"),
            meal(foreign, day: today, slot: "breakfast", ownerID: UUID()),
        ]
        let yesterdayOats = UUID()
        data.loggedFoodEntries = [
            entry(yesterdayOats, meal: breakfastYesterday, food: oats, name: "Oats", kcal100: 372, quantity: 60),
            entry(meal: breakfastYesterday, name: "Home granola", kcal100: 450, quantity: 40, order: 1),
            entry(meal: breakfastToday, food: banana, name: "Banana", kcal100: 89, quantity: 1, unit: "piece", grams: 120),
            entry(meal: recovery, name: "Shake", kcal100: 80, quantity: 300),
            entry(meal: old, name: "Rice", kcal100: 130, quantity: 200),
            entry(meal: foreign, name: "Someone else's toast", kcal100: 260, quantity: 50),
        ]
        data.foodPreferences = [FoodPreference(
            id: UUID(), userID: owner, foodID: banana, personalName: nil, aliases: [], favourite: true,
            usualAmount: 2, usualUnit: "piece", usageCount: 4, lastUsedAt: "\(today)T07:30:00Z", hidden: false
        )]

        let published = WatchMealCompanion.snapshot(
            ownerID: owner, day: today, data: data, language: .english, localize: { "·\($0)" },
            revision: 7, acknowledgedIDs: []
        )

        XCTAssertEqual(published.blocks.map(\.id), ["breakfast", "lunch", "snack", "dinner", "post_workout"])
        XCTAssertEqual(published.blocks.first?.label, "·Breakfast", "The dayline's own name, in the app's language")
        XCTAssertEqual(published.logs.map(\.day), [yesterday, yesterday, today, today])
        XCTAssertEqual(published.logs.map(\.block), ["breakfast", "breakfast", "breakfast", "post_workout"])
        XCTAssertEqual(published.logs.first?.portion.entryID, yesterdayOats)
        XCTAssertEqual(published.logs.first?.kcal, 223)
        XCTAssertEqual(published.logs[2].portion.gramsPerUnit, 120)
        XCTAssertFalse(published.logs.contains { $0.portion.quantity == 200 || $0.portion.quantity == 50 },
                       "Older days and other accounts stay off the Watch")
        XCTAssertEqual(published.favourites.map(\.foodID), [banana.uuidString.lowercased()])
        XCTAssertEqual(published.favourites.first?.quantity, 1, "The amount last logged wins over the usual one")
        XCTAssertEqual(published.memory["breakfast"]?.first?.foodID, banana.uuidString.lowercased())
        XCTAssertTrue(published.memory["breakfast"]?.contains { $0.foodID == oats.uuidString.lowercased() } == true)
        let ids = Set(published.foods.map(\.id))
        XCTAssertTrue((published.logs.map(\.portion.foodID) + published.favourites.map(\.foodID)).allSatisfy(ids.contains))

        // What the Watch offers for breakfast today from this: yesterday's two foods first.
        var watch = WatchMealState()
        watch.accept(published, ownerID: owner)
        XCTAssertEqual(watch.suggestions(day: today, block: "breakfast").prefix(2).map(\.food.name), ["Oats", "Home granola"])
    }

    func testThePhoneSendsEachMealOnlyTheFavouritesSavedToIt() {
        let (oats, potato, whey) = (UUID(), UUID(), UUID())
        var data = DashboardData.empty
        data.foods = [catalogueFood(oats, "Oats", kcal: 372), catalogueFood(potato, "Sweet potato", kcal: 90),
                      catalogueFood(whey, "Whey", kcal: 370)]
        func favourite(_ food: UUID, _ blocks: [String]?) -> FoodPreference {
            FoodPreference(
                id: UUID(), userID: owner, foodID: food, personalName: nil, aliases: [], favourite: true,
                usualAmount: 50, usualUnit: "g", usageCount: 1, lastUsedAt: nil, hidden: false, favouriteMealBlocks: blocks
            )
        }
        data.foodPreferences = [favourite(oats, ["breakfast"]), favourite(potato, ["dinner", "post_workout"]), favourite(whey, nil)]

        let published = WatchMealCompanion.snapshot(
            ownerID: owner, day: today, data: data, language: .english, localize: { $0 }, revision: 1, acknowledgedIDs: []
        )
        let id = { (food: UUID) in food.uuidString.lowercased() }
        XCTAssertEqual(Set(published.favouritesByBlock?["breakfast"] ?? []), [id(oats), id(whey)])
        XCTAssertEqual(Set(published.favouritesByBlock?["dinner"] ?? []), [id(potato), id(whey)])
        XCTAssertEqual(published.favouritesByBlock?["lunch"], [id(whey)])
        XCTAssertEqual(published.favourites.count, 3, "A food saved to several meals travels once")
    }

    func testAFoodOnlyHistoryKnowsIsOneFoodSoTodaysServingIsNotOfferedAgain() {
        let yesterdaysMeal = UUID()
        let todaysMeal = UUID()
        var data = DashboardData.empty
        data.loggedMeals = [meal(yesterdaysMeal, day: yesterday, slot: "breakfast"), meal(todaysMeal, day: today, slot: "breakfast")]
        data.loggedFoodEntries = [
            entry(meal: yesterdaysMeal, name: "Home granola", kcal100: 450, quantity: 40),
            entry(meal: yesterdaysMeal, name: "Oat milk", kcal100: 46, quantity: 200, order: 1),
            entry(meal: todaysMeal, name: "Home granola", kcal100: 450, quantity: 50),
        ]
        let published = WatchMealCompanion.snapshot(ownerID: owner, day: today, data: data, language: .english,
                                                    localize: { $0 }, revision: 1, acknowledgedIDs: [])
        var watch = WatchMealState()
        watch.accept(published, ownerID: owner)

        XCTAssertEqual(watch.suggestions(day: today, block: "breakfast").map(\.food.name), ["Oat milk"])
        XCTAssertEqual(Set(published.logs.map(\.portion.foodID)).count, 2, "Both granola entries are the same food")
    }

    func testTheSnapshotStaysSmallEnoughForTheWatchConnection() throws {
        var data = DashboardData.empty
        let foods = (0..<300).map { catalogueFood(UUID(), "Food number \($0) with a long descriptive name", kcal: 100) }
        data.foods = foods
        for dayOffset in 0..<60 {
            let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(byAdding: .day, value: -dayOffset,
                to: XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: today))))
            for (index, slot) in ["breakfast", "lunch", "snack", "dinner", "snack"].enumerated() {
                let mealID = UUID()
                data.loggedMeals.append(meal(mealID, day: date.apexDateKey, slot: slot, at: String(format: "%02d:00", 7 + index * 3)))
                for order in 0..<6 {
                    let food = foods[(dayOffset * 31 + index * 7 + order * 13) % foods.count]
                    data.loggedFoodEntries.append(entry(meal: mealID, food: UUID(uuidString: food.id), name: food.name,
                                                        kcal100: 100, quantity: 80, order: order))
                }
            }
        }
        data.foodPreferences = foods.prefix(40).map {
            FoodPreference(id: UUID(), userID: owner, foodID: UUID(uuidString: $0.id)!, personalName: nil, aliases: [],
                           favourite: true, usualAmount: 100, usualUnit: "g", usageCount: 1, lastUsedAt: nil, hidden: false)
        }
        let published = WatchMealCompanion.snapshot(ownerID: owner, day: today, data: data, language: .english,
                                                    localize: { $0 }, revision: 1, acknowledgedIDs: (0..<64).map { _ in UUID() })
        let bytes = try published.encoded().count
        XCTAssertEqual(published.favourites.count, WatchMealCompanion.favouriteLimit)
        XCTAssertLessThan(bytes, 16_000, "A heavy two months fits the shared application context (\(bytes) bytes)")
        XCTAssertEqual(try WatchMealSnapshot.decode(published.encoded()), published)
    }

    // MARK: - How the phone adds Watch foods

    func testAWatchFoodCopiesTheEntryItWasOfferedFromAtTheWatchsAmount() throws {
        let source = entry(meal: UUID(), name: "Eggs", kcal100: 143, quantity: 2, unit: "piece", grams: 110)
        var amount = portion("entry:x", 3, "piece", grams: 55)
        amount.entryID = source.id
        let watchFood = food("entry:x", kcal: 143)
        let item = WatchMealItem(id: UUID(), food: watchFood, portion: amount)

        let copied = try XCTUnwrap(WatchMealCompanion.composerItem(item, foods: [], ownedEntries: [source]))
        XCTAssertEqual(copied.id, item.id, "The Watch's ID is how a replay is recognised")
        XCTAssertEqual(copied.name, "Eggs")
        XCTAssertEqual(copied.unit, "piece")
        XCTAssertEqual(copied.quantity, 3)
        XCTAssertEqual(copied.equivalentAmount, 165)
        XCTAssertEqual(copied.nutrients.kcal.rounded(), amount.kcal(watchFood), "The phone logs what the Watch showed")
    }

    func testAFoodThePhoneNoLongerHoldsIsStillLoggedWithoutAFoodReference() throws {
        let missing = UUID().uuidString.lowercased()
        let item = WatchMealItem(id: UUID(), food: food(missing, kcal: 200), portion: portion(missing, 150))
        let rebuilt = try XCTUnwrap(WatchMealCompanion.composerItem(item, foods: [], ownedEntries: []))
        XCTAssertNil(rebuilt.foodID)
        XCTAssertEqual(rebuilt.nutrients.kcal, 300)
        XCTAssertNil(WatchMealCompanion.composerItem(
            WatchMealItem(id: UUID(), food: food("x"), portion: portion("x", 0)), foods: [], ownedEntries: []
        ))
    }

    func testAppendingKeepsEveryFoodTheMealHeldAndNamesTheVersionItRead() {
        let mealID = UUID()
        let existing = meal(mealID, day: today, slot: "snack", at: "21:05", key: "ios-meal-op-a|apex-meal-block=post_workout")
        let saved = [
            entry(meal: mealID, name: "Shake", kcal100: 80, quantity: 300),
            entry(meal: mealID, name: "Banana", kcal100: 89, quantity: 120, order: 1),
        ]
        let watchItem = MealComposerItem(entry: entry(meal: UUID(), name: "Whey", kcal100: 380, quantity: 30))
        let operationID = UUID()

        let draft = WatchMealCompanion.appending(
            [watchItem], to: existing,
            snapshot: MealEditSnapshot(version: existing.clientIdempotencyKey, entries: saved),
            operationID: operationID, fallbackTime: Date()
        )

        XCTAssertEqual(draft.id, mealID)
        XCTAssertEqual(draft.replaceMealID, mealID)
        XCTAssertEqual(draft.items.map(\.name), ["Shake", "Banana", "Whey"])
        XCTAssertEqual(draft.expectedEntryIDs, saved.map(\.id))
        XCTAssertEqual(draft.expectedMealVersion, existing.clientIdempotencyKey)
        XCTAssertEqual(draft.mealSlot, "post_workout", "The evening recovery block stays itself")
        XCTAssertEqual(draft.finishedAt.ISO8601Format(), "\(today)T21:05:00Z", "Adding food does not move the meal")
        XCTAssertEqual(draft.saveOperationID, operationID)

        let again = WatchMealCompanion.appending(
            [watchItem], to: existing,
            snapshot: MealEditSnapshot(version: "v2", entries: saved + [entry(watchItem.id, meal: mealID, name: "Whey", kcal100: 380, quantity: 30)]),
            operationID: operationID, fallbackTime: Date()
        )
        XCTAssertEqual(again.items.count, 3, "A food the server already holds is not added twice")
    }

    func testWatchFoodsGoToTheBlocksFirstMealButNeverIntoOneLoggedFromThePlan() {
        let planned = LoggedMeal(
            id: UUID(), userID: owner, localDate: today, mealSlot: "lunch", displayName: "Lunch",
            sourcePresetID: nil, sourcePlannedMealID: UUID(), loggedAt: "\(today)T12:00:00Z",
            clientIdempotencyKey: "ios-meal-op-plan", loggedAs: "planned",
            totalKcal: 0, totalProteinG: 0, totalCarbsG: 0, totalFatG: 0
        )
        let later = meal(day: today, slot: "lunch", at: "13:30")
        let earlier = meal(day: today, slot: "lunch", at: "12:45")
        XCTAssertEqual(WatchMealCompanion.blockMeal(day: today, block: "lunch", ownerID: owner,
                                                    meals: [planned, later, earlier])?.id, earlier.id)
        XCTAssertNil(WatchMealCompanion.blockMeal(day: today, block: "lunch", ownerID: owner, meals: [planned]))
    }

    func testTheWatchTimeStandsNearTheBlockAndTheBlockTimeOtherwise() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let morning = try XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: today))
        let atHalfPastSeven = morning.addingTimeInterval(7.5 * 3_600)
        let atTwo = morning.addingTimeInterval(14 * 3_600)
        XCTAssertEqual(WatchMealCompanion.finishedAt(addedAt: atHalfPastSeven, day: today, blockTime: "07:00", calendar: calendar),
                       atHalfPastSeven)
        XCTAssertEqual(WatchMealCompanion.finishedAt(addedAt: atTwo, day: today, blockTime: "07:00", calendar: calendar),
                       morning.addingTimeInterval(7 * 3_600), "A late catch-up keeps breakfast at breakfast time")
    }

    func testThePhoneRemembersRecentConfirmationsAndItsRevisionOnlyMovesForward() {
        var journal = WatchMealJournal()
        let first = journal.nextRevision(now: 1_000)
        XCTAssertGreaterThan(journal.nextRevision(now: 10), first, "A clock set back cannot reorder snapshots")
        let ids = (0..<300).map { _ in UUID() }
        ids.forEach { journal.acknowledge($0) }
        journal.acknowledge(ids.last!)
        XCTAssertEqual(journal.acknowledgedIDs, Array(ids.suffix(64)))
    }

    // MARK: - End to end on a local session

    private func sandbox() throws -> (AppSession, AccountOperationLease) {
        let session = AppSession(developerSandboxRole: .coach)
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data.loggedMeals = []
        session.data.loggedFoodEntries = []
        return (session, operation)
    }

    private func mutation(_ ownerID: UUID, block: String, items: [WatchMealItem]) -> WatchMealMutation {
        WatchMealMutation(ownerID: ownerID, day: Date().apexDateKey, block: block, addedAt: Date(), items: items)
    }

    func testWatchFoodsJoinTheBlocksMealOnceEvenWhenTheyArriveTwice() async throws {
        let (session, operation) = try sandbox()
        let ownerID = operation.ownerID
        let day = Date().apexDateKey
        let breakfast = meal(day: day, slot: "breakfast", at: "07:10", ownerID: ownerID)
        let toast = entry(meal: breakfast.id, name: "Toast", kcal100: 260, quantity: 60, ownerID: ownerID)
        session.data.loggedMeals = [breakfast]
        session.data.loggedFoodEntries = [toast]

        let item = WatchMealItem(id: UUID(), food: food("entry:skyr", kcal: 63), portion: portion("entry:skyr", 170))
        let sent = mutation(ownerID, block: "breakfast", items: [item])
        try await session.addWatchMeal(sent, operation: operation)
        func breakfastFoods() -> [LoggedFoodEntry] {
            session.data.loggedFoodEntries.filter { $0.mealID == breakfast.id }.sorted { $0.sortOrder < $1.sortOrder }
        }
        XCTAssertEqual(breakfastFoods().last?.id, item.id, "The entry carries the Watch's ID")
        XCTAssertEqual(breakfastFoods().last?.kcal, 107)

        // Sent again, as after the phone stopped before acknowledging it: saved again as a replay.
        try await session.addWatchMeal(sent, operation: operation)
        let meals = session.data.loggedMeals.filter { $0.localDate == day && MealBlocks.kind(for: $0) == "breakfast" }
        XCTAssertEqual(meals.map(\.id), [breakfast.id], "Still one breakfast")
        XCTAssertEqual(breakfastFoods().map(\.snapshotName), ["Toast", "Entry:Skyr"], "The toast stays; the skyr is there once")
    }

    func testWatchFoodsStartTheMealOfAnEmptyBlock() async throws {
        let (session, operation) = try sandbox()
        let ownerID = operation.ownerID
        let item = WatchMealItem(id: UUID(), food: food("entry:rice", kcal: 130), portion: portion("entry:rice", 200))
        let sent = mutation(ownerID, block: "lunch", items: [item])

        try await session.addWatchMeal(sent, operation: operation)

        let lunch = try XCTUnwrap(session.data.loggedMeals.first { MealBlocks.kind(for: $0) == "lunch" })
        XCTAssertEqual(lunch.id, APEXStableID.scopedUUID(namespace: "watch-meal", date: sent.id.uuidString.lowercased(), userID: ownerID))
        XCTAssertEqual(lunch.displayName, LanguageState.shared.text("Lunch"))
        XCTAssertEqual(session.data.loggedFoodEntries.filter { $0.mealID == lunch.id }.map(\.id), [item.id])
    }
}
