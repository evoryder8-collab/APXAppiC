import Foundation

/// The iPhone half of meals on the Watch: what it publishes, and how a Watch addition joins the dayline.
enum WatchMealCompanion {
    static let favouriteLimit = 12
    static let memoryLimit = 8

    /// The dayline's blocks for `day`, what they held on it and the day before, and the foods worth offering.
    static func snapshot(
        ownerID: UUID,
        day: String,
        data: DashboardData,
        language: AppLanguage,
        localize: (String) -> String,
        revision: UInt64,
        acknowledgedIDs: [UUID]
    ) -> WatchMealSnapshot {
        let previous = WatchMealState.previousDay(day)
        let blocks = MealBlocks.enabled(data.settings?.addons["meal_blocks"])
        let catalogue = Dictionary(data.foods.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let meals = data.loggedMeals.filter { $0.userID == ownerID }
        let entries = data.loggedFoodEntries.filter { $0.userID == ownerID }
        var entriesByMeal: [UUID: [LoggedFoodEntry]] = [:]
        for entry in entries { entriesByMeal[entry.mealID, default: []].append(entry) }
        for mealID in entriesByMeal.keys { entriesByMeal[mealID]?.sort { $0.sortOrder < $1.sortOrder } }

        /* Each food's latest logged entry: its snapshot is what the Watch counts
           and what the phone copies when it is added, as Same as yesterday does. */
        let times = finishTimes(meals)
        func isLater(_ left: LoggedMeal, _ right: LoggedMeal) -> Bool {
            let (leftTime, rightTime) = (times[left.id] ?? .distantPast, times[right.id] ?? .distantPast)
            return leftTime == rightTime ? left.id.uuidString > right.id.uuidString : leftTime > rightTime
        }
        var latest: [String: LoggedFoodEntry] = [:]
        for meal in meals.sorted(by: isLater) {
            for entry in entriesByMeal[meal.id] ?? [] where latest[key(entry)] == nil {
                latest[key(entry)] = entry
            }
        }

        var foods: [String: WatchMealFood] = [:]
        func remember(_ id: String) -> Bool {
            if foods[id] != nil { return true }
            let named = catalogue[id]?.localizedName(language)
            if let entry = latest[id] {
                foods[id] = WatchMealFood(
                    id: id, name: named ?? entry.snapshotName, kcal100: entry.snapshotKcal100,
                    protein100: entry.snapshotProtein100, carbs100: entry.snapshotCarbs100, fat100: entry.snapshotFat100,
                    basis: entry.snapshotNutritionBasis, preparation: entry.snapshotPreparationState
                )
            } else if let food = catalogue[id], FoodPortionMath.isComplete(food) {
                foods[id] = WatchMealFood(
                    id: id, name: named ?? food.name, kcal100: food.kcal100 ?? 0,
                    protein100: food.protein100 ?? 0, carbs100: food.carbs100 ?? 0, fat100: food.fat100 ?? 0,
                    basis: food.nutritionBasis, preparation: food.preparationState
                )
            }
            return foods[id] != nil
        }

        var logs: [WatchMealLog] = []
        for meal in meals.filter({ $0.localDate == day || $0.localDate == previous })
            .sorted(by: { isLater($1, $0) }) {
            let block = MealBlocks.kind(for: meal)
            for entry in entriesByMeal[meal.id] ?? [] {
                let id = key(entry)
                guard remember(id) else { continue }
                logs.append(WatchMealLog(
                    day: meal.localDate, block: block,
                    portion: WatchMealPortion(
                        foodID: id, quantity: entry.quantity, unit: entry.unit,
                        gramsPerUnit: entry.quantity > 0 ? entry.equivalentAmount / entry.quantity : 0,
                        entryID: entry.id
                    ),
                    kcal: entry.kcal,
                    planned: MealMemory.isPlannedPrescription(entry, foodByID: catalogue)
                ))
            }
        }

        /* Each block gets the favourites saved to it, most recently used first; the portions are
           shared, so a food starred for several meals travels once. */
        var favourites: [WatchMealPortion] = []
        var favouritePortions: [UUID: WatchMealPortion?] = [:]
        func favouritePortion(_ preference: FoodPreference) -> WatchMealPortion? {
            if let cached = favouritePortions[preference.foodID] { return cached }
            let id = preference.foodID.uuidString.lowercased()
            let entry = latest[id]
            var portion: WatchMealPortion?
            if let food = catalogue[id] ?? entry.map(MealMemory.food(from:)) {
                // The amount confirmed in history wins over the preference row, exactly as the phone opens it.
                let selection = FoodPortionMath.defaultSelection(
                    food, preference: preference,
                    remembered: entry.map { MealMemory.Selection(foodID: id, quantity: $0.quantity, unit: $0.unit) }
                )
                if let perUnit = gramsPerUnit(food, quantity: selection.quantity, unit: selection.unit.rawValue, entry: entry),
                   remember(id) {
                    portion = WatchMealPortion(
                        foodID: id, quantity: selection.quantity, unit: selection.unit.rawValue,
                        gramsPerUnit: perUnit, entryID: entry?.id
                    )
                }
            }
            favouritePortions[preference.foodID] = portion
            if let portion { favourites.append(portion) }
            return portion
        }
        let starred = data.foodPreferences
            .filter { $0.userID == ownerID && $0.favourite && !$0.hidden }
            .sorted { ($0.lastUsedAt ?? "") > ($1.lastUsedAt ?? "") }
        var favouritesByBlock: [String: [String]] = [:]
        for block in blocks {
            var ids: [String] = []
            for preference in starred where ids.count < favouriteLimit && preference.isFavourite(in: block.kind) {
                if let portion = favouritePortion(preference) { ids.append(portion.foodID) }
            }
            favouritesByBlock[block.kind] = ids
        }

        var memory: [String: [WatchMealPortion]] = [:]
        for block in blocks {
            let ranked = MealMemory.rank(
                context: MealMemory.Context(date: day, slot: block.kind, blockID: block.id, targetTime: block.time),
                meals: meals, entries: entries, foods: data.foods,
                mealLimit: 0, foodLimit: memoryLimit, presetLimit: 0
            )
            memory[block.kind] = ranked.foods.compactMap { food in
                let id = UUID(uuidString: food.id) != nil ? food.id.lowercased() : food.id
                guard let selection = ranked.selection(for: food.id),
                      let perUnit = gramsPerUnit(food, quantity: selection.quantity, unit: selection.unit, entry: latest[id]),
                      remember(id) else { return nil }
                return WatchMealPortion(
                    foodID: id, quantity: selection.quantity, unit: selection.unit,
                    gramsPerUnit: perUnit, entryID: latest[id]?.id
                )
            }
        }

        return WatchMealSnapshot(
            ownerID: ownerID,
            revision: revision,
            blocks: blocks.map { WatchMealBlock(id: $0.kind, label: localize($0.label), time: $0.time) },
            foods: foods.values.sorted { $0.id < $1.id },
            logs: logs,
            favourites: favourites,
            favouritesByBlock: favouritesByBlock,
            memory: memory,
            acknowledgedIDs: acknowledgedIDs
        )
    }

    /// The block's meal on that day as the dayline matches it: the first one logged into it. A meal logged
    /// from the plan is left alone: unticking the plan deletes it, and the Watch's foods with it.
    static func blockMeal(day: String, block: String, ownerID: UUID, meals: [LoggedMeal]) -> LoggedMeal? {
        func normalized(_ kind: String) -> String {
            kind.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        }
        let candidates = meals
            .filter { $0.userID == ownerID && $0.localDate == day && $0.sourcePlannedMealID == nil
                && normalized(MealBlocks.kind(for: $0)) == normalized(block) }
        let times = finishTimes(candidates)
        return candidates.min { left, right in
            let (leftTime, rightTime) = (times[left.id] ?? .distantPast, times[right.id] ?? .distantPast)
            return leftTime == rightTime ? left.id.uuidString < right.id.uuidString : leftTime < rightTime
        }
    }

    /// A Watch addition as a meal item, copied from the entry it was offered from when this phone still has it.
    static func composerItem(
        _ item: WatchMealItem,
        foods: [Food],
        ownedEntries: [LoggedFoodEntry]
    ) -> MealComposerItem? {
        let portion = item.portion
        var result: MealComposerItem
        if let entryID = portion.entryID, let entry = ownedEntries.first(where: { $0.id == entryID }) {
            result = MealComposerItem(entry: entry)
        } else if let food = foods.first(where: { $0.id.lowercased() == item.food.id }) {
            result = MealComposerItem(food: food, quantity: portion.quantity, unit: portion.unit)
        } else if let foodID = UUID(uuidString: item.food.id),
                  let entry = ownedEntries.first(where: { $0.foodID == foodID }) {
            result = MealComposerItem(entry: entry)
        } else {
            result = MealComposerItem(food: rebuiltFood(item.food), quantity: portion.quantity, unit: portion.unit)
        }
        result.id = item.id
        result.unit = portion.unit
        // The Watch counted this weight per unit; the phone logs the same amount.
        result.recordedPortionMass = portion.gramsPerUnit
        result.setQuantity(portion.quantity)
        return result.isLoggablePortion ? result : nil
    }

    /// The block's meal with the Watch's foods after its own. Every food it held stays, and the edit
    /// names the version it read, so the server refuses it rather than overwrite a newer edit.
    static func appending(
        _ items: [MealComposerItem],
        to meal: LoggedMeal,
        snapshot: MealEditSnapshot,
        operationID: UUID,
        fallbackTime: Date
    ) -> MealComposerDraft {
        let existing = snapshot.entries.map(MealComposerItem.init(entry:))
        let saved = Set(existing.map(\.id))
        return MealComposerDraft(
            id: meal.id,
            localDate: meal.localDate,
            mealSlot: MealBlocks.kind(for: meal),
            displayName: meal.displayName,
            finishedAt: finishTimes([meal])[meal.id] ?? fallbackTime,
            sourcePresetID: meal.sourcePresetID,
            sourcePlannedMealID: meal.sourcePlannedMealID,
            replaceMealID: meal.id,
            loggedAs: MealLogKind.normalized(meal.loggedAs),
            items: existing + items.filter { !saved.contains($0.id) },
            saveOperationID: operationID,
            expectedMealVersion: snapshot.version,
            expectedEntryIDs: snapshot.entries.map(\.id)
        )
    }

    /// A new meal in the block, for a block with nothing in it yet.
    static func newMeal(
        _ items: [MealComposerItem],
        day: String,
        block: String,
        name: String,
        finishedAt: Date,
        mealID: UUID,
        operationID: UUID
    ) -> MealComposerDraft {
        MealComposerDraft(
            id: mealID, localDate: day, mealSlot: block, displayName: name, finishedAt: finishedAt,
            sourcePresetID: nil, sourcePlannedMealID: nil, replaceMealID: nil, loggedAs: "custom",
            items: items, saveOperationID: operationID
        )
    }

    /// When the food was added, if that is near the block's own time on the day; otherwise the block's time,
    /// so a late catch-up does not drag breakfast into the afternoon.
    static func finishedAt(addedAt: Date, day: String, blockTime: String, calendar: Calendar = .current) -> Date {
        let clock = blockTime.split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2, let date = ISO8601DateFormatter.apexDateOnly.date(from: day),
              let scheduled = calendar.date(bySettingHour: clock[0], minute: clock[1], second: 0, of: date)
        else { return addedAt }
        return abs(addedAt.timeIntervalSince(scheduled)) <= 3 * 3_600 ? addedAt : scheduled
    }

    // MARK: - Helpers

    /// Food Memory's name for a food: its catalogue ID, or for a food only history knows, its snapshot,
    /// so every logged copy of it is the same food.
    private static func key(_ entry: LoggedFoodEntry) -> String {
        entry.foodID?.uuidString.lowercased() ?? MealMemory.food(from: entry).id
    }

    private static func gramsPerUnit(_ food: Food, quantity: Double, unit: String, entry: LoggedFoodEntry?) -> Double? {
        if let kind = FoodUnitKind(rawValue: unit),
           let grams = FoodPortionMath.equivalentAmount(food, quantity: quantity, unit: kind), grams > 0 {
            return grams / quantity
        }
        guard let entry, entry.unit == unit, entry.quantity > 0, entry.equivalentAmount > 0 else { return nil }
        return entry.equivalentAmount / entry.quantity
    }

    /// When each meal was eaten, read with one pair of formatters for the whole history.
    private static func finishTimes(_ meals: [LoggedMeal]) -> [UUID: Date] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var times: [UUID: Date] = [:]
        for meal in meals {
            if let time = fractional.date(from: meal.loggedAt) ?? plain.date(from: meal.loggedAt) { times[meal.id] = time }
        }
        return times
    }

    /// Only when neither the catalogue nor any logged entry still holds the food. Its ID is not a UUID,
    /// so the logged entry carries no food reference the server could refuse.
    private static func rebuiltFood(_ food: WatchMealFood) -> Food {
        Food(
            id: "watch:\(food.id)", ownerUserID: nil, name: food.name, namesI18n: [:], brand: nil, barcode: nil,
            source: "apex_cache", providerProductID: nil, externalImageURL: nil, packageQuantity: nil,
            nutritionBasis: food.basis, preparationState: food.preparation,
            kcal100: food.kcal100, protein100: food.protein100, carbs100: food.carbs100, fat100: food.fat100,
            fibre100: nil, sugar100: nil, saturatedFat100: nil, salt100: nil,
            servingAmount: nil, servingUnit: nil, servingGramsOrML: nil, pieceGramsOrML: nil,
            confidence: "complete"
        )
    }
}

/// Which Watch additions this phone has already put on the dayline, per account.
struct WatchMealJournal: Codable, Sendable {
    var revision: UInt64 = 0
    var acknowledgedIDs: [UUID] = []

    mutating func nextRevision(now: TimeInterval = Date().timeIntervalSince1970) -> UInt64 {
        let clock = now.isFinite ? UInt64(min(max(0, now) * 1_000, Double(Int64.max))) : 0
        revision = max(revision + 1, clock)
        return revision
    }

    /// Only the latest are kept: every snapshot carries them, and a Watch holds a handful at most.
    mutating func acknowledge(_ id: UUID) {
        if !acknowledgedIDs.contains(id) { acknowledgedIDs.append(id) }
        acknowledgedIDs = Array(acknowledgedIDs.suffix(64))
    }
}
