import SwiftUI

struct SimpleHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var showChecklist = false
    @State private var showWorkout = false
    @State private var workoutIsLite = false
    @State private var selectedDate = Date()
    @State private var showTargetEditor = false
    @State private var showCalendar = false
    @State private var showMealSlotPicker = false
    @State private var composerRequest: MealComposerRequest?
    @State private var health = HealthKitManager.shared
    @State private var quickPanel: SimpleQuickPanel?

    private let waterTargetL = 2.75

    private var today: String { selectedDate.apexDateKey }
    private var profile: Profile? { session.profile }
    private var meals: [Meal] { session.data.meals.sorted { $0.sortOrder < $1.sortOrder } }
    private var activities: [ActivityLog] { session.data.activityLogs.filter { $0.date == today } }
    private var targets: NutritionTargets? {
        guard let profile else { return nil }
        return EnergyEngine.targets(profile: profile, logs: activities, catalog: session.data.activityTypes)
    }
    private var adaptivePlan: [AdaptiveMeal] {
        guard let targets else { return [] }
        return AdaptiveMealPlanEngine.build(
            meals: meals,
            targets: targets,
            dayLabel: targets.level.title
        )
    }
    private var dailyLog: DailyLog? { session.data.dailyLogs.first { $0.date == today } }
    private var waterL: Double { dailyLog?.waterL ?? 0 }
    private var waterDone: Bool { waterL >= waterTargetL * 0.9 }

    private var supplementGroups: [SimpleSupplementGroup] {
        let grouped = Dictionary(grouping: session.data.supplements, by: \.groupLabel)
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

    private var transitionProgram: Program? { session.data.programs.first { $0.slug == "transition" } }
    private var todayWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        return weekday == 1 ? 7 : weekday - 1
    }
    private var todayProgramDay: ProgramDay? {
        guard let transitionProgram else { return nil }
        return session.data.programDays.first {
            $0.programID == transitionProgram.id && $0.weekday == todayWeekday
        }
    }
    private var workoutDone: Bool {
        guard let todayProgramDay else { return true }
        return session.data.workoutSessions.contains {
            $0.date == today && $0.programDayID == todayProgramDay.id && $0.completed
        }
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
    private var completedSupplementCount: Int { supplementGroups.filter(groupDone).count }
    private var totalTasks: Int {
        meals.count + supplementGroups.count + 1 + (todayProgramDay == nil ? 0 : 1)
    }
    private var completedTasks: Int {
        completedMealCount + completedSupplementCount + (waterDone ? 1 : 0) + (todayProgramDay == nil ? 0 : workoutDone ? 1 : 0)
    }
    private var completion: Int { SimpleHomeLogic.completion(completed: completedTasks, total: totalTasks) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                APEXTopBar(profile: profile) {
                    session.navigationPath.append(.settings)
                }

                HStack {
                    PortalModeSwitcher()
                    Spacer()
                    Text("ONE TAP FLOW")
                        .font(APEXFont.mono(9))
                        .tracking(1.1)
                        .foregroundStyle(APEXColor.secondaryInk)
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

            ScrollView {
                LazyVStack(spacing: 15) {
                    simpleHeader

                    RecoveryMorningCard(date: selectedDate)

                    if let targets {
                        NutritionGlanceCard(
                            date: selectedDate,
                            targets: targets,
                            onEditTargets: { showTargetEditor = true },
                            onOpenCalendar: { showCalendar = true }
                        )
                        APEXDaylineView(
                            date: selectedDate,
                            onOpenComposer: { composerRequest = $0 },
                            onAddMeal: { showMealSlotPicker = true },
                            compact: false
                        )
                    }

                    if let action = nextAction {
                        NextActionCard(action: action) {
                            perform(action.kind)
                        }
                    }

                    metrics
                    WearableActivityCard(date: selectedDate)
                    checklist

                    if let todayProgramDay, !workoutDone {
                        workoutShortcut(day: todayProgramDay)
                    }

                    orbitShortcut
                    avatarShortcut
                    fullDetailShortcuts

                    HStack {
                        PortalLanguagePicker()
                        Spacer()
                        if session.pendingSyncCount > 0 {
                            Label(language.format("%d queued", session.pendingSyncCount), systemImage: "icloud.and.arrow.up")
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.amberDeep)
                        } else {
                            Label("Synced", systemImage: "checkmark.icloud")
                                .font(APEXFont.mono(9))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 38)
            }
            .refreshable { await session.refresh() }
        }
        .apexEdgeDateSwipe(onPrevious: { changeDate(-1) }, onNext: { changeDate(1) })
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showWorkout) {
            if let todayProgramDay {
                WorkoutPlayerView(
                    day: todayProgramDay,
                    exercises: workoutExercises,
                    accent: APEXColor.teal,
                    lite: workoutIsLite
                )
            }
        }
        .sheet(isPresented: $showTargetEditor) {
            NutritionTargetSheet(date: selectedDate)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCalendar) {
            NutritionCalendarSheet(selectedDate: selectedDate) { selectedDate = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMealSlotPicker) {
            MealSlotPickerSheet(date: selectedDate) { composerRequest = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $quickPanel) { panel in
            switch panel {
            case .water:
                WaterQuickAddSheet(currentLiters: waterL, targetLiters: waterTargetL) { liters in
                    addWater(liters)
                }
                .presentationDetents([.medium])
            case .supplements:
                SupplementQuickSheet(date: selectedDate)
                    .presentationDetents([.large])
            case .stats:
                StatsQuickSheet(date: selectedDate)
                    .presentationDetents([.medium])
            case .training:
                TrainingQuickSheet(day: todayProgramDay) { lite in
                    guard todayProgramDay != nil else {
                        session.navigationPath.append(.transition)
                        return
                    }
                    workoutIsLite = lite
                    showWorkout = true
                }
                .presentationDetents([.medium])
            }
        }
        .fullScreenCover(item: $composerRequest) { request in
            MealComposerView(request: request)
        }
    }

    private var simpleHeader: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(language.format("Today, %@.", profile?.displayName.components(separatedBy: " ").first ?? "APEX"))
                    .font(APEXFont.display(31))
                    .minimumScaleFactor(0.8)
                Text("Only what matters. One tap at a time.")
                    .font(APEXFont.body(13, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Spacer(minLength: 4)
            CompletionRing(value: completion)
        }
        .padding(.vertical, 17)
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
            SimpleMetric(
                icon: "sparkles",
                value: "\(completedSupplementCount)/\(supplementGroups.count)",
                label: "Supps",
                done: !supplementGroups.isEmpty && completedSupplementCount == supplementGroups.count,
                color: APEXColor.violet,
                action: { quickPanel = .supplements }
            )
            SimpleMetric(
                icon: "chart.xyaxis.line",
                value: latestSnapshot.map { String(Int($0.overall.rounded())) } ?? "—",
                label: "Stats",
                done: false,
                color: APEXColor.green,
                action: { quickPanel = .stats }
            )
            SimpleMetric(
                icon: "figure.strengthtraining.traditional",
                value: todayProgramDay == nil ? language.text("Rest") : workoutDone ? language.text("Done") : todayProgramDay.map { "\($0.estimatedMinutes)m" } ?? language.text("Rest"),
                label: "Training",
                done: workoutDone,
                color: APEXColor.teal,
                action: { quickPanel = .training }
            )
        }
    }

    private var checklist: some View {
        GlassCard(radius: 25, padding: 16) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) { showChecklist.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Today’s checklist")
                                .font(APEXFont.display(18))
                            Text(language.format("%d of %d essentials complete", completedTasks, totalTasks))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: showChecklist ? "minus" : "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .buttonStyle(.plain)

                if showChecklist {
                    Divider().padding(.vertical, 13)
                    VStack(spacing: 8) {
                        ForEach(adaptivePlan) { prescription in
                            let meal = prescription.source
                            SimpleChecklistRow(
                                time: meal.time,
                                title: language.text(meal.name),
                                detail: language.format("%d kcal", prescription.kcal),
                                done: mealDone(meal)
                            ) {
                                Task { await session.togglePlannedMeal(prescription) }
                            }
                        }
                        ForEach(supplementGroups) { group in
                            SimpleChecklistRow(
                                time: clock(group.timeMinutes),
                                title: language.text(group.label),
                                detail: language.format("%d supplements", group.supplements.count),
                                done: groupDone(group)
                            ) {
                                Task { await toggle(group) }
                            }
                        }
                        SimpleChecklistRow(
                            time: language.text("NOW"),
                            title: language.text("Water"),
                            detail: language.format("%.2f / %.2f L", waterL, waterTargetL),
                            done: waterDone,
                            action: { addWater() }
                        )
                        if let todayProgramDay {
                            SimpleChecklistRow(
                                time: profile?.trainingTime ?? "19:00",
                                title: language.text(todayProgramDay.name),
                                detail: language.format("%d min", todayProgramDay.estimatedMinutes),
                                done: workoutDone
                            ) {
                                workoutIsLite = false
                                showWorkout = true
                            }
                        }
                    }
                }
            }
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
                    Text("Start directly. Skip calendar and setup.")
                        .font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer(minLength: 2)
                VStack(spacing: 6) {
                    Button("Quick") {
                        workoutIsLite = true
                        showWorkout = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Start") {
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

    private var fullDetailShortcuts: some View {
        HStack(spacing: 9) {
            Button("Food or activity changed?") { session.navigationPath.append(.nutrition) }
            Button("Open full schedule") { session.navigationPath.append(.transition) }
        }
        .font(APEXFont.body(11, weight: .bold))
        .buttonStyle(SimpleTextButtonStyle())
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
        if OrbitLocationManager.shared.hasRecoverableRun { return language.text("Continue interrupted run") }
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
            Task { await session.togglePlannedMeal(prescription) }
        case .supplements(let id):
            guard let group = supplementGroups.first(where: { $0.id == id }) else { return }
            Task { await toggle(group) }
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

    private func toggle(_ group: SimpleSupplementGroup) async {
        let completed = groupDone(group)
        for supplement in group.supplements {
            let isDone = session.data.supplementLogs.contains {
                $0.date == today && $0.supplementID == supplement.id
            }
            if completed || !isDone {
                await session.toggleSupplement(supplement)
            }
        }
    }

    private func addWater(_ liters: Double = 0.25) {
        guard let profile, let targets else { return }
        var row = dailyLog ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: today, userID: profile.userID),
            userID: profile.userID, date: today,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: targets.tdee, computedPAL: targets.pal,
            activityMode: activities.isEmpty ? "quick" : "precise", weightKG: nil
        )
        let added = max(0, min(liters, 6 - row.waterL))
        guard added > 0 else { return }
        row.waterL = min(6, ((row.waterL + added) * 100).rounded() / 100)
        Task {
            await session.updateDailyLog(row)
            try? await health.saveWater(liters: added, date: selectedDate)
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
        }
        .frame(width: 63, height: 63)
        .accessibilityLabel("Daily completion")
        .accessibilityValue("\(value) percent")
    }
}

private struct SimpleMetric: View {
    @State private var language = LanguageState.shared
    let icon: String
    let value: String
    let label: String
    let done: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        VStack(spacing: 5) {
            Image(systemName: done ? "checkmark" : icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(done ? .white : color)
                .frame(width: 27, height: 27)
                .background(done ? APEXColor.green : color.opacity(0.11), in: Circle())
            Text(value)
                .font(APEXFont.mono(9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(language.text(label).uppercased(with: language.language.locale))
                .font(APEXFont.mono(7))
                .tracking(0.4)
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(.ultraThinMaterial.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(done ? APEXColor.green.opacity(0.26) : .white.opacity(0.82)))
        }
        .buttonStyle(.plain)
    }
}

private struct SimpleChecklistRow: View {
    let time: String
    let title: String
    let detail: String
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: done ? "checkmark" : "circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(done ? .white : APEXColor.secondaryInk.opacity(0.42))
                    .frame(width: 29, height: 29)
                    .background(done ? APEXColor.green : .clear, in: Circle())
                    .overlay(Circle().stroke(done ? Color.clear : APEXColor.ink.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(APEXFont.body(13, weight: .bold))
                        .foregroundStyle(done ? APEXColor.secondaryInk : APEXColor.ink)
                        .strikethrough(done)
                    Text(detail)
                        .font(APEXFont.body(9, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                Text(time)
                    .font(APEXFont.mono(8))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 51)
            .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SimpleShortcutCard: View {
    @State private var language = LanguageState.shared
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
                Text(language.text(subtitle))
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
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
}

enum WearableActivityEngine {
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
    @Environment(\.dismiss) private var dismiss
    let currentLiters: Double
    let targetLiters: Double
    let add: (Double) -> Void
    @State private var customML = ""

    var body: some View {
        VStack(spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Water quick add").font(APEXFont.display(25))
                    Text(String(format: "%.2f / %.2f L", currentLiters, targetLiters))
                        .font(APEXFont.body(12, weight: .semibold)).foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                HydrationFigureView(progress: min(1, currentLiters / targetLiters))
                    .frame(width: 62, height: 96)
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach([250, 300, 500], id: \.self) { amount in
                    quickButton("\(amount) ml") { add(Double(amount) / 1_000); dismiss() }
                }
                TextField("Custom ml", text: $customML)
                    .keyboardType(.numberPad).font(APEXFont.mono(14)).multilineTextAlignment(.center)
                    .frame(minHeight: 54).background(APEXColor.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
                    .onSubmit { addCustom() }
            }
            Button("Add custom amount") { addCustom() }
                .buttonStyle(.borderedProminent).tint(APEXColor.cyan).disabled(Double(customML) == nil)
        }
        .padding(22)
        .presentationBackground(.ultraThinMaterial)
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(APEXFont.mono(13)).frame(maxWidth: .infinity, minHeight: 54)
            .background(APEXColor.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 17)).buttonStyle(.plain)
    }
    private func addCustom() {
        guard let ml = Double(customML), ml > 0 else { return }
        add(min(3_000, ml) / 1_000); dismiss()
    }
}

private struct HydrationFigureView: View {
    let progress: Double
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HydrationBodyShape().fill(APEXColor.ink.opacity(0.08))
                Rectangle()
                    .fill(LinearGradient(colors: [APEXColor.cyan, .blue.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height * progress)
                    .offset(x: phase ? 2 : -2)
                    .mask(HydrationBodyShape())
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: phase)
                HydrationBodyShape().stroke(APEXColor.cyan.opacity(0.62), lineWidth: 1.4)
            }
            .onAppear { phase = true }
        }
        .accessibilityLabel("Hydration level")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct HydrationBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        p.addEllipse(in: CGRect(x: cx - rect.width * 0.13, y: rect.minY, width: rect.width * 0.26, height: rect.width * 0.26))
        p.addRoundedRect(in: CGRect(x: cx - rect.width * 0.19, y: rect.height * 0.23, width: rect.width * 0.38, height: rect.height * 0.42), cornerSize: CGSize(width: 12, height: 12))
        p.addRoundedRect(in: CGRect(x: cx - rect.width * 0.34, y: rect.height * 0.26, width: rect.width * 0.13, height: rect.height * 0.46), cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(in: CGRect(x: cx + rect.width * 0.21, y: rect.height * 0.26, width: rect.width * 0.13, height: rect.height * 0.46), cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(in: CGRect(x: cx - rect.width * 0.18, y: rect.height * 0.61, width: rect.width * 0.15, height: rect.height * 0.38), cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(in: CGRect(x: cx + rect.width * 0.03, y: rect.height * 0.61, width: rect.width * 0.15, height: rect.height * 0.38), cornerSize: CGSize(width: 8, height: 8))
        return p
    }
}

private struct SupplementQuickSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date

    var body: some View {
        NavigationStack {
            List(session.data.supplements.sorted { $0.sortOrder < $1.sortOrder }) { supplement in
                let done = session.data.supplementLogs.contains { $0.date == date.apexDateKey && $0.supplementID == supplement.id }
                Button { Task { await session.toggleSupplement(supplement, on: date) } } label: {
                    HStack {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? APEXColor.green : APEXColor.secondaryInk)
                        VStack(alignment: .leading) {
                            Text(supplement.name).font(APEXFont.body(14, weight: .bold))
                            Text("\(supplement.dose) · \(supplement.groupLabel)").font(APEXFont.body(10)).foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                }.buttonStyle(.plain)
            }
            .navigationTitle("Supplement stack")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct StatsQuickSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date
    private var snapshot: RPGSnapshot? { session.data.snapshots.filter { $0.date <= date.apexDateKey }.max { $0.date < $1.date } }

    var body: some View {
        VStack(spacing: 16) {
            Text("Body signals").font(APEXFont.display(26))
            if let snapshot {
                Text(String(Int(snapshot.overall.rounded()))).font(APEXFont.mono(54)).foregroundStyle(APEXColor.green)
                Text("Overall Fitness Level").font(APEXFont.body(13, weight: .bold))
            } else { ContentUnavailableView("No stats yet", systemImage: "chart.xyaxis.line") }
            Button("Open full Avatar") { dismiss(); session.navigationPath.append(.avatar) }
                .buttonStyle(.borderedProminent).tint(APEXColor.green)
        }.padding(24).presentationBackground(.ultraThinMaterial)
    }
}

private struct TrainingQuickSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: ProgramDay?
    let start: (Bool) -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 42)).foregroundStyle(APEXColor.teal)
            Text(day?.name ?? "Recovery day").font(APEXFont.display(26))
            Text(day.map { "\($0.estimatedMinutes) min planned" } ?? "No planned strength session today")
                .font(APEXFont.body(12)).foregroundStyle(APEXColor.secondaryInk)
            HStack {
                Button("Open plan") { dismiss(); start(false) }.buttonStyle(.bordered)
                if day != nil { Button("Quick start") { dismiss(); start(true) }.buttonStyle(.borderedProminent).tint(APEXColor.teal) }
            }
        }.padding(24).presentationBackground(.ultraThinMaterial)
    }
}

private struct WearableActivityCard: View {
    @Environment(AppSession.self) private var session
    @State private var health = HealthKitManager.shared
    @State private var showEditor = false
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
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wearable activity").font(APEXFont.display(18))
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
                    Button("Use \(level.title)") { Task { await session.setActivityLevel(level) } }
                        .buttonStyle(.borderedProminent).tint(APEXColor.cyan)
                } else if date.apexDateKey == Date().apexDateKey {
                    Button(health.isAuthorized ? "Refresh Apple Health" : "Connect Apple Health") {
                        Task { if let snapshot = await health.requestAccessAndImport() { await session.applyHealthSnapshot(snapshot) } }
                    }.buttonStyle(.borderedProminent).tint(APEXColor.cyan)
                }
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
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let existing: WearableActivityRecord?
    @State private var steps = ""
    @State private var calories = ""
    @State private var minutes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Wearable activity").font(APEXFont.display(25))
            HStack { field("Steps", text: $steps); field("Active kcal", text: $calories); field("Exercise min", text: $minutes) }
            Button("Save and use suggested mode") {
                let record = WearableActivityRecord(date: date.apexDateKey, steps: Int(steps) ?? 0, activeCalories: Int(calories) ?? 0, exerciseMinutes: Int(minutes) ?? 0, source: "manual", updatedAt: Date().ISO8601Format())
                Task { await session.saveWearableActivity(record, automaticallyApply: true); dismiss() }
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
    @State private var sleep = ""
    @State private var recovery = ""
    let date: Date
    private var source: String { session.data.settings?.addons["recovery_data_source"]?.stringValue ?? "apple" }
    private var context: [String: JSONValue]? { session.data.settings?.addons["apple_recovery_context"]?.objectValue }
    private var isToday: Bool { date.apexDateKey == Date().apexDateKey }

    var body: some View {
        GlassCard(radius: 25, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(source == "athlytic" ? "Athlytic morning check" : "Apple morning check").font(APEXFont.display(18)); Spacer(); Text(health.isAuthorized ? "AUTO + MANUAL" : "MANUAL").font(APEXFont.mono(8)).foregroundStyle(APEXColor.green) }
                if isToday, let hours = context?["sleep_duration_hours"]?.numberValue {
                    Text(String(format: "Apple Health sleep: %.1f h", hours)).font(APEXFont.body(10, weight: .semibold)).foregroundStyle(APEXColor.secondaryInk)
                }
                HStack {
                    scoreField("Sleep", text: $sleep)
                    if source == "athlytic" { scoreField("Recovery", text: $recovery) }
                }
                Text(source == "athlytic" ? "Athlytic’s proprietary score is entered manually; Apple Health context is imported automatically." : "Apple Health sleep context imports automatically. Add the 0–100 score when your watch does not expose one.")
                    .font(APEXFont.body(9)).foregroundStyle(APEXColor.secondaryInk)
                Button("Save morning check") { save() }.buttonStyle(.borderedProminent).tint(APEXColor.green)
            }
        }
        .onAppear { load() }
    }
    private func scoreField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(title).font(APEXFont.body(9, weight: .bold)); TextField("%", text: text).keyboardType(.numberPad).font(APEXFont.mono(15)).multilineTextAlignment(.center).padding(11).background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 14)) }
    }
    private func load() {
        let history = session.data.settings?.addons["recovery_history"]?.arrayValue ?? []
        guard let row = history.compactMap(\.objectValue).last(where: { $0["date"]?.stringValue == date.apexDateKey }) else { return }
        sleep = row["sleep_score"]?.numberValue.map { String(Int($0)) } ?? ""
        recovery = row["recovery_pct"]?.numberValue.map { String(Int($0)) } ?? ""
    }
    private func save() {
        let sleepValue = min(100, max(0, Double(sleep) ?? 0)); let recoveryValue = min(100, max(0, Double(recovery) ?? sleepValue))
        Task { await session.updateSettings { settings in
            var rows = settings.addons["recovery_history"]?.arrayValue ?? []
            rows.removeAll { $0.objectValue?["date"]?.stringValue == date.apexDateKey }
            rows.append(.object(["date": .string(date.apexDateKey), "source": .string(source), "sleep_score": .number(sleepValue), "sleep_pct": .number(sleepValue), "recovery_pct": .number(recoveryValue), "updated_at": .string(Date().ISO8601Format())]))
            settings.addons["recovery_history"] = .array(Array(rows.suffix(730)))
        } }
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
