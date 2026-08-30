import SwiftUI

struct NutritionView: View {
    @Environment(AppSession.self) private var session
    @State private var selectedDate = Date()
    @State private var showAddActivity = false
    @State private var showActivityGuide = false
    @State private var showTargetEditor = false
    @State private var showCalendar = false
    @State private var showMealSlotPicker = false
    @State private var composerRequest: MealComposerRequest?
    @State private var language = LanguageState.shared

    private var dayKey: String { selectedDate.apexDateKey }
    private var dayActivities: [ActivityLog] {
        session.data.activityLogs
            .filter { $0.date == dayKey }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var targets: NutritionTargets? {
        guard let profile = session.profile else { return nil }
        return EnergyEngine.targets(
            profile: profile,
            logs: dayActivities,
            catalog: session.data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: session.data.settings),
            settings: session.data.settings,
            wearableActiveCalories: WearableActivityRecord.activeCalories(
                on: dayKey,
                settings: session.data.settings,
                ownerID: profile.userID
            )
        )
    }

    private var goalLabel: String {
        guard let goal = session.profile?.goal else { return "Goal" }
        return NutritionGoalPolicy.preset(
            for: goal,
            context: NutritionGoalPolicy.context(from: session.data.settings)
        ).label
    }

    /* Mirrors the web's collapsed supplement row: "3/7 · 17 Aug" */
    private var supplementSummary: String {
        let total = session.activeSupplements.count
        let done = session.data.supplementLogs.filter { $0.date == dayKey }.count
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(min(done, total))/\(total) · \(formatter.string(from: selectedDate))"
    }

    var body: some View {
        VStack(spacing: 8) {
            nutritionHeader
                .padding(.horizontal, 18)
                .padding(.top, 10)

            /* The web renders its top bar once for every page, so the mode
               switch is reachable from nutrition too. Native only had it on
               the two portal screens. */
            HStack {
                PortalModeSwitcher()
                Spacer()
            }
            .padding(.horizontal, 18)

            APEXDateNavigator(
                date: selectedDate,
                onPrevious: { changeDate(-1) },
                onNext: { changeDate(1) },
                onOpenCalendar: { showCalendar = true }
            )
            .padding(.horizontal, 18)

            ScrollView {
                /* Not lazy: the 900pt Dayline is taller than the viewport, and
                   a lazy stack never materialised what follows it, so the page
                   stopped scrolling at the timeline and the sections below were
                   unreachable. The page holds a handful of cards, so building
                   them all costs nothing. */
                VStack(spacing: 22) {
                    if let targets {
                        NutritionGlanceCard(
                            date: selectedDate,
                            targets: targets,
                            onEditTargets: { showTargetEditor = true },
                            onOpenCalendar: { showCalendar = true }
                        )
                    }
                    /*
                     * Web parity: only what you act on every day stays open.
                     * Reference and configuration sit behind a disclosure the
                     * way the web page does, which is why the web fits this
                     * page in four screens where the native build needed nine.
                     */
                    if let targets {
                        APEXDaylineView(
                            date: selectedDate,
                            onOpenComposer: { composerRequest = $0 },
                            onAddMeal: { showMealSlotPicker = true },
                            compact: false
                        )

                        CollapsibleSection(
                            id: "activities",
                            title: language.text("Activity & nutrition targets"),
                            subtitle: language.format(
                                "%d kcal · %@ · %@",
                                targets.targetCalories,
                                language.text(targets.level.title),
                                language.text(goalLabel)
                            )
                        ) {
                            VStack(spacing: 18) {
                                TodaysActivitiesPanel(
                                    date: selectedDate,
                                    logs: dayActivities,
                                    targets: targets,
                                    onAdd: { showAddActivity = true },
                                    onGuide: { showActivityGuide = true }
                                )
                                DailyTargetsCard(targets: targets, precise: !dayActivities.isEmpty)
                            }
                        }

                        CollapsibleSection(
                            id: "supplements",
                            title: language.text("Supplement stack"),
                            subtitle: supplementSummary
                        ) {
                            SupplementStackEditor(date: selectedDate, showsHeader: false)
                        }

                        DailyLogCard(
                            date: selectedDate,
                            targets: targets,
                            onAdjustActivities: { showAddActivity = true }
                        )

                        CollapsibleSection(
                            id: "assessment",
                            title: language.text("APEX assessment"),
                            subtitle: language.text("Today's energy model and the clearest gap.")
                        ) {
                            BodyAssessmentCard(targets: targets, date: selectedDate)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 28)
.dockClearance()
            }
            .refreshable { await session.refresh() }
        }
        .apexEdgeDateSwipe(onPrevious: { changeDate(-1) }, onNext: { changeDate(1) })
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddActivity) {
            AddActivitySheet(date: selectedDate)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showActivityGuide) {
            ActivityGuideSheet()
                .apexTransientSheet()
                .presentationDragIndicator(.visible)
        }
        .apexPopover(isPresented: $showTargetEditor) {
            NutritionTargetSheet(date: selectedDate, onClose: { showTargetEditor = false })
                .environment(session)
        }
        .sheet(isPresented: $showCalendar) {
            NutritionCalendarSheet(selectedDate: selectedDate) { selectedDate = $0 }
                /* A month grid is six rows tall, so opening at full height left
                   the bottom third empty. */
                .apexTransientSheet(.fraction(0.74))
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMealSlotPicker) {
            MealSlotPickerSheet(date: selectedDate) { composerRequest = $0 }
                .apexTransientSheet()
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $composerRequest) { request in
            MealComposerView(request: request)
        }
        .task(id: dayKey) {
            await session.prefillEventActivitiesIfNeeded(for: selectedDate)
        }
    }

    private func changeDate(_ offset: Int) {
        withAnimation(.snappy) {
            selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var nutritionHeader: some View {
        APEXTopBar(profile: session.profile) {
            session.navigationPath.append(.settings)
        }
    }

}

private struct TodaysActivitiesPanel: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let date: Date
    let logs: [ActivityLog]
    let targets: NutritionTargets?
    let onAdd: () -> Void
    let onGuide: () -> Void

    private var resolvedActivity: WearableActivityEngine.Resolution {
        let wearable = WearableActivityRecord
            .history(from: session.data.settings?.addons["watch_activity_history"])
            .last { $0.date == date.apexDateKey }
        return WearableActivityEngine.resolve(
            persona: session.profile?.persona ?? .constantine,
            wearable: wearable,
            logs: logs
        )
    }

    private var catalog: [String: ActivityType] {
        Dictionary(uniqueKeysWithValues: session.data.activityTypes.map { ($0.id, $0) })
    }

    var body: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language.text("Today's Activities"))
                            .font(APEXFont.display(25))
                        Text(language.text(logs.isEmpty ? "Quick mode" : "Precise mode · computed from your day"))
                            .font(APEXFont.body(13, weight: .semibold))
                            .foregroundStyle(logs.isEmpty ? APEXColor.secondaryInk : APEXColor.amberDeep)
                    }
                    Spacer()
                    Button(action: onGuide) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }

                if let targets {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(resolvedActivity.activeCalories)")
                                .font(APEXFont.display(44))
                                .contentTransition(.numericText())
                            Text(language.text("NET ACTIVITY KCAL"))
                                .font(APEXFont.mono(9))
                                .tracking(1.4)
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(language.text(targets.level.title).uppercased(with: language.language.locale))
                                .font(APEXFont.mono(11))
                                .tracking(1.1)
                                .foregroundStyle(APEXColor.amberDeep)
                            Text(language.format("PAL %.2f · %d kcal day", targets.pal, targets.tdee))
                                .font(APEXFont.body(12, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .padding(16)
                    .background(APEXColor.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if !logs.isEmpty {
                    VStack(spacing: 9) {
                        ForEach(logs) { log in
                            HStack(spacing: 11) {
                                Image(systemName: systemIcon(catalog[log.typeID]?.icon ?? "figure.walk"))
                                    .foregroundStyle(APEXColor.amberDeep)
                                    .frame(width: 32, height: 32)
                                    .background(APEXColor.amber.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.text(catalog[log.typeID]?.name ?? "Activity"))
                                        .font(APEXFont.body(14, weight: .bold))
                                    Text(detail(log))
                                        .font(APEXFont.body(11, weight: .medium))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                                Spacer()
                                Text(language.format("%d kcal", Int(log.computedKcal.rounded())))
                                    .font(APEXFont.mono(11))
                                Button(role: .destructive) {
                                    Task { await session.removeActivity(log) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(APEXColor.secondaryInk.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }

                CompletedWorkoutHistoryCards(
                    date: date.apexDateKey,
                    accent: APEXColor.amber
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(frequentTypes.prefix(5)) { type in
                            Button {
                                Task {
                                    await session.addActivity(
                                        type: type,
                                        date: date,
                                        durationMinutes: type.defaultDurationMinutes
                                    )
                                }
                            } label: {
                                Label(language.text(type.name), systemImage: systemIcon(type.icon))
                                    .font(APEXFont.body(12, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 13)
                                    .frame(height: 40)
                                    .background(.white.opacity(0.66), in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.9)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: onAdd) {
                    Label(language.text("Add activity block"), systemImage: "plus")
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))

                HStack(spacing: 10) {
                    if logs.isEmpty, yesterdayLogs.isEmpty == false {
                        Button {
                            Task { await session.repeatYesterday(onto: date) }
                        } label: {
                            Label(language.text("Repeat yesterday"), systemImage: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    if logs.isEmpty == false {
                        Button(role: .destructive) {
                            Task { await session.clearActivities(on: date) }
                        } label: {
                            Label(language.text("Clear day"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var yesterdayLogs: [ActivityLog] {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return [] }
        return session.data.activityLogs.filter { $0.date == yesterday.apexDateKey }
    }

    private var frequentTypes: [ActivityType] {
        let counts = Dictionary(grouping: session.data.activityLogs, by: \.typeID).mapValues(\.count)
        return session.data.activityTypes.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    private func detail(_ log: ActivityLog) -> String {
        if let distance = log.distanceKM { return language.format("%.1f km", distance) }
        if let duration = log.durationMinutes {
            return log.quantity > 1
                ? language.format("%d min × %d", duration, Int(log.quantity))
                : language.format("%d min", duration)
        }
        if log.typeID == "incidental-steps" { return language.format("%d steps", Int(log.quantity)) }
        return language.format("× %d", Int(log.quantity))
    }
}

private struct DailyTargetsCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let targets: NutritionTargets
    let precise: Bool

    private var activeGoalLabel: String {
        guard let goal = session.profile?.goal else { return "Goal" }
        return NutritionGoalPolicy.preset(
            for: goal,
            context: NutritionGoalPolicy.context(from: session.data.settings)
        ).label
    }

    var body: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(language.text("Daily targets"))
                        .font(APEXFont.display(27))
                    Spacer()
                    Text(language.text(activeGoalLabel).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(10))
                        .tracking(1.2)
                        .foregroundStyle(APEXColor.amberDeep)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(APEXColor.amber.opacity(0.1), in: Capsule())
                }

                Grid(horizontalSpacing: 25, verticalSpacing: 20) {
                    GridRow {
                        targetMetric("CALORIES", "\(targets.targetCalories)", APEXColor.amberDeep)
                        targetMetric("PROTEIN", language.format("%d g", targets.proteinG), APEXColor.ink)
                    }
                    GridRow {
                        targetMetric("FAT", language.format("%d g", targets.fatG), APEXColor.ink)
                        targetMetric("CARBS", language.format("%d g", targets.carbsG), APEXColor.ink)
                    }
                }

                Divider().opacity(0.55)

                HStack(spacing: 18) {
                    Text(language.format("BMR: %d", targets.bmr))
                    Text(language.format("TDEE: %d", targets.tdee))
                }
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)

                if !precise {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language.text("QUICK MODE"))
                            .font(APEXFont.mono(9))
                            .tracking(1.5)
                            .foregroundStyle(APEXColor.secondaryInk)
                        FlowLayout(spacing: 8) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                Button(language.text(level.title)) {
                                    Task { await session.setActivityLevel(level) }
                                }
                                .buttonStyle(ChoicePillStyle(selected: session.profile?.activityLevel == level))
                            }
                        }
                    }
                } else {
                    Label(language.text("Activity levels are computed from today's blocks"), systemImage: "sparkles")
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                NutritionGoalPresetPicker(
                    presets: NutritionGoalPolicy.presets(
                        context: NutritionGoalPolicy.context(from: session.data.settings)
                    ),
                    selected: session.profile?.goal,
                    onSelect: { goal in Task { await session.setGoal(goal) } }
                )

                if targets.safetyFloorApplied {
                    Label(language.text("Target held above the recovery safety floor"), systemImage: "shield.lefthalf.filled")
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.green)
                }
            }
        }
    }

    private func targetMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(label))
                .font(APEXFont.mono(10))
                .foregroundStyle(APEXColor.secondaryInk)
            Text(value)
                .font(APEXFont.display(36))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealTimeline: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let date: Date
    let targets: NutritionTargets

    private var plan: [AdaptiveMeal] {
        AdaptiveMealPlanEngine.build(
            meals: session.data.meals,
            targets: targets,
            dayLabel: targets.level.title
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Meal timeline"))
                .font(APEXFont.display(28))
            Text(language.text("Portions adapt to your activity and goal selection."))
                .font(APEXFont.body(14, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)

            ForEach(plan) { prescription in
                let meal = prescription.source
                let checked = session.data.mealLogs.contains { $0.date == date.apexDateKey && $0.mealID == meal.id }
                Button {
                    Task { await session.toggleMeal(meal, on: date) }
                } label: {
                    GlassCard(radius: 27, padding: 18) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(checked ? APEXColor.amber : APEXColor.amberDeep)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(meal.time)
                                        .font(APEXFont.mono(16))
                                        .foregroundStyle(APEXColor.amberDeep)
                                    Text(language.text(meal.name))
                                        .font(APEXFont.display(19))
                                }
                                Text(language.text(meal.foods))
                                    .font(APEXFont.body(14, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                    .multilineTextAlignment(.leading)
                                Text(language.format("%d kcal   P %d   F %d   C %d", prescription.kcal, prescription.proteinG, prescription.fatG, prescription.carbsG))
                                    .font(APEXFont.mono(11))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                Text(language.text(prescription.portionNote))
                                    .font(APEXFont.body(11, weight: .bold))
                                    .foregroundStyle(APEXColor.amberDeep)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(APEXColor.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .opacity(checked ? 0.64 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

}

private struct FoodLoggingCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let date: Date
    @Binding var showBarcode: Bool
    @Binding var showFoodSearch: Bool

    private var meals: [LoggedMeal] {
        session.data.loggedMeals
            .filter { $0.localDate == date.apexDateKey }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    var body: some View {
        GlassCard(radius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("Food log"))
                            .font(APEXFont.display(25))
                        Text(language.text("Log what you actually ate"))
                            .font(APEXFont.body(13, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Button {
                        showBarcode = true
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 30, weight: .semibold))
                            Text(language.text("SCAN"))
                                .font(APEXFont.mono(8))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 72)
                        .background(APEXColor.ink, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if !meals.isEmpty {
                    VStack(spacing: 9) {
                        ForEach(meals) { meal in
                            HStack(spacing: 11) {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(APEXColor.amberDeep)
                                    .frame(width: 34, height: 34)
                                    .background(APEXColor.amber.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(meal.displayName)
                                        .font(APEXFont.body(14, weight: .bold))
                                    Text(language.format(
                                        "%d kcal · P %d · C %d · F %d",
                                        Int(meal.totalKcal.rounded()),
                                        Int(meal.totalProteinG.rounded()),
                                        Int(meal.totalCarbsG.rounded()),
                                        Int(meal.totalFatG.rounded())
                                    ))
                                        .font(APEXFont.mono(9))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await session.deleteLoggedMeal(meal) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(APEXColor.danger)
                            }
                            .padding(12)
                            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }

                Button { showFoodSearch = true } label: {
                    Label(language.text("Add food or use a saved meal"), systemImage: "plus.circle.fill")
                        .font(APEXFont.body(14, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DailyLogCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var morningWeightText = ""
    let date: Date
    let targets: NutritionTargets
    let onAdjustActivities: () -> Void

    private var current: DailyLog? {
        session.data.dailyLogs.first { $0.date == date.apexDateKey }
    }

    var body: some View {
        GlassCard(radius: 32, padding: 21) {
            VStack(alignment: .leading, spacing: 19) {
                Text(language.text("Daily log"))
                    .font(APEXFont.display(27))
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(language.language.locale)))
                    .font(APEXFont.mono(12))
                    .foregroundStyle(APEXColor.secondaryInk)

                Text(language.text("Nutrition is calculated from logged meals. Enter only water and morning weight here."))
                    .font(APEXFont.body(13, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)

                if preciseLogs.isEmpty == false {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.text(allReconciled ? "Day reconciled" : "Did the day go as planned?"))
                                    .font(APEXFont.display(19))
                                Text(language.format("%d kcal TDEE · PAL %.2f · %@", targets.tdee, targets.pal, language.text(targets.level.title)))
                                    .font(APEXFont.body(11, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer()
                            if allReconciled {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 25))
                                    .foregroundStyle(APEXColor.green)
                            }
                        }
                        HStack(spacing: 10) {
                            Button(language.text("Adjust blocks"), action: onAdjustActivities)
                                .buttonStyle(.bordered)
                            if allReconciled == false {
                                Button(language.text("Yes, finalize")) {
                                    Task { await session.finalizeActivityDay(date, targets: targets) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.amber)
                            }
                        }
                    }
                    .padding(16)
                    .background(APEXColor.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                }

                Divider()

                VStack(alignment: .leading, spacing: 11) {
                    Text(language.text("Water"))
                        .font(APEXFont.display(19))
                    Text(language.text("Editable here or from the workout calendar."))
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                    logStepper(title: "Water", value: current?.waterL ?? 0, unit: "L", step: 0.25)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(language.text("Morning weight"))
                        .font(APEXFont.display(19))
                    Text(language.text("Optional · feeds the 7-day calibration EMA"))
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                    HStack(spacing: 10) {
                        TextField(language.text("Weight"), text: $morningWeightText)
                            .keyboardType(.decimalPad)
                            .font(APEXFont.mono(17))
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(APEXColor.ink.opacity(0.08)))
                            .onSubmit(saveMorningWeight)
                        Text(language.text("kg"))
                            .font(APEXFont.mono(12))
                            .foregroundStyle(APEXColor.secondaryInk)
                        Button(language.text("Save"), action: saveMorningWeight)
                            .buttonStyle(.borderedProminent)
                            .tint(APEXColor.teal)
                    }
                }

            }
        }
        .task(id: date.apexDateKey) {
            let value = current?.weightKG ?? session.profile?.weightKG
            morningWeightText = value.map { $0.formatted(.number.precision(.fractionLength(1)).locale(language.language.locale)) } ?? ""
        }
    }

    private var preciseLogs: [ActivityLog] {
        session.data.activityLogs.filter { $0.date == date.apexDateKey }
    }

    private var allReconciled: Bool {
        preciseLogs.isEmpty == false && preciseLogs.allSatisfy(\.reconciled)
    }

    private func logStepper(title: String, value: Double, unit: String, step: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(title)).font(APEXFont.display(18))
                Text(language.format(
                    "%@ %@",
                    value.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0)).locale(language.language.locale)),
                    language.text(unit)
                ))
                    .font(APEXFont.mono(12))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Spacer()
            Button { update(title: title, delta: -step) } label: { Image(systemName: "minus") }
                .buttonStyle(LogStepperButtonStyle())
            Button { update(title: title, delta: step) } label: { Image(systemName: "plus") }
                .buttonStyle(LogStepperButtonStyle())
        }
    }

    private func update(title: String, delta: Double) {
        guard title == "Water" else { return }
        /* Routed through the session so the HealthKit watermark moves with the
           edit. Writing the row directly here let the next sync restore the
           old, higher total and a decrease could never stick. */
        Task { await session.adjustWater(deltaLiters: delta, on: date) }
    }

    private func saveMorningWeight() {
        let normalized = morningWeightText.replacingOccurrences(of: ",", with: ".")
        guard let weight = Double(normalized), (25...350).contains(weight) else { return }
        Task { await session.saveMorningWeight(weight, on: date) }
    }
}

/*
 * Web-parity disclosure: a single glass row that states what is inside and
 * expands on tap. Expansion is remembered per section so a person who always
 * opens their supplements keeps them open.
 */
struct CollapsibleSection<Content: View>: View {
    let id: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    @AppStorage private var expanded: Bool

    init(id: String, title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.content = content
        _expanded = AppStorage(wrappedValue: false, "apex.section.expanded.\(id)")
    }

    var body: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded.toggle() }
            } label: {
                GlassCard(radius: 26, padding: 17) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(APEXFont.display(19))
                                .foregroundStyle(APEXColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(subtitle)
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .rotationEffect(.degrees(expanded ? 45 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("section-toggle-\(id)")
            /* A disclosure control should say whether it is open, both for
               VoiceOver and so a test can tell without guessing. */
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Collapse" : "Expand")

            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct BodyAssessmentCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let targets: NutritionTargets
    let date: Date

    var body: some View {
        GlassCard(radius: 32, padding: 22) {
            VStack(alignment: .leading, spacing: 13) {
                Label(language.text("APEX assessment"), systemImage: "sparkles")
                    .font(APEXFont.display(24))
                Text(assessment)
                    .font(APEXFont.body(15, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(4)
                Text(language.text("This is performance guidance, not medical advice."))
                    .font(APEXFont.body(10, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk.opacity(0.75))
            }
        }
    }

    private var assessment: String {
        guard let profile = session.profile else { return "" }
        let log = session.data.dailyLogs.first { $0.date == date.apexDateKey }
        let protein = log?.proteinG ?? 0
        let water = log?.waterL ?? 0
        var statements: [String] = []
        statements.append(language.format(
            "Today's energy model places you at %@ with a %d kcal target.",
            language.lowercased(targets.level.title),
            targets.targetCalories
        ))
        if protein < Int(Double(targets.proteinG) * 0.75) {
            statements.append(language.format(
                "Protein is currently the clearest nutrition gap. Aim toward %d g to protect recovery and lean mass.",
                targets.proteinG
            ))
        } else {
            let goalLabel = NutritionGoalPolicy.preset(
                for: profile.goal,
                context: NutritionGoalPolicy.context(from: session.data.settings)
            ).label
            statements.append(language.format("Protein coverage is on track for %@.", language.lowercased(goalLabel)))
        }
        if water < 1.5 {
            statements.append(language.text("Hydration is still light in the log. Add water progressively, especially around training or physical work."))
        }
        return statements.joined(separator: " ")
    }
}

struct ChoicePillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(APEXFont.body(12, weight: .bold))
            .foregroundStyle(selected ? .white : APEXColor.secondaryInk)
            .padding(.horizontal, 14)
            .frame(height: 39)
            .background(selected ? APEXColor.amber : .white.opacity(0.62), in: Capsule())
            .overlay(Capsule().stroke(selected ? APEXColor.amber : .white.opacity(0.92)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct LogStepperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 44)
            .background(APEXColor.amber, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + lineHeight), points)
    }
}

func systemIcon(_ catalogIcon: String) -> String {
    switch catalogIcon {
    case "hands": "hand.raised.fingers.spread"
    case "camera": "video"
    case "tripod": "camera.on.rectangle"
    case "case": "suitcase.rolling"
    case "desk": "desktopcomputer"
    case "stand": "figure.stand"
    case "walk": "figure.walk"
    case "hammer": "hammer"
    case "play": "figure.play"
    case "cart": "cart"
    case "home": "house"
    case "route": "point.topleft.down.to.point.bottomright.curvepath"
    case "steps": "shoeprints.fill"
    case "strength": "dumbbell"
    case "bolt": "bolt.fill"
    case "mobility": "figure.cooldown"
    case "run": "figure.run"
    case "watch": "applewatch"
    default: "figure.walk"
    }
}
