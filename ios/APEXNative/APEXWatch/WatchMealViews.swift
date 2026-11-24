import SwiftUI
import WatchKit

/// The meals page: today's dayline blocks around a day dial, the one nearest the clock lit.
struct WatchMealsPage: View {
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var timelineAnchor = Date()
    #if DEBUG
    /// Launch with APEX_WATCH_PREVIEW_MEAL=block or =amount (and the meals page) to open lunch, or the amount page
    /// for its longest-named food.
    @State private var preview = ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_MEAL"]
    #endif

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
            #if DEBUG
            .navigationDestination(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                let day = Date().apexDateKey
                if let block = snapshot.blocks.first(where: { $0.id == "lunch" }) {
                    if preview == "block" {
                        WatchMealBlockView(block: block, day: day).environmentObject(meals)
                    } else if let longest = meals.state.suggestions(day: day, block: block.id)
                        .max(by: { $0.food.name.count < $1.food.name.count }) {
                        WatchMealPortionView(block: block, day: day, food: longest.food, portion: longest.portion)
                            .environmentObject(meals)
                    }
                }
            }
            #endif
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
                if let guide = block.guide {
                    WatchMealMacroGuide(logged: meals.state.macros(day: day, block: block.id), guide: guide)
                        .padding(.bottom, 2)
                }

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

/// The amount: the crown or a sideways swipe moves it a gram at a time when slow and faster when fast, the
/// buttons nudge it by one, and tapping the figure types an exact one. The amount and Add share the first screen,
/// so a remembered amount that is already right is one tap.
private struct WatchMealPortionView: View {
    let block: WatchMealBlock
    let day: String
    let food: WatchMealFood
    let portion: WatchMealPortion
    @EnvironmentObject private var meals: WatchMealStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Double
    /// The crown's own position; each detent moves the amount through the dial.
    @State private var crown = 0.0
    @State private var dial = WatchMealAmountDial()
    @State private var swipeIsSideways: Bool?
    @State private var swipeTravel = 0.0
    @State private var lastHaptic = -Double.infinity
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

    private var adjusted: WatchMealPortion {
        var value = portion
        value.quantity = quantity
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text(verbatim: food.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 2) {
                    stepButton("minus", by: -step)
                    // Tapping the figure opens the Watch's own input: keyboard, Scribble or dictation.
                    TextFieldLink(prompt: Text("Type an amount", tableName: "WatchMeals")) {
                        WatchMealFigure(sizes: [30, 26, 22, 18]) { size in
                            Text(verbatim: WatchMealFormat.amount(adjusted))
                                .font(.system(size: size, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    } onSubmit: { text in
                        if let typed = WatchMealPortion.typedQuantity(text) { set(typed, haptic: false) }
                        amountFocused = true
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: food.name))
                    .accessibilityValue(Text(verbatim: WatchMealFormat.amount(adjusted)))
                    .accessibilityHint(Text("Type an amount", tableName: "WatchMeals"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: set(quantity + step, haptic: false)
                        case .decrement: set(quantity - step, haptic: false)
                        @unknown default: break
                        }
                    }
                    stepButton("plus", by: step)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)
                .focusable()
                .focused($amountFocused)
                .digitalCrownRotation(
                    $crown, from: -1_000_000, through: 1_000_000,
                    by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
                )
                .onChange(of: crown) { old, new in turn(new - old, travelPerStep: 1, haptic: false) }

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
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 20, isLit: true))
                .disabled(!adjusted.isLoggable)
                .padding(.top, 2)

                Text("Turn the crown or swipe. Tap the number to type it.", tableName: "WatchMeals")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(Text(verbatim: block.label))
        .onAppear { amountFocused = true }
    }

    /// A sideways swipe across the amount; an up-and-down one is left to the page's scroll.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let sideways = value.translation.width
                if swipeIsSideways == nil { swipeIsSideways = abs(sideways) > abs(value.translation.height) * 1.2 }
                guard swipeIsSideways == true else { return }
                turn(sideways - swipeTravel, travelPerStep: 5, haptic: true)
                swipeTravel = sideways
            }
            .onEnded { _ in
                swipeIsSideways = nil
                swipeTravel = 0
            }
    }

    private func stepButton(_ systemImage: String, by delta: Double) -> some View {
        Button { set(quantity + delta, haptic: false) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(WatchGlassButtonStyle(tint: WatchTint.leaf, cornerRadius: 15))
        // The figure is the one adjustable control VoiceOver offers.
        .accessibilityHidden(true)
    }

    private func turn(_ travel: Double, travelPerStep: Double, haptic: Bool) {
        let steps = dial.steps(for: travel, travelPerStep: travelPerStep, at: Date.timeIntervalSinceReferenceDate)
        if steps != 0 { set(quantity + Double(steps) * step, haptic: haptic) }
    }

    /// The crown ticks by itself; a swipe ticks here, at most every 80 ms, when the wearer keeps haptics on.
    private func set(_ value: Double, haptic: Bool) {
        let next = min(maximum, max(step, value.rounded(toMultipleOf: step)))
        guard next.isFinite, next != quantity else { return }
        quantity = next
        let now = Date.timeIntervalSinceReferenceDate
        if haptic, meals.hapticsEnabled, now - lastHaptic >= 0.08 {
            WKInterfaceDevice.current().play(.click)
            lastHaptic = now
        }
    }
}

/// The meal's protein, carbs and fat: what it holds against its share of the day, one line each.
private struct WatchMealMacroGuide: View {
    let logged: WatchMealMacros
    let guide: WatchMealMacros

    var body: some View {
        VStack(spacing: 6) {
            row("Protein", logged.protein, guide.protein, WatchTint.leaf)
            row("Carbs", logged.carbs, guide.carbs, WatchTint.gold)
            row("Fat", logged.fat, guide.fat, WatchTint.ember)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: LocalizedStringKey, _ value: Double, _ target: Double, _ tint: Color) -> some View {
        let (grams, goal) = (Int(value.rounded()), Int(target.rounded()))
        let label = Text(title, tableName: "WatchMeals")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        // One unbreakable figure, so the grams never wrap away from their unit.
        let figure = Text(verbatim: "\(grams)\u{00A0}/\u{00A0}\(goal)\u{00A0}g")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(target > 0 && value > target * 1.15 ? WatchTint.ember : .primary)
            .fixedSize()
        return VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    label.lineLimit(1).fixedSize()
                    Spacer(minLength: 4)
                    figure
                }
                VStack(alignment: .leading, spacing: 1) {
                    label.fixedSize(horizontal: false, vertical: true)
                    figure
                }
            }
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(tint)
                            .frame(width: proxy.size.width * min(1, target > 0 ? max(0, value) / target : 0))
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title, tableName: "WatchMeals"))
        .accessibilityValue(Text("\(grams) of \(goal) g", tableName: "WatchMeals"))
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
