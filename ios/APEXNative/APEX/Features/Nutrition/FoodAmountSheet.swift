/*
 * Configure Amount: the native twin of the web composer's amount modal
 * (src/components/food/MealComposer.tsx). Quantity, serving type, live
 * portion preview and provenance, with the portion math ported 1:1 from
 * src/lib/food.ts so a gram is the same gram on both platforms.
 */
import SwiftUI
import UIKit

enum FoodUnitKind: String, CaseIterable, Hashable, Sendable {
    case grams = "g"
    case millilitres = "ml"
    case serving
    case piece
}

struct FoodPortionResult: Equatable {
    let equivalentAmount: Double
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

enum FoodPortionMath {
    /* Parity: availableFoodUnits */
    static func availableUnits(_ food: Food) -> [FoodUnitKind] {
        let basis: FoodUnitKind = food.nutritionBasis == "per_100ml" ? .millilitres : .grams
        var units: [FoodUnitKind] = [basis]
        if let serving = food.servingGramsOrML, serving > 0 { units.append(.serving) }
        if let piece = food.pieceGramsOrML, piece > 0 { units.append(.piece) }
        return units
    }

    /* Parity: isFoodNutritionComplete */
    static func isComplete(_ food: Food) -> Bool {
        [food.kcal100, food.protein100, food.carbs100, food.fat100]
            .allSatisfy { value in
                guard let value else { return false }
                return value.isFinite && value >= 0
            }
    }

    /* Parity: equivalentAmount */
    static func equivalentAmount(_ food: Food, quantity: Double, unit: FoodUnitKind) -> Double? {
        guard quantity.isFinite, quantity > 0 else { return nil }
        switch unit {
        case .grams:
            return food.nutritionBasis == "per_100g" ? quantity : nil
        case .millilitres:
            return food.nutritionBasis == "per_100ml" ? quantity : nil
        case .serving:
            guard let serving = food.servingGramsOrML else { return nil }
            return quantity * serving
        case .piece:
            guard let piece = food.pieceGramsOrML else { return nil }
            return quantity * piece
        }
    }

    /* Parity: calculatePortion, including the web's rounding */
    static func portion(_ food: Food, quantity: Double, unit: FoodUnitKind) -> FoodPortionResult? {
        guard isComplete(food),
              let equivalent = equivalentAmount(food, quantity: quantity, unit: unit) else { return nil }
        let factor = equivalent / 100
        func round1(_ v: Double) -> Double { ((v * 10).rounded(.toNearestOrAwayFromZero)) / 10 }
        return FoodPortionResult(
            equivalentAmount: ((equivalent * 100).rounded(.toNearestOrAwayFromZero)) / 100,
            kcal: ((food.kcal100 ?? 0) * factor).rounded(.toNearestOrAwayFromZero),
            proteinG: round1((food.protein100 ?? 0) * factor),
            carbsG: round1((food.carbs100 ?? 0) * factor),
            fatG: round1((food.fat100 ?? 0) * factor)
        )
    }

    /* Parity: beginFoodSelection defaults */
    static func defaultSelection(
        _ food: Food,
        preference: FoodPreference?
    ) -> (quantity: Double, unit: FoodUnitKind) {
        let units = availableUnits(food)
        if let amount = preference?.usualAmount, amount > 0,
           let rawUnit = preference?.usualUnit,
           let unit = FoodUnitKind(rawValue: rawUnit), units.contains(unit) {
            return (amount, unit)
        }
        if let piece = food.pieceGramsOrML, piece > 0 { return (1, .piece) }
        if food.servingUnit == "serving", let serving = food.servingGramsOrML, serving > 0 {
            return (1, .serving)
        }
        return (100, units.first ?? .grams)
    }

    static func provenanceLabel(_ food: Food) -> String {
        if food.source == "private" { return "Your private food" }
        if food.source == "open_food_facts" {
            return "Open Food Facts community record. Check the package label."
        }
        if food.confidence == "provider_verified" {
            return "Verified label or nutrition-provider reference"
        }
        return "Curated reference profile. Product labels can vary."
    }
}

struct FoodAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    let food: Food
    let preference: FoodPreference?
    var onClose: () -> Void = {}
    let onConfirm: (Double, String) -> Void

    @State private var quantity: Double = 100
    @State private var unit: FoodUnitKind = .grams
    @State private var quantityText = "100"
    @FocusState private var quantityFocused: Bool

    private var units: [FoodUnitKind] { FoodPortionMath.availableUnits(food) }
    private var portion: FoodPortionResult? {
        FoodPortionMath.portion(food, quantity: quantity, unit: unit)
    }
    private var basisLabel: String { food.nutritionBasis == "per_100ml" ? "ml" : "g" }

    var body: some View {
        /* Card content: choosing an amount is a glance, not a screen. */
        VStack(alignment: .leading, spacing: 13) {
            header
            nutritionPanel
            amountControls
            portionPreview
            actions
        }
        .onAppear {
            let start = FoodPortionMath.defaultSelection(food, preference: preference)
            quantity = start.quantity
            unit = start.unit
            quantityText = formatted(start.quantity)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("CONFIGURE AMOUNT"))
                    .font(APEXFont.mono(10))
                    .tracking(1.8)
                    .foregroundStyle(APEXColor.amberDeep)
                Text(food.name)
                    .font(APEXFont.display(20))
                    .foregroundStyle(APEXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = food.brand, !brand.isEmpty {
                    Text(brand)
                        .font(APEXFont.body(13, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("Close"))
        }
    }

    private var nutritionPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text(language.format("NUTRITION PER 100 %@", basisLabel.uppercased()))
                    .font(APEXFont.mono(10))
                    .tracking(1.2)
                    .foregroundStyle(APEXColor.secondaryInk)
                Spacer()
                Text(language.text(food.preparationState.replacingOccurrences(of: "_", with: " ")))
                    .font(APEXFont.mono(9))
                    .foregroundStyle(APEXColor.amberDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(APEXColor.amber.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 9) {
                macroTile(value: food.kcal100, label: "KCAL", suffix: "")
                macroTile(value: food.protein100, label: "PROTEIN", suffix: "g")
                macroTile(value: food.carbs100, label: "CARBS", suffix: "g")
                macroTile(value: food.fat100, label: "FAT", suffix: "g")
            }
        }
        .padding(15)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func macroTile(value: Double?, label: String, suffix: String) -> some View {
        VStack(spacing: 3) {
            Text(value == nil ? language.text("N/A") : "\(formatted(value!))\(suffix)")
                .font(APEXFont.mono(19, weight: .bold))
                .foregroundStyle(APEXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(language.text(label))
                .font(APEXFont.mono(8))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var amountControls: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("QUANTITY"))
                    .font(APEXFont.mono(10))
                    .tracking(1.1)
                    .foregroundStyle(APEXColor.secondaryInk)
                TextField("", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .focused($quantityFocused)
                    .font(APEXFont.mono(18, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: quantityText) { _, value in
                        let normalized = value.replacingOccurrences(of: ",", with: ".")
                        quantity = max(0, Double(normalized) ?? 0)
                    }
                    .accessibilityIdentifier("food-amount-quantity")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("SERVING TYPE"))
                    .font(APEXFont.mono(10))
                    .tracking(1.1)
                    .foregroundStyle(APEXColor.secondaryInk)
                Menu {
                    ForEach(units, id: \.self) { option in
                        Button {
                            unit = option
                            let next: Double = (option == .grams || option == .millilitres) ? 100 : 1
                            quantity = next
                            quantityText = formatted(next)
                        } label: {
                            Text(unitLabel(option))
                        }
                    }
                } label: {
                    HStack {
                        Text(unitLabel(unit))
                            .font(APEXFont.body(16, weight: .bold))
                            .foregroundStyle(APEXColor.ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityIdentifier("food-amount-unit")
            }
        }
    }

    private func unitLabel(_ option: FoodUnitKind) -> String {
        let equivalent: Double? = option == .serving
            ? food.servingGramsOrML
            : option == .piece ? food.pieceGramsOrML : nil
        let name = language.text(option.rawValue)
        guard let equivalent else { return name }
        return "\(name) (\(formatted(equivalent)) \(basisLabel))"
    }

    private var portionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text("\(portion.map { formatted($0.kcal) } ?? language.text("N/A")) kcal")
                Text("P \(portion.map { formatted($0.proteinG) } ?? language.text("N/A"))g")
                Text("C \(portion.map { formatted($0.carbsG) } ?? language.text("N/A"))g")
                Text("F \(portion.map { formatted($0.fatG) } ?? language.text("N/A"))g")
            }
            .font(APEXFont.mono(13, weight: .bold))
            .foregroundStyle(APEXColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(language.text(FoodPortionMath.provenanceLabel(food)))
                .font(APEXFont.body(11, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(APEXColor.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("food-amount-preview")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(language.text("Cancel")) { onClose() }
                .font(APEXFont.body(13, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)

            Button {
                guard let portion else { return }
                onConfirm(quantity, unit.rawValue)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                _ = portion
                onClose()
            } label: {
                Text(portion.map { language.format("Add food · %d kcal", Int($0.kcal)) } ?? language.text("Add food"))
                    .font(APEXFont.body(17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(APEXColor.amber.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(portion == nil)
            .opacity(portion == nil ? 0.45 : 1)
            .accessibilityIdentifier("food-amount-confirm")
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
