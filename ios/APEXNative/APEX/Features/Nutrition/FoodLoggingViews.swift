import SwiftUI

struct FoodSearchRequest: Sendable {
    fileprivate let generation: UInt64
}

@MainActor
final class FoodSearchRequestGate {
    private var generation: UInt64 = 0

    func begin() -> FoodSearchRequest {
        generation &+= 1
        return FoodSearchRequest(generation: generation)
    }

    func clear() {
        generation &+= 1
    }

    func canPublish(_ request: FoodSearchRequest, taskIsCancelled: Bool) -> Bool {
        taskIsCancelled == false && request.generation == generation
    }

    func isCurrent(_ request: FoodSearchRequest) -> Bool {
        request.generation == generation
    }
}

struct FoodMemorySearchBar: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(APEXColor.amberDeep)
            TextField(placeholder, text: $query)
                .focused($isFocused)
                .font(APEXFont.body(15, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .onSubmit(onSearch)
                .accessibilityIdentifier("food-memory-search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(APEXColor.secondaryInk.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.95), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

struct FoodSearchSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date

    @State private var query = ""
    @State private var remoteResults: [Food] = []
    @State private var selectedFood: Food?
    @State private var isSearching = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGate = FoodSearchRequestGate()
    @FocusState private var searchFocused: Bool

    private var localFoods: [Food] {
        let ownerID = session.profile?.userID
        let accountVisible = session.data.foods.filter { food in
            guard let foodOwnerID = food.ownerUserID else { return true }
            return ownerID != nil && foodOwnerID == ownerID
        }
        return FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(accountVisible)
    }

    private var displayedFoods: [Food] {
        if remoteResults.isEmpty == false { return visible(remoteResults) }
        guard !query.isEmpty else {
            guard let userID = session.profile?.userID else { return ranked(localFoods) }
            return MealMemory.recentFoods(
                foods: localFoods,
                preferences: session.data.foodPreferences,
                meals: session.data.loggedMeals,
                entries: session.data.loggedFoodEntries,
                userID: userID
            )
        }
        return ranked(MealMemory.searchFoods(
            query: query,
            foods: localFoods,
            preferences: session.data.foodPreferences,
            userID: session.profile?.userID
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isSearching {
                        ProgressView("Searching APEX Food Memory")
                            .font(APEXFont.body(13, weight: .semibold))
                            .padding(.vertical, 24)
                    }

                    if let message {
                        Text(language.text(message))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(APEXColor.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 17))
                    }

                    ForEach(displayedFoods) { food in
                        Button {
                            searchFocused = false
                            selectedFood = food
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "leaf.fill")
                                    .foregroundStyle(APEXColor.green)
                                    .frame(width: 42, height: 42)
                                    .background(APEXColor.green.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.localizedName(language.language))
                                        .font(APEXFont.body(15, weight: .bold))
                                        .foregroundStyle(APEXColor.ink)
                                    HStack(spacing: 6) {
                                        if let brand = food.brand, !brand.isEmpty { Text(brand) }
                                        Text(language.format("%d kcal / 100", Int((food.kcal100 ?? 0).rounded())))
                                    }
                                    .font(APEXFont.body(11, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            .padding(14)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.9)))
                        }
                        .buttonStyle(.plain)
                    }

                    if displayedFoods.isEmpty, !isSearching {
                        ContentUnavailableView(
                            "No food found",
                            systemImage: "fork.knife.circle",
                            description: Text(language.text("Try the exact product name or scan its barcode."))
                        )
                    }
                }
                .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Food Memory"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FoodMemorySearchBar(
                    query: $query,
                    isFocused: $searchFocused,
                    placeholder: language.text("Search foods and brands"),
                    onSearch: { beginSearch() }
                )
            }
            .onChange(of: query) { _, _ in clearSearch() }
            .onChange(of: session.profile?.userID) { _, _ in clearSearch() }
            .onDisappear { cancelSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Done")) { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                FoodPortionSheet(food: food, date: date)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func ranked(_ foods: [Food]) -> [Food] {
        let preferences = Dictionary(uniqueKeysWithValues: session.data.foodPreferences.map { ($0.foodID.uuidString.lowercased(), $0) })
        return foods.filter { food in
            preferences[food.id.lowercased()]?.hidden != true
        }.sorted { lhs, rhs in
            let left = preferences[lhs.id.lowercased()]
            let right = preferences[rhs.id.lowercased()]
            if (left?.favourite ?? false) != (right?.favourite ?? false) {
                return left?.favourite == true
            }
            if (left?.lastUsedAt ?? "") != (right?.lastUsedAt ?? "") {
                return (left?.lastUsedAt ?? "") > (right?.lastUsedAt ?? "")
            }
            if (left?.usageCount ?? 0) != (right?.usageCount ?? 0) {
                return (left?.usageCount ?? 0) > (right?.usageCount ?? 0)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func visible(_ foods: [Food]) -> [Food] {
        let preferences = Dictionary(uniqueKeysWithValues: session.data.foodPreferences.map { ($0.foodID.uuidString.lowercased(), $0) })
        let ownerID = session.profile?.userID
        return foods.filter { food in
            let belongsToAccount = food.ownerUserID == nil || (ownerID != nil && food.ownerUserID == ownerID)
            return belongsToAccount && preferences[food.id.lowercased()]?.hidden != true
        }
    }

    private func beginSearch() {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            clearSearch()
            return
        }
        guard let operation = session.accountOperationLease() else {
            clearSearch()
            return
        }
        searchTask?.cancel()
        let request = searchGate.begin()
        remoteResults = []
        isSearching = true
        message = nil
        searchTask = Task { @MainActor in
            await search(query: cleaned, request: request, operation: operation)
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGate.clear()
        remoteResults = []
        isSearching = false
        message = nil
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGate.clear()
    }

    @MainActor
    private func search(
        query: String,
        request: FoodSearchRequest,
        operation: AccountOperationLease
    ) async {
        do {
            let results = try await session.searchFoods(query: query, operation: operation)
            guard session.accountOperationIsCurrent(operation),
                  searchGate.canPublish(request, taskIsCancelled: Task.isCancelled) else { return }
            remoteResults = results
            if remoteResults.isEmpty { message = "No reliable nutrition match was returned." }
            isSearching = false
            searchTask = nil
        } catch is CancellationError {
            guard session.accountOperationIsCurrent(operation),
                  searchGate.isCurrent(request) else { return }
            isSearching = false
            searchTask = nil
        } catch {
            guard session.accountOperationIsCurrent(operation),
                  searchGate.canPublish(request, taskIsCancelled: Task.isCancelled) else { return }
            remoteResults = []
            message = "Online search is unavailable. Your saved Food Memory remains usable."
            isSearching = false
            searchTask = nil
        }
    }
}

struct FoodPortionSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let food: Food
    let date: Date
    var onAdd: ((Food, Double, String) -> Void)? = nil

    @State private var amount: Double
    @State private var unit: String
    @State private var mealSlot: String
    @State private var isSaving = false
    /// The hour the sheet was opened at, so the slot can be recomputed once the
    /// user preference is readable.
    @State private var slotHour = 12
    @State private var slotResolved = false
    @State private var errorMessage: String?

    init(food: Food, date: Date, onAdd: ((Food, Double, String) -> Void)? = nil) {
        self.food = food
        self.date = date
        self.onAdd = onAdd
        let start = FoodPortionMath.defaultSelection(food, preference: nil)
        _amount = State(initialValue: start.quantity)
        _unit = State(initialValue: start.unit.rawValue)
        let hour = Calendar.current.component(.hour, from: date)
        /* The clock's answer. Corrected once the environment exists, because
           the user's late-dinner preference lives in settings and this
           initialiser runs before those are reachable. */
        _mealSlot = State(initialValue: MealSlotDefault.slot(hour: hour, adaptiveLateDinner: false))
        _slotHour = State(initialValue: hour)
    }

    private var availableUnits: [String] {
        FoodPortionMath.availableUnits(food).map(\.rawValue)
    }

    private func unitLabel(_ rawUnit: String) -> String {
        guard let unit = FoodUnitKind(rawValue: rawUnit) else {
            return language.text(rawUnit.capitalized)
        }
        return FoodPortionMath.unitLabel(
            food,
            unit: unit,
            localizedName: language.text(rawUnit.capitalized)
        )
    }

    private var equivalentAmount: Double {
        switch unit {
        case "serving": amount * (food.servingGramsOrML ?? 0)
        case "piece": amount * (food.pieceGramsOrML ?? 0)
        default: amount
        }
    }

    private var nutrients: FoodNutrients { food.nutrients(forEquivalentAmount: equivalentAmount) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(food.localizedName(language.language))
                                .font(APEXFont.display(28))
                            if let brand = food.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(APEXFont.body(13, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            HStack(spacing: 14) {
                                nutritionMetric("KCAL", nutrients.kcal)
                                nutritionMetric("PROTEIN", nutrients.proteinG)
                                nutritionMetric("CARBS", nutrients.carbsG)
                                nutritionMetric("FAT", nutrients.fatG)
                            }
                            .padding(.top, 8)
                        }
                    }

                    GlassCard(radius: 28, padding: 19) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(language.text("Portion"))
                                .font(APEXFont.display(21))
                            HStack(spacing: 12) {
                                Button { amount = max(step, amount - step) } label: { Image(systemName: "minus") }
                                    .buttonStyle(PortionStepperStyle())
                                TextField(language.text("Amount"), value: $amount, format: .number.precision(.fractionLength(0...1)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(APEXFont.display(28))
                                    .frame(maxWidth: .infinity)
                                Button { amount += step } label: { Image(systemName: "plus") }
                                    .buttonStyle(PortionStepperStyle())
                            }
                            Picker("Unit", selection: $unit) {
                                ForEach(availableUnits, id: \.self) { Text(unitLabel($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            Picker("Meal", selection: $mealSlot) {
                                ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) {
                                    Text(language.text($0.capitalized)).tag($0)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Button {
                        guard let operation = session.accountOperationLease() else { return }
                        Task { await save(operation: operation) }
                    } label: {
                        if isSaving { ProgressView().tint(.white) }
                        else { Label(language.text("Log food"), systemImage: "checkmark.circle.fill") }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                    .disabled(isSaving || equivalentAmount <= 0)
                }
                .padding(18)
            }
            .background(APEXBackground())
            .task {
                /* The user's late-dinner preference decides whether a 22:00
                   entry is a snack or a real dinner. Applied here rather than
                   in the initialiser, and only once, so it never overrides a
                   slot the user has since chosen by hand. */
                guard !slotResolved else { return }
                slotResolved = true
                let adaptive = session.data.settings?.addons["adaptive_post_workout_dinner"]?.boolValue ?? true
                mealSlot = MealSlotDefault.slot(hour: slotHour, adaptiveLateDinner: adaptive)
            }
            .navigationTitle(language.text("Confirm food"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("Cancel")) { dismiss() } }
            }
            .alert("Could not log food", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(language.text("OK"), role: .cancel) {}
            } message: {
                Text(language.text(errorMessage ?? "Please try again."))
            }
        }
    }

    private var step: Double { unit == "g" || unit == "ml" ? 10 : 1 }

    private func nutritionMetric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(title)).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text("\(Int(value.rounded()))").font(APEXFont.display(16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func save(operation: AccountOperationLease) async {
        isSaving = true
        defer {
            if session.accountOperationIsCurrent(operation) {
                isSaving = false
            }
        }
        if let onAdd {
            guard session.accountOperationIsCurrent(operation) else { return }
            onAdd(food, amount, unit)
            dismiss()
            return
        }
        do {
            try await session.logFood(
                food,
                amount: amount,
                unit: unit,
                mealSlot: mealSlot,
                date: date,
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PortionStepperStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 46)
            .background(APEXColor.amber, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
