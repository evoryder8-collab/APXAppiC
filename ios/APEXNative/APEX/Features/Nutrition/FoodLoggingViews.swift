import SwiftUI

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

    private var displayedFoods: [Food] {
        let base = remoteResults.isEmpty ? session.data.foods : remoteResults
        guard !query.isEmpty, remoteResults.isEmpty else { return ranked(base) }
        return ranked(base.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.brand?.localizedCaseInsensitiveContains(query) ?? false)
        })
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
                        Button { selectedFood = food } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "leaf.fill")
                                    .foregroundStyle(APEXColor.green)
                                    .frame(width: 42, height: 42)
                                    .background(APEXColor.green.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.name)
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
                            description: Text("Try the exact product name or scan its barcode.")
                        )
                    }
                }
                .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle("Food Memory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods and brands")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, value in
                if value.isEmpty {
                    remoteResults = []
                    message = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await search() } } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
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
            if (left?.usageCount ?? 0) != (right?.usageCount ?? 0) {
                return (left?.usageCount ?? 0) > (right?.usageCount ?? 0)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @MainActor
    private func search() async {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            remoteResults = try await session.searchFoods(query: cleaned)
            if remoteResults.isEmpty { message = "No reliable nutrition match was returned." }
        } catch {
            remoteResults = []
            message = "Online search is unavailable. Your saved Food Memory remains usable."
        }
    }
}

struct FoodPortionSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let food: Food
    let date: Date

    @State private var amount: Double
    @State private var unit: String
    @State private var mealSlot: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(food: Food, date: Date) {
        self.food = food
        self.date = date
        if food.servingGramsOrML != nil {
            _amount = State(initialValue: 1)
            _unit = State(initialValue: "serving")
        } else if food.pieceGramsOrML != nil {
            _amount = State(initialValue: 1)
            _unit = State(initialValue: "piece")
        } else {
            _amount = State(initialValue: 100)
            _unit = State(initialValue: food.nutritionBasis == "per_100ml" ? "ml" : "g")
        }
        let hour = Calendar.current.component(.hour, from: date)
        _mealSlot = State(initialValue: hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack")
    }

    private var availableUnits: [String] {
        var units = [food.nutritionBasis == "per_100ml" ? "ml" : "g"]
        if food.servingGramsOrML != nil { units.append("serving") }
        if food.pieceGramsOrML != nil { units.append("piece") }
        return units
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
                            Text(food.name)
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
                            Text("Portion")
                                .font(APEXFont.display(21))
                            HStack(spacing: 12) {
                                Button { amount = max(step, amount - step) } label: { Image(systemName: "minus") }
                                    .buttonStyle(PortionStepperStyle())
                                TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...1)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(APEXFont.display(28))
                                    .frame(maxWidth: .infinity)
                                Button { amount += step } label: { Image(systemName: "plus") }
                                    .buttonStyle(PortionStepperStyle())
                            }
                            Picker("Unit", selection: $unit) {
                                ForEach(availableUnits, id: \.self) { Text(language.text($0.capitalized)).tag($0) }
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
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(.white) }
                        else { Label("Log food", systemImage: "checkmark.circle.fill") }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                    .disabled(isSaving || equivalentAmount <= 0)
                }
                .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle("Confirm food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Could not log food", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
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
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.logFood(food, amount: amount, unit: unit, mealSlot: mealSlot, date: date)
            dismiss()
        } catch {
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
