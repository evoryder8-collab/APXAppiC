import SwiftUI

private struct CoachSimpleShortcut: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(APEXFont.body(15, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(APEXFont.body(10, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(APEXColor.violet)
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.84)))
    }
}

struct SimpleHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var nudges = NudgeCenter.shared
    @State private var showNudges = false
    @State private var showPaywall = false
    @State private var showWorkout = false
    @State private var workoutIsLite = false
    @State private var selectedProgramDayID: UUID?
    @State private var selectedDate = Date()
    @State private var showTargetEditor = false
    @State private var showCalendar = false
    @State private var showMealSlotPicker = false
    @State private var composerRequest: MealComposerRequest?
    @State private var health = HealthKitManager.shared
    @State private var quickPanel: SimpleQuickPanel?
    @State private var showingSyncIssues = false

    private var today: String { selectedDate.apexDateKey }

    /* Clean hides the explanatory lines under each card; detailed keeps them.
       The setting has existed since Simple mode did and nothing had ever read
       it, so both choices produced the same screen. */
    private var showsGuidance: Bool {
        (session.data.settings?.addons["interface_mode"]?.stringValue ?? "clean") == "detailed"
    }
    private var profile: Profile? { session.profile }
    private var meals: [Meal] { session.data.meals.sorted { $0.sortOrder < $1.sortOrder } }
    private var activities: [ActivityLog] {
        guard let ownerID = profile?.userID else { return [] }
        return session.data.activityLogs.filter {
            $0.userID == ownerID && $0.date == today
        }
    }
    private var targets: NutritionTargets? {
        guard let profile else { return nil }
        return EnergyEngine.targets(
            profile: profile,
            logs: activities,
            catalog: session.data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: session.data.settings),
            settings: session.data.settings,
            wearableActiveCalories: WearableActivityRecord.activeCalories(
                on: today,
                settings: session.data.settings,
                ownerID: profile.userID
            )
        )
    }
    private var adaptivePlan: [AdaptiveMeal] {
        guard let targets else { return [] }
        return AdaptiveMealPlanEngine.build(
            meals: meals,
            targets: targets,
            dayLabel: targets.level.title
        )
    }
    private var hydrationResolution: HydrationDayResolution { session.hydrationResolution(on: selectedDate) }
    private var drinkWaterL: Double { Double(hydrationResolution.drinkML) / 1_000 }
    private var foodWaterL: Double {
        max(Double(hydrationResolution.foodML) / 1_000, session.foodHydrationLiters(on: selectedDate))
    }
    private var waterTargetL: Double {
        Double(session.hydrationTargetResolution(
            on: selectedDate,
            plannedExerciseMinutes: todayProgramDay?.estimatedMinutes
        ).targetML) / 1_000
    }
    private var waterL: Double { min(6, drinkWaterL + foodWaterL) }
    private var waterDone: Bool { waterL >= waterTargetL * 0.9 }

    private var supplementGroups: [SimpleSupplementGroup] {
        let grouped = Dictionary(grouping: session.activeSupplements, by: \.groupLabel)
        return grouped.map { label, items in
            let sorted = items.sorted { $0.sortOrder < $1.sortOrder }
            return SimpleSupplementGroup(
                label: label,
                timeMinutes: sorted.map(supplementTime).min() ?? 0,
                supplements: sorted
            )
        }
        .sorted { left, right in
            if left.timeMinutes == right.timeMinutes { return left.label < right.label }
            return left.timeMinutes < right.timeMinutes
        }
    }

    private var todayWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        return weekday == 1 ? 7 : weekday - 1
    }
    private var guidedProgramSlug: String {
        if session.coachClientPolicy.canFollowCoachPlan,
           TrainingInduction.hasUsablePrescription(in: session.data, slug: "coach") {
            return "coach"
        }
        let fallback = SimpleHomeLogic.guidedProgramSlug(
            persona: profile?.persona,
            mainIsUsable: TrainingInduction.hasUsablePrescription(in: session.data, slug: "main"),
            transitionIsUsable: TrainingInduction.hasUsablePrescription(in: session.data, slug: "transition")
        )
        guard session.data.settings?.addons["training_induction"]?.objectValue != nil else {
            return fallback
        }
        if TrainingPlanEngine.isInsideInductionWindow(session.data, slug: "transition", date: today),
           TrainingInduction.hasUsablePrescription(in: session.data, slug: "transition") {
            return "transition"
        }
        if TrainingPlanEngine.isInsideInductionWindow(session.data, slug: "main", date: today),
           TrainingInduction.hasUsablePrescription(in: session.data, slug: "main") {
            return "main"
        }
        return fallback
    }
    private var guidedProgramRoute: PortalDestination {
        guidedProgramSlug == "coach" ? .coachWorkouts : guidedProgramSlug == "main" ? .mainPhase : .transition
    }
    private var hasUsableTrainingPlan: Bool {
        guard TrainingInduction.hasUsablePrescription(in: session.data, slug: guidedProgramSlug) else {
            return false
        }
        if guidedProgramSlug == "coach" { return true }
        guard session.data.settings?.addons["training_induction"]?.objectValue != nil else {
            return true
        }
        return TrainingPlanEngine.isInsideInductionWindow(
            session.data,
            slug: guidedProgramSlug,
            date: today
        )
    }
    private var workoutPlans: [PlannedDay] {
        guard hasUsableTrainingPlan else { return [] }
        return TrainingPlanEngine.programDays(
            session.data,
            slug: guidedProgramSlug,
            date: today,
            lite: workoutIsLite
        )
    }
    private var todayProgramDays: [ProgramDay] {
        workoutPlans.compactMap(\.programDay)
    }
    private var todayProgramDay: ProgramDay? {
        todayProgramDays.first { $0.id == selectedProgramDayID } ?? todayProgramDays.first
    }
    private var workoutDone: Bool {
        guard hasUsableTrainingPlan else { return false }
        let prescribed = workoutPlans.filter { !$0.exercises.isEmpty }.compactMap(\.programDay)
        guard !prescribed.isEmpty else { return true }
        return prescribed.allSatisfy { day in
            SimpleHomeLogic.completedSessionID(
                sessions: session.data.workoutSessions,
                date: today,
                programDayID: day.id
            ) != nil
        }
    }
    private var completedWorkoutSessionID: UUID? {
        guard let todayProgramDay else { return nil }
        return SimpleHomeLogic.completedSessionID(
            sessions: session.data.workoutSessions,
            date: today,
            programDayID: todayProgramDay.id
        )
    }
    private var workoutPlan: PlannedDay {
        TrainingPlanEngine.plan(
            session.data,
            slug: guidedProgramSlug,
            date: today,
            lite: workoutIsLite,
            programDayID: todayProgramDay?.id
        )
    }
    private var workoutExercises: [Exercise] {
        guard let todayProgramDay else { return [] }
        let requested = session.data.exercises
            .filter { $0.programDayID == todayProgramDay.id && $0.isLite == workoutIsLite }
            .sorted { $0.sortOrder < $1.sortOrder }
        let source: [Exercise]
        if requested.isEmpty, workoutIsLite {
            source = Array(session.data.exercises
                .filter { $0.programDayID == todayProgramDay.id && !$0.isLite }
                .sorted { $0.sortOrder < $1.sortOrder }
                .prefix(3))
        } else {
            source = requested
        }
        return TrainingAdjustmentEngine.adjustedExercises(source, isDeload: todayIsDeload)
    }

    private var todayIsDeload: Bool {
        TrainingAdjustmentEngine.isDeload(on: today, marks: session.data.deloadMarks ?? [])
    }

    private var completedMealCount: Int { meals.filter(mealDone).count }

    /* Individual supplements, for the tile. The tile opens a list of
       supplements with ticks against them, so it has to count the same things
       that list does. Showing "1/3" over a popup with three of seven ticked
       was two different questions wearing one answer. */
    private var takenSupplementCount: Int {
        session.activeSupplements.filter { supplement in
            session.data.supplementLogs.contains {
                $0.date == today && $0.supplementID == supplement.id
            }
        }.count
    }

    private var consumedNutrition: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        session.data.loggedMeals
            .filter { $0.localDate == today }
            .reduce(into: (0, 0, 0, 0)) { totals, meal in
                totals.0 += meal.totalKcal
                totals.1 += meal.totalProteinG
                totals.2 += meal.totalCarbsG
                totals.3 += meal.totalFatG
            }
    }

    private var wearableActivity: WearableActivityRecord? {
        WearableActivityRecord
            .history(from: session.data.settings?.addons["watch_activity_history"])
            .last { $0.date == today }
    }

    private var resolvedActivity: WearableActivityEngine.Resolution {
        WearableActivityEngine.resolve(
            persona: profile?.persona ?? .constantine,
            wearable: wearableActivity,
            logs: activities
        )
    }

    private var completion: Int {
        guard let profile, let targets else { return 0 }
        let consumed = consumedNutrition
        let activityProgress = SimpleHomeLogic.activityProgress(
            persona: profile.persona,
            goal: profile.goal,
            steps: resolvedActivity.steps,
            activeCalories: resolvedActivity.activeCalories,
            exerciseMinutes: resolvedActivity.exerciseMinutes
        )
        let supplements = session.activeSupplements.map { supplement in
            (
                name: supplement.name,
                taken: session.data.supplementLogs.contains {
                    $0.date == today && $0.supplementID == supplement.id
                }
            )
        }
        return SimpleHomeLogic.dailyProgress(
            completedMeals: completedMealCount,
            totalMeals: meals.count,
            consumedKcal: consumed.kcal,
            targetKcal: Double(targets.targetCalories),
            consumedProteinG: consumed.protein,
            targetProteinG: Double(targets.proteinG),
            consumedCarbsG: consumed.carbs,
            targetCarbsG: Double(targets.carbsG),
            consumedFatG: consumed.fat,
            targetFatG: Double(targets.fatG),
            waterL: waterL,
            waterTargetL: waterTargetL,
            workoutScheduled: todayProgramDay != nil,
            workoutCompleted: workoutDone,
            activityProgress: activityProgress,
            supplements: supplements,
            goal: profile.goal
        )
    }

    /* Simple-mode surface preferences, mirroring the web's defaults exactly */
    private var addons: [String: JSONValue] { session.data.settings?.addons ?? [:] }
    private func flag(_ key: String, default fallback: Bool) -> Bool {
        addons[key]?.boolValue ?? fallback
    }
    private var showNextAction: Bool { flag("simple_show_next_action", default: false) }
    private var showGuidedPlan: Bool { flag("simple_show_guided_plan", default: true) }
    private var showOrbitShortcut: Bool { flag("simple_show_orbit", default: true) }
    private var showBodyIndexShortcut: Bool { flag("simple_show_body_index", default: true) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                APEXTopBar(
                    profile: profile,
                    onSettings: { session.navigationPath.append(.settings) },
                    nudges: nudges,
                    onOpenNudges: { showNudges = true },
                    onOpenPaywall: { showPaywall = true }
                )

                HStack {
                    PortalModeSwitcher()
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            APEXDateNavigator(
                date: selectedDate,
                onPrevious: { changeDate(-1) },
                onNext: { changeDate(1) },
                onOpenCalendar: { showCalendar = true }
            )
            .padding(.horizontal, 18)

            if session.coachContext.capabilities.sponsoredClient {
                Button {
                    session.navigationPath.append(.coachPlan)
                } label: {
                    CoachSimpleShortcut(
                        title: language.text("Your coach plan"),
                        subtitle: language.format("Provided by %@", session.coachContext.sponsorship?.coachDisplayName ?? "APEX"),
                        icon: "person.crop.circle.badge.checkmark"
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
            }
            if session.coachContext.capabilities.coachWorkspace {
                Button {
                    session.navigationPath.append(.coachWorkspace)
                } label: {
                    CoachSimpleShortcut(
                        title: language.text("Coach workspace"),
                        subtitle: language.text("Your clients, plans and reviews in one private place."),
                        icon: "person.2.badge.gearshape"
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
            }

            ScrollView {
                /* The Dayline is taller than the viewport and owns a fixed-height
                   geometry canvas. Keeping that canvas in a lazy stack can make
                   SwiftUI repeatedly evict and remeasure it while a fast scroll
                   crosses the viewport boundary, pinning the main thread in an
                   AttributeGraph layout cycle. This screen has only a handful
                   of cards, so eager layout is both bounded and stable. */
                VStack(spacing: 15) {
                    RecoveryMorningCard(date: selectedDate)

                    if let targets {
                        NutritionGlanceCard(
                            date: selectedDate,
                            targets: targets,
                            onEditTargets: { showTargetEditor = true },
                            onOpenCalendar: { showCalendar = true },
                            completion: completion
                        )
                        APEXDaylineView(
                            date: selectedDate,
                            onOpenComposer: { composerRequest = $0 },
                            onAddMeal: { showMealSlotPicker = true },
                            compact: false
                        )
                    }

                    /* The web keeps this card behind a preference that is off
                       by default, because the metric tiles below already
                       cover water, supplements, stats and training. iOS was
                       rendering it unconditionally, which is why a large
                       hydration block sat above tiles that do the same job
                       and why the settings switch appeared to do nothing. */
                    if showNextAction, let action = nextAction {
                        NextActionCard(action: action) {
                            perform(action.kind)
                        }
                    }

                    metrics
                    CompletedWorkoutHistoryCards(date: selectedDate.apexDateKey, accent: APEXColor.teal)
                    WorkoutInsightsCard(anchorDate: selectedDate.apexDateKey, accent: APEXColor.teal)
                    WearableActivityCard(date: selectedDate)

                    if showGuidedPlan {
                        ForEach(workoutPlans.compactMap(\.programDay)) { day in
                            if SimpleHomeLogic.completedSessionID(
                                sessions: session.data.workoutSessions,
                                date: today,
                                programDayID: day.id
                            ) == nil,
                               workoutPlans.first(where: { $0.programDay?.id == day.id })?.exercises.isEmpty == false {
                                workoutShortcut(day: day)
                            }
                        }
                    }

                    if showOrbitShortcut, session.coachClientPolicy.canUseOrbit { orbitShortcut }
                    if showBodyIndexShortcut { avatarShortcut }

                    HStack {
                        PortalLanguagePicker()
                        Spacer()
                        if session.failedSyncCount > 0 {
                            SyncIssuesButton(count: session.failedSyncCount) {
                                showingSyncIssues = true
                            }
                        } else if session.pendingSyncCount > 0 {
                            Label(language.format("%d queued", session.pendingSyncCount), systemImage: "icloud.and.arrow.up")
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.amberDeep)
                        } else {
                            Label(language.text("Synced"), systemImage: "checkmark.icloud")
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 38)
.dockClearance()
            }
            .refreshable { await session.refresh() }
        }
        .apexEdgeDateSwipe(onPrevious: { changeDate(-1) }, onNext: { changeDate(1) })
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
        .sheet(isPresented: $showNudges) {
            NudgeSheet(nudges: nudges) { showNudges = false }
                .apexTransientSheet(.fraction(0.62))
        }
        .sheet(isPresented: $showingSyncIssues) {
            SyncIssuesSheet()
                .environment(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-open-water") {
                /* Let the Simple/Advanced mode transition finish before the
                   test-only presentation. Presenting in the same render pass
                   is discarded by SwiftUI on iOS 27. */
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    quickPanel = .water
                }
            }
#endif
        }
        .task { await session.refreshNudges() }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showWorkout) {
            if let todayProgramDay {
                WorkoutPlayerView(
                    day: todayProgramDay,
                    exercises: workoutExercises,
                    accent: APEXColor.teal,
                    lite: workoutIsLite,
                    date: today,
                    warmupText: workoutPlan.warmup,
                    warmupDuration: workoutPlan.warmupDuration
                )
            }
        }
        .apexPopover(isPresented: $showTargetEditor) {
            NutritionTargetSheet(date: selectedDate, onClose: { showTargetEditor = false })
                .environment(session)
        }
        .sheet(isPresented: $showCalendar) {
            NutritionCalendarSheet(selectedDate: selectedDate) { selectedDate = $0 }
                /* A month grid is six rows tall, so full height left the bottom
                   third of the sheet empty. */
                .apexTransientSheet(.fraction(0.74))
        }
        .sheet(isPresented: $showMealSlotPicker) {
            MealSlotPickerSheet(date: selectedDate) { composerRequest = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        /* Water is a task with its own interface and keeps the sheet. The rest
           are glances, and a glance belongs in a card over the page. */
        .sheet(isPresented: Binding(
            get: { quickPanel == .water },
            set: { if !$0, quickPanel == .water { quickPanel = nil } }
        )) {
            WaterQuickAddSheet(
                date: selectedDate,
                drinkLiters: drinkWaterL,
                foodLiters: foodWaterL,
                targetLiters: waterTargetL,
                sex: profile?.sex ?? "male",
                composition: hydrationResolution.composition
            )
            .presentationDetents([.large])
        }
        .apexPopover(item: Binding(
            get: { quickPanel == .water ? nil : quickPanel },
            set: { quickPanel = $0 }
        )) { panel in
            switch panel {
            case .supplements:
                SupplementStackEditor(date: selectedDate, onClose: { quickPanel = nil })
            case .stats:
                StatsQuickSheet(date: selectedDate, onClose: { quickPanel = nil })
            case .training:
                if let completedWorkoutSessionID {
                    WorkoutReceiptSheet(sessionID: completedWorkoutSessionID) {
                        quickPanel = nil
                    }
                    .environment(session)
                } else {
                    TrainingQuickSheet(
                        day: todayProgramDay,
                        hasUsablePrescription: hasUsableTrainingPlan,
                        isDeload: todayIsDeload,
                        completed: false,
                        onClose: { quickPanel = nil }
                    ) { lite in
                        quickPanel = nil
                        guard todayProgramDay != nil else {
                            session.navigationPath.append(guidedProgramRoute)
                            return
                        }
                        workoutIsLite = lite
                        showWorkout = true
                    }
                }
            case .water:
                EmptyView()
            }
        }
        .fullScreenCover(item: $composerRequest) { request in
            MealComposerView(request: request)
        }
    }

    private func changeDate(_ offset: Int) {
        withAnimation(.snappy) {
            selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var metrics: some View {
        HStack(spacing: 7) {
            SimpleMetric(
                icon: "drop.fill",
                value: language.format("%.1f L", waterL),
                label: "Water",
                done: waterDone,
                color: APEXColor.cyan,
                action: { quickPanel = .water }
            )
            .accessibilityIdentifier("simple-water-metric")
            .accessibilityLabel(language.text("Water"))
            SimpleMetric(
                icon: "sparkles",
                value: "\(takenSupplementCount)/\(session.activeSupplements.count)",
                label: "Supps",
                done: !session.activeSupplements.isEmpty
                    && takenSupplementCount == session.activeSupplements.count,
                color: APEXColor.violet,
                action: { quickPanel = .supplements }
            )
            SimpleMetric(
                icon: "chart.xyaxis.line",
                value: latestSnapshot.map { String(Int($0.overall.rounded())) } ?? "—",
                label: "Stats",
                done: false,
                color: APEXColor.green,
                portrait: (profile?.persona ?? .constantine).rawValue,
                action: { quickPanel = .stats }
            )
            SimpleMetric(
                icon: "figure.strengthtraining.traditional",
                value: !hasUsableTrainingPlan
                    ? language.text("No plan")
                    : todayProgramDay == nil
                        ? language.text("Rest")
                        : workoutDone
                            ? language.text("Done")
                            : todayProgramDay.map { "\($0.estimatedMinutes)m" } ?? language.text("Rest"),
                label: "Training",
                done: workoutDone,
                color: APEXColor.teal,
                action: { quickPanel = .training }
            )
            .accessibilityIdentifier("simple-training-metric")
            .accessibilityLabel(language.text("Training"))
            .accessibilityValue(
                todayProgramDay.map { language.text($0.name) }
                    ?? language.text(hasUsableTrainingPlan ? "Rest" : "No plan")
            )
        }
    }

    private func workoutShortcut(day: ProgramDay) -> some View {
        GlassCard(radius: 27, padding: 17) {
            HStack(spacing: 13) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 51, height: 51)
                    .background(APEXColor.teal.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(day.name))
                        .font(APEXFont.display(17))
                    /* Guidance, which Clean mode hides. The card is a button
                       with a name on it: what it does is not a mystery that
                       needs a sentence under it every day. */
                    if showsGuidance {
                        Text(language.text("Start directly. Skip calendar and setup."))
                            .font(APEXFont.body(10, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                Spacer(minLength: 2)
                VStack(spacing: 6) {
                    Button(language.text("Quick")) {
                        selectedProgramDayID = day.id
                        workoutIsLite = true
                        showWorkout = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(language.text("Start")) {
                        selectedProgramDayID = day.id
                        workoutIsLite = false
                        showWorkout = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.teal)
                    .controlSize(.small)
                }
            }
        }
    }

    private var orbitShortcut: some View {
        Button {
            session.navigationPath.append(.orbit)
        } label: {
            SimpleShortcutCard(
                icon: "figure.run",
                title: "APEX Orbit",
                subtitle: orbitSubtitle,
                trailing: language.text("RUN"),
                color: APEXColor.cyan
            )
        }
        .buttonStyle(.plain)
    }

    private var avatarShortcut: some View {
        Button {
            session.navigationPath.append(.avatar)
        } label: {
            SimpleShortcutCard(
                icon: "sparkles",
                title: "Your body index",
                subtitle: avatarSubtitle,
                trailing: latestSnapshot.map { String(Int($0.overall.rounded())) } ?? "—",
                color: APEXColor.green
            )
        }
        .buttonStyle(.plain)
    }

    private var latestSnapshot: RPGSnapshot? {
        session.data.snapshots.max { $0.date < $1.date }
    }

    private var avatarSubtitle: String {
        let sorted = session.data.snapshots.sorted { $0.date > $1.date }
        guard let current = sorted.first else { return language.text("Complete your first logs to give the Avatar reliable signals.") }
        let previous = sorted.dropFirst().first(where: { $0.date <= fourteenDaysAgo }) ?? sorted.last ?? current
        let delta = current.overall - previous.overall
        return language.format("%+.1f over 14 days · tap for the full story", delta)
    }

    private var fourteenDaysAgo: String {
        Calendar.current.date(byAdding: .day, value: -14, to: .now)?.apexDateKey ?? today
    }

    private var orbitSubtitle: String {
        if OrbitLocationManager.shared.hasRecoverableRun(for: session.profile?.userID) {
            return language.text("Continue interrupted run")
        }
        if let campaign = session.data.orbitCampaigns.first(where: { $0.status == "active" }),
           let planned = session.data.orbitCampaignSessions.first(where: {
               $0.campaignID == campaign.id && $0.date == today && $0.status == "planned"
           }) {
            let duration = Int(planned.adapted["duration_min"]?.numberValue ?? 0)
            let rawMission = planned.adapted["mission"]?.stringValue ?? "Run"
            let mission = rawMission.replacingOccurrences(of: "_", with: " ").capitalized
            return language.format("%d min · %@", duration, language.text(mission))
        }
        return language.text("Your next run, already reasoned through")
    }

    private var nextAction: SimpleAction? {
        var candidates: [SimpleAction] = []
        for prescription in adaptivePlan where !mealDone(prescription.source) {
            let meal = prescription.source
            candidates.append(.init(
                time: minutes(meal.time), kind: .meal(meal.id), eyebrow: "Next meal",
                title: language.text(meal.name), meta: language.format("%@ · %d kcal", meal.time, prescription.kcal),
                button: "Log as planned", color: APEXColor.amber
            ))
        }
        for group in supplementGroups where !groupDone(group) {
            candidates.append(.init(
                time: group.timeMinutes, kind: .supplements(group.id), eyebrow: "Next supplements",
                title: language.text(group.label), meta: language.format("%@ · %d items", clock(group.timeMinutes), group.supplements.count),
                button: "Mark group done", color: APEXColor.cyan
            ))
        }
        if let todayProgramDay, !workoutDone {
            candidates.append(.init(
                time: minutes(profile?.trainingTime ?? "19:00"), kind: .workout, eyebrow: "Today’s movement",
                title: language.text(todayProgramDay.name), meta: language.format("~%d min · %d exercises", todayProgramDay.estimatedMinutes, fullWorkoutExerciseCount),
                button: "Start session", color: APEXColor.teal
            ))
        }
        if !waterDone {
            candidates.append(.init(
                time: 21 * 60, kind: .water, eyebrow: "Hydration",
                title: language.format("%.2f of %.2f L", waterL, waterTargetL), meta: "One glass takes one tap",
                button: "+ 250 ml", color: APEXColor.cyan
            ))
        }
        if candidates.isEmpty {
            return .init(
                time: nowMinutes, kind: .progress, eyebrow: "Routine complete",
                title: "You kept the promise today", meta: "Everything essential is logged",
                button: "View progress", color: APEXColor.green
            )
        }
        guard let index = SimpleHomeLogic.nextCandidateIndex(times: candidates.map(\.time), nowMinutes: nowMinutes) else { return nil }
        return candidates[index]
    }

    private var fullWorkoutExerciseCount: Int {
        guard let todayProgramDay else { return 0 }
        return session.data.exercises.filter { $0.programDayID == todayProgramDay.id && !$0.isLite }.count
    }

    private var nowMinutes: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func perform(_ kind: SimpleAction.Kind) {
        switch kind {
        case .meal(let id):
            guard let prescription = adaptivePlan.first(where: { $0.id == id }) else { return }
            guard let operation = session.accountOperationLease() else { return }
            Task {
                do {
                    try await session.togglePlannedMeal(prescription, operation: operation)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        case .supplements(let id):
            guard let group = supplementGroups.first(where: { $0.id == id }) else { return }
            toggle(group)
        case .workout:
            workoutIsLite = false
            showWorkout = true
        case .water:
            addWater()
        case .progress:
            session.navigationPath.append(.avatar)
        }
    }

    private func mealDone(_ meal: Meal) -> Bool {
        session.data.mealLogs.contains { $0.date == today && $0.mealID == meal.id }
    }

    private func groupDone(_ group: SimpleSupplementGroup) -> Bool {
        !group.supplements.isEmpty && group.supplements.allSatisfy { supplement in
            session.data.supplementLogs.contains { $0.date == today && $0.supplementID == supplement.id }
        }
    }

    private func toggle(_ group: SimpleSupplementGroup) {
        guard let operation = session.accountOperationLease() else { return }
        let completed = groupDone(group)
        Task {
            do {
                for supplement in group.supplements {
                    try Task.checkCancellation()
                    guard session.accountOperationIsCurrent(operation) else {
                        throw CancellationError()
                    }
                    let isDone = session.data.supplementLogs.contains {
                        $0.userID == operation.ownerID
                            && $0.date == today
                            && $0.supplementID == supplement.id
                    }
                    if completed || !isDone {
                        try await session.toggleSupplement(
                            supplement,
                            operation: operation
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }

    /* Single owner of water writes: keeps the HealthKit watermark honest so a
       later reduction is never undone by the next sync. */
    private func addWater(_ liters: Double = 0.25) {
        guard let operation = session.accountOperationLease() else { return }
        Task {
            do {
                _ = try await session.adjustWater(
                    deltaLiters: liters,
                    on: selectedDate,
                    operation: operation
                )
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }

    private func supplementTime(_ supplement: Supplement) -> Int {
        if supplement.timing == "clock", let clockTime = supplement.clockTime {
            return minutes(clockTime)
        }
        return minutes(profile?.trainingTime ?? "19:00") + (supplement.offsetMinutes ?? 0)
    }

    private func minutes(_ clock: String) -> Int {
        let components = clock.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return 0 }
        return components[0] * 60 + components[1]
    }

    private func clock(_ rawMinutes: Int) -> String {
        let safe = (rawMinutes % 1_440 + 1_440) % 1_440
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

private struct SimpleSupplementGroup: Identifiable {
    let label: String
    let timeMinutes: Int
    let supplements: [Supplement]
    var id: String { label }
}

private func hydrationColor(_ token: String) -> Color {
    switch token {
    case "espresso": Color(red: 0.55, green: 0.29, blue: 0.13)
    case "tea": Color(red: 0.24, green: 0.68, blue: 0.34)
    case "citrus": Color(red: 1.00, green: 0.52, blue: 0.05)
    case "cocoa": Color(red: 0.66, green: 0.39, blue: 0.24)
    case "violet": Color(red: 0.55, green: 0.34, blue: 0.98)
    case "food": Color(red: 0.12, green: 0.66, blue: 0.56)
    case "external": Color(red: 0.90, green: 0.24, blue: 0.55)
    case "legacy": Color(red: 0.32, green: 0.52, blue: 0.72)
    case "blue": Color(red: 0.11, green: 0.39, blue: 0.98)
    default: APEXColor.cyan
    }
}

private struct SimpleAction {
    enum Kind {
        case meal(UUID)
        case supplements(String)
        case workout
        case water
        case progress
    }

    let time: Int
    let kind: Kind
    let eyebrow: String
    let title: String
    let meta: String
    let button: String
    let color: Color
}

private struct NextActionCard: View {
    @State private var language = LanguageState.shared
    let action: SimpleAction
    let perform: () -> Void

    var body: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text(action.eyebrow).uppercased(with: language.language.locale))
                    .font(APEXFont.mono(9))
                    .tracking(1.7)
                    .foregroundStyle(action.color)
                HStack(alignment: .bottom, spacing: 13) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text(action.title))
                            .font(APEXFont.display(23))
                            .lineLimit(2)
                        Text(language.text(action.meta))
                            .font(APEXFont.body(11, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer(minLength: 4)
                    Button(language.text(action.button), action: perform)
                        .font(APEXFont.body(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 42)
                        .background(action.color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .shadow(color: action.color.opacity(0.12), radius: 23, y: 12)
    }
}

private struct SimpleMetric: View {
    @State private var language = LanguageState.shared
    let icon: String
    let value: String
    let label: String
    let done: Bool
    let color: Color
    /* When set, the tile shows the person instead of a glyph, as the web does */
    var portrait: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        VStack(spacing: 5) {
            if let portrait {
                PortraitImage(name: portrait)
                    .frame(width: 27, height: 27)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1.5))
            } else {
            Image(systemName: done ? "checkmark" : icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(done ? .white : color)
                .frame(width: 27, height: 27)
                .background(done ? APEXColor.green : color.opacity(0.11), in: Circle())
            }
            Text(value)
                .font(APEXFont.mono(9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(language.shortText(label).uppercased(with: language.language.locale))
                .font(APEXFont.mono(7))
                .tracking(0.4)
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 84)
        .background(.ultraThinMaterial.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(done ? APEXColor.green.opacity(0.26) : .white.opacity(0.82)))
        }
        .buttonStyle(.plain)
    }
}

private struct SimpleShortcutCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    /// Clean hides the explanatory line; Detailed keeps it.
    private var showsGuidance: Bool {
        (session.data.settings?.addons["interface_mode"]?.stringValue ?? "clean") == "detailed"
    }

    let icon: String
    let title: String
    let subtitle: String
    let trailing: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(title))
                    .font(APEXFont.display(17))
                if showsGuidance {
                    Text(language.text(subtitle))
                        .font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            Text(language.text(trailing))
                .font(APEXFont.mono(trailing.count <= 3 ? 19 : 9))
                .foregroundStyle(color)
        }
        .padding(15)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.88)))
        .shadow(color: color.opacity(0.1), radius: 18, y: 9)
    }
}

enum SimpleQuickPanel: String, Identifiable {
    case water, supplements, stats, training
    var id: String { rawValue }
}

struct WearableActivityRecord: Hashable, Sendable {
    let date: String
    let steps: Int
    let activeCalories: Int
    let exerciseMinutes: Int
    let source: String
    let updatedAt: String

    var jsonValue: JSONValue {
        .object([
            "date": .string(date), "steps": .number(Double(steps)),
            "active_calories": .number(Double(activeCalories)),
            "exercise_minutes": .number(Double(exerciseMinutes)),
            "source": .string(source), "updated_at": .string(updatedAt)
        ])
    }

    static func history(from value: JSONValue?) -> [Self] {
        (value?.arrayValue ?? []).compactMap { item in
            guard let object = item.objectValue, let date = object["date"]?.stringValue else { return nil }
            return Self(
                date: date,
                steps: Int(object["steps"]?.numberValue ?? 0),
                activeCalories: Int(object["active_calories"]?.numberValue ?? 0),
                exerciseMinutes: Int(object["exercise_minutes"]?.numberValue ?? 0),
                source: object["source"]?.stringValue ?? "manual",
                updatedAt: object["updated_at"]?.stringValue ?? ""
            )
        }
    }

    static func activeCalories(
        on date: String,
        settings: UserSettings?,
        ownerID: UUID
    ) -> Int? {
        guard settings?.userID == ownerID else { return nil }
        return history(from: settings?.addons["watch_activity_history"])
            .last { $0.date == date }?
            .activeCalories
    }

    static func mergingHealthImport(
        date: String,
        existing: Self?,
        steps: Double?,
        activeEnergyKcal: Double?,
        exerciseMinutes: Double?,
        updatedAt: String
    ) -> Self? {
        guard steps != nil || activeEnergyKcal != nil || exerciseMinutes != nil else {
            return nil
        }
        let prior = existing?.date == date ? existing : nil
        return Self(
            date: date,
            steps: resolvedCount(steps, fallback: prior?.steps ?? 0),
            activeCalories: resolvedCount(activeEnergyKcal, fallback: prior?.activeCalories ?? 0),
            exerciseMinutes: resolvedCount(exerciseMinutes, fallback: prior?.exerciseMinutes ?? 0),
            source: "apple_health",
            updatedAt: updatedAt
        )
    }

    private static func resolvedCount(_ value: Double?, fallback: Int) -> Int {
        guard let value, value.isFinite else { return fallback }
        return Int(min(Double(Int.max), max(0, value)).rounded())
    }
}

enum WearableActivityEngine {
    struct Resolution: Equatable, Sendable {
        let steps: Int
        let activeCalories: Int
        let exerciseMinutes: Int
        let level: ActivityLevel
    }

    static func shouldAutomaticallyApplyMode(
        profile: Profile?,
        requested: Bool,
        hasActivityLogs: Bool
    ) -> Bool {
        guard requested, hasActivityLogs == false, let profile else { return false }
        return EnergyEngine.usesPersonalProtocol(profile) == false
    }

    static func resolve(
        persona: Persona,
        wearable: WearableActivityRecord?,
        logs: [ActivityLog]
    ) -> Resolution {
        let activeCalories = EnergyEngine.resolvedActiveCalories(
            wearableActiveCalories: wearable?.activeCalories,
            logs: logs
        )
        let loggedMinutes = logs.reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) }
        let exerciseMinutes = max(wearable?.exerciseMinutes ?? 0, loggedMinutes)
        let steps = max(0, wearable?.steps ?? 0)
        return Resolution(
            steps: steps,
            activeCalories: activeCalories,
            exerciseMinutes: exerciseMinutes,
            level: suggestedLevel(
                persona: persona,
                steps: steps,
                activeCalories: activeCalories,
                exerciseMinutes: exerciseMinutes
            )
        )
    }

    static func suggestedLevel(persona: Persona, steps: Int, activeCalories: Int, exerciseMinutes: Int) -> ActivityLevel {
        let stepCuts = persona == .june ? [4_000, 7_000, 11_500, 16_000] : [4_000, 7_500, 12_000, 18_000]
        let calorieCuts = persona == .june ? [180, 350, 550, 800] : [250, 500, 750, 1_100]
        let exerciseCuts = [10, 25, 50, 80]
        let rank = max(rank(steps, cuts: stepCuts), rank(activeCalories, cuts: calorieCuts), rank(exerciseMinutes, cuts: exerciseCuts))
        return [ActivityLevel.sedentary, .light, .moderate, .very, .extra][rank]
    }

    private static func rank(_ value: Int, cuts: [Int]) -> Int {
        cuts.reduce(0) { $0 + (value >= $1 ? 1 : 0) }
    }
}

private struct WaterQuickAddSheet: View {
    @State private var language = LanguageState.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var session
    let date: Date
    let drinkLiters: Double
    let foodLiters: Double
    let targetLiters: Double
    let sex: String
    let composition: [HydrationCompositionBand]
    @State private var customML = ""
    @State private var pulse = false
    @State private var showsManagement = false
    @FocusState private var customIsFocused: Bool

    private var totalLiters: Double { min(6, drinkLiters + foodLiters) }
    private var progress: Double { targetLiters > 0 ? min(1, max(0, totalLiters / targetLiters)) : 0 }
    private var customAmountML: Double? {
        guard let amount = Double(customML), amount > 0 else { return nil }
        return min(3_000, amount)
    }

    private var compositionGradient: LinearGradient {
        let stops = HydrationCompositionLayout.timelineStops(for: composition).map { stop in
            Gradient.Stop(
                color: hydrationColor(stop.paletteToken),
                location: CGFloat(stop.location)
            )
        }
        return LinearGradient(
            gradient: Gradient(stops: stops.isEmpty
                ? [
                    .init(color: APEXColor.cyan, location: 0),
                    .init(color: APEXColor.cyan, location: 1),
                ]
                : stops),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("Water quick add")).font(APEXFont.display(24))
                    Text(String(format: "Drinks %.2f L · Food %.2f L", drinkLiters, foodLiters))
                        .font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text(language.text("Done"))
                        .font(APEXFont.body(13, weight: .bold))
                        .foregroundStyle(APEXColor.cyan)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(APEXColor.cyan.opacity(0.20), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hydration-done")
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            /* The figure owns the free space, so it grows with the sheet
               instead of sitting small above a field of emptiness. */
            HydrationFigureGauge(
                totalLiters: totalLiters,
                targetLiters: targetLiters,
                sex: sex,
                composition: composition
            )
            .allowsHitTesting(false) // hydration gauge is presentation only
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)

            VStack(spacing: 11) {
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(String(format: "%.2f", totalLiters))
                        .font(APEXFont.mono(30, weight: .bold))
                        .foregroundStyle(APEXColor.ink)
                        .contentTransition(.numericText())
                        .scaleEffect(pulse ? 1.06 : 1)
                    Text(String(format: "/ %.2f L", targetLiters))
                        .font(APEXFont.mono(18, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(APEXColor.ink.opacity(0.08))
                        compositionGradient
                            .frame(width: max(0, proxy.size.width * progress))
                            .clipShape(Capsule())
                    }
                }
                .frame(height: 8)

                Text(targetLiters > 0
                     ? String(format: "%.0f%% of today's target", min(1, totalLiters / targetLiters) * 100)
                     : "")
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)

                if !composition.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(composition.enumerated()), id: \.offset) { _, band in
                                Label {
                                    Text("\(hydrationBandName(band.kind)) · \(band.milliliters) mL")
                                } icon: {
                                    Image(systemName: band.iconToken)
                                }
                                .font(APEXFont.mono(9, weight: .bold))
                                .foregroundStyle(hydrationColor(band.paletteToken))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    hydrationColor(band.paletteToken).opacity(0.10),
                                    in: Capsule()
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("hydration-composition")
                }
            }
            .padding(15)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: APEXColor.cyan.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text("ADD")).font(APEXFont.mono(10, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView(.horizontal) {
                        HStack(spacing: 9) {
                            ForEach(session.hydrationPresets) { preset in
                                presetButton(preset)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("hydration-presets")
                    HStack(spacing: 9) {
                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Custom amount", text: $customML)
                                    .keyboardType(.numberPad)
                                    .font(APEXFont.mono(14, weight: .semibold))
                                    .multilineTextAlignment(.trailing)
                                    .onSubmit(addCustom)
                                    .submitLabel(.done)
                                    .focused($customIsFocused)
                                    .accessibilityIdentifier("hydration-custom-ml")
                                Text("mL")
                                    .font(APEXFont.mono(12, weight: .bold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                    .allowsHitTesting(false)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                            .onTapGesture { customIsFocused = true }
                            if customIsFocused {
                                Button {
                                    customIsFocused = false
                                } label: {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(APEXColor.cyan)
                                        .frame(width: 34, height: 34)
                                        .background(APEXColor.cyan.opacity(0.10), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hide keyboard")
                                .accessibilityIdentifier("hydration-keyboard-dismiss")
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(APEXColor.cyan.opacity(customIsFocused ? 0.55 : 0.16), lineWidth: 1)
                        )

                        Button(action: addCustom) {
                            Label(language.text("Add"), systemImage: "plus")
                                .font(APEXFont.body(12, weight: .bold))
                                .foregroundStyle(customAmountML == nil ? APEXColor.ink.opacity(0.72) : .white)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 54)
                                .background(
                                    customAmountML == nil
                                        ? AnyShapeStyle(APEXColor.ink.opacity(0.09))
                                        : AnyShapeStyle(APEXColor.cyan.gradient),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay {
                                    if customAmountML == nil {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(APEXColor.ink.opacity(0.12), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(customAmountML == nil)
                        .accessibilityIdentifier("hydration-custom-add")
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text("REMOVE")).font(APEXFont.mono(10, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 9) {
                        ForEach([250, 300, 500], id: \.self) { amount in
                            quickButton("− \(amount)", tint: APEXColor.danger) {
                                commit(-Double(amount) / 1_000)
                            }
                            .disabled(drinkLiters <= 0)
                            .opacity(drinkLiters <= 0 ? 0.35 : 1)
                        }
                        Button {
                            showsManagement = true
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "gearshape.fill")
                                Text(language.shortText("Settings"))
                                    .font(APEXFont.body(10, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(APEXColor.cyan)
                            .background(APEXColor.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(APEXColor.cyan.opacity(0.16), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hydration settings, presets and history")
                        .accessibilityIdentifier("hydration-settings-bottom")
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
        .presentationBackground(.ultraThinMaterial)
        .sheet(isPresented: $showsManagement) {
            HydrationManagementSheet(date: date)
                .environment(session)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(language.text("Hide keyboard")) { customIsFocused = false }
            }
        }
        .background {
            ZStack {
                APEXColor.canvas
                RadialGradient(
                    colors: [APEXColor.cyan.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
        }
    }

    /* Logging never dismisses the sheet: the figure animates the new level
       and you close it when you have finished drinking. */
    private func commit(_ liters: Double) {
        guard let operation = session.accountOperationLease() else { return }
        Task {
            do {
                _ = try await session.adjustWater(
                    deltaLiters: liters,
                    on: date,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                animateConfirmation()
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }

    private func commit(_ preset: HydrationPreset) {
        guard let operation = session.accountOperationLease() else { return }
        Task {
            do {
                try await session.logHydration(
                    preset: preset,
                    on: date,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                animateConfirmation()
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }

    private func animateConfirmation() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false }
        }
    }

    private func presetButton(_ preset: HydrationPreset) -> some View {
        let tint = hydrationColor(preset.paletteToken)
        let displayName = language.hydrationPresetName(preset.name)
        return Button {
            commit(preset)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: preset.iconToken)
                Text(displayName).lineLimit(1)
                Text("\(preset.amountML) mL")
                    .font(APEXFont.mono(9, weight: .medium))
            }
            .font(APEXFont.body(11, weight: .bold))
            .foregroundStyle(tint)
        .frame(width: 84)
        .frame(minHeight: 58)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            language.format("Add %d millilitres of %@", preset.amountML, displayName)
        )
    }

    private func quickButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(APEXFont.mono(13, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(tint)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
            .buttonStyle(.plain)
    }

    private func addCustom() {
        guard let ml = customAmountML else { return }
        commit(ml / 1_000)
        customML = ""
        customIsFocused = false
    }

    private func hydrationBandName(_ kind: HydrationKind) -> String {
        switch kind {
        case .water: language.text("Water")
        case .coffee: language.text("Coffee")
        case .tea: language.text("Tea")
        case .juice: language.text("Juice")
        case .shake: language.text("Shake")
        case .food: language.text("Food")
        case .external: language.text("Health")
        case .legacy: language.text("Imported")
        case .other: language.text("Other")
        }
    }
}

private struct HydrationManagementSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date
    @State private var draft = WatchHydrationPreferences.default
    @State private var loaded = false
    @State private var editingPreset: HydrationPreset?
    @State private var addingPreset = false
    @State private var validationMessage: String?

    private var automaticTarget: HydrationTargetResolution {
        session.hydrationTargetResolution(on: date)
    }

    private var events: [HydrationEvent] {
        guard let ownerID = session.profile?.userID else { return [] }
        return (session.data.hydrationEvents ?? [])
            .filter { $0.userID == ownerID && $0.localDate == date.apexDateKey }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily target") {
                    Picker(
                        "Target mode",
                        selection: Binding(
                            get: { draft.effectiveTargetMode },
                            set: { next in
                                if next == .custom,
                                   draft.effectiveTargetMode == .automatic,
                                   abs(draft.targetLiters - 2.75) < 0.001 {
                                    draft.targetLiters = Double(automaticTarget.targetML) / 1_000
                                }
                                draft.targetMode = next
                            }
                        )
                    ) {
                        Text("Automatic").tag(HydrationTargetMode.automatic)
                        Text("Custom").tag(HydrationTargetMode.custom)
                    }
                    .pickerStyle(.segmented)

                    if draft.effectiveTargetMode == .automatic {
                        Text(draft.formattedAmount(liters: Double(automaticTarget.targetML) / 1_000))
                            .font(APEXFont.display(20))
                        Text(
                            "Body baseline \(automaticTarget.baselineML) mL"
                                + (automaticTarget.exerciseAdjustmentML > 0
                                    ? " · exercise +\(automaticTarget.exerciseAdjustmentML) mL" : "")
                                + (automaticTarget.wearableAdjustmentML > 0
                                    ? " · wearable +\(automaticTarget.wearableAdjustmentML) mL" : "")
                        )
                        .font(APEXFont.body(11))
                        .foregroundStyle(APEXColor.secondaryInk)
                        Text("An APEX estimate for total water from drinks and food. Sweat loss varies, so thirst and measured pre/post-workout weight change remain more personal than wearable calories.")
                            .font(APEXFont.body(10))
                            .foregroundStyle(APEXColor.secondaryInk)
                    } else {
                        TextField(
                            "Exact litres",
                            value: $draft.targetLiters,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        Stepper(value: $draft.targetLiters, in: 1...6, step: 0.1) {
                            Text("\(draft.targetLiters.formatted(.number.precision(.fractionLength(2)))) L")
                        }
                    }
                    Picker("Units", selection: $draft.unit) {
                        ForEach(WatchHydrationPreferences.Unit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                }

                Section("Gentle reminders") {
                    Toggle("Remind only when behind pace", isOn: $draft.remindersEnabled)
                    if draft.remindersEnabled {
                        Picker("Minimum gap", selection: $draft.reminderIntervalMinutes) {
                            Text("60 minutes").tag(60)
                            Text("90 minutes").tag(90)
                            Text("120 minutes").tag(120)
                        }
                        Text("Quiet hours and the three-per-day ceiling stay synchronized with the Watch.")
                            .font(APEXFont.body(11))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }

                Section("Preset buttons") {
                    ForEach(session.hydrationPresets) { preset in
                        Button {
                            editingPreset = preset
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: preset.iconToken)
                                    .foregroundStyle(hydrationColor(preset.paletteToken))
                                    .frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text(language.hydrationPresetName(preset.name))
                                        .font(APEXFont.body(14, weight: .bold))
                                    HStack(spacing: 0) {
                                        Text("\(preset.amountML) mL")
                                        Text(" · ")
                                        Text(language.text(preset.kind.rawValue.capitalized))
                                    }
                                        .font(APEXFont.mono(10))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                guard let operation = session.accountOperationLease() else { return }
                                Task {
                                    do {
                                        try await session.deleteHydrationPreset(
                                            preset,
                                            operation: operation
                                        )
                                    } catch is CancellationError {
                                        return
                                    } catch {
                                        guard session.accountOperationIsCurrent(operation) else { return }
                                        session.alertMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                    Button("Create preset", systemImage: "plus.circle.fill") {
                        addingPreset = true
                    }
                }

                Section("Presentation") {
                    Toggle("Show preset names", isOn: $draft.showsPresetNames)
                    Toggle("Confirmation haptics", isOn: $draft.confirmationHaptics)
                    Picker("Motion", selection: $draft.motionIntensity) {
                        ForEach(WatchHydrationPreferences.MotionIntensity.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }

                Section("History") {
                    if events.isEmpty {
                        Text("No hydration facts for this day.")
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    ForEach(events) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.iconToken)
                                .foregroundStyle(hydrationColor(event.paletteToken))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 0) {
                                    Text("\(event.amountML) mL")
                                    Text(" · ")
                                    Text(language.text(event.kind.rawValue.capitalized))
                                }
                                    .font(APEXFont.body(13, weight: .bold))
                                Text(event.source.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(APEXFont.mono(9))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: canDelete(event) ? "trash.circle" : "lock.fill")
                                .foregroundStyle(canDelete(event) ? APEXColor.danger : APEXColor.secondaryInk)
                        }
                        .swipeActions {
                            if canDelete(event) {
                                Button("Remove", role: .destructive) {
                                    guard let operation = session.accountOperationLease() else { return }
                                    Task {
                                        do {
                                            try await session.deleteHydrationEvent(
                                                event,
                                                on: date,
                                                operation: operation
                                            )
                                        } catch is CancellationError {
                                            return
                                        } catch {
                                            guard session.accountOperationIsCurrent(operation) else { return }
                                            session.alertMessage = error.localizedDescription
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let validationMessage {
                    Text(validationMessage).foregroundStyle(APEXColor.danger)
                }
            }
            .navigationTitle("Hydration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .task { load() }
            .sheet(item: $editingPreset) { preset in
                HydrationPresetEditor(preset: preset).environment(session)
            }
            .sheet(isPresented: $addingPreset) {
                HydrationPresetEditor(preset: nil).environment(session)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        draft = session.hydrationPreferences.map(WatchHydrationPreferences.init(account:)) ?? .default
    }

    private func save() {
        guard let operation = session.accountOperationLease() else { return }
        do {
            if draft.effectiveTargetMode == .custom {
                draft.targetLiters = try WatchHydrationPreferences.validatedTargetLiters(draft.targetLiters)
            }
            let preferences = draft.accountRow(
                ownerID: operation.ownerID,
                existing: session.hydrationPreferences
            )
            Task {
                do {
                    try await session.saveHydrationPreferences(
                        preferences,
                        operation: operation
                    )
                    guard session.accountOperationIsCurrent(operation) else { return }
                    dismiss()
                } catch is CancellationError {
                    return
                } catch {
                    guard session.accountOperationIsCurrent(operation) else { return }
                    validationMessage = error.localizedDescription
                }
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func canDelete(_ event: HydrationEvent) -> Bool {
        event.source == .iPhone || event.source == .legacy
    }
}

private struct HydrationPresetEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let preset: HydrationPreset?
    @State private var name: String
    @State private var amountML: Int
    @State private var kind: HydrationPresetKind
    @State private var paletteToken: String
    @State private var iconToken: String

    private let kinds = HydrationPresetKind.allCases
    private let palettes = ["aqua", "blue", "espresso", "tea", "citrus", "cocoa", "violet"]
    private let icons = [
        "drop.fill", "waterbottle.fill", "cup.and.saucer.fill", "mug.fill",
        "takeoutbag.and.cup.and.straw.fill", "bolt.heart.fill", "leaf.fill",
    ]

    init(preset: HydrationPreset?) {
        self.preset = preset
        _name = State(initialValue: preset?.name ?? "")
        _amountML = State(initialValue: preset?.amountML ?? 250)
        _kind = State(initialValue: preset?.kind ?? .water)
        _paletteToken = State(initialValue: preset?.paletteToken ?? "aqua")
        _iconToken = State(initialValue: preset?.iconToken ?? "drop.fill")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Preset name", text: $name)
                Stepper("\(amountML) mL", value: $amountML, in: 10...5_000, step: 10)
                Picker("Drink type", selection: $kind) {
                    ForEach(kinds, id: \.self) { value in
                        Text(language.text(value.rawValue.capitalized)).tag(value)
                    }
                }
                Section("Colour") {
                    HStack {
                        ForEach(palettes, id: \.self) { token in
                            Button {
                                paletteToken = token
                            } label: {
                                Circle()
                                    .fill(hydrationColor(token))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if token == paletteToken {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Picker("Icon", selection: $iconToken) {
                    ForEach(icons, id: \.self) { icon in
                        Label(icon.replacingOccurrences(of: ".fill", with: ""), systemImage: icon).tag(icon)
                    }
                }
            }
            .navigationTitle(preset == nil ? "New preset" : "Edit preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let operation = session.accountOperationLease() else { return }
        let now = Date().ISO8601Format()
        let row = HydrationPreset(
            id: preset?.id ?? UUID(),
            userID: operation.ownerID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amountML: amountML,
            kind: kind,
            paletteToken: paletteToken,
            iconToken: iconToken,
            sortOrder: preset?.sortOrder ?? ((session.hydrationPresets.map(\.sortOrder).max() ?? -1) + 1),
            enabled: true,
            createdAt: preset?.createdAt ?? now,
            updatedAt: now
        )
        Task {
            do {
                try await session.saveHydrationPreset(row, operation: operation)
                guard session.accountOperationIsCurrent(operation) else { return }
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }
}

/*
 * The silhouette with a litre scale locked to its body.
 *
 * The figure is an SVG whose viewBox is `-150 -150 W 1015`, drawn with
 * xMidYMid meet. Inside that box the crown of the head sits at y = 0 and the
 * feet, where the water level rests at zero, sit at y = 712. So the body
 * occupies a fixed slice of the rendered frame: 150/1015 of the way down at
 * the hairline and 862/1015 at the feet. Sizing the frame to the viewBox's
 * own aspect ratio removes any letterboxing, which lets the ruler land
 * exactly on the body: 0 L at the feet, the target at the crown.
 */
private struct HydrationFigureGauge: View {
    let totalLiters: Double
    let targetLiters: Double
    let sex: String
    let composition: [HydrationCompositionBand]

    private var isFemale: Bool { sex.lowercased().contains("female") }
    /* viewBox widths differ slightly between the two figures */
    private var aspect: CGFloat { (isFemale ? 568.0 : 583.6) / 1015.0 }

    private let crownFraction: CGFloat = 150.0 / 1015.0
    private let feetFraction: CGFloat = 862.0 / 1015.0

    private var progress: Double { targetLiters > 0 ? min(1, max(0, totalLiters / targetLiters)) : 0 }

    /* Minor ticks every 250 ml, labels every 500 ml, plus 0 and the target. */
    private var minorStep: Double { targetLiters > 4 ? 0.5 : 0.25 }

    private var tickValues: [Double] {
        guard targetLiters > 0 else { return [] }
        var values: [Double] = []
        var value: Double = 0
        while value < targetLiters - 0.001 {
            values.append((value * 100).rounded() / 100)
            value += minorStep
        }
        values.append(targetLiters)
        return values
    }

    private func isLabelled(_ value: Double) -> Bool {
        if value == 0 || value == targetLiters { return true }
        let halves = value / 0.5
        return abs(halves - halves.rounded()) < 0.001
    }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size
            /* Reserve the ruler column, then take the largest figure that
               still fits both dimensions. */
            let rulerWidth: CGFloat = 62
            let heightLimited = available.height
            let widthLimited = max(0, available.width - rulerWidth - 10) / aspect
            /* Never overflow the GeometryReader. UIKit-backed content can
               otherwise keep an invisible hit region over the controls that
               follow this gauge when vertical space is compressed. */
            let figureHeight = max(0, min(heightLimited, widthLimited))
            let figureWidth = figureHeight * aspect

            let crownY = crownFraction * figureHeight
            let feetY = feetFraction * figureHeight
            let span = feetY - crownY

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                ZStack(alignment: .topLeading) {
                    ForEach(tickValues, id: \.self) { value in
                        let fraction = targetLiters > 0 ? value / targetLiters : 0
                        let y = feetY - CGFloat(fraction) * span
                        let labelled = isLabelled(value)
                        let isTarget = value == targetLiters
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            if labelled {
                                Text(isTarget || value == 0
                                     ? String(format: "%.2fL", value)
                                     : String(format: "%.1f", value))
                                    .font(APEXFont.mono(isTarget ? 11 : 10, weight: isTarget ? .bold : .medium))
                                    .foregroundStyle(isTarget ? APEXColor.cyan : APEXColor.secondaryInk)
                                    .fixedSize()
                            }
                            Rectangle()
                                .fill(isTarget ? APEXColor.cyan : APEXColor.secondaryInk.opacity(labelled ? 0.45 : 0.22))
                                .frame(width: labelled ? 12 : 6, height: isTarget ? 1.6 : 1)
                        }
                        .frame(width: rulerWidth, alignment: .trailing)
                        .position(x: rulerWidth / 2, y: y)
                    }

                    /* Where the level actually stands right now */
                    if progress > 0 {
                        let y = feetY - CGFloat(progress) * span
                        Text(String(format: "%.2f", totalLiters))
                            .font(APEXFont.mono(10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(APEXColor.cyan, in: Capsule())
                            .position(x: rulerWidth / 2, y: y)
                            .animation(.spring(response: 0.75, dampingFraction: 0.85), value: progress)
                    }
                }
                .frame(width: rulerWidth, height: figureHeight)

                HydrationFigureWebView(
                    progress: progress,
                    sex: sex,
                    composition: composition
                )
                    .frame(width: figureWidth, height: figureHeight)

                Spacer(minLength: 0)
            }
            .frame(width: available.width, height: available.height, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Hydration %.2f of %.2f litres", totalLiters, targetLiters))
    }
}

struct SupplementStackEditor: View {
    @State private var language = LanguageState.shared
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date
    var showsHeader = true
    var onClose: () -> Void = {}

    @State private var showPicker = false
    @State private var pendingDelete: Supplement?

    private var supplements: [Supplement] {
        session.activeSupplements
    }

    private var taken: Int {
        session.activeSupplements.filter { supplement in
            session.data.supplementLogs.contains { $0.date == date.apexDateKey && $0.supplementID == supplement.id }
        }.count
    }

    var body: some View {
        /* Card content, not a screen: no stack, no bar, no scrolling to see
           what is a short list. */
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                APEXPopoverHeader(
                    title: language.text("Supplement stack"),
                    subtitle: language.format(
                        "%d of %d taken",
                        taken,
                        session.activeSupplements.count
                    ),
                    onClose: onClose
                )
            }

            /* A List rather than a stack of buttons, because swipe-to-delete
               should be the real gesture -- it comes with the resistance, the
               full-swipe and the VoiceOver actions people already expect,
               none of which a hand-rolled drag gets right. */
            List {
                ForEach(supplements) { supplement in
                    let done = session.data.supplementLogs.contains {
                        $0.date == date.apexDateKey && $0.supplementID == supplement.id
                    }
                    Button {
                        guard let operation = session.accountOperationLease() else { return }
                        Task {
                            do {
                                try await session.toggleSupplement(
                                    supplement,
                                    on: date,
                                    operation: operation
                                )
                            } catch is CancellationError {
                                return
                            } catch {
                                guard session.accountOperationIsCurrent(operation) else { return }
                                session.alertMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 19))
                                .foregroundStyle(done ? APEXColor.green : APEXColor.secondaryInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(supplement.name)
                                    .font(APEXFont.body(14, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(supplement.dose) · \(language.text(supplement.groupLabel))")
                                    .font(APEXFont.body(10))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(.white.opacity(done ? 0.85 : 0.6), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        /* Retires it from the plan and keeps the history.
                           Not a full swipe, so it cannot happen by accident
                           while scrolling a list you check off every morning. */
                        Button(role: .destructive) { pendingDelete = supplement } label: {
                            Label(language.text("Remove"), systemImage: "archivebox")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            /* The height used to grow with the number of supplements and
               scrolling was switched off, so anyone whose stack ran past the
               bottom of the sheet could not reach the rest of it. It now takes
               what it needs up to a ceiling, and scrolls beyond that. */
            /* A definite height, not a maximum: a List has no intrinsic
               height of its own, so maxHeight let it collapse to nothing and
               the sheet rendered empty. Capped so a long stack scrolls. */
            .frame(height: min(CGFloat(max(1, supplements.count)) * 78, 420))
            .scrollDisabled(false)

            Button {
                showPicker = true
            } label: {
                Label(language.text("Add"), systemImage: "plus")
                    .font(APEXFont.body(13, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(APEXColor.green)
        }
        .sheet(isPresented: $showPicker) {
            SupplementPickerSheet { entry, dose in
                guard let operation = session.accountOperationLease() else { return }
                Task {
                    do {
                        try await session.addSupplement(
                            name: entry.name,
                            dose: entry.formattedDose(dose),
                            groupLabel: entry.timing,
                            operation: operation
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        guard session.accountOperationIsCurrent(operation) else { return }
                        session.alertMessage = error.localizedDescription
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove from your plan?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(language.text("Remove"), role: .destructive) {
                if let supplement = pendingDelete {
                    guard let operation = session.accountOperationLease() else { return }
                    Task {
                        do {
                            try await session.archiveSupplement(
                                supplement,
                                operation: operation
                            )
                        } catch is CancellationError {
                            return
                        } catch {
                            guard session.accountOperationIsCurrent(operation) else { return }
                            session.alertMessage = error.localizedDescription
                        }
                    }
                }
                pendingDelete = nil
            }
            Button(language.text("Keep"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(language.text("It stops appearing in your plan. Everything you have already logged is kept."))
        }
    }

}

private struct StatsQuickSheet: View {
    @State private var language = LanguageState.shared
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date
    var onClose: () -> Void = {}
    private var snapshot: RPGSnapshot? { session.data.snapshots.filter { $0.date <= date.apexDateKey }.max { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            APEXPopoverHeader(title: "Body signals", onClose: onClose)
            if let snapshot {
                VStack(spacing: 3) {
                    Text(String(Int(snapshot.overall.rounded())))
                        .font(APEXFont.mono(52))
                        .foregroundStyle(APEXColor.green)
                    Text(language.text("Overall Fitness Level")).font(APEXFont.body(12, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(language.text("No stats yet"))
                    .font(APEXFont.body(13, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
            Button(language.text("Open full Avatar")) {
                onClose()
                session.navigationPath.append(.avatar)
            }
            .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.green))
        }
    }
}

/*
 * Training preview, matching the web quick panel: today's session at a
 * glance with both prescriptions side by side, so the choice between the
 * full session and the short one is made before the player opens.
 *
 * Durations use the web's formulas exactly. Full is the authored estimate
 * for the day; Light is derived from the session timeline, so it reflects
 * the sets, rests and holds that will actually run.
 */
private struct TrainingQuickSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var lite = false
    let day: ProgramDay?
    let hasUsablePrescription: Bool
    let isDeload: Bool
    let completed: Bool
    var onClose: () -> Void = {}
    let start: (Bool) -> Void

    private func exercises(lite wantsLite: Bool) -> [Exercise] {
        guard let day else { return [] }
        let requested = session.data.exercises
            .filter { $0.programDayID == day.id && $0.isLite == wantsLite }
            .sorted { $0.sortOrder < $1.sortOrder }
        let source: [Exercise]
        if requested.isEmpty, wantsLite {
            source = Array(session.data.exercises
                .filter { $0.programDayID == day.id && !$0.isLite }
                .sorted { $0.sortOrder < $1.sortOrder }
                .prefix(3))
        } else {
            source = requested
        }
        return TrainingAdjustmentEngine.adjustedExercises(source, isDeload: isDeload)
    }

    private var fullExercises: [Exercise] { exercises(lite: false) }
    private var liteExercises: [Exercise] { exercises(lite: true) }
    private var shown: [Exercise] { lite ? liteExercises : fullExercises }

    /* Web parity: est_minutes for the full day, timeline estimate for light */
    private var fullMinutes: Int {
        day?.estimatedMinutes ?? max(15, fullExercises.count * 8)
    }
    private var liteMinutes: Int { max(8, estimatedMinutes(liteExercises)) }
    private var shownMinutes: Int { lite ? liteMinutes : fullMinutes }

    private func estimatedMinutes(_ rows: [Exercise]) -> Int {
        var seconds = 60.0 // warm-up block
        for exercise in rows {
            let sets = Double(max(1, exercise.sets))
            let perRep = max(1.6, exercise.tempoUp + exercise.tempoDown + exercise.tempoPause + 0.4)
            let work: Double
            switch exercise.repUnit {
            case "seconds": work = Double((exercise.repMin + exercise.repMax) / 2)
            case "minutes": work = Double((exercise.repMin + exercise.repMax) / 2) * 60
            case "check": work = 30
            case "max": work = 12 * perRep
            default: work = Double(max(1, (exercise.repMin + exercise.repMax) / 2)) * perRep
            }
            seconds += sets * work
            seconds += Double(max(0, sets - 1)) * Double(exercise.restSeconds)
            seconds += 20 // logging
        }
        return max(1, Int((seconds / 60).rounded()))
    }

    private func prescription(_ exercise: Exercise) -> String {
        let reps: String
        switch exercise.repUnit {
        case "max": reps = language.text("MAX")
        case "seconds": reps = exercise.repMin == exercise.repMax ? "\(exercise.repMax)s" : "\(exercise.repMin)–\(exercise.repMax)s"
        case "minutes": reps = "\(exercise.repMax) min"
        case "check": reps = language.text("DONE")
        default: reps = exercise.repMin == exercise.repMax ? "\(exercise.repMax)" : "\(exercise.repMin)–\(exercise.repMax)"
        }
        let base = "\(exercise.sets) × \(reps)"
        return exercise.perSide ? base + " / " + language.text("side") : base
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(completed ? "Completed training" : "Training preview"))
                        .font(APEXFont.display(20))
                    if day != nil {
                        Text(language.format("%d exercises · %d min", shown.count, shownMinutes))
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                Spacer(minLength: 6)
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if let day {
                /* Prescription switch */
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { wantsLite in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { lite = wantsLite }
                        } label: {
                            Text(language.text(wantsLite ? "LIGHT PRESCRIPTION" : "FULL PRESCRIPTION"))
                                .font(APEXFont.mono(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(lite == wantsLite ? .white : APEXColor.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    lite == wantsLite
                                        ? AnyShapeStyle(APEXColor.green.gradient)
                                        : AnyShapeStyle(Color.clear),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(wantsLite ? "prescription-light" : "prescription-full")
                    }
                }
                .padding(3)
                .background(.white.opacity(0.6), in: Capsule())
                .padding(.top, 14)

                Group {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 9) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(APEXColor.teal.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.text(day.name)).font(APEXFont.display(16))
                                Text(language.format("%d min · %d exercises", shownMinutes, shown.count))
                                    .font(APEXFont.mono(10))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }

                        Text(language.text(lite
                            ? "The light prescription keeps the primary movements so a short day still counts."
                            : "This list is the exact Full prescription."))
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(APEXColor.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                        if isDeload {
                            Text(language.text("Deload week: one fewer set per exercise, 3 RIR, no tests or burnouts."))
                                .font(APEXFont.body(11, weight: .semibold))
                                .foregroundStyle(APEXColor.cyan)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(11)
                                .background(APEXColor.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                        }

                        Text(language.text("TODAY’S EXERCISES"))
                            .font(APEXFont.mono(10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(APEXColor.green)
                            .padding(.top, 2)

                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, exercise in
                            HStack(spacing: 11) {
                                Text("\(index + 1)")
                                    .font(APEXFont.mono(11, weight: .bold))
                                    .foregroundStyle(APEXColor.green)
                                    .frame(width: 22, height: 22)
                                    .background(APEXColor.green.opacity(0.13), in: Circle())
                                Text(language.text(exercise.name))
                                    .font(APEXFont.body(12, weight: .bold))
                                    .lineLimit(2)
                                Spacer(minLength: 6)
                                Text(prescription(exercise))
                                    .font(APEXFont.mono(11))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                }

                VStack(spacing: 9) {
                    Button {
                        dismiss(); start(false)
                    } label: {
                        Text(language.format("Start Full · %d min", fullMinutes))
                            .font(APEXFont.body(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(APEXColor.green.gradient, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("start-full")

                    Button {
                        dismiss(); start(true)
                    } label: {
                        Text(language.format("Start Light · %d min", liteMinutes))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(APEXColor.cyan.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("start-light")
                }
            } else if hasUsablePrescription {
                VStack(spacing: 14) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(APEXColor.teal.opacity(0.75))
                    Text(language.text("Recovery day"))
                        .font(APEXFont.display(21))
                    Text(language.text("No planned strength session today. Rest is part of the plan."))
                        .font(APEXFont.body(12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(APEXColor.secondaryInk)
                    Button { dismiss(); start(false) } label: {
                        Text(language.text("Open plan"))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(APEXColor.teal.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 38))
                        .foregroundStyle(APEXColor.teal.opacity(0.75))
                    Text(language.text("No training plan yet"))
                        .font(APEXFont.display(21))
                    Text(language.text("Build a plan before APEX labels any day as training or recovery."))
                        .font(APEXFont.body(12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(APEXColor.secondaryInk)
                    Button { dismiss(); start(false) } label: {
                        Text(language.text("Build plan"))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(APEXColor.teal.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct WearableActivityCard: View {
    @State private var language = LanguageState.shared
    @Environment(AppSession.self) private var session
    @State private var health = HealthKitManager.shared
    @State private var showEditor = false
    @AppStorage("apex.section.expanded.wearable") private var expanded = false
    let date: Date

    private var record: WearableActivityRecord? {
        let history = WearableActivityRecord.history(from: session.data.settings?.addons["watch_activity_history"])
        return history.last { $0.date == date.apexDateKey }
    }
    private var level: ActivityLevel {
        guard let record else { return .sedentary }
        return WearableActivityEngine.suggestedLevel(persona: session.profile?.persona ?? .constantine, steps: record.steps, activeCalories: record.activeCalories, exerciseMinutes: record.exerciseMinutes)
    }

    var body: some View {
        GlassCard(radius: 25, padding: 16) {
            VStack(alignment: .leading, spacing: expanded ? 11 : 0) {
                /* Collapsed to its name by default. Steps and mode are
                   reference, not something acted on every day. */
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("Wearable activity"))
                                .font(APEXFont.display(18))
                                .foregroundStyle(APEXColor.ink)
                            if let record {
                                Text(
                                    "\(record.steps.formatted()) \(language.text("Steps").lowercased(with: language.language.locale))"
                                        + " · \(record.activeCalories.formatted()) \(language.text("Active kcal"))"
                                        + " · \(record.exerciseMinutes.formatted()) \(language.text("Exercise min"))"
                                )
                                .font(APEXFont.body(9, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wearable-activity-toggle")

                if expanded {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.map { "\($0.steps.formatted()) steps · \(level.title)" } ?? "No wearable data for this day")
                            .font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Button { showEditor = true } label: { Image(systemName: record == nil ? "plus" : "pencil") }.buttonStyle(.bordered)
                }
                if let record {
                    HStack(spacing: 8) {
                        wearableMetric("Steps", record.steps)
                        wearableMetric("Active kcal", record.activeCalories)
                        wearableMetric("Exercise min", record.exerciseMinutes)
                    }
                    Button("Use \(level.title)") {
                        guard let operation = session.accountOperationLease() else { return }
                        Task {
                            do {
                                try await session.setActivityLevel(level, operation: operation)
                            } catch is CancellationError {
                                return
                            } catch {
                                return
                            }
                        }
                    }
                        .buttonStyle(.borderedProminent).tint(APEXColor.cyan)
                } else if date.apexDateKey == Date().apexDateKey {
                    Button(
                        session.healthImportIsEnabledForCurrentAccount
                            ? "Refresh Apple Health" : "Connect Apple Health"
                    ) {
                        guard let operation = session.accountOperationLease() else { return }
                        Task { _ = await session.connectHealth(operation: operation) }
                    }.buttonStyle(.borderedProminent).tint(APEXColor.cyan)
                }
                } // end expanded
            }
        }
        .sheet(isPresented: $showEditor) { WearableActivityEditor(date: date, existing: record).presentationDetents([.medium]) }
    }

    private func wearableMetric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 3) { Text(value.formatted()).font(APEXFont.mono(12)); Text(label).font(APEXFont.body(8)).foregroundStyle(APEXColor.secondaryInk) }
            .frame(maxWidth: .infinity).padding(.vertical, 10).background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct WearableActivityEditor: View {
    @State private var language = LanguageState.shared
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let existing: WearableActivityRecord?
    @State private var steps = ""
    @State private var calories = ""
    @State private var minutes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(language.text("Wearable activity")).font(APEXFont.display(25))
            HStack { field("Steps", text: $steps); field("Active kcal", text: $calories); field("Exercise min", text: $minutes) }
            Button(language.text("Save and use suggested mode")) {
                let record = WearableActivityRecord(date: date.apexDateKey, steps: Int(steps) ?? 0, activeCalories: Int(calories) ?? 0, exerciseMinutes: Int(minutes) ?? 0, source: "manual", updatedAt: Date().ISO8601Format())
                guard let operation = session.accountOperationLease() else { return }
                Task { [record] in
                    await session.saveWearableActivity(
                        record,
                        automaticallyApply: true,
                        operation: operation
                    )
                    guard session.accountOperationIsCurrent(operation) else { return }
                    dismiss()
                }
            }.buttonStyle(.borderedProminent).tint(APEXColor.cyan).frame(maxWidth: .infinity)
        }.padding(22).onAppear { steps = existing.map { String($0.steps) } ?? ""; calories = existing.map { String($0.activeCalories) } ?? ""; minutes = existing.map { String($0.exerciseMinutes) } ?? "" }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(label).font(APEXFont.body(9, weight: .bold)); TextField("0", text: text).keyboardType(.numberPad).font(APEXFont.mono(14)).padding(11).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13)) }
    }
}

private struct RecoveryMorningCard: View {
    @Environment(AppSession.self) private var session
    @State private var health = HealthKitManager.shared
    @State private var language = LanguageState.shared
    @State private var sleep = ""
    @State private var recovery = ""
    @State private var weight = ""
    @State private var expanded = false
    @FocusState private var morningFieldFocused: Bool
    let date: Date
    private var source: String { session.data.settings?.addons["recovery_data_source"]?.stringValue ?? "apple" }
    private var weightUnit: WeightUnit { .current(session.data.settings) }
    private var importedSleepHours: Double? {
        RecoveryAssessment.sleepDurationHours(session.data, date: date.apexDateKey)
    }

    /* Today's explicit vendor score, if one was recorded. */
    private var checkin: RecoveryAssessment.Checkin? {
        RecoveryAssessment.todaysCheckin(session.data, date: date.apexDateKey)
    }

    private var verdict: RecoveryAssessment.Verdict? {
        checkin.map { RecoveryAssessment.assess($0) }
    }

    private var headlineScore: Int? {
        guard let checkin else { return nil }
        return source == "other" ? checkin.recoveryPercent : checkin.sleepScore
    }

    private var statusTint: Color {
        switch verdict?.state {
        case .strong: APEXColor.green
        case .normal: APEXColor.cyan
        case .low: APEXColor.amberDeep
        case .veryLow: APEXColor.danger
        case nil: APEXColor.secondaryInk
        }
    }

    var body: some View {
        /* Always a single thin line until it is asked to open. It is the first
           thing on the page every day, and an unanswered question was costing
           half the first screen: the editor used to force itself open whenever
           no score had arrived yet, which is most mornings before the watch
           syncs. The arrow is how you get to it instead. */
        GlassCard(radius: 18, padding: expanded ? 14 : 9) {
            VStack(alignment: .leading, spacing: 9) {
                summary
                if expanded { editor }
            }
        }
        .onAppear { load() }
        .animation(.snappy(duration: 0.22), value: expanded)
    }

    private var summary: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 9) {
                Text(language.text("Morning check"))
                    .font(APEXFont.display(expanded ? 17 : 14))
                    .foregroundStyle(APEXColor.ink)
                    .lineLimit(1)
                    .fixedSize()

                /* Collapsed, the line carries only what it can prove: the
                   score if the watch supplied one, and nothing at all if it
                   did not. The subtitle moves inside the editor, where there
                   is room for it. */
                if expanded {
                    Text(collapsedSubtitle)
                        .font(APEXFont.body(9, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if let headlineScore {
                    Text("\(headlineScore)")
                        .font(APEXFont.mono(15, weight: .bold))
                        .foregroundStyle(statusTint)
                    if let state = verdict?.state {
                        /* One word at a glance. The full verdict sentence keeps
                           its place in the body signals panel. */
                        Text(language.text(stateLabel(state)).uppercased())
                            .font(APEXFont.mono(8))
                            .tracking(0.9)
                            .foregroundStyle(statusTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(statusTint.opacity(0.12), in: Capsule())
                    }
                } else if let importedSleepHours {
                    Text(language.format("%.1f h", importedSleepHours))
                        .font(APEXFont.mono(15, weight: .bold))
                        .foregroundStyle(APEXColor.cyan)
                    Text(language.text("Sleep").uppercased(with: language.language.locale))
                        .font(APEXFont.mono(8))
                        .tracking(0.9)
                        .foregroundStyle(APEXColor.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(APEXColor.cyan.opacity(0.12), in: Capsule())
                } else {
                    /* No score or measured sleep fact yet. Say so in one word
                       rather than opening a form nobody asked for. */
                    Text(language.text(health.isAuthorized ? "Waiting" : "Tap to add"))
                        .font(APEXFont.mono(8))
                        .tracking(0.9)
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("morning-check-summary")
        .accessibilityLabel(summaryAccessibilityLabel)
        .accessibilityHint(headlineScore == nil ? "" : language.text(expanded ? "Collapse" : "Edit the score"))
    }

    private var summaryAccessibilityLabel: String {
        if let headlineScore { return language.format("Morning check, %d", headlineScore) }
        if let importedSleepHours { return language.format("Morning check, %.1f hours sleep", importedSleepHours) }
        return language.text("Morning check")
    }

    private func stateLabel(_ state: RecoveryAssessment.State) -> String {
        switch state {
        case .strong: "Strong"
        case .normal: "Steady"
        case .low: "Low"
        case .veryLow: "Very low"
        }
    }

    private var collapsedSubtitle: String {
        if let hours = importedSleepHours {
            return String(format: language.text("%@ Health sleep: %.1f h"), source == "other" ? language.text("Your device") : "Apple", hours)
        }
        return language.text(source == "other" ? "Recovery score" : "Apple Health sleep")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                scoreField(
                    language.text(source == "other" ? "Sleep" : "Watch Sleep Score"),
                    text: $sleep,
                    identifier: "morning-sleep-score"
                )
                if source == "other" {
                    scoreField("Recovery", text: $recovery, identifier: "morning-recovery-score")
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("Morning weight"))
                    .font(APEXFont.body(9, weight: .bold))
                HStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .foregroundStyle(APEXColor.cyan)
                    TextField(language.text("Weight"), text: $weight)
                        .keyboardType(.decimalPad)
                        .focused($morningFieldFocused)
                        .accessibilityIdentifier("morning-weight")
                        .font(APEXFont.mono(15))
                    Text(weightUnit.suffix)
                        .font(APEXFont.mono(11, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .padding(11)
                .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 14))
            }
            Text(language.text(source == "other" ? "Enter the 0 to 100 score your own watch or app gives you. Apple Health context is still imported automatically." : "HealthKit exposes measured sleep duration and stages, but not Apple's Sleep Score to third-party apps. Enter the score shown in the Sleep app to use it in APEX."))
                .font(APEXFont.body(9)).foregroundStyle(APEXColor.secondaryInk)
            Button(language.text("Save morning check")) {
                morningFieldFocused = false
                save()
                expanded = false
            }
                .accessibilityIdentifier("morning-save")
                .buttonStyle(.borderedProminent)
                .tint(APEXColor.green)
                .controlSize(.small)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(language.text("Done")) { morningFieldFocused = false }
                    .accessibilityIdentifier("morning-keyboard-dismiss")
            }
        }
    }
    private func scoreField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(APEXFont.body(9, weight: .bold)); TextField("%", text: text).keyboardType(.numberPad).focused($morningFieldFocused).accessibilityIdentifier(identifier).font(APEXFont.mono(15)).multilineTextAlignment(.center).padding(11).background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 14)) }
    }
    private func load() {
        if let kilograms = session.data.dailyLogs.last(where: { $0.date == date.apexDateKey })?.weightKG {
            let displayed = weightUnit.value(fromKilograms: kilograms)
            weight = displayed.formatted(
                .number.precision(.fractionLength(1)).locale(language.language.locale)
            )
        } else {
            weight = ""
        }
        let history = session.data.settings?.addons["recovery_history"]?.arrayValue ?? []
        guard let row = history.compactMap(\.objectValue).last(where: { $0["date"]?.stringValue == date.apexDateKey }) else {
            sleep = ""
            recovery = ""
            return
        }
        let sleepKey = source == "other" ? "sleep_pct" : "sleep_score"
        sleep = row[sleepKey]?.numberValue.map { String(Int($0)) } ?? ""
        recovery = row["recovery_pct"]?.numberValue.map { String(Int($0)) } ?? ""
    }
    private func save() {
        guard let entry = MorningCheckLogic.entry(
            sleep: sleep,
            recovery: recovery,
            weight: weight,
            source: source,
            weightUnit: weightUnit
        ), let operation = session.accountOperationLease() else { return }
        Task {
            do {
                if let weightKG = entry.weightKG {
                    try await session.saveMorningWeight(
                        weightKG,
                        on: date,
                        operation: operation
                    )
                }
                guard let sleepValue = entry.sleepScore else { return }
                try await session.updateSettings({ settings in
                    var rows = settings.addons["recovery_history"]?.arrayValue ?? []
                    rows.removeAll { $0.objectValue?["date"]?.stringValue == date.apexDateKey }
                    rows.append(.object([
                        "date": .string(date.apexDateKey),
                        "source": .string(source),
                        "sleep_score": source == "apple" ? .number(sleepValue) : .null,
                        "sleep_pct": source == "other" ? .number(sleepValue) : .null,
                        "recovery_pct": source == "other" ? (entry.recoveryScore.map(JSONValue.number) ?? .null) : .null,
                        "updated_at": .string(Date().ISO8601Format()),
                    ]))
                    settings.addons["recovery_history"] = .array(Array(rows.suffix(730)))
                }, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }
}

private struct SimpleTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(APEXColor.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(.white.opacity(configuration.isPressed ? 0.42 : 0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.85)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/*
 * Picking a supplement from the catalogue instead of typing one.
 *
 * Typing a name in by hand meant remembering how it is spelled and guessing a
 * dose, and produced a stack full of near-duplicates: "Ashwaganda", "ashwa",
 * "Ashwagandha KSM-66". The catalogue gives one canonical name per supplement,
 * the sizes it is actually sold in, and a straight answer about how well
 * supported it is -- including for the ones that are not.
 */
private struct SupplementPickerSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var query = ""
    let onAdd: (SupplementCatalogue.Entry, Double) -> Void

    private var results: [SupplementCatalogue.Entry] {
        SupplementCatalogue.search(query, age: session.profile?.age ?? 0)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, results.count >= 2 {
                    Section(language.text("Core evidence")) {
                        ForEach(Array(results.prefix(2))) { entry in
                            pickerRow(entry)
                        }
                    }
                    Section(language.text("A to Z catalogue")) {
                        ForEach(Array(results.dropFirst(2))) { entry in
                            pickerRow(entry)
                        }
                    }
                } else {
                    ForEach(results) { entry in
                        pickerRow(entry)
                    }
                }

                if results.isEmpty {
                    Text(language.text("Nothing matches that. You can still add it by name from the full editor."))
                        .font(APEXFont.body(12))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(APEXBackground())
            .searchable(text: $query, prompt: Text(language.text("Search supplements")))
            .navigationTitle(language.text("Add supplement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerRow(_ entry: SupplementCatalogue.Entry) -> some View {
        SupplementPickerRow(
            entry: entry,
            isFemale: (session.profile?.sex ?? "").lowercased().hasPrefix("f"),
            isUnderEighteen: (session.profile?.age ?? 0) > 0 && (session.profile?.age ?? 0) < 18,
            onAdd: { dose in
                onAdd(entry, dose)
                dismiss()
            }
        )
        .listRowBackground(Color.clear)
    }
}

/*
 * One supplement in the picker.
 *
 * Its own view because the row carries a lot: the name, an information icon,
 * a sex-specific caution where one is genuinely documented, two ready-made
 * doses and a third that takes whatever is printed on the tub.
 */
private struct SupplementPickerRow: View {
    @State private var language = LanguageState.shared
    let entry: SupplementCatalogue.Entry
    let isFemale: Bool
    let isUnderEighteen: Bool
    let onAdd: (Double) -> Void

    @State private var showInfo = false
    @State private var showWarning = false
    @State private var chosen: Double?
    @State private var custom = ""
    @State private var typingCustom = false
    @FocusState private var customFocused: Bool

    private var warning: String? { isFemale ? entry.femaleWarning : nil }

    private var dose: Double {
        if typingCustom, let value = Double(custom), value > 0 { return value }
        return chosen ?? entry.presetDoses.first ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if showInfo { infoPanel }
            if showWarning, let warning { warningPanel(warning) }
            doseRow
            if typingCustom { customField }
        }
        .padding(.vertical, 5)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(entry.name))
                    .font(APEXFont.body(15, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text(entry.category))
                    .font(APEXFont.body(10))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.format("What %@ does", language.text(entry.name)))

            /* Shown only where there is a documented, sex-specific reason.
               Most supplements have none, and a warning on everything would
               be noise that teaches people to ignore the ones that matter. */
            if warning != nil {
                Button {
                    showWarning.toggle()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("Caution for women"))
            }
            Spacer(minLength: 0)
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(entry.evidenceLabel))
                .font(APEXFont.mono(9))
                .tracking(1.1)
                .foregroundStyle(evidenceColor)
            Text(language.text(entry.summary))
                .font(APEXFont.body(12))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let note = entry.youthNote, isUnderEighteen {
                Text(language.text(note))
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
    }

    private func warningPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text("Caution for women"))
                .font(APEXFont.mono(9))
                .tracking(1.1)
                .foregroundStyle(.orange)
            Text(language.text(text))
                .font(APEXFont.body(12))
                .foregroundStyle(APEXColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
    }

    private var doseRow: some View {
        HStack(spacing: 7) {
            ForEach(entry.presetDoses, id: \.self) { value in
                dosePill(
                    label: entry.formattedDose(value),
                    selected: !typingCustom && (chosen ?? entry.presetDoses.first) == value
                ) {
                    chosen = value
                    typingCustom = false
                }
            }
            /* The third pill is a way in rather than a size. Brands differ
               enough that a fixed list is always wrong for somebody, and
               asking for the brand name to get a number would be worse. */
            dosePill(
                label: typingCustom && !custom.isEmpty ? "\(custom) \(entry.unit)" : language.text("Yours"),
                selected: typingCustom
            ) {
                typingCustom = true
                customFocused = true
            }
            Spacer(minLength: 0)
            Button {
                onAdd(dose)
            } label: {
                Text(language.text("Add"))
                    .font(APEXFont.body(12, weight: .bold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(APEXColor.green, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(dose <= 0)
        }
    }

    private var customField: some View {
        HStack(spacing: 8) {
            TextField(language.format("Amount in %@", entry.unit), text: $custom)
                .keyboardType(.decimalPad)
                .focused($customFocused)
                .font(APEXFont.mono(13))
                .padding(10)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            Button(language.text("Clear")) {
                custom = ""
                typingCustom = false
                customFocused = false
            }
            .font(APEXFont.body(11, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(APEXColor.secondaryInk)
        }
    }

    private func dosePill(label: String, selected: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(APEXFont.mono(10))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    selected ? APEXColor.green.opacity(0.16) : .white.opacity(0.55),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(
                    selected ? APEXColor.green.opacity(0.5) : APEXColor.ink.opacity(0.07)
                ))
                .foregroundStyle(selected ? APEXColor.green : APEXColor.secondaryInk)
        }
        .buttonStyle(.plain)
    }

    private var evidenceColor: Color {
        switch entry.evidence {
        case "strong": return APEXColor.green
        case "moderate": return APEXColor.ink
        case "limited": return APEXColor.secondaryInk
        default: return .orange
        }
    }
}
