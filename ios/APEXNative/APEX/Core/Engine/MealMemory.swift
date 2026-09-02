import Foundation

/* Port of src/lib/mealExperience.ts — the Food Memory ranking. Repeatable
   starts are read out of immutable logged history rather than the mutable
   preference table, so the amount a food opens with is the amount that food
   was last confirmed at, on any device, even when preferences never synced. */
enum MealMemory {
    enum Mode: String, Sendable {
        case daily
        case weekly
    }

    /// Anything that is not the literal 'weekly' string stays on daily, matching the web.
    static func normalizeMode(_ value: JSONValue?) -> Mode {
        if case .string(let raw) = value, raw == "weekly" { return .weekly }
        return .daily
    }

    struct Selection: Hashable, Sendable {
        let foodID: String
        let quantity: Double
        let unit: String
    }

    struct Context: Sendable {
        var date: String
        var slot: String
        var mode: Mode = .daily
        var blockID: String?
        var targetTime: String?
        var sequenceIndex: Int?
        var excludeMealID: UUID?

        init(
            date: String,
            slot: String,
            mode: Mode = .daily,
            blockID: String? = nil,
            targetTime: String? = nil,
            sequenceIndex: Int? = nil,
            excludeMealID: UUID? = nil
        ) {
            self.date = date
            self.slot = slot
            self.mode = mode
            self.blockID = blockID
            self.targetTime = targetTime
            self.sequenceIndex = sequenceIndex
            self.excludeMealID = excludeMealID
        }
    }

    struct Recommendations: Sendable {
        var meals: [LoggedMeal] = []
        var foods: [Food] = []
        var selections: [Selection] = []
        var presets: [MealPreset] = []

        /// Last confirmed amount for a food, or nil when history has never seen it.
        func selection(for foodID: String) -> Selection? {
            selections.first { $0.foodID == foodID }
        }
    }

    // MARK: - Date and clock helpers

    private static func dateMs(_ value: String) -> Double {
        guard let date = APEXDateMath.date(from: value) else { return 0 }
        return date.timeIntervalSince1970 * 1000
    }

    /// Sunday = 0, matching the web's getUTCDay so both sides bucket alike.
    private static func weekday(_ value: String) -> Int {
        guard let date = APEXDateMath.date(from: value) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.component(.weekday, from: date) - 1
    }

    private static func clockMinutes(_ value: String?) -> Int? {
        guard let value, value.count >= 5 else { return nil }
        let characters = Array(value)
        guard characters[2] == ":" else { return nil }
        guard let hours = Int(String(characters[0...1])), let minutes = Int(String(characters[3...4])) else { return nil }
        return hours * 60 + minutes
    }

    private static func mealClock(_ meal: LoggedMeal) -> String? {
        guard let marker = meal.loggedAt.firstIndex(of: "T") else { return nil }
        let after = meal.loggedAt[meal.loggedAt.index(after: marker)...]
        guard after.count >= 5 else { return nil }
        return String(after.prefix(5))
    }

    /// The dayline block a meal was logged into, recovered from its idempotency key.
    static func markedBlock(_ meal: LoggedMeal) -> String? {
        let token = "apex-meal-block="
        guard let marker = meal.clientIdempotencyKey.range(of: token, options: .backwards) else { return nil }
        let value = meal.clientIdempotencyKey[marker.upperBound...].split(separator: "|", maxSplits: 1).first
        guard let value, !value.isEmpty else { return nil }
        return String(value)
    }

    /// Position of a meal within its own day, so "the second thing I eat" repeats.
    private static func sequenceIndexes(_ meals: [LoggedMeal]) -> [UUID: Int] {
        var byDate: [String: [LoggedMeal]] = [:]
        for meal in meals { byDate[meal.localDate, default: []].append(meal) }
        var result: [UUID: Int] = [:]
        for dayMeals in byDate.values {
            let ordered = dayMeals.sorted {
                $0.loggedAt == $1.loggedAt
                    ? $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
                    : $0.loggedAt < $1.loggedAt
            }
            for (index, meal) in ordered.enumerated() { result[meal.id] = index }
        }
        return result
    }

    private static func recommendationIdentity(_ meal: LoggedMeal) -> String {
        if let preset = meal.sourcePresetID { return "preset:\(preset.uuidString.lowercased())" }
        let name = meal.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "meal:\(meal.mealSlot):\(name)"
    }

    /// Rebuild a catalogue row from its meal snapshot, so history stays usable
    /// after a catalogue release drops or renames the original food.
    static func food(from entry: LoggedFoodEntry) -> Food {
        let signature = [
            entry.snapshotName,
            entry.snapshotBrand ?? "",
            entry.snapshotPreparationState,
            entry.snapshotNutritionBasis,
            String(entry.snapshotKcal100),
            String(entry.snapshotProtein100),
            String(entry.snapshotCarbs100),
            String(entry.snapshotFat100),
        ].joined(separator: "|")
        let divisor = max(1, entry.quantity)
        return Food(
            id: entry.foodID?.uuidString.lowercased() ?? "history:\(signature)",
            ownerUserID: nil,
            name: entry.snapshotName,
            namesI18n: [:],
            brand: entry.snapshotBrand,
            barcode: nil,
            source: "apex_cache",
            providerProductID: "apex-protocol:history:\(signature)",
            externalImageURL: nil,
            packageQuantity: nil,
            nutritionBasis: entry.snapshotNutritionBasis,
            preparationState: entry.snapshotPreparationState,
            kcal100: entry.snapshotKcal100,
            protein100: entry.snapshotProtein100,
            carbs100: entry.snapshotCarbs100,
            fat100: entry.snapshotFat100,
            fibre100: entry.snapshotFibre100,
            sugar100: entry.snapshotSugar100,
            saturatedFat100: entry.snapshotSaturatedFat100,
            salt100: entry.snapshotSalt100,
            waterML100: entry.snapshotWaterML100,
            waterBasis: entry.snapshotWaterBasis ?? "legacy",
            waterSourceID: entry.snapshotWaterSourceID,
            servingAmount: entry.unit == "serving" ? 1 : nil,
            servingUnit: entry.unit == "serving" ? "serving" : nil,
            servingGramsOrML: entry.unit == "serving" ? entry.equivalentAmount / divisor : nil,
            pieceGramsOrML: entry.unit == "piece" ? entry.equivalentAmount / divisor : nil,
            confidence: "complete",
            nutrientEvidence: entry.snapshotNutrientEvidence ?? []
        )
    }

    /// A standalone Food Memory view is not tied to one meal slot. Build its
    /// first rows from immutable, account-owned log history so a barcode food
    /// remains available even when the shared catalogue query no longer
    /// includes that row. Preferences remain useful metadata, but are not the
    /// source of truth for whether a food was actually logged.
    static func recentFoods(
        foods: [Food],
        preferences: [FoodPreference],
        meals: [LoggedMeal],
        entries: [LoggedFoodEntry],
        userID: UUID
    ) -> [Food] {
        var foodByID: [String: Food] = [:]
        for food in foods { foodByID[food.id.lowercased()] = food }
        let ownedPreferences = preferences.filter { $0.userID == userID }
        let preferenceByFoodID = Dictionary(
            uniqueKeysWithValues: ownedPreferences.map { ($0.foodID.uuidString.lowercased(), $0) }
        )
        let hiddenIDs = Set(ownedPreferences.filter(\.hidden).map { $0.foodID.uuidString.lowercased() })
        var entriesByMeal: [UUID: [LoggedFoodEntry]] = [:]
        for entry in entries where entry.userID == userID {
            entriesByMeal[entry.mealID, default: []].append(entry)
        }

        var result: [Food] = []
        var seen: Set<String> = []
        func append(_ food: Food) {
            let id = food.id.lowercased()
            guard !hiddenIDs.contains(id), seen.insert(id).inserted else { return }
            result.append(food)
        }

        let recentMeals = meals
            .filter { $0.userID == userID }
            .sorted {
                let left = $0.loggedAt.isEmpty ? $0.localDate : $0.loggedAt
                let right = $1.loggedAt.isEmpty ? $1.localDate : $1.loggedAt
                return left == right ? $0.id.uuidString > $1.id.uuidString : left > right
            }
        for meal in recentMeals {
            for entry in (entriesByMeal[meal.id] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
                guard entry.snapshotBrand != "APEX plan",
                      !entry.snapshotName.lowercased().contains("planned prescription") else { continue }
                let food = entry.foodID.flatMap { foodByID[$0.uuidString.lowercased()] } ?? Self.food(from: entry)
                append(food)
            }
        }

        let rememberedCatalogue = foods.filter { food in
            guard let preference = preferenceByFoodID[food.id.lowercased()] else { return false }
            return preference.favourite || preference.usageCount > 0
        }.sorted { left, right in
            let lhs = preferenceByFoodID[left.id.lowercased()]
            let rhs = preferenceByFoodID[right.id.lowercased()]
            if (lhs?.favourite ?? false) != (rhs?.favourite ?? false) { return lhs?.favourite == true }
            if (lhs?.lastUsedAt ?? "") != (rhs?.lastUsedAt ?? "") { return (lhs?.lastUsedAt ?? "") > (rhs?.lastUsedAt ?? "") }
            if (lhs?.usageCount ?? 0) != (rhs?.usageCount ?? 0) { return (lhs?.usageCount ?? 0) > (rhs?.usageCount ?? 0) }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
        rememberedCatalogue.forEach(append)
        foods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.forEach(append)
        return result
    }

    /// Searches the account's in-memory Food Memory before any public
    /// provider is contacted. This keeps private foods, personal names,
    /// aliases and localized catalogue names useful while offline.
    static func searchFoods(
        query: String,
        foods: [Food],
        preferences: [FoodPreference],
        userID: UUID? = nil,
        limit: Int = 50
    ) -> [Food] {
        let needle = normalizedSearchText(query)
        guard needle.count >= 2 else { return [] }
        let tokens = needle.split(separator: " ").map(String.init)
        let scopedPreferences = preferences.filter { preference in
            userID == nil || preference.userID == userID
        }
        let scopedFoods = foods.filter { food in
            guard let ownerUserID = food.ownerUserID else { return true }
            guard let userID else { return false }
            return ownerUserID == userID
        }
        let preferenceByFoodID = Dictionary(
            scopedPreferences.map { ($0.foodID.uuidString.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        struct Match {
            let food: Food
            let score: Int
            let categoryPriority: Int
            let favourite: Bool
            let usageCount: Int
        }

        let matches = scopedFoods.compactMap { food -> Match? in
            let preference = preferenceByFoodID[food.id.lowercased()]
            guard preference?.hidden != true else { return nil }
            let fields = ([food.name, food.brand]
                + Array(food.namesI18n.values)
                + [preference?.personalName]
                + (preference?.aliases ?? []))
                .compactMap { $0 }
                .map(normalizedSearchText)
                .filter { !$0.isEmpty }
            guard !fields.isEmpty else { return nil }
            let score: Int
            if fields.contains(needle) {
                score = 0
            } else if fields.contains(where: { $0.hasPrefix(needle) }) {
                score = 1
            } else if fields.contains(where: { $0.contains(needle) }) {
                score = 2
            } else if fields.contains(where: { fuzzySearchMatch(needle, $0) }) {
                score = 3
            } else {
                return nil
            }
            return Match(
                food: food,
                score: score,
                categoryPriority: foodCategoryPriority(queryTokens: tokens, food: food),
                favourite: preference?.favourite ?? false,
                usageCount: preference?.usageCount ?? 0
            )
        }

        return matches.sorted { left, right in
            if left.categoryPriority != right.categoryPriority {
                return left.categoryPriority < right.categoryPriority
            }
            if left.score != right.score { return left.score < right.score }
            if left.favourite != right.favourite { return left.favourite }
            if left.usageCount != right.usageCount { return left.usageCount > right.usageCount }
            return left.food.name.localizedCaseInsensitiveCompare(right.food.name) == .orderedAscending
        }.prefix(max(1, limit)).map(\.food)
    }

    /// Diacritic, punctuation and token-order tolerant matching mirrors the
    /// forgiving food search used by the web client.
    private static func normalizedSearchText(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let plain = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
        let normalized = plain
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
        return normalized
    }

    private static func fuzzySearchMatch(_ query: String, _ candidate: String) -> Bool {
        let queryTokens = query.split(separator: " ").map(String.init)
        let candidateTokens = candidate.split(separator: " ").map(String.init)
        guard queryTokens.isEmpty == false, candidateTokens.isEmpty == false else { return false }

        var candidateForms = Set<String>()
        for token in candidateTokens {
            candidateForms.insert(token)
            if token.hasSuffix("ies"), token.count > 4 {
                candidateForms.insert(String(token.dropLast(3)) + "y")
            }
            if token.hasSuffix("oes"), token.count > 4 {
                candidateForms.insert(String(token.dropLast(2)))
            }
            if token.hasSuffix("o"), token.count > 3 {
                candidateForms.insert(token + "es")
            }
        }
        for start in candidateTokens.indices {
            for length in 2...3 where start + length <= candidateTokens.count {
                candidateForms.insert(candidateTokens[start..<(start + length)].joined())
            }
        }

        return queryTokenGroups(queryTokens).contains { group in
            /* Every meaningful query token must align. A generic partial hit
               such as "extra" can no longer admit "beef extract" when the
               user asked for "extra virgin". */
            group.allSatisfy { queryToken in
                candidateForms.contains { candidateToken in
                    tokenSimilarity(queryToken, candidateToken) > 0
                }
            }
        }
    }

    private static func queryTokenGroups(_ tokens: [String]) -> [[String]] {
        var results: [[String]] = []
        func walk(_ index: Int, _ current: [String]) {
            guard index < tokens.count else {
                results.append(current)
                return
            }
            walk(index + 1, current + [tokens[index]])
            if index + 1 < tokens.count {
                let joined = tokens[index] + tokens[index + 1]
                if (4...18).contains(joined.count) {
                    walk(index + 2, current + [joined])
                }
            }
        }
        walk(0, [])
        return results
    }

    private static func tokenSimilarity(_ queryToken: String, _ candidateToken: String) -> Double {
        if queryToken == candidateToken { return 1 }
        if queryToken.count >= 3,
           candidateToken.count >= 3,
           candidateToken.hasPrefix(queryToken) {
            return 0.92
        }
        if queryToken.count >= 3,
           candidateToken.count >= 3,
           queryToken.hasPrefix(candidateToken),
           queryToken.count - candidateToken.count <= 2 {
            return 0.88
        }
        guard queryToken.count >= 4, candidateToken.count >= 4,
              queryToken.first == candidateToken.first else { return 0 }
        let limit = queryToken.count >= 9 || (queryToken.count >= 5 && queryToken.count <= 6) ? 2 : 1
        let distance = editDistance(queryToken, candidateToken, limit: limit)
        guard distance <= limit else { return 0 }
        let similarity = 1 - Double(distance) / Double(max(queryToken.count, candidateToken.count))
        return similarity >= (queryToken.count >= 5 ? 0.66 : 0.74) ? similarity : 0
    }

    private static func foodCategoryPriority(queryTokens: [String], food: Food) -> Int {
        guard queryTokens.count == 1,
              ["oil", "ulei", "ol", "huile", "olio", "aceite"].contains(queryTokens[0]) else { return 0 }
        let text = normalizedSearchText(([food.name, food.brand] + Array(food.namesI18n.values))
            .compactMap { $0 }
            .joined(separator: " "))
        let pureCookingOil = (food.fat100 ?? 0) >= 90
            && (food.protein100 ?? 0) <= 1
            && (food.carbs100 ?? 0) <= 1
            && ["oil", "ulei", "ol", "huile", "olio", "aceite"].contains { token in
                text.split(separator: " ").contains(Substring(token))
            }
        let textTokens = Set(text.split(separator: " ").map(String.init))
        if pureCookingOil
            && (textTokens.contains("evoo")
                || (textTokens.contains("extra") && textTokens.contains("virgin"))) {
            return -3
        }
        if pureCookingOil
            && (textTokens.contains("olive") || textTokens.contains("vegetable")) {
            return -2
        }
        if pureCookingOil { return -1 }
        if ["margarine", "margarin", "margarina"].contains(where: text.contains) { return 2 }
        return 0
    }

    private static func editDistance(_ left: String, _ right: String, limit: Int) -> Int {
        if abs(left.count - right.count) > limit { return limit + 1 }
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        var previous = Array(0...rightCharacters.count)
        for leftIndex in leftCharacters.indices {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for rightIndex in rightCharacters.indices {
                let cost = leftCharacters[leftIndex] == rightCharacters[rightIndex] ? 0 : 1
                let value = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + cost
                )
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[rightCharacters.count]
    }

    /// Produce only the account-owned preference rows touched by a confirmed
    /// meal. Repeated appearances increment independently and the final item
    /// supplies the exact quantity used by quick add next time.
    static func usagePreferenceUpdates(
        current: [FoodPreference],
        items: [MealComposerItem],
        userID: UUID,
        usedAt: String
    ) -> [FoodPreference] {
        var working = Dictionary(
            uniqueKeysWithValues: current
                .filter { $0.userID == userID }
                .map { ($0.foodID, $0) }
        )
        var touched: [UUID] = []
        var touchedSet: Set<UUID> = []
        for item in items {
            guard let foodID = item.foodID else { continue }
            let previous = working[foodID]
            working[foodID] = FoodPreference(
                id: previous?.id ?? UUID(),
                userID: userID,
                foodID: foodID,
                personalName: previous?.personalName,
                aliases: previous?.aliases ?? [],
                favourite: previous?.favourite ?? false,
                usualAmount: item.quantity,
                usualUnit: item.unit,
                usageCount: (previous?.usageCount ?? 0) + 1,
                lastUsedAt: usedAt,
                hidden: previous?.hidden ?? false
            )
            if touchedSet.insert(foodID).inserted { touched.append(foodID) }
        }
        return touched.compactMap { working[$0] }
    }

    // MARK: - Ranking

    static func rank(
        context: Context,
        meals: [LoggedMeal],
        entries: [LoggedFoodEntry],
        foods: [Food],
        presets: [MealPreset] = [],
        mealLimit: Int = 5,
        foodLimit: Int = 10,
        presetLimit: Int = 5
    ) -> Recommendations {
        let targetMs = dateMs(context.date)
        let targetWeekday = weekday(context.date)
        let targetMinutes = clockMinutes(context.targetTime)
        var foodByID: [String: Food] = [:]
        for food in foods { foodByID[food.id.lowercased()] = food }
        var entriesByMeal: [UUID: [LoggedFoodEntry]] = [:]
        for entry in entries { entriesByMeal[entry.mealID, default: []].append(entry) }

        /* Planned prescriptions are written into history as meals so the dayline
           can show them, but they were never a choice the user made. */
        func isSyntheticPlannedMeal(_ meal: LoggedMeal) -> Bool {
            (entriesByMeal[meal.id] ?? []).contains { entry in
                if entry.snapshotBrand == "APEX plan" { return true }
                if entry.snapshotName.lowercased().contains("planned prescription") { return true }
                guard let foodID = entry.foodID?.uuidString.lowercased(),
                      let provider = foodByID[foodID]?.providerProductID else { return false }
                return provider.hasPrefix("apex-plan:")
            }
        }

        let eligibleSlotMeals = meals.filter { meal in
            meal.id != context.excludeMealID
                && meal.localDate <= context.date
                && meal.mealSlot == context.slot
                && !isSyntheticPlannedMeal(meal)
        }
        let sameWeekdayMeals = eligibleSlotMeals.filter { weekday($0.localDate) == targetWeekday }
        /* Weekly memory stays strict when matching history exists, but a new
           user still receives useful recent starts instead of an empty list. */
        let candidateMeals = context.mode == .weekly && !sameWeekdayMeals.isEmpty
            ? sameWeekdayMeals
            : eligibleSlotMeals
        let indexes = sequenceIndexes(candidateMeals)
        var frequencyByIdentity: [String: Int] = [:]
        var weekdayFrequencyByIdentity: [String: Int] = [:]
        for meal in candidateMeals {
            let identity = recommendationIdentity(meal)
            frequencyByIdentity[identity, default: 0] += 1
            if weekday(meal.localDate) == targetWeekday {
                weekdayFrequencyByIdentity[identity, default: 0] += 1
            }
        }

        var scoreByMeal: [UUID: Double] = [:]
        for meal in candidateMeals {
            let ageDays = max(0, ((targetMs - dateMs(meal.localDate)) / 86_400_000).rounded())
            var score = max(0, 260 - ageDays * 3)
            score += 260
            if let blockID = context.blockID, markedBlock(meal) == blockID { score += 320 }
            if weekday(meal.localDate) == targetWeekday { score += 90 }
            if let sequence = context.sequenceIndex, indexes[meal.id] == sequence { score += 120 }
            if let targetMinutes, let loggedMinutes = clockMinutes(mealClock(meal)) {
                let raw = abs(loggedMinutes - targetMinutes)
                let delta = min(raw, 1440 - raw)
                score += max(0, 130 - Double(delta) / 2)
            }
            if meal.sourcePresetID != nil { score += 35 }
            let identity = recommendationIdentity(meal)
            score += min(560, Double(max(0, (frequencyByIdentity[identity] ?? 1) - 1)) * 80)
            score += min(180, Double(max(0, (weekdayFrequencyByIdentity[identity] ?? 0) - 1)) * 45)
            scoreByMeal[meal.id] = score
        }

        let rankedMeals = candidateMeals.sorted { left, right in
            let leftScore = scoreByMeal[left.id] ?? 0
            let rightScore = scoreByMeal[right.id] ?? 0
            if leftScore != rightScore { return leftScore > rightScore }
            if left.localDate != right.localDate { return left.localDate > right.localDate }
            return left.loggedAt > right.loggedAt
        }

        var foodScores: [String: Double] = [:]
        /* First-seen order breaks score ties exactly as the web's insertion-ordered
           Map does, so both platforms rank identical history identically. */
        var foodOrder: [String: Int] = [:]
        var recommendationFoods: [String: Food] = [:]
        var latestSelectionByFood: [String: (selection: Selection, usedAt: String)] = [:]
        var presetScores: [UUID: Double] = [:]
        /* Eighty high-signal meals cover months of repetition without turning a
           blank-search render into a quadratic scan of a full history. */
        for meal in rankedMeals.prefix(80) {
            let mealScore = scoreByMeal[meal.id] ?? 0
            if let preset = meal.sourcePresetID { presetScores[preset, default: 0] += mealScore }
            for entry in entriesByMeal[meal.id] ?? [] {
                let food = entry.foodID.flatMap { foodByID[$0.uuidString.lowercased()] } ?? Self.food(from: entry)
                let foodID = food.id
                recommendationFoods[foodID] = food
                if foodOrder[foodID] == nil { foodOrder[foodID] = foodOrder.count }
                foodScores[foodID, default: 0] += mealScore + 45
                let usedAt = meal.loggedAt.isEmpty ? meal.localDate : meal.loggedAt
                if let previous = latestSelectionByFood[foodID], usedAt <= previous.usedAt { continue }
                latestSelectionByFood[foodID] = (
                    Selection(foodID: foodID, quantity: entry.quantity, unit: entry.unit),
                    usedAt
                )
            }
        }

        var uniqueMeals: [LoggedMeal] = []
        var seenMealStarts: Set<String> = []
        for meal in rankedMeals where seenMealStarts.insert(recommendationIdentity(meal)).inserted {
            uniqueMeals.append(meal)
        }

        let rankedFoodIDs = foodScores
            .sorted {
                $0.value == $1.value
                    ? (foodOrder[$0.key] ?? 0) < (foodOrder[$1.key] ?? 0)
                    : $0.value > $1.value
            }
            .map(\.key)
            .prefix(foodLimit)

        return Recommendations(
            meals: Array(uniqueMeals.prefix(mealLimit)),
            foods: rankedFoodIDs.compactMap { recommendationFoods[$0] ?? foodByID[$0.lowercased()] },
            selections: rankedFoodIDs.compactMap { latestSelectionByFood[$0]?.selection },
            presets: Array(
                presets
                    .filter { !$0.archived && ($0.mealSlot == context.slot || presetScores[$0.id] != nil) }
                    .sorted { (presetScores[$0.id] ?? 0) > (presetScores[$1.id] ?? 0) }
                    .prefix(presetLimit)
            )
        )
    }
}
