import SwiftUI

/// The meals page: today's dayline blocks around a day dial, the one nearest the clock lit.
struct WatchMealsPage: View {
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var timelineAnchor = Date()

    var body: some View {
        if let snapshot = meals.state.snapshot {
            TimelineView(.periodic(from: timelineAnchor, by: 60)) { timeline in
                let day = timeline.date.apexDateKey
                let minute = Calendar.current.component(.hour, from: timeline.date) * 60
                    + Calendar.current.component(.minute, from: timeline.date)
                let current = WatchMealState.currentBlock(snapshot.blocks, minute: minute)
                let filled = Set(snapshot.blocks.map(\.id).filter { !meals.state.logged(day: day, block: $0).isEmpty })

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                WatchMealDayDial(blocks: snapshot.blocks, filled: filled, current: current, minute: minute)
                                    .frame(width: 62, height: 62)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Meals", tableName: "WatchMeals")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    WatchMealFigure(sizes: [24, 20, 17]) { size in
                                        Text(verbatim: "\(Int(meals.state.kcal(day: day)))")
                                            .font(.system(size: size, weight: .bold, design: .rounded))
                                            + Text(verbatim: "\u{00A0}kcal")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(filled.count) of \(snapshot.blocks.count) logged", tableName: "WatchMeals")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(WatchTint.leaf)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            }
                            .padding(.bottom, 2)

                            ForEach(snapshot.blocks) { block in
                                let lines = meals.state.logged(day: day, block: block.id)
                                NavigationLink {
                                    WatchMealBlockView(block: block, day: day)
                                        .environmentObject(meals)
                                } label: {
                                    WatchMealBlockRow(block: block, lines: lines, isCurrent: block.id == current)
                                }
                                .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 18,
                                                                   isLit: block.id == current))
                                .id(block.id)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onAppear {
                        // The block being eaten is the one in reach, without scrolling past the dial.
                        if let current, current != snapshot.blocks.first?.id { proxy.scrollTo(current, anchor: .center) }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { timelineAnchor = .now }
            }
        }
    }
}

/// A day on a clock face, midnight at the top: each block a light at its time, lit once it holds food,
/// with a small mark for now.
private struct WatchMealDayDial: View {
    let blocks: [WatchMealBlock]
    let filled: Set<String>
    let current: String?
    let minute: Int

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2 - 5
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)
                    .frame(width: radius * 2, height: radius * 2)
                Circle()
                    .trim(from: 0, to: Double(minute) / 1440)
                    .stroke(
                        AngularGradient(colors: [WatchTint.leaf.opacity(0.05), WatchTint.leaf.opacity(0.55)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: radius * 2, height: radius * 2)
                Image(systemName: "fork.knife")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WatchTint.leaf)
                ForEach(blocks) { block in
                    if let blockMinute = block.minute {
                        let lit = filled.contains(block.id)
                        Circle()
                            .fill(lit ? WatchTint.leaf : Color.black)
                            .overlay(Circle().strokeBorder(lit ? .white.opacity(0.6) : WatchTint.leaf.opacity(0.7),
                                                           lineWidth: lit ? 0.8 : 1.4))
                            .frame(width: block.id == current ? 9 : 7, height: block.id == current ? 9 : 7)
                            .shadow(color: lit ? WatchTint.leaf.opacity(0.9) : .clear, radius: 3)
                            .position(point(blockMinute, radius: radius, center: center))
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: 3.5, height: 3.5)
                    .position(point(minute, radius: radius - 6, center: center))
            }
        }
        .accessibilityHidden(true)
    }

    private func point(_ minute: Int, radius: Double, center: CGPoint) -> CGPoint {
        let angle = Double(minute) / 1440 * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

private struct WatchMealBlockRow: View {
    let block: WatchMealBlock
    let lines: [WatchMealState.Line]
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 9) {
            Text(verbatim: block.time)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? WatchTint.leaf : .secondary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: block.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if lines.isEmpty {
                    Text(isCurrent ? "Now" : "Nothing yet", tableName: "WatchMeals")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(isCurrent ? WatchTint.leaf : .secondary)
                } else {
                    (Text("\(lines.count) foods", tableName: "WatchMeals") + Text(verbatim: " · ")
                        + Text("\(Int(lines.reduce(0) { $0 + $1.kcal })) kcal", tableName: "WatchMeals"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !lines.isEmpty {
                WatchMealTick(isPending: lines.contains(where: \.isPending))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 50)
        .contentShape(.rect)
    }
}

/// A block's page: what it holds today, then foods to add, yesterday's first.
struct WatchMealBlockView: View {
    let block: WatchMealBlock
    let day: String
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lines = meals.state.logged(day: day, block: block.id)
        let suggestions = meals.state.suggestions(day: day, block: block.id)
        let yesterday = suggestions.filter { $0.reason == .yesterday }

        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                if !lines.isEmpty {
                    WatchMealSectionTitle(title: "Logged", systemImage: "checkmark.circle.fill",
                                          detail: Int(lines.reduce(0) { $0 + $1.kcal }))
                    ForEach(lines) { line in
                        WatchMealLoggedRow(line: line)
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }

                if yesterday.count >= 2 {
                    NavigationLink {
                        WatchMealConfirmView(block: block, day: day, suggestions: yesterday)
                            .environmentObject(meals)
                    } label: {
                        WatchMealActionRow(
                            title: Text("Same as yesterday", tableName: "WatchMeals"),
                            detail: Text("\(yesterday.count) foods", tableName: "WatchMeals") + Text(verbatim: " · ")
                                + Text("\(Int(yesterday.reduce(0) { $0 + $1.kcal })) kcal", tableName: "WatchMeals"),
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 18, isLit: true))
                    .padding(.top, lines.isEmpty ? 0 : 4)
                }

                section(.yesterday, suggestions)
                section(.favourite, suggestions)
                section(.recent, suggestions)

                if suggestions.isEmpty && lines.isEmpty {
                    Text("Foods you log in FITR MAX on iPhone will be offered here.", tableName: "WatchMeals")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 8)
            .animation(reduceMotion ? nil : .snappy, value: lines.map(\.id))
        }
        .navigationTitle(Text(verbatim: block.label))
    }

    @ViewBuilder
    private func section(_ reason: WatchMealState.Reason, _ suggestions: [WatchMealState.Suggestion]) -> some View {
        let rows = suggestions.filter { $0.reason == reason }
        if !rows.isEmpty {
            switch reason {
            case .yesterday: WatchMealSectionTitle(title: "Yesterday", systemImage: "arrow.uturn.backward")
            case .favourite: WatchMealSectionTitle(title: "Favourites", systemImage: "star.fill")
            case .recent: WatchMealSectionTitle(title: "Recent", systemImage: "clock")
            }
            ForEach(rows) { suggestion in
                NavigationLink {
                    WatchMealPortionView(block: block, day: day, food: suggestion.food, portion: suggestion.portion)
                        .environmentObject(meals)
                } label: {
                    WatchMealFoodRow(food: suggestion.food, portion: suggestion.portion)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 16))
            }
        }
    }
}

/// The amount, turned with the Digital Crown, then one tap to add it.
private struct WatchMealPortionView: View {
    let block: WatchMealBlock
    let day: String
    let food: WatchMealFood
    let portion: WatchMealPortion
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Double
    /// The crown turns the amount from the moment the page opens, not the page.
    @FocusState private var amountFocused: Bool

    init(block: WatchMealBlock, day: String, food: WatchMealFood, portion: WatchMealPortion) {
        self.block = block
        self.day = day
        self.food = food
        self.portion = portion
        _quantity = State(initialValue: portion.quantity)
    }

    private var step: Double { portion.step }
    private var maximum: Double { portion.maximum }

    private func amount(sizes: [CGFloat]) -> some View {
        WatchMealFigure(sizes: sizes) { size in
            Text(verbatim: WatchMealFormat.amount(adjusted)).font(.system(size: size, weight: .bold, design: .rounded))
        }
    }

    private var adjusted: WatchMealPortion {
        var value = portion
        value.quantity = quantity
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(verbatim: food.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // The buttons go under the amount when the two cannot share a line on a small Watch.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        stepButton("minus", by: -step)
                        Spacer(minLength: 2)
                        amount(sizes: [30])
                        Spacer(minLength: 2)
                        stepButton("plus", by: step)
                    }
                    VStack(spacing: 4) {
                        amount(sizes: [26, 21, 16])
                        HStack(spacing: 20) {
                            stepButton("minus", by: -step)
                            stepButton("plus", by: step)
                        }
                    }
                }
                .focusable()
                .focused($amountFocused)
                .digitalCrownRotation(
                    $quantity, from: step, through: maximum,
                    by: step, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: food.name))
                .accessibilityValue(Text(verbatim: WatchMealFormat.amount(adjusted)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: change(by: step)
                    case .decrement: change(by: -step)
                    @unknown default: break
                    }
                }

                Text("\(Int(adjusted.kcal(food))) kcal · \(Int(adjusted.protein(food))) g protein",
                     tableName: "WatchMeals")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    if meals.add([(food, adjusted)], block: block.id, day: day) {
                        dismiss()
                    }
                } label: {
                    Label { Text("Add", tableName: "WatchMeals") } icon: { Image(systemName: "plus") }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 22, isLit: true))
                .disabled(!adjusted.isLoggable)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle(Text(verbatim: block.label))
        .onAppear { amountFocused = true }
    }

    private func stepButton(_ systemImage: String, by delta: Double) -> some View {
        Button { change(by: delta) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 15))
    }

    private func change(by delta: Double) {
        quantity = max(step, (quantity + delta).rounded(toMultipleOf: step))
    }
}

/// Yesterday's foods for this block, all at once.
private struct WatchMealConfirmView: View {
    let block: WatchMealBlock
    let day: String
    let suggestions: [WatchMealState.Suggestion]
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                WatchMealSectionTitle(title: "Yesterday", systemImage: "arrow.uturn.backward",
                                      detail: Int(suggestions.reduce(0) { $0 + $1.kcal }))
                ForEach(suggestions) { suggestion in
                    WatchMealFoodRow(food: suggestion.food, portion: suggestion.portion, showsAdd: false)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    if meals.add(suggestions.map { ($0.food, $0.portion) }, block: block.id, day: day) {
                        dismiss()
                    }
                } label: {
                    Label { Text("Add all", tableName: "WatchMeals") } icon: { Image(systemName: "plus") }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 22, isLit: true))
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle(Text(verbatim: block.label))
    }
}

/// A figure on one line at the largest size that fits; it steps down rather than wrap or shrink to fit.
private struct WatchMealFigure: View {
    let sizes: [CGFloat]
    let text: (CGFloat) -> Text

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(sizes, id: \.self) { size in
                text(size)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .contentTransition(.numericText())
    }
}

private struct WatchMealSectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String
    var detail: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTint.leaf)
            Text(title, tableName: "WatchMeals")
            Spacer(minLength: 4)
            if let detail {
                Text("\(detail) kcal", tableName: "WatchMeals")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct WatchMealFoodRow: View {
    let food: WatchMealFood
    let portion: WatchMealPortion
    var showsAdd = true

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: food.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: WatchMealFormat.detail(portion, food: food))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAdd {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black.opacity(0.85), WatchTint.leaf)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 46)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchMealLoggedRow: View {
    let line: WatchMealState.Line

    var body: some View {
        HStack(spacing: 8) {
            WatchMealTick(isPending: line.isPending)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: line.food.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: WatchMealFormat.amount(line.portion) + " · " + WatchMealFormat.kcal(line.kcal))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Logged: a lit tick. Waiting for the iPhone: the same tick, hollow, with the phone beside it.
private struct WatchMealTick: View {
    let isPending: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isPending ? Color.clear : WatchTint.leaf)
                .overlay(Circle().strokeBorder(WatchTint.leaf.opacity(isPending ? 0.8 : 0), lineWidth: 1.4))
            Image(systemName: isPending ? "iphone" : "checkmark")
                .font(.system(size: isPending ? 9 : 10, weight: .heavy))
                .foregroundStyle(isPending ? WatchTint.leaf : .black.opacity(0.8))
        }
        .frame(width: 20, height: 20)
        .accessibilityElement()
        .accessibilityLabel(isPending
            ? Text("Waiting for iPhone", tableName: "WatchMeals")
            : Text("Logged", tableName: "WatchMeals"))
    }
}

private struct WatchMealActionRow: View {
    let title: Text
    let detail: Text
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WatchTint.leaf)
                .frame(width: 28, height: 28)
                .background(WatchTint.leaf.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                detail
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 50)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

enum WatchMealFormat {
    /// "150 g", "2 pc." with a no-break space, so a figure never wraps away from its unit.
    static func amount(_ portion: WatchMealPortion) -> String {
        let number = portion.quantity.formatted(.number.precision(.fractionLength(0...1)))
        switch portion.unit {
        case "piece": return String(localized: "\(number) pc.", table: "WatchMeals")
        case "serving": return String(localized: "\(number) serv.", table: "WatchMeals")
        default: return number + "\u{00A0}" + portion.unit
        }
    }

    static func kcal(_ value: Double) -> String {
        String(localized: "\(Int(value)) kcal", table: "WatchMeals")
    }

    static func detail(_ portion: WatchMealPortion, food: WatchMealFood) -> String {
        amount(portion) + " · " + kcal(portion.kcal(food))
    }
}

private extension Double {
    func rounded(toMultipleOf step: Double) -> Double {
        step > 0 ? (self / step).rounded() * step : self
    }
}
