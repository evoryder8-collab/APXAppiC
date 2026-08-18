import SwiftUI

/*
 * One day, opened from the calendar.
 *
 * A port of src/components/DaySheet.tsx: what the planner prescribes for that
 * date, the Full/Light choice, the muscles it targets, water for the day, a
 * deload switch, and the way into the session itself. A finished day shows what
 * was actually lifted instead.
 */
struct WorkoutDaySheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    let date: String
    let slug: String
    let accent: Color

    @State private var lite = false
    @State private var showPlayer = false

    private var plan: PlannedDay {
        TrainingPlanEngine.plan(session.data, slug: slug, date: date, lite: lite)
    }

    private var completed: WorkoutSession? {
        let program = session.data.programs.first { $0.slug == slug }
        let dayIDs = Set(
            session.data.programDays.filter { $0.programID == program?.id }.map(\.id)
        )
        return session.data.workoutSessions.first {
            $0.date == date && $0.completed && (dayIDs.contains($0.programDayID) || $0.isEventRecovery)
        }
    }

    private var logs: [WorkoutLog] {
        guard let completed else { return [] }
        return session.data.workoutLogs
            .filter { $0.sessionID == completed.id }
            .sorted { ($0.createdAt, $0.setNumber) < ($1.createdAt, $1.setNumber) }
    }

    private var isDeloadMarked: Bool {
        (session.data.deloadMarks ?? []).contains { $0.date == date }
    }

    private var water: Double {
        session.data.dailyLogs.first { $0.date == date }?.waterL ?? 0
    }

    private var isPastOrToday: Bool { date <= Date().apexDateKey }

    private var heading: String {
        guard let date = APEXDateMath.date(from: date) else { return self.date }
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !plan.badges.isEmpty {
                        badgeStack
                    }

                    if let day = plan.programDay {
                        MuscleMapCard(
                            dayType: plan.isRecoveryMicro ? "mobility" : day.dayType,
                            exerciseNames: plan.exercises.map(\.name),
                            height: 240,
                            accent: accent
                        )
                    }

                    if !plan.isRecoveryMicro && plan.programDay != nil {
                        Picker("Mode", selection: $lite) {
                            Text(language.text("Full")).tag(false)
                            Text(language.text("Light")).tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    if !plan.warmup.isEmpty {
                        Text("\(language.text("Warm-up")): \(language.text(plan.warmup))")
                            .font(APEXFont.body(13, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }

                    ForEach(plan.exercises) { planned in
                        exerciseCard(planned)
                    }

                    if let completed {
                        completedCard(completed)
                    }

                    dayControls

                    if completed == nil, !plan.exercises.isEmpty, isPastOrToday {
                        Button {
                            showPlayer = true
                        } label: {
                            Label(
                                language.text(plan.isRecoveryMicro ? "START RECOVERY" : "START SESSION"),
                                systemImage: "play.fill"
                            )
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                        .accessibilityIdentifier("day-sheet-start")
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(APEXBackground())
            .navigationTitle(language.text(plan.programDay?.name ?? "Rest"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done")) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let day = plan.programDay {
                    WorkoutPlayerView(
                        day: day,
                        exercises: plan.exercises.map { row in
                            var exercise = row.exercise
                            exercise.sets = row.plannedSets
                            return exercise
                        },
                        accent: accent,
                        lite: lite
                    )
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading.uppercased(with: language.language.locale))
                .font(APEXFont.mono(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(APEXColor.secondaryInk)
            Text(language.text(
                plan.isRecoveryMicro ? "Recovery micro-session" : (plan.programDay?.name ?? "Rest")
            ))
            .font(APEXFont.display(26))
            if let day = plan.programDay, !plan.isRecoveryMicro {
                Text(language.format("~%d min", day.estimatedMinutes))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgeStack: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(plan.badges, id: \.self) { badge in
                Text(language.text(badge))
                    .font(APEXFont.body(11, weight: .bold))
                    .foregroundStyle(tint(badge))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint(badge).opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ badge: String) -> Color {
        if badge.hasPrefix("Deload") || badge.hasPrefix("Return") || badge.hasPrefix("Scheduled deload") {
            return APEXColor.teal
        }
        if badge.contains("Taper") || badge.contains("Championship") || badge.contains("recovery") {
            return APEXColor.amberDeep
        }
        return accent
    }

    private func exerciseCard(_ planned: PlannedExercise) -> some View {
        let exercise = planned.exercise
        let recommendation = exercise.incrementKG > 0
            ? ProgressionEngine.recommend(session.data, exercise: exercise)
            : nil
        return GlassCard(radius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(language.text(exercise.name))
                        .font(APEXFont.body(14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if exercise.optional {
                        Text(language.text("OPTIONAL"))
                            .font(APEXFont.mono(8, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    if planned.swapped {
                        Text(language.text("SWAP"))
                            .font(APEXFont.mono(8, weight: .bold))
                            .foregroundStyle(APEXColor.amberDeep)
                    }
                    Spacer(minLength: 6)
                    Text(prescription(planned))
                        .font(APEXFont.mono(12, weight: .bold))
                        .foregroundStyle(accent)
                        .fixedSize()
                }
                HStack(spacing: 11) {
                    if exercise.restSeconds > 0 {
                        Text(language.format("rest %ds", exercise.restSeconds))
                    }
                    if !exercise.tempoNote.isEmpty { Text(language.text(exercise.tempoNote)) }
                }
                .font(APEXFont.body(10, weight: .semibold))
                .foregroundStyle(APEXColor.secondaryInk)
                if !exercise.notes.isEmpty {
                    Text(language.text(exercise.notes))
                        .font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let recommendation, let weight = recommendation.weight {
                    Text(recommendedText(weight: weight, recommendation: recommendation))
                        .font(APEXFont.mono(10, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.1), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recommendedText(weight: Double, recommendation: LoadRecommendation) -> String {
        let base = language.format("Recommended: %@ kg", number(weight))
        if let previous = recommendation.previous, weight > previous.weight {
            return base + language.format(" (was %@ kg)", number(previous.weight))
        }
        return base
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func prescription(_ planned: PlannedExercise) -> String {
        let exercise = planned.exercise
        let reps: String
        switch exercise.repUnit {
        case "check": return language.text("Check")
        case "max": reps = "max"
        case "seconds": reps = "\(exercise.repMin)-\(exercise.repMax)s"
        case "minutes": reps = language.format("%d-%d min", exercise.repMin, exercise.repMax)
        default: reps = exercise.repMin == exercise.repMax ? "\(exercise.repMin)" : "\(exercise.repMin)-\(exercise.repMax)"
        }
        return "\(planned.plannedSets)x\(reps)\(exercise.perSide ? "/side" : "")"
    }

    private func completedCard(_ workout: WorkoutSession) -> some View {
        GlassCard(radius: 20, padding: 15) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(language.text("Completed"))
                        .font(APEXFont.display(16))
                    Spacer()
                    Text(language.format("QUALITY %d%%", Int((workout.qualityScore * 100).rounded())))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent, in: Capsule())
                }
                ForEach(logs.prefix(14)) { log in
                    Text(logLine(log))
                        .font(APEXFont.mono(10, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                if logs.count > 14 {
                    Text(language.format("… %d more sets", logs.count - 14))
                        .font(APEXFont.mono(10, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logLine(_ log: WorkoutLog) -> String {
        let prefix = "\(log.exerciseName) · \(language.text("set")) \(log.setNumber): "
        if log.skipped { return prefix + language.text("skipped") }
        var body = ""
        if let weight = log.weightKG { body += "\(number(weight)) kg × " }
        body += "\(log.reps.map(String.init) ?? "?") \(language.text("reps"))"
        if let rir = log.rir { body += ", RIR \(rir)" }
        return prefix + body
    }

    private var dayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(language.text("Water · one record with Nutrition"), systemImage: "drop.fill")
                        .font(APEXFont.body(11, weight: .bold))
                        .foregroundStyle(APEXColor.cyan)
                    HStack(spacing: 8) {
                        stepButton("minus") {
                            Task { await adjust(-0.25) }
                        }
                        Text(String(format: "%.2f L", water))
                            .font(APEXFont.mono(13, weight: .bold))
                            .frame(minWidth: 62)
                        stepButton("plus") {
                            Task { await adjust(0.25) }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await session.toggleDeload(on: APEXDateMath.date(from: date) ?? .now) }
                } label: {
                    Text(language.text(isDeloadMarked ? "Deload day ✓" : "Mark deload"))
                        .font(APEXFont.body(12, weight: .bold))
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .foregroundStyle(isDeloadMarked ? .white : APEXColor.cyan)
                        .background(
                            isDeloadMarked
                                ? AnyShapeStyle(APEXColor.cyan.gradient)
                                : AnyShapeStyle(Color.white.opacity(0.6)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-sheet-deload")
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(APEXColor.cyan)
                .background(APEXColor.cyan.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ delta: Double) async {
        guard let day = APEXDateMath.date(from: date) else { return }
        await session.adjustWater(deltaLiters: delta, on: day)
    }
}
