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
    /* Food is where most people get a third of their water, and the tracker
       already counts it once the entry is logged. Showing it here means the
       number stops appearing from nowhere afterwards. */
    let waterML: Double?
}

private struct FoodPortionMetric: Identifiable {
    let id: String
    let text: String
    let color: Color
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
            fatG: round1((food.fat100 ?? 0) * factor),
            waterML: FoodHydration.portionWater(food.waterML100, equivalentAmount: equivalent)
                .map { ($0).rounded(.toNearestOrAwayFromZero) }
        )
    }

    /* Parity: beginFoodSelection defaults */
    /* Parity: beginFoodSelection. The amount confirmed in history wins over the
       preference row, so a food reopens at the grams it was last logged at even
       when preferences never reached this device. */
    static func defaultSelection(
        _ food: Food,
        preference: FoodPreference?,
        remembered: MealMemory.Selection? = nil
    ) -> (quantity: Double, unit: FoodUnitKind) {
        let units = availableUnits(food)
        if let remembered, remembered.quantity > 0,
           let unit = FoodUnitKind(rawValue: remembered.unit), units.contains(unit) {
            return (remembered.quantity, unit)
        }
        if let amount = preference?.usualAmount, amount > 0,
           let rawUnit = preference?.usualUnit,
           let unit = FoodUnitKind(rawValue: rawUnit), units.contains(unit) {
            return (amount, unit)
        }
        let providerID = food.providerProductID?.lowercased() ?? ""
        let wholeItemRestaurantReference = providerID == "fsvo-v5.3:10675"
            || providerID.hasPrefix("mcdonalds-ch:")
            || providerID.hasPrefix("burger-king-ch:")
            || providerID.hasPrefix("kfc-ch:")
            || providerID.hasPrefix("popeyes-ch:")
        if wholeItemRestaurantReference, food.servingUnit == "serving", units.contains(.serving) {
            return (food.servingAmount ?? 1, .serving)
        }
        return (100, units.first ?? .grams)
    }

    static func unitLabel(
        _ food: Food,
        unit: FoodUnitKind,
        localizedName: String
    ) -> String {
        let equivalent: Double? = unit == .serving
            ? food.servingGramsOrML
            : unit == .piece ? food.pieceGramsOrML : nil
        guard let equivalent, equivalent > 0 else { return localizedName }
        let amount = equivalent.rounded() == equivalent
            ? String(Int(equivalent))
            : String(format: "%.1f", equivalent)
        let basis = food.nutritionBasis == "per_100ml" ? "ml" : "g"
        return "\(localizedName) (\(amount) \(basis))"
    }

    static func provenanceLabel(_ food: Food) -> String {
        if food.source == "private" { return "Your private food" }
        if food.source == "open_food_facts" {
            return "Check the package label."
        }
        if food.confidence == "provider_verified" {
            return "Verified label or nutrition-provider reference"
        }
        return "Curated reference profile. Product labels can vary."
    }
}

struct FoodAmountSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var language = LanguageState.shared

    let food: Food
    let preference: FoodPreference?
    /// Last amount this food was confirmed at, read from logged history.
    var remembered: MealMemory.Selection?
    var onClose: () -> Void = {}
    let onConfirm: (Double, String) -> Void

    @State private var quantity: Double = 100
    @State private var unit: FoodUnitKind = .grams
    @State private var quantityText = "100"
    @State private var showNutrientDetail = false
    @FocusState private var quantityFocused: Bool

    private var region: FoodRegion { FoodRegion.resolved(session.data.settings) }
    private var units: [FoodUnitKind] { FoodPortionMath.availableUnits(food) }
    private var portion: FoodPortionResult? {
        FoodPortionMath.portion(food, quantity: quantity, unit: unit)
    }
    private var waterDisclosure: FoodHydration.Disclosure {
        FoodHydration.disclosure(for: food.waterBasis)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let start = FoodPortionMath.defaultSelection(food, preference: preference, remembered: remembered)
            quantity = start.quantity
            unit = start.unit
            quantityText = formatted(start.quantity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(language.text("Done")) {
                    quantityFocused = false
                }
                .font(APEXFont.body(15, weight: .bold))
                .accessibilityIdentifier("food-amount-keyboard-done")
            }
        }
        .sheet(isPresented: $showNutrientDetail) {
            FoodNutrientDetailSheet(food: food)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("CONFIGURE AMOUNT"))
                    .font(APEXFont.mono(10))
                    .tracking(1.8)
                    .foregroundStyle(APEXColor.amberDeep)
                Text(food.localizedName(language.language))
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
            Button { showNutrientDetail = true } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(APEXColor.cyan)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.78), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("Detailed nutrition"))
            .accessibilityHint(language.text("Shows reported vitamins, minerals and nutrient details"))
            .accessibilityIdentifier("food-nutrient-info")
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
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 82),
                        spacing: 9
                    )
                ],
                spacing: 9
            ) {
                macroTile(value: food.kcal100, label: "KCAL", suffix: "", identifier: "kcal")
                macroTile(value: food.protein100, label: "PROTEIN", suffix: "g", identifier: "protein")
                macroTile(value: food.carbs100, label: "CARBS", suffix: "g", identifier: "carbs")
                macroTile(value: food.fat100, label: "FAT", suffix: "g", identifier: "fat")
                if food.waterML100 != nil {
                    macroTile(
                        value: food.waterML100,
                        label: waterDisclosure.isEstimated ? "EST. WATER" : "WATER",
                        suffix: "ml",
                        prefix: waterDisclosure.prefix,
                        identifier: "water"
                    )
                }
            }
        }
        .padding(15)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func macroTile(
        value: Double?,
        label: String,
        suffix: String,
        prefix: String = "",
        identifier: String
    ) -> some View {
        let displayValue = value.map { "\(prefix)\(formatted($0))\(suffix)" } ?? language.text("N/A")
        return VStack(spacing: 3) {
            Text(displayValue)
                .font(APEXFont.mono(15, weight: .bold))
                .foregroundStyle(APEXColor.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Text(language.text(label))
                .font(APEXFont.mono(8))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text(label))
        .accessibilityValue(displayValue)
        .accessibilityIdentifier("food-amount-macro-\(identifier)-value")
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unitLabel(_ option: FoodUnitKind) -> String {
        FoodPortionMath.unitLabel(
            food,
            unit: option,
            localizedName: language.text(option.rawValue)
        )
    }

    private var portionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            let metrics = portionMetrics
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    ForEach(metrics) { metric in
                        portionMetric(metric)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                    ForEach(Array(stride(from: 0, to: metrics.count, by: 3)), id: \.self) { start in
                        GridRow {
                            ForEach(start ..< min(start + 3, metrics.count), id: \.self) { index in
                                portionMetric(metrics[index])
                            }
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metrics) { metric in
                        portionMetric(metric)
                    }
                }
            }
            .font(APEXFont.mono(12, weight: .bold))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("food-amount-preview-metrics")

            Text(language.text(FoodPortionMath.provenanceLabel(food)))
                .font(APEXFont.body(11, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(APEXColor.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("food-amount-preview")
    }

    private var portionMetrics: [FoodPortionMetric] {
        var metrics = [
            FoodPortionMetric(
                id: "kcal",
                text: "\(portion.map { formatted($0.kcal) } ?? language.text("N/A")) kcal",
                color: APEXColor.ink
            )
        ]
        /* EU labelling leads with kilojoules, so European users see the
           figure their packets show alongside the one they track. */
        if region.presentation.showsKilojoules, let portion {
            metrics.append(FoodPortionMetric(
                id: "kilojoules",
                text: "\(FoodRegion.kilojoules(portion.kcal)) kJ",
                color: APEXColor.secondaryInk
            ))
        }
        metrics.append(contentsOf: [
            FoodPortionMetric(
                id: "protein",
                text: "P \(portion.map { formatted($0.proteinG) } ?? language.text("N/A"))g",
                color: APEXColor.ink
            ),
            FoodPortionMetric(
                id: "carbs",
                text: "C \(portion.map { formatted($0.carbsG) } ?? language.text("N/A"))g",
                color: APEXColor.ink
            ),
            FoodPortionMetric(
                id: "fat",
                text: "F \(portion.map { formatted($0.fatG) } ?? language.text("N/A"))g",
                color: APEXColor.ink
            )
        ])
        if let water = portion?.waterML, water > 0 {
            metrics.append(FoodPortionMetric(
                id: "water",
                text: "\(language.text("W")) \(waterDisclosure.prefix)\(formatted(water))ml",
                color: APEXColor.cyan
            ))
        }
        return metrics
    }

    private func portionMetric(_ metric: FoodPortionMetric) -> some View {
        Text(metric.text)
            .foregroundStyle(metric.color)
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
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
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

struct FoodNutrientDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    let food: Food

    private var observations: [NutrientEvidenceObservation] {
        FoodNutrientEvidence.observations(for: food)
    }

    private var grouped: [(NutrientCategory, [NutrientEvidenceObservation])] {
        NutrientCategory.allCases.compactMap { category in
            let rows = observations.filter { FoodNutrientEvidence.category($0) == category }
            return rows.isEmpty ? nil : (category, rows)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(food.localizedName(language.language))
                            .font(APEXFont.display(27))
                            .foregroundStyle(APEXColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(language.format(
                            "Reported per 100 %@ · %@",
                            food.nutritionBasis == "per_100ml" ? "ml" : "g",
                            language.text(food.preparationState.replacingOccurrences(of: "_", with: " "))
                        ))
                            .font(APEXFont.body(13, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if grouped.isEmpty {
                        detailNotice(
                            icon: "doc.text.magnifyingglass",
                            title: language.text("No detailed nutrient evidence"),
                            body: language.text("The available label does not report vitamins, minerals or additional nutrient values.")
                        )
                    } else {
                        ForEach(grouped, id: \.0) { category, rows in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(language.text(categoryTitle(category)), systemImage: categoryIcon(category))
                                    .font(APEXFont.body(16, weight: .bold))
                                    .foregroundStyle(categoryColor(category))
                                VStack(spacing: 0) {
                                    ForEach(rows, id: \.self) { row in
                                        nutrientRow(row)
                                        if row != rows.last { Divider().opacity(0.45) }
                                    }
                                }
                                .padding(.horizontal, 15)
                                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }

                    detailNotice(
                        icon: "checkmark.shield",
                        title: language.text("Evidence, not a diagnosis"),
                        body: language.text("Only values reported by the source are shown. Trace and unavailable values are never changed to zero.")
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Label(language.text("Source and product notice"), systemImage: "shippingbox.and.arrow.backward")
                            .font(APEXFont.body(15, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                        Text(language.text(FoodPortionMath.provenanceLabel(food)))
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(language.text("Source")): \(language.text(sourceLabel(food.source)))")
                            .font(APEXFont.mono(10))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reference = food.providerProductID ?? food.barcode, !reference.isEmpty {
                            Text("\(language.text("Reference")): \(reference)")
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let brand = food.brand, !brand.isEmpty {
                            Text(language.text("Branded products can change. Check the current package label before relying on these values."))
                                .font(APEXFont.body(12, weight: .bold))
                                .foregroundStyle(APEXColor.violet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(APEXColor.violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .background(APEXColor.canvas.ignoresSafeArea())
            .navigationTitle(language.text("Detailed nutrition"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Done")) { dismiss() }
                        .font(APEXFont.body(15, weight: .bold))
                }
            }
        }
    }

    private func nutrientRow(_ row: NutrientEvidenceObservation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(row.name))
                    .font(APEXFont.body(14, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text(statusLabel(row.observationStatus)))
                    .font(APEXFont.mono(9))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.originalValueText.isEmpty {
                    Text("\(language.text("Original source value")): \(row.originalValueText)")
                        .font(APEXFont.mono(8))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(language.text("Source")): \(language.text(sourceLabel(row.sourceKey ?? food.source)))")
                    .font(APEXFont.mono(8))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let reference = row.sourceReference, !reference.isEmpty {
                    Text("\(language.text("Reference")): \(reference)")
                        .font(APEXFont.mono(8))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.derivationMethod != nil {
                    Text(language.text("Normalized from the source value."))
                        .font(APEXFont.body(9, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(valueLabel(row))
                .font(APEXFont.mono(13))
                .foregroundStyle(APEXColor.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }

    private func valueLabel(_ row: NutrientEvidenceObservation) -> String {
        guard let value = row.valuePer100 else {
            return language.text(statusLabel(row.observationStatus))
        }
        let formatted = value >= 100 ? String(format: "%.0f", value)
            : value >= 10 ? String(format: "%.1f", value)
            : String(format: "%.2f", value)
        return "\(formatted) \(row.unit)"
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "open_food_facts": return "Open Food Facts"
        case "private": return "Your private food"
        case "apex_cache": return "APEX curated reference"
        default: return source.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func statusLabel(_ status: NutrientObservationStatus) -> String {
        switch status {
        case .measured: "Measured"
        case .calculated: "Calculated by source"
        case .estimated: "Estimated"
        case .reported: "Reported on source label"
        case .trace: "Trace"
        case .belowDetection: "Below detection"
        case .notMeasured: "Not measured"
        case .missing: "Not available"
        }
    }

    private func categoryTitle(_ category: NutrientCategory) -> String {
        switch category {
        case .vitamins: "Vitamins"
        case .minerals: "Minerals"
        case .fats: "Fat details"
        case .carbohydrates: "Carbohydrate details"
        case .other: "Other nutrition"
        }
    }

    private func categoryIcon(_ category: NutrientCategory) -> String {
        switch category {
        case .vitamins: "sparkles"
        case .minerals: "diamond.fill"
        case .fats: "drop.fill"
        case .carbohydrates: "leaf.fill"
        case .other: "list.bullet.rectangle"
        }
    }

    private func categoryColor(_ category: NutrientCategory) -> Color {
        switch category {
        case .vitamins: APEXColor.violet
        case .minerals: APEXColor.cyan
        case .fats: APEXColor.amberDeep
        case .carbohydrates: APEXColor.green
        case .other: APEXColor.secondaryInk
        }
    }

    private func detailNotice(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(APEXColor.cyan)
                .frame(width: 34, height: 34)
                .background(APEXColor.cyan.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(APEXFont.body(14, weight: .bold))
                Text(body)
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
