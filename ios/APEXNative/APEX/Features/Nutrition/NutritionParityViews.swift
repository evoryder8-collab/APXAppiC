import SwiftUI

struct NutritionCalorieBalance: Equatable {
    let label: String
    let amount: Int
    let isOverTarget: Bool

    static func resolve(target: Int, consumed: Int) -> NutritionCalorieBalance {
        let isOverTarget = consumed > target
        return NutritionCalorieBalance(
            label: isOverTarget ? "Exceeding by" : "Remaining",
            amount: abs(target - consumed),
            isOverTarget: isOverTarget
        )
    }
}

/// The native equivalent of the web "Nutrition at a glance" card. All values
/// come from the selected user's structured Supabase meal rows, with the daily
/// log used only as the backward-compatible fallback for older/manual days.
struct NutritionGlanceCard: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var language = LanguageState.shared

    let date: Date
    let targets: NutritionTargets
    let onEditTargets: () -> Void
    var onOpenCalendar: (() -> Void)?
    var completion: Int? = nil

    private var meals: [LoggedMeal] {
        session.data.loggedMeals.filter { $0.localDate == date.apexDateKey }
    }

    private var dailyLog: DailyLog? {
        session.data.dailyLogs.first { $0.date == date.apexDateKey }
    }

    private var totals: FoodNutrients {
        if !meals.isEmpty {
            return FoodNutrients(
                kcal: meals.reduce(0) { $0 + $1.totalKcal },
                proteinG: meals.reduce(0) { $0 + $1.totalProteinG },
                carbsG: meals.reduce(0) { $0 + $1.totalCarbsG },
                fatG: meals.reduce(0) { $0 + $1.totalFatG }
            )
        }
        return FoodNutrients(
            kcal: Double(dailyLog?.kcal ?? 0),
            proteinG: Double(dailyLog?.proteinG ?? 0),
            carbsG: Double(dailyLog?.carbsG ?? 0),
            fatG: Double(dailyLog?.fatG ?? 0)
        )
    }

    private var calorieBalance: NutritionCalorieBalance {
        NutritionCalorieBalance.resolve(
            target: targets.targetCalories,
            consumed: Int(totals.kcal.rounded())
        )
    }

    private var wearableActiveCalories: Int? {
        WearableActivityRecord
            .history(from: session.data.settings?.addons["watch_activity_history"])
            .last { $0.date == date.apexDateKey }?
            .activeCalories
    }

    private var resolvedBurnedCalories: Int {
        EnergyEngine.resolvedActiveCalories(
            wearableActiveCalories: wearableActiveCalories,
            logs: session.data.activityLogs.filter { $0.date == date.apexDateKey }
        )
    }

    private var calorieProgress: Double {
        min(max(totals.kcal / Double(max(targets.targetCalories, 1)), 0), 1)
    }

    var body: some View {
        GlassCard(radius: 34, padding: 20) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("TODAY"))
                            .font(APEXFont.mono(10))
                            .tracking(2)
                            .foregroundStyle(APEXColor.amberDeep)
                        Button(action: onEditTargets) {
                            HStack(spacing: 7) {
                                Text(language.text("Nutrition at a glance"))
                                    .font(APEXFont.display(26))
                                    /* Wraps rather than truncates once the text
                                       is large: a clipped heading tells the
                                       reader less than a two-line one. */
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                    /* Romanian and Thai run longer than the
                                       English this was sized for. Shrinking a
                                       little is better than wrapping, and far
                                       better than hyphenating a title. */
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(APEXColor.amberDeep)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(APEXColor.ink)
                    }
                    /* The "private" badge said nothing: every screen in the app
                       is private, so a label claiming it on one card is noise.
                       The date went with it, because the navigator at the top of
                       the page already carries the date and stays there however
                       far down you scroll. */
                    Spacer(minLength: 4)
                    if let completion {
                        CompletionRing(value: completion)
                            .scaleEffect(0.68)
                            .frame(width: 47, height: 47)
                    }
                }

                /* Three columns around a 164pt ring only fit while the text is
                   small. At accessibility sizes the outer numbers ran into the
                   ring and their labels were cut off, so the row becomes a
                   column and each figure gets the full width. */
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 18))
                    : AnyLayout(HStackLayout(spacing: 15))
                layout {
                    VStack(spacing: 3) {
                        /* Four-digit intakes wrapped mid-number, dropping the
                           last digit onto its own line. The column is narrow by
                           design, so the figure scales instead of wrapping. */
                        Text("\(Int(totals.kcal.rounded()))")
                            .font(APEXFont.display(32))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text(language.text("Eaten").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: onEditTargets) {
                        ZStack {
                            Circle()
                                .stroke(
                                    calorieBalance.isOverTarget ? Color.red.opacity(0.13) : APEXColor.ink.opacity(0.07),
                                    lineWidth: 15
                                )
                            Circle()
                                .trim(from: 0, to: max(calorieProgress, 0.012))
                                .stroke(
                                    AngularGradient(
                                        colors: calorieBalance.isOverTarget
                                            ? [Color.orange, Color.red, Color.orange]
                                            : [APEXColor.amber, APEXColor.cyan, APEXColor.amber],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.snappy, value: calorieProgress)
                            VStack(spacing: 2) {
                                Text(language.text(calorieBalance.label))
                                    .font(APEXFont.body(10, weight: .semibold))
                                    .foregroundStyle(calorieBalance.isOverTarget ? Color.red : APEXColor.secondaryInk)
                                Text("\(calorieBalance.amount)")
                                    .font(APEXFont.display(34))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .foregroundStyle(calorieBalance.isOverTarget ? Color.red : APEXColor.ink)
                                    .contentTransition(.numericText())
                                Text(language.format("of %d kcal", targets.targetCalories))
                                    .font(APEXFont.mono(8))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }
                        .frame(width: 164, height: 164)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 3) {
                        Text("\(resolvedBurnedCalories)")
                            .font(APEXFont.display(29))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text(language.text("Burned").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 9) {
                    GlanceMacroCard(
                        title: "Protein", value: totals.proteinG,
                        target: Double(targets.proteinG), color: Color(red: 0.87, green: 0.22, blue: 0.52)
                    )
                    GlanceMacroCard(
                        title: "Carbs", value: totals.carbsG,
                        target: Double(targets.carbsG), color: APEXColor.cyan
                    )
                    GlanceMacroCard(
                        title: "Fat", value: totals.fatG,
                        target: Double(targets.fatG), color: APEXColor.violet
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-glance-card")
    }
}

private struct CompletionRing: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle().stroke(APEXColor.ink.opacity(0.07), lineWidth: 7)
            Circle()
                .trim(from: 0, to: Double(value) / 100)
                .stroke(APEXColor.green.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: value)
            Text("\(value)%")
                .font(APEXFont.mono(12))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(width: 63, height: 63)
        .accessibilityLabel("Daily completion")
        .accessibilityValue("\(value) percent")
    }
}

private struct GlanceMacroCard: View {
    @State private var language = LanguageState.shared
    let title: String
    let value: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.text(title))
                .font(APEXFont.body(11, weight: .bold))
            Text(language.format("%.0f/%.0f g", value, target))
                .font(APEXFont.mono(9))
                .foregroundStyle(APEXColor.secondaryInk)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(APEXColor.ink.opacity(0.07))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: proxy.size.width * min(max(value / max(target, 1), 0), 1))
                }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct APEXDateNavigator: View {
    @State private var language = LanguageState.shared
    let date: Date
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(language.text("Previous day"))

            Button(action: onOpenCalendar) {
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(language.language.locale)).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(10))
                        /* The date is the whole point of this control, so it
                           shrinks rather than becoming "FRIDAY 21 AUGU…". */
                        .minimumScaleFactor(0.5)
                        .tracking(1.25)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(Calendar.current.isDateInToday(date) ? language.text("TODAY") : language.text("OPEN CALENDAR"))
                        .font(APEXFont.mono(8))
                        .foregroundStyle(APEXColor.violet)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("Open calendar"))

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(language.text("Next day"))
        }
        .foregroundStyle(APEXColor.secondaryInk)
        .shadow(color: APEXColor.ink.opacity(0.08), radius: 10, y: 5)
    }
}

private struct APEXEdgeDateSwipeModifier: ViewModifier {
    let onPrevious: () -> Void
    let onNext: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 28).onEnded { value in
                        guard value.translation.width > 54, abs(value.translation.height) < 90 else { return }
                        onPrevious()
                    })
            }
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 28).onEnded { value in
                        guard value.translation.width < -54, abs(value.translation.height) < 90 else { return }
                        onNext()
                    })
            }
    }
}

extension View {
    func apexEdgeDateSwipe(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        modifier(APEXEdgeDateSwipeModifier(onPrevious: onPrevious, onNext: onNext))
    }
}

struct NutritionTargetSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var pendingQuickLevel: ActivityLevel?

    let date: Date
    var onClose: () -> Void = {}

    private var logs: [ActivityLog] {
        session.data.activityLogs.filter { $0.date == date.apexDateKey }
    }

    private var targets: NutritionTargets? {
        guard let profile = session.profile else { return nil }
        return EnergyEngine.targets(
            profile: profile,
            logs: logs,
            catalog: session.data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: session.data.settings)
        )
    }

    private var goalPresets: [NutritionGoalPreset] {
        NutritionGoalPolicy.presets(context: NutritionGoalPolicy.context(from: session.data.settings))
    }

    private var activeGoalLabel: String {
        guard let goal = session.profile?.goal else { return "Goal" }
        return NutritionGoalPolicy.preset(
            for: goal,
            context: NutritionGoalPolicy.context(from: session.data.settings)
        ).label
    }

    var body: some View {
        /* Card content: goal and activity level are a glance and a tap, not a
           screen that has to be dismissed. */
        VStack(alignment: .leading, spacing: 12) {
                    APEXPopoverHeader(title: language.text("Daily calorie target"), onClose: onClose)
                    if let targets {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(targets.targetCalories)")
                                .font(APEXFont.display(32))
                                .contentTransition(.numericText())
                            Text("kcal")
                                .font(APEXFont.body(15, weight: .bold))
                                .foregroundStyle(APEXColor.secondaryInk)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(language.text(activeGoalLabel))
                                Text(language.text(targets.level.title))
                            }
                            .font(APEXFont.mono(10))
                            .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }

                    targetGroup(title: "GOAL") {
                        NutritionGoalPresetPicker(
                            presets: goalPresets,
                            selected: session.profile?.goal,
                            onSelect: { goal in Task { await session.setGoal(goal) } }
                        )
                    }

                    targetGroup(title: "ACTIVITY LEVEL") {
                        VStack(alignment: .leading, spacing: 8) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                                ForEach(ActivityLevel.allCases, id: \.self) { level in
                                    Button(language.text(level.title)) {
                                        if logs.isEmpty {
                                            Task { await session.setActivityLevel(level) }
                                        } else {
                                            pendingQuickLevel = level
                                        }
                                    }
                                    .buttonStyle(TargetChoiceStyle(
                                        selected: session.profile?.activityLevel == level && logs.isEmpty,
                                        color: APEXColor.cyan
                                    ))
                                }
                            }
                            if !logs.isEmpty {
                                Label(language.text("Wearable or detailed activity is active. Tap a level to use manual activity."), systemImage: "applewatch")
                                    .font(APEXFont.body(9, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }
                    }

                    if let targets {
                        HStack(spacing: 12) {
                            targetFooterMetric("PROTEIN", targets.proteinG, "g")
                            targetFooterMetric("CARBS", targets.carbsG, "g")
                            targetFooterMetric("FAT", targets.fatG, "g")
                            targetFooterMetric("TDEE", targets.tdee, "")
                        }
                    }
            }
            .confirmationDialog(
                language.text("Wearable data is active"),
                isPresented: Binding(
                    get: { pendingQuickLevel != nil },
                    set: { if !$0 { pendingQuickLevel = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(language.text("Switch to manual activity"), role: .destructive) {
                    guard let level = pendingQuickLevel else { return }
                    pendingQuickLevel = nil
                    Task {
                        await session.clearActivities(on: date)
                        await session.setActivityLevel(level)
                    }
                }
                Button(language.text("Cancel"), role: .cancel) { pendingQuickLevel = nil }
            } message: {
                Text(language.text("This clears today's detailed activity blocks and uses the manual level you selected."))
            }
    }

    private func targetGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(radius: 24, padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                Text(language.text(title))
                    .font(APEXFont.mono(10))
                    .tracking(1.4)
                    .foregroundStyle(APEXColor.secondaryInk)
                content()
            }
        }
    }

    private func targetFooterMetric(_ title: String, _ value: Int, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text(language.text(title))
                .font(APEXFont.mono(7))
                .foregroundStyle(APEXColor.secondaryInk)
            Text("\(value)\(unit)")
                .font(APEXFont.mono(11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct NutritionGoalPresetPicker: View {
    @State private var language = LanguageState.shared
    @State private var explainedGoal: Goal?

    let presets: [NutritionGoalPreset]
    let selected: Goal?
    let onSelect: (Goal) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(presets, id: \.goal) { preset in
                    goalChoice(preset)
                }
            }

            if let explained = presets.first(where: { $0.goal == explainedGoal }) {
                VStack(alignment: .leading, spacing: 4) {
                    let percent = Int(((explained.factor - 1) * 100).rounded())
                    Text("\(language.text(explained.label)) · \(percent > 0 ? "+" : "")\(percent)%")
                        .font(APEXFont.body(11, weight: .bold))
                    Text(language.text(explained.explanation))
                        .font(APEXFont.body(10, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                    Text(language.text(explained.caution))
                        .font(APEXFont.body(9, weight: .bold))
                        .foregroundStyle(APEXColor.amberDeep)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(APEXColor.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private func goalChoice(_ preset: NutritionGoalPreset) -> some View {
        let active = selected == preset.goal
        return ZStack(alignment: .topTrailing) {
            Button {
                onSelect(preset.goal)
            } label: {
                Text(language.text(preset.label))
                    .font(APEXFont.body(10, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.horizontal, 4)
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .background {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(active ? AnyShapeStyle(APEXColor.amber.gradient) : AnyShapeStyle(Color.white.opacity(0.78)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(APEXColor.amber.opacity(active ? 0 : 0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(active ? .isSelected : [])

            Button {
                explainedGoal = explainedGoal == preset.goal ? nil : preset.goal
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(active ? Color.white : APEXColor.amberDeep)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("About \(preset.label)"))
        }
    }
}

private struct TargetChoiceStyle: ButtonStyle {
    let selected: Bool
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(APEXFont.body(12, weight: .bold))
            .foregroundStyle(selected ? .white : APEXColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(selected ? color.gradient : Color.white.opacity(0.56).gradient, in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct DaylineEntry: Identifiable {
    let id: String
    let minute: Int
    let slot: String
    let title: String
    let plannedMeal: Meal?
    let loggedMeal: LoggedMeal?

    var isLogged: Bool { loggedMeal != nil }
}

enum DaylineAxisLabels {
    static func shouldShow(lineMinute: Int, entryMinutes: [Int]) -> Bool {
        let axisClockMinute = clockMinute(lineMinute)
        return !entryMinutes.contains { clockMinute($0) == axisClockMinute }
    }

    private static func clockMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }
}

/// A native, scroll-efficient version of the web metabolic Dayline. It keeps
/// planned meal moments and actual finish times distinct and opens the same
/// structured meal editor from either state.
struct APEXDaylineView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var dragPreview: [String: Int] = [:]
    /*
     * Swipe-to-delete state lives here, not inside the row. Rows are rebuilt
     * whenever the day's data changes, and row-local @State is discarded with
     * them, which slammed a revealed card shut a moment after it opened.
     * Only one card may stand open at a time, as on the web.
     */
    @State private var revealedEntryID: String?
    @State private var swipingEntryID: String?
    @State private var liveRevealOffset: CGFloat = 0

    private let revealWidth: CGFloat = 96

    let date: Date
    let onOpenComposer: (MealComposerRequest) -> Void
    let onAddMeal: () -> Void
    var compact = false

    private func revealOffset(for entry: DaylineEntry) -> CGFloat {
        if swipingEntryID == entry.id { return liveRevealOffset }
        return revealedEntryID == entry.id ? -revealWidth : 0
    }

    private func beginReveal(_ entry: DaylineEntry, translation: CGFloat) {
        let base: CGFloat = revealedEntryID == entry.id ? -revealWidth : 0
        swipingEntryID = entry.id
        liveRevealOffset = max(-revealWidth, min(0, base + translation))
    }

    private func endReveal(_ entry: DaylineEntry, translation: CGFloat) {
        let base: CGFloat = revealedEntryID == entry.id ? -revealWidth : 0
        let settled = base + translation
        /* A third of the way is enough to commit. Requiring half meant an
           ordinary swipe fell back to closed and the delete button was never
           reachable. Closing still needs a deliberate swipe back. */
        let opensAt = -revealWidth / 3
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            revealedEntryID = settled < opensAt ? entry.id : nil
            swipingEntryID = nil
            liveRevealOffset = 0
        }
    }

    private func closeReveal() {
        guard revealedEntryID != nil || swipingEntryID != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            revealedEntryID = nil
            swipingEntryID = nil
            liveRevealOffset = 0
        }
    }

    private var daylineTimeZone: TimeZone {
        let identifier = session.data.settings?.addons["time_zone"]?.stringValue
        return identifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    private var daylineCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = daylineTimeZone
        return calendar
    }

    /*
     * The day's rows come from the configured meal blocks, exactly as the web
     * builds them, and a logged meal is matched into the block it belongs to.
     *
     * The native version had been reading the planned-meals table instead. That
     * table is the meal timeline's source, not the Dayline's, and when it was
     * empty the Dayline had nothing to draw: a day arrived with no blocks at
     * all, where the web still showed every slot waiting to be filled.
     */
    private var entries: [DaylineEntry] {
        let logged = session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .sorted { parsedTimestamp($0.loggedAt) < parsedTimestamp($1.loggedAt) }
        var claimed: Set<UUID> = []

        var rows = MealBlocks.enabled(session.data.settings?.addons["meal_blocks"]).map { block -> DaylineEntry in
            let match = logged.first { candidate in
                normalize(candidate.mealSlot) == normalize(block.kind) && !claimed.contains(candidate.id)
            }
            if let match { claimed.insert(match.id) }
            /* A saved schedule can move a block's time; the block keeps its
               place either way. */
            let plannedTime = session.data.meals
                .first { normalize(slot(for: $0)) == normalize(block.kind) }?
                .time
            return DaylineEntry(
                id: "block-\(block.id)",
                minute: match.map { minute(of: $0.loggedAt) } ?? minute(ofClock: plannedTime ?? block.time),
                slot: block.kind,
                title: match?.displayName ?? language.text(block.label),
                plannedMeal: nil,
                loggedMeal: match
            )
        }

        /* Anything eaten that no block accounts for still belongs on the day. */
        rows.append(
            contentsOf: logged
                .filter { !claimed.contains($0.id) }
                .map { meal in
                    DaylineEntry(
                        id: "logged-\(meal.id)",
                        minute: minute(of: meal.loggedAt),
                        slot: normalize(meal.mealSlot),
                        title: meal.displayName,
                        plannedMeal: nil,
                        loggedMeal: meal
                    )
                }
        )
        return rows.sorted { lineMinute($0.minute) < lineMinute($1.minute) }
    }

    private var visibleEntries: [DaylineEntry] { entries }

    private var currentMinute: Int {
        let components = daylineCalendar.dateComponents([.hour, .minute], from: .now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var currentLineMinute: Int { lineMinute(currentMinute) }

    private var snapMinutes: Int {
        let value = Int(session.data.settings?.addons["meal_timeline_snap_minutes"]?.numberValue ?? 30)
        return [5, 15, 30, 60].contains(value) ? value : 30
    }

    private var timelineHeight: CGFloat {
        if compact { return 560 }
        switch session.data.settings?.addons["meal_dayline_density"]?.stringValue {
        case "compact": return 720
        case "long": return 1_140
        default: return 900
        }
    }

    private var comfortContexts: [DaylineComfortContext] {
        session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .map { meal in
                let window = MealTimingEngine.comfortWindow(for: meal, entries: session.data.loggedFoodEntries)
                return DaylineComfortContext(
                    meal: meal,
                    anchor: MealTimingEngine.ComfortAnchor(
                        startMinute: lineMinute(minute(of: meal.loggedAt)),
                        window: window
                    )
                )
            }
            .sorted { $0.anchor.startMinute < $1.anchor.startMinute }
    }

    private var comfortBands: [MealTimingEngine.ComfortBand] {
        MealTimingEngine.mergedComfortBands(comfortContexts.map(\.anchor))
    }

    private var activeComfortContexts: [DaylineComfortContext] {
        guard daylineCalendar.isDate(date, inSameDayAs: .now) else { return [] }
        return comfortContexts.filter { context in
            context.anchor.startMinute <= currentLineMinute
                && currentLineMinute < context.anchor.startMinute + context.anchor.window.readyAfterMinutes
        }
    }

    private var activeComfortContext: DaylineComfortContext? {
        activeComfortContexts.max { left, right in
            let leftReady = left.anchor.startMinute + left.anchor.window.readyAfterMinutes
            let rightReady = right.anchor.startMinute + right.anchor.window.readyAfterMinutes
            if leftReady == rightReady { return left.anchor.startMinute < right.anchor.startMinute }
            return leftReady < rightReady
        }
    }

    private func comfortLabel(_ load: String) -> String {
        switch load {
        case "large": return language.text("Large meal")
        case "substantial": return language.text("Substantial meal")
        case "standard": return language.text("Standard meal")
        default: return language.text("Light meal")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text("LIVE METABOLIC DAYLINE"))
                        .font(APEXFont.mono(9))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.48, green: 0.74, blue: 0.79))
                    Text(language.text("Meals and training"))
                        .font(APEXFont.display(27))
                        .foregroundStyle(.white)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 2) {
                        Text(clockText(context.date))
                            .font(APEXFont.mono(15))
                            .foregroundStyle(.white)
                        Text(daylineTimeZone.identifier)
                            .font(APEXFont.mono(7))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
            }

            if let context = activeComfortContext {
                let window = context.anchor.window
                let label = comfortLabel(window.load)
                HStack(spacing: 7) {
                    Circle().fill(Color.red.opacity(0.9)).frame(width: 7, height: 7)
                    Text(language.format("%@ settling", label))
                    Image(systemName: "arrow.right")
                    Text(language.format("trade-off at %@", clock(lineClockMinute(context.anchor.startMinute + window.transitionAfterMinutes))))
                    Image(systemName: "arrow.right")
                    Text(language.format("ready at %@", clock(lineClockMinute(context.anchor.startMinute + window.readyAfterMinutes))))
                }
                .font(APEXFont.mono(7))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.055), in: Capsule())
            }

            if visibleEntries.isEmpty {
                Button(action: onAddMeal) {
                    Label(language.text("Add your first meal moment"), systemImage: "plus")
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            } else {
                GeometryReader { proxy in
                    let railX: CGFloat = 56
                    let occupiedClockMinutes = visibleEntries.map { entry in
                        dragPreview[entry.id] ?? entry.minute
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(stride(from: 180, through: 1_620, by: 180)), id: \.self) { minute in
                            let y = yPosition(for: minute, height: timelineHeight)
                            Path { path in
                                path.move(to: CGPoint(x: railX + 12, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                            .stroke(Color.white.opacity(0.035), lineWidth: 1)
                            if DaylineAxisLabels.shouldShow(
                                lineMinute: minute,
                                entryMinutes: occupiedClockMinutes
                            ) {
                                Text(clock(lineClockMinute(minute)))
                                    .font(APEXFont.mono(8))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .position(x: 17, y: y)
                            }
                        }

                        Capsule()
                            .fill(Color(red: 0.18, green: 0.25, blue: 0.31).opacity(0.9))
                            .frame(width: 10, height: timelineHeight)
                            .position(x: railX, y: timelineHeight / 2)

                        readinessBands(railX: railX, height: timelineHeight)

                        if daylineCalendar.isDate(date, inSameDayAs: .now) {
                            let nowY = yPosition(for: currentLineMinute, height: timelineHeight)
                            Path { path in
                                path.move(to: CGPoint(x: railX, y: nowY))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: nowY))
                            }
                            .stroke(Color(red: 0.34, green: 0.88, blue: 0.98).opacity(0.42), lineWidth: 1)
                            Circle()
                                .fill(Color(red: 0.34, green: 0.88, blue: 0.98))
                                .frame(width: 22, height: 22)
                                .shadow(color: Color.cyan.opacity(0.5), radius: 10)
                                .position(x: railX, y: nowY)
                            Text(language.text("NOW"))
                                .font(APEXFont.mono(6))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.13), in: Capsule())
                                .position(x: 18, y: nowY)
                        }

                        let laidOut = separated(visibleEntries, height: timelineHeight)
                        ForEach(visibleEntries) { entry in
                            let y = laidOut[entry.id] ?? yPosition(
                                for: lineMinute(dragPreview[entry.id] ?? entry.minute),
                                height: timelineHeight
                            )
                            DaylineEntryRow(
                                entry: entry,
                                /* The card can be nudged down to clear its
                                   neighbour, but it still states its own time. */
                                displayedMinute: dragPreview[entry.id] ?? entry.minute,
                                isDragging: dragPreview[entry.id] != nil,
                                timelineOriginY: proxy.frame(in: .global).minY,
                                revealOffset: revealOffset(for: entry),
                                action: { open(entry) },
                                /* Absolute Y inside the timeline, so the meal
                                   follows the finger and never chases its own
                                   moving frame. */
                                onDragChanged: { locationY in
                                    let snapped = snap(minuteAt(y: locationY, height: timelineHeight))
                                    dragPreview[entry.id] = lineClockMinute(snapped)
                                },
                                onDragEnded: { locationY in
                                    let snappedLine = snap(minuteAt(y: locationY, height: timelineHeight))
                                    let finalClock = lineClockMinute(snappedLine)
                                    dragPreview[entry.id] = nil
                                    move(entry, to: snappedLine, clockMinute: finalClock)
                                },
                                onSwipeChanged: { beginReveal(entry, translation: $0) },
                                onSwipeEnded: { endReveal(entry, translation: $0) },
                                onDelete: {
                                    guard let logged = entry.loggedMeal else { return }
                                    closeReveal()
                                    Task { await session.deleteLoggedMeal(logged) }
                                }
                            )
                            .frame(width: proxy.size.width)
                            .position(x: proxy.size.width / 2, y: y)
                        }
                    }
                    .coordinateSpace(name: "apex-dayline")
                }
                .frame(height: timelineHeight)

                Text(language.format("Hold and drag a meal to move it in %d-minute steps.", snapMinutes))
                    .font(APEXFont.body(9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
            }

            Button(action: onAddMeal) {
                Label(language.text("Add meal"), systemImage: "plus")
                    .font(APEXFont.body(13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.09, blue: 0.12), Color(red: 0.02, green: 0.13, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 34).stroke(Color.white.opacity(0.12)))
        .shadow(color: APEXColor.teal.opacity(0.18), radius: 24, y: 12)
        .accessibilityIdentifier("nutrition-dayline")
    }

    @ViewBuilder
    private func readinessBands(railX: CGFloat, height: CGFloat) -> some View {
        ForEach(Array(comfortBands.enumerated()), id: \.offset) { indexed in
            let band = indexed.element
            readinessBand(
                from: band.startMinute,
                to: band.endMinute,
                colors: band.zone == .settling
                    ? [Color.red, Color.orange]
                    : [Color.orange, Color.yellow, APEXColor.green],
                railX: railX,
                height: height
            )
        }
    }

    private func readinessBand(
        from start: Int,
        to end: Int,
        colors: [Color],
        railX: CGFloat,
        height: CGFloat
    ) -> some View {
        let startY = yPosition(for: start, height: height)
        let endY = yPosition(for: end, height: height)
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .frame(width: 12, height: max(endY - startY, 2))
            .clipShape(Capsule())
            .shadow(color: colors.last?.opacity(0.45) ?? .clear, radius: 7)
            .position(x: railX, y: startY + max(endY - startY, 2) / 2)
            .allowsHitTesting(false)
    }

    private func open(_ entry: DaylineEntry) {
        if let logged = entry.loggedMeal {
            onOpenComposer(.edit(logged))
        } else {
            onOpenComposer(.create(date: date, slot: entry.slot, name: entry.title))
        }
    }

    private func move(_ entry: DaylineEntry, to lineMinute: Int, clockMinute: Int) {
        Task {
            if let logged = entry.loggedMeal {
                await session.updateLoggedMealFinishedAt(logged.id, to: dateAt(lineMinute: lineMinute))
            } else if let planned = entry.plannedMeal {
                await session.updatePlannedMealTime(planned.id, to: clock(clockMinute))
            }
        }
    }

    private func dateAt(lineMinute: Int) -> Date {
        let start = daylineCalendar.startOfDay(for: date)
        return daylineCalendar.date(byAdding: .minute, value: lineMinute, to: start) ?? date
    }

    private func snap(_ minute: Int) -> Int {
        let clamped = min(max(minute, 180), 1_619)
        return min(max(Int((Double(clamped) / Double(snapMinutes)).rounded()) * snapMinutes, 180), 1_619)
    }

    private func lineMinute(_ minute: Int) -> Int {
        minute < 180 ? minute + 1_440 : minute
    }

    private func lineClockMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }

    /*
     * Two meals an hour apart sit 37pt apart on a 900pt day, and a card is
     * ninety. Placed on the clock alone they overlap, which reads as one meal
     * and hands a tap to whichever card happens to be on top. Each card keeps
     * its time unless the one above it is too close, and then it steps down
     * just far enough to stay its own target.
     */
    private func separated(_ entries: [DaylineEntry], height: CGFloat) -> [String: CGFloat] {
        let minimumGap: CGFloat = 84
        let cardHalf: CGFloat = 38
        var placed: [String: CGFloat] = [:]
        var lastY: CGFloat?
        let ordered = entries.sorted { $0.minute < $1.minute }
        /* Nudging down can only go so far: the last card has to stay on the
           rail rather than spill past its end into the controls below, so each
           card reserves room for the ones still to come. */
        let ceiling = max(cardHalf, height - cardHalf)
        for (index, entry) in ordered.enumerated() {
            let remaining = CGFloat(ordered.count - 1 - index)
            let limit = max(cardHalf, ceiling - remaining * minimumGap)
            let wanted = yPosition(for: lineMinute(dragPreview[entry.id] ?? entry.minute), height: height)
            let stepped = lastY.map { max(wanted, $0 + minimumGap) } ?? wanted
            let y = min(limit, max(cardHalf, stepped))
            placed[entry.id] = y
            lastY = y
        }
        return placed
    }

    private func yPosition(for minute: Int, height: CGFloat) -> CGFloat {
        CGFloat(min(max(minute, 180), 1_620) - 180) / 1_440 * height
    }

    /* Inverse of yPosition: which timeline minute a point on the rail is. */
    private func minuteAt(y: CGFloat, height: CGFloat) -> Int {
        guard height > 0 else { return 180 }
        return Int((y / height * 1_440).rounded()) + 180
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func slot(for meal: Meal) -> String {
        let name = meal.name.lowercased()
        if name.contains("breakfast") { return "breakfast" }
        if name.contains("lunch") { return "lunch" }
        if name.contains("dinner") { return "dinner" }
        if name.contains("post") { return "post_workout" }
        if name.contains("snack") { return "snack" }
        return normalize(meal.name)
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func minute(of value: String) -> Int {
        let date = parsedTimestamp(value)
        let components = daylineCalendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.timeZone = daylineTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parsedTimestamp(_ value: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    private func minute(ofClock value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 12 * 60 }
        return min(max(parts[0], 0), 23) * 60 + min(max(parts[1], 0), 59)
    }
}

private struct DaylineComfortContext {
    let meal: LoggedMeal
    let anchor: MealTimingEngine.ComfortAnchor
}

private struct DaylineEntryRow: View {
    @State private var language = LanguageState.shared
    /* A completed hold-and-drag must not also open the composer on release */
    @State private var dragConsumedTap = false
    /* A finished sideways swipe must not also deliver a tap. The card is a
       Button and the swipe is a simultaneousGesture, so on release SwiftUI
       recognises both: the tap arrived a frame after the reveal opened and
       closed it again, which read as the card refusing to stay open. */
    @State private var swipeConsumedTap = false
    /* Which axis this touch committed to, decided once per gesture so a
       sideways swipe can never also nudge the meal's time. */
    @State private var axisLock: Axis?
    let entry: DaylineEntry
    let displayedMinute: Int
    let isDragging: Bool
    /// Where the timeline starts on screen, so a hold reported in window
    /// coordinates can be read as a position along the rail.
    let timelineOriginY: CGFloat
    /* Owned by the parent so a data refresh cannot discard it mid-swipe */
    let revealOffset: CGFloat
    let action: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onSwipeChanged: (CGFloat) -> Void
    let onSwipeEnded: (CGFloat) -> Void
    let onDelete: () -> Void

    private enum Axis { case horizontal, vertical }

    private let revealWidth: CGFloat = 96

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 3) {
                Text(clock(displayedMinute))
                    .font(APEXFont.mono(10))
                    .foregroundStyle(.white)
                if isDragging {
                    Text(language.text("MOVE"))
                        .font(APEXFont.mono(6))
                        .foregroundStyle(Color.cyan)
                }
            }
            .frame(width: 42)

            ZStack {
                Circle().fill(Color(red: 0.025, green: 0.09, blue: 0.11)).frame(width: 27, height: 27)
                Circle().stroke(entry.isLogged ? APEXColor.green : Color.white.opacity(0.32), lineWidth: 3).frame(width: 23, height: 23)
                Image(systemName: entry.isLogged ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(entry.isLogged ? APEXColor.green : .white.opacity(0.72))
            }
            .zIndex(2)

            ZStack(alignment: .trailing) {
                /* Revealed behind the card by a left swipe, exactly like the web */
                if entry.isLogged {
                    Button {
                        onDelete()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .heavy))
                            Text(language.text("DELETE"))
                                .font(APEXFont.mono(7, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: revealWidth, height: 72)
                        .background(APEXColor.danger, in: RoundedRectangle(cornerRadius: 19))
                    }
                    .buttonStyle(.plain)
                    .opacity(revealOffset < -8 ? 1 : 0)
                    .accessibilityIdentifier("meal-dayline-delete-\(entry.slot)")
                }

                Group {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.text(entry.title))
                                .font(APEXFont.display(16))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .accessibilityIdentifier("meal-dayline-title-\(entry.slot)")
                            if let meal = entry.loggedMeal {
                                Text(language.format("%d kcal · finish recorded", Int(meal.totalKcal.rounded())))
                                    .font(APEXFont.mono(8))
                                    .foregroundStyle(Color(red: 0.65, green: 0.86, blue: 0.84))
                            } else {
                                Text(language.text("Add meal"))
                                    .font(APEXFont.body(10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                        }
                        Spacer()
                        Text(entry.isLogged ? "LOGGED" : "SCHEDULED")
                            .font(APEXFont.mono(7))
                            .foregroundStyle(.white.opacity(0.34))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 15)
                    .frame(height: 72)
                    .background(.white.opacity(entry.isLogged ? 0.095 : 0.045), in: RoundedRectangle(cornerRadius: 19))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(entry.isLogged ? APEXColor.green.opacity(0.26) : Color.white.opacity(0.11), style: StrokeStyle(lineWidth: 1, dash: entry.isLogged ? [] : [5]))
                    )
                }
                .buttonStyle(.plain)
                .offset(x: revealOffset)
            }
        }
        /*
         * The row states its own height before the gesture layer goes on top.
         * A UIViewRepresentable has no intrinsic size and takes whatever it is
         * offered, so without this the overlay stretched each row to the full
         * height of the timeline and the cards disappeared into one another.
         */
        .frame(height: 72)
        .contentShape(Rectangle())
        /*
         * Tap, sideways swipe and hold-to-move live together in UIKit, where a
         * gesture can refuse a touch instead of taking it and then ignoring it.
         * A drag that starts vertical fails outright and the scroll view keeps
         * the finger, so landing on a meal by accident never costs the scroll.
         */
        .overlay(
            MealRowGestures(
                onTap: {
                    guard !dragConsumedTap, !swipeConsumedTap else { return }
                    /* An open card closes on tap instead of opening the editor */
                    if revealOffset != 0 {
                        onSwipeEnded(revealWidth)
                        return
                    }
                    action()
                },
                onSwipeChanged: { translation in
                    guard entry.isLogged else { return }
                    swipeConsumedTap = true
                    onSwipeChanged(translation)
                },
                onSwipeEnded: { translation, velocity in
                    guard entry.isLogged else { return }
                    /* Where the flick was heading, not where the finger stopped. */
                    onSwipeEnded(min(translation, translation + velocity * 0.12))
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(320))
                        swipeConsumedTap = false
                    }
                },
                onHoldChanged: { y in
                    dragConsumedTap = true
                    onDragChanged(y - timelineOriginY)
                },
                onHoldEnded: { y in
                    onDragEnded(y - timelineOriginY)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(280))
                        dragConsumedTap = false
                    }
                }
            )
        )
        /* Contained rather than combined: combining turns the row into a single
           accessibility element whose activation bypasses the touch layer the
           gestures live in, so a tap would stop opening the meal. */
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal-dayline-\(entry.slot)")
        .accessibilityLabel(Text(language.text(entry.title)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(language.text("Open"))) { action() }
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct MealSlotPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date
    let onSelect: (MealComposerRequest) -> Void

    @State private var customName = ""
    @State private var customTime = Date()

    private let slots: [MealSlotChoice] = [
        MealSlotChoice(name: "Breakfast", slot: "breakfast", time: "07:00"),
        MealSlotChoice(name: "Lunch", slot: "lunch", time: "13:00"),
        MealSlotChoice(name: "Dinner", slot: "dinner", time: "19:00"),
        MealSlotChoice(name: "Snack", slot: "snack", time: "16:00"),
        MealSlotChoice(name: "Post-workout", slot: "post_workout", time: "21:00")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 11) {
                    ForEach(slots) { slot in
                        Button {
                            onSelect(.create(date: date, slot: slot.slot, name: slot.name))
                            dismiss()
                        } label: {
                            HStack {
                                Text(language.text(slot.name))
                                    .font(APEXFont.display(19))
                                Spacer()
                                Text(slot.time)
                                    .font(APEXFont.mono(11))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            .foregroundStyle(APEXColor.ink)
                            .padding(17)
                            .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }

                    GlassCard(radius: 24, padding: 17) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(language.text("Create a custom meal"))
                                .font(APEXFont.display(19))
                            TextField(language.text("Meal name"), text: $customName)
                                .textFieldStyle(.roundedBorder)
                            DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
                            Button(language.text("Create meal")) {
                                let clean = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let slot = clean.isEmpty ? "custom" : clean.lowercased().replacingOccurrences(of: " ", with: "_")
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: customTime)
                                let finishedAt = Calendar.current.date(
                                    bySettingHour: parts.hour ?? 12,
                                    minute: parts.minute ?? 0,
                                    second: 0,
                                    of: date
                                )
                                onSelect(.create(
                                    date: date,
                                    slot: slot,
                                    name: clean.isEmpty ? "Custom meal" : clean,
                                    finishedAt: finishedAt
                                ))
                                dismiss()
                            }
                            .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                        }
                    }
                }
                .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Add meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("Close")) { dismiss() } }
            }
        }
    }
}

private struct MealSlotChoice: Identifiable {
    let name: String
    let slot: String
    let time: String
    var id: String { slot }
}

struct NutritionCalendarSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var month: Date
    @State private var copiedSource: Date?
    @State private var workflow: NutritionCalendarWorkflow?
    @State private var selectedMealIDs = Set<UUID>()
    @State private var isWorking = false
    @State private var errorMessage: String?

    let selectedDate: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate)
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var output = Array<Date?>(repeating: nil, count: leading)
        for day in range {
            output.append(calendar.date(byAdding: .day, value: day - 1, to: interval.start))
        }
        while output.count % 7 != 0 { output.append(nil) }
        return output
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 20) {
                    HStack {
                        Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(CalendarArrowStyle())
                        Spacer()
                        VStack(spacing: 4) {
                            Text(month.formatted(.dateTime.month(.wide).year().locale(language.language.locale)))
                                .font(APEXFont.display(22))
                            if copiedSource == nil {
                                Button(language.text("Jump to today")) {
                                    month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
                                    onSelect(.now)
                                    dismiss()
                                }
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.violet)
                            } else {
                                Text(language.text("CHOOSE WHERE TO PASTE"))
                                    .font(APEXFont.mono(9))
                                    .tracking(1.15)
                                    .foregroundStyle(APEXColor.cyan)
                            }
                        }
                        Spacer()
                        Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(CalendarArrowStyle())
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                        /* Keyed by position, not by the letter: Tuesday and
                           Thursday are both "T", and identical ids made one of
                           them disappear from the header. */
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            if let date = cell {
                                calendarCell(date)
                            } else {
                                Color.clear.frame(height: 48)
                            }
                        }
                    }

                    if let copiedSource {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                            Text(language.format(
                                "Copied %@. Tap a different day to continue.",
                                copiedSource.formatted(.dateTime.day().month(.abbreviated).locale(language.language.locale))
                            ))
                            Spacer()
                            Button(language.text("Cancel")) { self.copiedSource = nil }
                                .font(APEXFont.body(10, weight: .bold))
                        }
                        .font(APEXFont.body(10, weight: .semibold))
                        .foregroundStyle(APEXColor.cyan)
                        .padding(12)
                        .background(APEXColor.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        Text(language.text("Tap to open a day. Hold any day to copy or clear its meals and snacks."))
                            .font(APEXFont.body(11, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(20)

                if workflow != nil {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture { workflow = nil }
                    workflowOverlay
                        .padding(18)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .background(APEXBackground())
            /* No navigation title: the month name is the heading, and an inline
               bar title lands straight on top of it in a sheet this short. */
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.text("Close")) { dismiss() } } }
            .animation(.snappy, value: workflow)
            .alert("Calendar action failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(language.text("OK"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func calendarCell(_ date: Date) -> some View {
        let dayState = APEXDateMath.calendarDayState(
            date: date.apexDateKey,
            selectedDate: selectedDate.apexDateKey,
            today: Date.now.apexDateKey
        )
        let selected = dayState.isSelected
        let source = copiedSource.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let choosingDestination = copiedSource != nil && !source
        return VStack(spacing: 4) {
            ZStack {
                if dayState.isToday {
                    Circle()
                        .stroke(selected || source ? .white.opacity(0.9) : APEXColor.violet, lineWidth: 2)
                }
                Text("\(calendar.component(.day, from: date))")
                    .font(APEXFont.mono(12))
            }
            .frame(width: 28, height: 28)
            Circle()
                .fill(hasEvidence(on: date) ? APEXColor.green : Color.clear)
                .frame(width: 5, height: 5)
        }
        .foregroundStyle((selected || source) ? .white : APEXColor.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            source ? APEXColor.cyan : selected ? APEXColor.violet : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            if choosingDestination {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(APEXColor.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if let copiedSource, !source {
                workflow = .paste(source: copiedSource, destination: date)
            } else if copiedSource == nil {
                onSelect(date)
                dismiss()
            }
        }
        .onLongPressGesture(minimumDuration: 0.42) {
            copiedSource = nil
            workflow = .actions(date)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(
            dayState.isToday
                ? "\(date.formatted(date: .long, time: .omitted)), \(language.text("Today"))"
                : date.formatted(date: .long, time: .omitted)
        )
        .accessibilityIdentifier(dayState.isToday ? "nutrition-calendar-today" : "nutrition-calendar-day-\(date.apexDateKey)")
    }

    @ViewBuilder
    private var workflowOverlay: some View {
        if let workflow {
            switch workflow {
            case .actions(let date):
                calendarActionCard(date)
            case .paste(let source, let destination):
                pasteChoiceCard(source: source, destination: destination)
            case .select(let source, let destination):
                selectMealsCard(source: source, destination: destination)
            }
        }
    }

    private func calendarActionCard(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(language.language.locale)))
                        .font(APEXFont.display(23))
                    Text(language.text("Copy or clear this day’s meals and snacks."))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                closeWorkflowButton
            }
            Button {
                copiedSource = date
                workflow = nil
            } label: {
                Label(language.text("Copy"), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CalendarWorkflowButtonStyle(color: APEXColor.cyan))
            Button(role: .destructive) {
                isWorking = true
                Task {
                    await session.clearNutritionDay(date)
                    isWorking = false
                    workflow = nil
                }
            } label: {
                Label(isWorking ? "Clearing…" : "Clear", systemImage: "xmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CalendarWorkflowButtonStyle(color: Color(red: 0.87, green: 0.3, blue: 0.55)))
            .disabled(isWorking)
        }
        .calendarWorkflowCard()
    }

    private func pasteChoiceCard(source: Date, destination: Date) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Paste copied day"))
                        .font(APEXFont.display(23))
                    Text("\(shortDate(source)) → \(shortDate(destination))")
                        .font(APEXFont.body(13, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                closeWorkflowButton
            }
            Button {
                pasteDay(source: source, destination: destination, mealIDs: nil)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("Paste")).font(APEXFont.display(18))
                    Text(language.text("All meals and snacks")).font(APEXFont.body(11, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CalendarWorkflowButtonStyle(color: APEXColor.cyan, filled: true))
            .disabled(isWorking)

            Button {
                selectedMealIDs = []
                workflow = .select(source: source, destination: destination)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("Select")).font(APEXFont.display(18))
                    Text(language.text("Choose individual meals or snacks")).font(APEXFont.body(11, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CalendarWorkflowButtonStyle(color: APEXColor.violet))
        }
        .calendarWorkflowCard()
    }

    private func selectMealsCard(source: Date, destination: Date) -> some View {
        let meals = sourceMeals(on: source)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("Choose meals"))
                        .font(APEXFont.display(23))
                    Text("\(shortDate(source)) → \(shortDate(destination))")
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                closeWorkflowButton
            }
            if meals.isEmpty {
                Text(language.text("No structured meals are available to copy from this day."))
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(meals) { meal in
                            Button {
                                if selectedMealIDs.contains(meal.id) {
                                    selectedMealIDs.remove(meal.id)
                                } else {
                                    selectedMealIDs.insert(meal.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedMealIDs.contains(meal.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 23, weight: .semibold))
                                        .foregroundStyle(selectedMealIDs.contains(meal.id) ? APEXColor.amber : APEXColor.secondaryInk.opacity(0.45))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meal.displayName)
                                            .font(APEXFont.display(16))
                                        Text(language.format("%d kcal", Int(meal.totalKcal.rounded())))
                                            .font(APEXFont.mono(9))
                                            .foregroundStyle(APEXColor.secondaryInk)
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(APEXColor.ink)
                                .padding(12)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 17))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 290)

                Button {
                    pasteDay(source: source, destination: destination, mealIDs: selectedMealIDs)
                } label: {
                    Text(language.format("Paste %d selected", selectedMealIDs.count))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CalendarWorkflowButtonStyle(color: APEXColor.amber, filled: true))
                .disabled(selectedMealIDs.isEmpty || isWorking)
            }
        }
        .calendarWorkflowCard()
    }

    private var closeWorkflowButton: some View {
        Button { workflow = nil } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .black))
                .frame(width: 42, height: 42)
                .background(APEXColor.ink.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func pasteDay(source: Date, destination: Date, mealIDs: Set<UUID>?) {
        isWorking = true
        Task {
            do {
                try await session.copyNutritionDay(from: source, to: destination, mealIDs: mealIDs)
                onSelect(destination)
                copiedSource = nil
                workflow = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func sourceMeals(on date: Date) -> [LoggedMeal] {
        session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(language.language.locale))
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return Array(symbols.dropFirst()) + [symbols.first ?? "S"]
    }

    private func hasEvidence(on date: Date) -> Bool {
        let key = date.apexDateKey
        return session.data.loggedMeals.contains { $0.localDate == key }
            || session.data.dailyLogs.contains { $0.date == key }
            || session.data.supplementLogs.contains { $0.date == key }
            || session.data.activityLogs.contains { $0.date == key }
            || session.data.workoutSessions.contains { $0.date == key }
    }

    private func changeMonth(_ value: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: value, to: month) ?? month
        }
    }
}

private enum NutritionCalendarWorkflow: Equatable {
    case actions(Date)
    case paste(source: Date, destination: Date)
    case select(source: Date, destination: Date)
}

private struct CalendarWorkflowButtonStyle: ButtonStyle {
    let color: Color
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(APEXFont.body(15, weight: .bold))
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 17)
            .frame(minHeight: 58)
            .background(
                filled ? color.opacity(configuration.isPressed ? 0.72 : 1) : color.opacity(configuration.isPressed ? 0.13 : 0.075),
                in: RoundedRectangle(cornerRadius: 20)
            )
    }
}

private extension View {
    func calendarWorkflowCard() -> some View {
        self
            .padding(20)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.8)))
            .shadow(color: APEXColor.ink.opacity(0.18), radius: 25, y: 13)
    }
}

private struct CalendarArrowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(APEXColor.secondaryInk)
            .frame(width: 48, height: 48)
            .background(.white.opacity(configuration.isPressed ? 0.42 : 0.7), in: Circle())
    }
}

struct LoggedMealsCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let date: Date
    let onAdd: () -> Void
    let onEdit: (LoggedMeal) -> Void

    private var meals: [LoggedMeal] {
        session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    var body: some View {
        GlassCard(radius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("Meals"))
                            .font(APEXFont.display(25))
                        Text(language.text("Tap a logged meal to see or change what you ate."))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 46, height: 46)
                            .background(APEXColor.amber.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if meals.isEmpty {
                    Text(language.text("No meals logged for this date."))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .padding(.vertical, 8)
                } else {
                    ForEach(meals) { meal in
                        Button { onEdit(meal) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(APEXColor.amberDeep)
                                    .frame(width: 38, height: 38)
                                    .background(APEXColor.amber.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(meal.displayName)
                                        .font(APEXFont.display(16))
                                        .foregroundStyle(APEXColor.ink)
                                    Text(language.format(
                                        "%d kcal · P %.0f · C %.0f · F %.0f",
                                        Int(meal.totalKcal.rounded()), meal.totalProteinG,
                                        meal.totalCarbsG, meal.totalFatG
                                    ))
                                    .font(APEXFont.mono(8))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            .padding(12)
                            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(language.text("Delete meal"), role: .destructive) {
                                Task { await session.deleteLoggedMeal(meal) }
                            }
                        }
                    }
                }

                Button(action: onAdd) {
                    Label(language.text("Add meal"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(APEXColor.amberDeep)
            }
        }
    }
}
