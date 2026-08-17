import SwiftUI

/// The native equivalent of the web "Nutrition at a glance" card. All values
/// come from the selected user's structured Supabase meal rows, with the daily
/// log used only as the backward-compatible fallback for older/manual days.
struct NutritionGlanceCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    let date: Date
    let targets: NutritionTargets
    let onEditTargets: () -> Void
    var onOpenCalendar: (() -> Void)?

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

    private var remaining: Int {
        max(0, targets.targetCalories - Int(totals.kcal.rounded()))
    }

    private var configuredMealCount: Int {
        max(session.data.meals.count, 1)
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
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(APEXColor.amberDeep)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(APEXColor.ink)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(language.text("Private").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(9))
                            .tracking(1.2)
                            .foregroundStyle(APEXColor.amberDeep)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .overlay(Capsule().stroke(APEXColor.amber.opacity(0.45)))
                        Button {
                            onOpenCalendar?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                Text(date.formatted(.dateTime.day().month(.abbreviated).locale(language.language.locale)))
                            }
                            .font(APEXFont.mono(9))
                            .foregroundStyle(APEXColor.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 15) {
                    VStack(spacing: 3) {
                        Text("\(Int(totals.kcal.rounded()))")
                            .font(APEXFont.display(32))
                            .contentTransition(.numericText())
                        Text(language.text("Eaten").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: onEditTargets) {
                        ZStack {
                            Circle()
                                .stroke(APEXColor.ink.opacity(0.07), lineWidth: 15)
                            Circle()
                                .trim(from: 0, to: max(calorieProgress, 0.012))
                                .stroke(
                                    AngularGradient(
                                        colors: [APEXColor.amber, APEXColor.cyan, APEXColor.amber],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.snappy, value: calorieProgress)
                            VStack(spacing: 2) {
                                Text(language.text("Remaining"))
                                    .font(APEXFont.body(10, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                Text("\(remaining)")
                                    .font(APEXFont.display(34))
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
                        Text("\(meals.count)/\(configuredMealCount)")
                            .font(APEXFont.display(29))
                        Text(language.text("Meals").uppercased(with: language.language.locale))
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

struct NutritionTargetSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    let date: Date

    private var logs: [ActivityLog] {
        session.data.activityLogs.filter { $0.date == date.apexDateKey }
    }

    private var targets: NutritionTargets? {
        guard let profile = session.profile else { return nil }
        return EnergyEngine.targets(profile: profile, logs: logs, catalog: session.data.activityTypes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let targets {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(targets.targetCalories)")
                                .font(APEXFont.display(44))
                                .contentTransition(.numericText())
                            Text("kcal")
                                .font(APEXFont.body(15, weight: .bold))
                                .foregroundStyle(APEXColor.secondaryInk)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(language.text(session.profile?.goal.title ?? "Goal"))
                                Text(language.text(targets.level.title))
                            }
                            .font(APEXFont.mono(10))
                            .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }

                    targetGroup(title: "GOAL") {
                        HStack(spacing: 8) {
                            ForEach(Goal.allCases, id: \.self) { goal in
                                Button(language.text(goal.title)) {
                                    Task { await session.setGoal(goal) }
                                }
                                .buttonStyle(TargetChoiceStyle(selected: session.profile?.goal == goal, color: APEXColor.amber))
                            }
                        }
                    }

                    targetGroup(title: "ACTIVITY LEVEL") {
                        VStack(alignment: .leading, spacing: 11) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                                ForEach(ActivityLevel.allCases, id: \.self) { level in
                                    Button(language.text(level.title)) {
                                        guard logs.isEmpty else { return }
                                        Task { await session.setActivityLevel(level) }
                                    }
                                    .buttonStyle(TargetChoiceStyle(
                                        selected: session.profile?.activityLevel == level && logs.isEmpty,
                                        color: APEXColor.cyan
                                    ))
                                    .disabled(!logs.isEmpty)
                                }
                            }
                            if !logs.isEmpty {
                                Label("Computed from your day. Clear every activity block to return to Quick Mode.", systemImage: "sparkles")
                                    .font(APEXFont.body(11, weight: .semibold))
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
                .padding(20)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Daily calorie target"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(APEXFont.body(14, weight: .bold))
                }
            }
        }
    }

    private func targetGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(radius: 27, padding: 17) {
            VStack(alignment: .leading, spacing: 13) {
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
            .frame(height: 52)
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

/// A native, scroll-efficient version of the web metabolic Dayline. It keeps
/// planned meal moments and actual finish times distinct and opens the same
/// structured meal editor from either state.
struct APEXDaylineView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    let date: Date
    let onOpenComposer: (MealComposerRequest) -> Void
    let onAddMeal: () -> Void
    var compact = false

    private var daylineTimeZone: TimeZone {
        let identifier = session.data.settings?.addons["time_zone"]?.stringValue
        return identifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    private var daylineCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = daylineTimeZone
        return calendar
    }

    private var entries: [DaylineEntry] {
        let planned = session.data.meals.sorted { $0.sortOrder < $1.sortOrder }
        let logged = session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .sorted { parsedTimestamp($0.loggedAt) < parsedTimestamp($1.loggedAt) }
        var claimed: Set<UUID> = []
        var rows: [DaylineEntry] = planned.map { meal in
            let slot = slot(for: meal)
            let match = logged.first { candidate in
                if let source = candidate.sourcePlannedMealID, source == meal.id { return true }
                return normalize(candidate.mealSlot) == normalize(slot) && !claimed.contains(candidate.id)
            }
            if let match { claimed.insert(match.id) }
            return DaylineEntry(
                id: "planned-\(meal.id)",
                minute: match.map { minute(of: $0.loggedAt) } ?? minute(ofClock: meal.time),
                slot: slot,
                title: match?.displayName ?? meal.name,
                plannedMeal: meal,
                loggedMeal: match
            )
        }
        rows.append(contentsOf: logged.filter { !claimed.contains($0.id) }.map { meal in
            DaylineEntry(
                id: "logged-\(meal.id)",
                minute: minute(of: meal.loggedAt),
                slot: meal.mealSlot,
                title: meal.displayName,
                plannedMeal: nil,
                loggedMeal: meal
            )
        })
        return rows.sorted {
            if $0.minute == $1.minute { return $0.title < $1.title }
            return $0.minute < $1.minute
        }
    }

    private var visibleEntries: [DaylineEntry] {
        guard compact, entries.count > 4 else { return entries }
        let now = currentMinute
        let completed = entries.filter { $0.isLogged }.suffix(1)
        let upcoming = entries.filter { !$0.isLogged && $0.minute >= now }.prefix(3)
        let combined = Array(completed) + Array(upcoming)
        return combined.isEmpty ? Array(entries.prefix(4)) : Array(Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0) }).values).sorted { $0.minute < $1.minute }
    }

    private var currentMinute: Int {
        let components = daylineCalendar.dateComponents([.hour, .minute], from: .now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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

            if visibleEntries.isEmpty {
                Button(action: onAddMeal) {
                    Label("Add your first meal moment", systemImage: "plus")
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        let priorMinute = index > 0 ? visibleEntries[index - 1].minute : max(180, entry.minute - 120)
                        if index > 0 {
                            Color.clear.frame(height: gapHeight(from: priorMinute, to: entry.minute))
                        }
                        DaylineEntryRow(
                            entry: entry,
                            isNow: isNow(entry, at: index),
                            isLast: index == visibleEntries.count - 1
                        ) {
                            if let logged = entry.loggedMeal {
                                onOpenComposer(.edit(logged))
                            } else {
                                onOpenComposer(.create(date: date, slot: entry.slot, name: entry.title))
                            }
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.34, blue: 0.38), APEXColor.green, Color(red: 0.22, green: 0.28, blue: 0.38)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 6)
                    .clipShape(Capsule())
                    .padding(.leading, 52)
                    .padding(.vertical, 22)
                    .allowsHitTesting(false)
                }
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

    private func isNow(_ entry: DaylineEntry, at index: Int) -> Bool {
        guard daylineCalendar.isDate(date, inSameDayAs: .now) else { return false }
        let next = visibleEntries.indices.contains(index + 1) ? visibleEntries[index + 1].minute : 1_440
        return currentMinute >= entry.minute && currentMinute < next
    }

    private func gapHeight(from: Int, to: Int) -> CGFloat {
        guard !compact else { return 12 }
        return min(max(CGFloat(to - from) * 0.12, 14), 82)
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

private struct DaylineEntryRow: View {
    @State private var language = LanguageState.shared
    let entry: DaylineEntry
    let isNow: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 3) {
                Text(clock(entry.minute))
                    .font(APEXFont.mono(10))
                    .foregroundStyle(.white)
                if isNow {
                    Text(language.text("NOW"))
                        .font(APEXFont.mono(6))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12), in: Capsule())
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

            Button(action: action) {
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
            .accessibilityIdentifier("meal-dayline-\(entry.slot)")
        }
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
                            Text("Create a custom meal")
                                .font(APEXFont.display(19))
                            TextField("Meal name", text: $customName)
                                .textFieldStyle(.roundedBorder)
                            DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
                            Button("Create meal") {
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
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
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
            VStack(spacing: 20) {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(CalendarArrowStyle())
                    Spacer()
                    VStack(spacing: 4) {
                        Text(month.formatted(.dateTime.month(.wide).year().locale(language.language.locale)))
                            .font(APEXFont.display(22))
                        Button("Jump to today") {
                            month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
                            onSelect(.now)
                            dismiss()
                        }
                        .font(APEXFont.mono(9))
                        .foregroundStyle(APEXColor.violet)
                    }
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(CalendarArrowStyle())
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(APEXFont.mono(9))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        if let date = cell {
                            let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                            Button {
                                onSelect(date)
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(APEXFont.mono(12))
                                    Circle()
                                        .fill(hasEvidence(on: date) ? APEXColor.green : Color.clear)
                                        .frame(width: 5, height: 5)
                                }
                                .foregroundStyle(selected ? .white : APEXColor.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(selected ? APEXColor.violet : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }

                Text("Dots mark dates with meals, water, supplements, workouts, or activity evidence.")
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(20)
            .background(APEXBackground())
            .navigationTitle(language.text("Calendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
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
                            Button("Delete meal", role: .destructive) {
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
