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
                icon: "leaf.fill",
                value: "\(completedMealCount)/\(meals.count)",
                label: "Meals",
                done: !meals.isEmpty && completedMealCount == meals.count,
                color: APEXColor.amber
            )
            SimpleMetric(
                icon: "sparkles",
                value: "\(completedSupplementCount)/\(supplementGroups.count)",
                label: "Supps",
                done: !supplementGroups.isEmpty && completedSupplementCount == supplementGroups.count,
                color: APEXColor.violet
            )
            SimpleMetric(
                icon: "drop.fill",
                value: language.format("%.1f L", waterL),
                label: "Water",
                done: waterDone,
                color: APEXColor.cyan
            )
            SimpleMetric(
                icon: "figure.strengthtraining.traditional",
                value: todayProgramDay == nil ? language.text("Rest") : workoutDone ? language.text("Done") : todayProgramDay.map { "\($0.estimatedMinutes)m" } ?? language.text("Rest"),
                label: "Training",
                done: workoutDone,
                color: APEXColor.teal
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
                            action: addWater
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

    private func addWater() {
        guard let profile, let targets else { return }
        var row = dailyLog ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: today, userID: profile.userID),
            userID: profile.userID, date: today,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: targets.tdee, computedPAL: targets.pal,
            activityMode: activities.isEmpty ? "quick" : "precise", weightKG: nil
        )
        let added = max(0, min(0.25, 6 - row.waterL))
        guard added > 0 else { return }
        row.waterL = min(6, ((row.waterL + added) * 100).rounded() / 100)
        Task {
            await session.updateDailyLog(row)
            try? await HealthKitManager.shared.saveWater(liters: added, date: .now)
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

    var body: some View {
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
