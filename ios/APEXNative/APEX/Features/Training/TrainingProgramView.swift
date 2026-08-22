import AudioToolbox
import AVFoundation
import Combine
import SwiftUI
import UIKit

struct TrainingProgramView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let slug: String
    let accent: Color
    @State private var lite = false
    @State private var showBuilder = false
    @State private var savedFromBuilder = false
    @State private var selectedDay: CalendarDaySelection?
    @State private var showManualLogger = false
    @State private var exportURL: ExportedReport?

    private var program: Program? { session.data.programs.first { $0.slug == slug } }
    private var days: [ProgramDay] {
        guard let program else { return [] }
        return session.data.programDays.filter { $0.programID == program.id }.sorted { $0.weekday < $1.weekday }
    }
    private var todayWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return weekday == 1 ? 7 : weekday - 1
    }
    private var todayIsDeload: Bool {
        TrainingAdjustmentEngine.isDeload(
            on: Date().apexDateKey,
            marks: session.data.deloadMarks ?? []
        )
    }

    /// Web parity: the starter-plan builder belongs to newbie mode. Showing it
    /// to everyone pushed the day the person came for below three other cards.
    private var showInduction: Bool {
        (session.data.settings?.addons["newbie_mode"]?.boolValue ?? false)
            && (slug == "transition" || slug == "main")
    }

    private var todayPlan: PlannedDay {
        TrainingPlanEngine.plan(session.data, slug: slug, date: Date().apexDateKey, lite: lite)
    }

    /// The hero, hologram and briefing must describe the same prescription.
    /// Looking up the weekly template independently allowed a generated rest
    /// day to keep an upper-body hologram and explanation.
    private var todayMuscleDayType: String {
        if todayPlan.isRecoveryMicro { return "mobility" }
        return todayPlan.programDay?.dayType ?? "rest"
    }

    private var todayExerciseNames: [String] {
        todayPlan.exercises.map(\.name)
    }

    /// Last night, if the watch had something to say about it.
    private var readiness: RecoveryAssessment.Verdict? {
        RecoveryAssessment.todaysCheckin(session.data, date: Date().apexDateKey)
            .map { RecoveryAssessment.assess($0) }
    }

    private func readinessTint(_ state: RecoveryAssessment.State) -> Color {
        switch state {
        case .strong: APEXColor.green
        case .normal: accent
        case .low: APEXColor.amberDeep
        case .veryLow: APEXColor.danger
        }
    }

    /// What today asks for, before anything else on the screen.
    private var todayHero: some View {
        let plan = todayPlan
        return GlassCard(radius: 26, padding: 17) {
            VStack(alignment: .leading, spacing: 9) {
                Text(language.text("TODAY"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(APEXColor.secondaryInk)

                /* The watch already knew how the night went; this is where it
                   finally changes what the day asks for. */
                if let readiness {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(readinessTint(readiness.state))
                            .frame(width: 7, height: 7)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text(readiness.title))
                                .font(APEXFont.body(12, weight: .bold))
                                .foregroundStyle(readinessTint(readiness.state))
                            Text(language.text(readiness.guidance))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(readinessTint(readiness.state).opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityIdentifier("training-readiness")
                }
                Text(language.text(
                    plan.isRecoveryMicro ? "Recovery micro-session" : (plan.programDay?.name ?? "Rest day")
                ))
                .font(APEXFont.display(21))
                if let day = plan.programDay {
                    Text(language.format("~%d min · %d exercises", day.estimatedMinutes, plan.exercises.count))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                if !plan.badges.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(plan.badges.prefix(3), id: \.self) { badge in
                            Text(language.text(badge))
                                .font(APEXFont.body(10, weight: .bold))
                                .foregroundStyle(badgeTint(badge))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(badgeTint(badge).opacity(0.12), in: Capsule())
                        }
                    }
                }
                if !plan.exercises.isEmpty {
                    Button {
                        selectedDay = CalendarDaySelection(date: Date().apexDateKey)
                    } label: {
                        Label(language.text("Open today"), systemImage: "arrow.right")
                            .font(APEXFont.body(13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.white)
                            .background(accent.gradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("training-today-open")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Teal for recovery, amber for anything that removes work, accent otherwise.
    private func badgeTint(_ badge: String) -> Color {
        if badge.hasPrefix("Deload") || badge.hasPrefix("Return") || badge.hasPrefix("Scheduled deload") {
            return APEXColor.teal
        }
        if badge.contains("Taper") || badge.contains("Championship") || badge.contains("recovery") {
            return APEXColor.amberDeep
        }
        return accent
    }

    /// Writes the Markdown report for the last ninety days and offers it to the
    /// share sheet, which is how a file leaves the phone.
    private func exportReport() {
        let today = Date().apexDateKey
        let markdown = ExportReport.build(
            session.data,
            slug: slug,
            from: APEXDateMath.adding(days: -90, to: today),
            to: today
        )
        guard let url = try? ExportReport.writeTemporaryFile(
            markdown, filename: "apex-\(slug)-\(today).md"
        ) else { return }
        exportURL = ExportedReport(url: url, markdown: markdown)
    }

    /// The date this weekday lands on in the current week, so a plan for it can
    /// be resolved without asking the person to pick a date first.
    private func dateOfNext(weekday: Int) -> String {
        let today = Date().apexDateKey
        return APEXDateMath.adding(days: weekday - todayWeekday, to: today)
    }

    private var fallbackTitle: String {
        switch slug {
        case "main": return "Main Phase"
        case "custom": return "Custom workouts"
        default: return "Transition Phase"
        }
    }

    private var headline: String {
        switch slug {
        case "main": return "Build what lasts."
        case "custom": return "Your own sessions."
        default: return "Prepare the system."
        }
    }

    private var fallbackDescription: String {
        slug == "custom"
            ? "Search the movement library and assemble a session that belongs to you."
            : "Your programme is syncing from APEX."
    }

    var body: some View {
        ScrollView {
            /* Not lazy: the month grid is taller than the viewport, and a lazy
               stack never materialised the day cards below it, so scrolling
               stopped at the calendar and the sessions were unreachable. The
               same trap the nutrition page fell into. */
            VStack(spacing: 18) {
                APEXTopBar(profile: session.profile) {
                    session.navigationPath.append(.settings)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text(program?.name ?? fallbackTitle).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(11))
                        .tracking(2)
                        .foregroundStyle(accent)
                    Text(language.text(headline))
                        .font(APEXFont.display(36))
                    Text(language.text(program?.description ?? fallbackDescription))
                        .font(APEXFont.body(15, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)

                if showInduction {
                    TrainingInductionPanel(slug: slug)
                        .environment(session)
                }

                if slug != "custom" { todayHero }

                MuscleMapCard(
                    dayType: todayMuscleDayType,
                    exerciseNames: todayExerciseNames,
                    height: 442,
                    accent: accent,
                    eyebrow: language.text("TODAY'S SIGNAL"),
                    focus: language.text(muscleFocus)
                )

                if slug != "custom" {
                    Picker("Mode", selection: $lite) {
                        Text(language.text("Full session")).tag(false)
                        Text(language.text("Minimum effective")).tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                /* The month, as on the web: every planned day carries its type,
                   and tapping one opens what that date actually prescribes. */
                if slug != "custom" {
                    GlassCard(radius: 26, padding: 16) {
                        TrainingCalendarView(slug: slug, accent: accent) { day in
                            selectedDay = CalendarDaySelection(date: day)
                        }
                    }
                }

                /* Web parity: the studio opens from any training screen, not
                   only from the custom one, so a first session is reachable. */
                GlassCard(radius: 26, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("APEX WORKOUT STUDIO"))
                            .font(APEXFont.mono(9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(APEXColor.violet)
                        Text(language.text("Create your own workout"))
                            .font(APEXFont.display(22))
                        Text(language.text("Search machines, free weights, calisthenics, street training, HIIT and mobility."))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                        Button {
                            showBuilder = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(language.text("Build a workout"))
                                    .font(APEXFont.body(15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("custom-workout-build")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        showManualLogger = true
                    } label: {
                        Label(language.text("Quick log"), systemImage: "square.and.pencil")
                            .font(APEXFont.body(13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(APEXColor.cyan)
                            .background(APEXColor.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("training-quick-log")

                    Button {
                        exportReport()
                    } label: {
                        Label(language.text("Export"), systemImage: "square.and.arrow.up")
                            .font(APEXFont.body(13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(APEXColor.secondaryInk)
                            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("training-export")
                }

                if slug == "custom" && days.isEmpty {
                    Text(language.text("Saving another workout on the same weekday replaces that day's custom plan."))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if todayIsDeload {
                    GlassCard(radius: 22, padding: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(APEXColor.teal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.text("DELOAD ACTIVE"))
                                    .font(APEXFont.mono(9))
                                    .tracking(1.2)
                                Text(language.text("One set removed from each exercise. Keep 3 to 4 reps in reserve and use lighter loads."))
                                    .font(APEXFont.body(12, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer()
                            Button {
                                Task { await session.toggleDeload() }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.72), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(days) { day in
                    NavigationLink {
                        WorkoutDayView(
                            day: day,
                            accent: accent,
                            lite: lite,
                            isDeload: day.weekday == todayWeekday && todayIsDeload,
                            date: dateOfNext(weekday: day.weekday),
                            slug: slug
                        )
                    } label: {
                        DayCard(
                            day: day,
                            accent: accent,
                            isToday: day.weekday == todayWeekday,
                            isDeload: day.weekday == todayWeekday && todayIsDeload
                        )
                    }
                    .buttonStyle(.plain)
                    /* Its own name: the today hero repeats the same session
                       title, so the card needs to be addressable on its own. */
                    .accessibilityIdentifier("training-day-\(day.weekday)")
                    .contextMenu {
                        if day.weekday == todayWeekday {
                            Button {
                                Task { await session.toggleDeload() }
                            } label: {
                                Label(
                                    language.text(todayIsDeload ? "Remove today's deload" : "Mark today as deload"),
                                    systemImage: todayIsDeload ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent"
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .dockClearance()
        }
        .navigationTitle(language.text(program?.name ?? "Training"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManualLogger) {
            ManualWorkoutLoggerView()
                .environment(session)
        }
        .sheet(item: $exportURL) { report in
            ExportPreviewSheet(report: report, accent: accent)
                .apexTransientSheet()
        }
        .sheet(item: $selectedDay) { selection in
            /* A day is something to look at before deciding, so it opens part
               height with the calendar still visible behind it. */
            WorkoutDaySheet(date: selection.date, slug: slug, accent: accent)
                .environment(session)
                .apexTransientSheet()
        }
        .sheet(isPresented: $showBuilder, onDismiss: {
            guard savedFromBuilder else { return }
            savedFromBuilder = false
            /* Saving from a prescribed programme lands on the custom section,
               where the new session lives. */
            if slug != "custom" { session.navigationPath.append(.customWorkouts) }
        }) {
            CustomWorkoutBuilder(didSave: $savedFromBuilder)
                .environment(session)
        }
    }

    private var muscleFocus: String {
        switch todayMuscleDayType {
        case "legs_a", "legs_b": "Glutes · Quads · Hamstrings"
        case "push": "Chest · Delts · Triceps"
        case "pull": "Back · Biceps · Grip"
        case "upper": "Chest · Back · Arms"
        case "mobility", "fix": "Mobility · Joint quality"
        case "t25": "Cardiovascular engine"
        case "rest": "Rest · Restore · Adapt"
        default: "Full-body readiness"
        }
    }
}

private struct DayCard: View {
    @State private var language = LanguageState.shared
    let day: ProgramDay
    let accent: Color
    let isToday: Bool
    let isDeload: Bool

    var body: some View {
        GlassCard(radius: 27, padding: 17) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(shortWeekday(day.weekday))
                        .font(APEXFont.mono(9))
                        .tracking(1)
                    Image(systemName: icon)
                        .font(.system(size: 23, weight: .semibold))
                }
                .foregroundStyle(isToday ? .white : accent)
                .frame(width: 58, height: 62)
                .background(isToday ? accent : accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 19, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(language.text(day.name))
                            .font(APEXFont.display(18))
                        if isToday {
                            Text(language.text("TODAY"))
                                .font(APEXFont.mono(8))
                                .tracking(1)
                                .foregroundStyle(accent)
                        }
                        if isDeload {
                            Text(language.text("DELOAD"))
                                .font(APEXFont.mono(8))
                                .tracking(1)
                                .foregroundStyle(APEXColor.teal)
                        }
                    }
                    Text(language.format("%d min · %@", day.estimatedMinutes, language.text(day.warmupNote)))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private var icon: String {
        switch day.dayType {
        case "legs_a", "legs_b": "figure.strengthtraining.traditional"
        case "push": "arrow.up.forward"
        case "pull": "arrow.down.to.line"
        case "mobility", "fix": "figure.cooldown"
        case "t25": "bolt.heart"
        default: "dumbbell"
        }
    }

    private func shortWeekday(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sundayFirstIndex = weekday == 7 ? 0 : weekday
        return symbols[sundayFirstIndex].uppercased(with: language.language.locale)
    }
}

/// A written report, wrapped so a sheet can key off it.
struct ExportedReport: Identifiable, Hashable {
    let url: URL
    let markdown: String
    var id: URL { url }
}

/// Shows what is about to leave the phone before it leaves.
private struct ExportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let report: ExportedReport
    let accent: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report.markdown)
                    .font(APEXFont.mono(10))
                    .foregroundStyle(APEXColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Training report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Done")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: report.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(accent)
                }
            }
        }
    }
}

/// A date the calendar handed over, wrapped so a sheet can key off it.
struct CalendarDaySelection: Identifiable, Hashable {
    let date: String
    var id: String { date }
}

/// The two ways to complete a planned day stay visible together. The tint only
/// communicates the remembered/default choice; neither path is hidden or made
/// secondary.
struct WorkoutSessionModeButtons: View {
    let preferred: WorkoutSessionMode
    let accent: Color
    let choose: (WorkoutSessionMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("HOW WOULD YOU LIKE TO TRAIN?")
                .font(APEXFont.mono(9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(APEXColor.secondaryInk)
            HStack(spacing: 9) {
                ForEach(WorkoutSessionMode.allCases, id: \.self) { mode in
                    Button {
                        choose(mode)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode == .guided ? "figure.strengthtraining.traditional" : "checklist")
                                .font(.system(size: 17, weight: .bold))
                            Text(mode == .guided ? "Guided" : "Tracked")
                                .font(APEXFont.body(13, weight: .bold))
                            Text(mode == .guided ? "Follow along" : "Log each set")
                                .font(APEXFont.body(10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .foregroundStyle(mode == preferred ? .white : APEXColor.ink)
                        .background(
                            mode == preferred ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(.white.opacity(0.7)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-session-mode-\(mode.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("workout-session-mode-choices")
    }
}

/// Turns the planner's already-adjusted rows into the same completion input
/// boundary that the guided player uses. RIR deliberately starts unreported.
enum TrackedWorkout {
    static func setInputs(for exercises: [Exercise]) -> [WorkoutSetInput] {
        exercises.flatMap { exercise in
            (1...max(exercise.sets, 1)).map { set in
                WorkoutSetInput(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    setNumber: set,
                    weightKG: nil,
                    reps: exercise.repMax > 0 ? exercise.repMax : nil,
                    rir: nil,
                    skipped: false
                )
            }
        }
    }
}

struct TrackedWorkoutView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let day: ProgramDay
    let exercises: [Exercise]
    let accent: Color
    let lite: Bool

    @State private var setInputs: [WorkoutSetInput]
    @State private var startedAt = Date()
    @State private var isSaving = false
    @State private var completedSession: FinishedSession?

    init(day: ProgramDay, exercises: [Exercise], accent: Color, lite: Bool) {
        self.day = day
        self.exercises = exercises
        self.accent = accent
        self.lite = lite
        _setInputs = State(initialValue: TrackedWorkout.setInputs(for: exercises))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRACKED SESSION")
                            .font(APEXFont.mono(10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                        Text(day.name)
                            .font(APEXFont.display(29))
                        Text("Record each planned set, or mark it skipped.")
                            .font(APEXFont.body(13, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }

                    ForEach(setInputs.indices, id: \.self) { index in
                        trackedSetRow($setInputs[index])
                    }

                    Button(action: finishWorkout) {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Finish workout", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                    .disabled(isSaving)
                    .accessibilityIdentifier("tracked-workout-finish")
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(APEXBackground())
            .navigationTitle("Tracked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $completedSession) { finished in
            WorkoutReceiptSheet(sessionID: finished.id) {
                completedSession = nil
                dismiss()
            }
            .environment(session)
        }
    }

    private func trackedSetRow(_ input: Binding<WorkoutSetInput>) -> some View {
        let current = input.wrappedValue
        return GlassCard(radius: 19, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(current.exerciseName)
                        .font(APEXFont.body(14, weight: .bold))
                    Spacer()
                    Text("SET \(current.setNumber)")
                        .font(APEXFont.mono(10, weight: .bold))
                        .foregroundStyle(accent)
                }
                Toggle("Skipped", isOn: Binding(
                    get: { input.wrappedValue.skipped },
                    set: { input.wrappedValue.skipped = $0 }
                ))
                .tint(accent)

                if !input.wrappedValue.skipped {
                    Stepper(
                        "Reps: \(input.wrappedValue.reps ?? 0)",
                        value: Binding(
                            get: { input.wrappedValue.reps ?? 0 },
                            set: { input.wrappedValue.reps = $0 }
                        ),
                        in: 0...600
                    )
                    if asksRIR(for: input.wrappedValue) {
                        reportedEffortRow(input)
                    }
                }
            }
        }
    }

    /// Timed holds and flows have no repetitions in reserve to report.
    private func asksRIR(for input: WorkoutSetInput) -> Bool {
        exercises.first(where: { $0.id == input.exerciseID })?.repUnit == "reps"
    }

    private func reportedEffortRow(_ input: Binding<WorkoutSetInput>) -> some View {
        HStack(spacing: 6) {
            Button("Clear") { input.wrappedValue.rir = nil }
                .buttonStyle(.bordered)
                .tint(input.wrappedValue.rir == nil ? accent : APEXColor.secondaryInk)
            ForEach(0...5, id: \.self) { rir in
                Button("\(rir)") { input.wrappedValue.rir = rir }
                    .buttonStyle(.bordered)
                    .tint(input.wrappedValue.rir == rir ? accent : APEXColor.secondaryInk)
            }
        }
        .accessibilityIdentifier("tracked-workout-rir")
    }

    private func finishWorkout() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let finished = await session.completeWorkout(
                day: day, setInputs: setInputs, lite: lite, startedAt: startedAt
            )
            isSaving = false
            if let finished {
                completedSession = FinishedSession(id: finished)
            } else {
                dismiss()
            }
        }
    }
}

struct WorkoutDayView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let day: ProgramDay
    let accent: Color
    let lite: Bool
    let isDeload: Bool
    /// Defaults to today; the calendar opens this view on any date.
    var date: String = Date().apexDateKey
    var slug: String = "main"
    @State private var showGuidedPlayer = false
    @State private var showTrackedWorkout = false

    /* The planner decides what today actually prescribes: event tapers, the
       championship leg rule, scheduled and marked deloads, recovery micros. */
    private var plan: PlannedDay {
        TrainingPlanEngine.plan(session.data, slug: slug, date: date, lite: lite)
    }

    private var exercises: [PlannedExercise] {
        let planned = plan
        guard planned.programDay?.id == day.id, !planned.exercises.isEmpty else {
            let source = session.data.exercises
                .filter { $0.programDayID == day.id && $0.isLite == lite }
                .sorted { $0.sortOrder < $1.sortOrder }
            return TrainingAdjustmentEngine.adjustedExercises(source, isDeload: isDeload)
                .map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) }
        }
        return planned.exercises
    }

    private var sessionExercises: [Exercise] {
        exercises.map { row in
            var exercise = row.exercise
            /* The player counts what the planner prescribed, not what the
               programme row says. */
            exercise.sets = row.plannedSets
            return exercise
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 17) {
                MuscleMapCard(
                    dayType: day.dayType,
                    exerciseNames: exercises.map(\.name),
                    height: 270,
                    accent: accent
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text(lite ? "MINIMUM EFFECTIVE" : "FULL SESSION"))
                        .font(APEXFont.mono(10))
                        .tracking(1.5)
                        .foregroundStyle(accent)
                    Text(language.text(day.name))
                        .font(APEXFont.display(31))
                    Text(language.text(day.warmupNote))
                        .font(APEXFont.body(14, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                /* What the planner decided, in its own words: tapers, the
                   championship rule, benchmark weeks, layoff deloads. */
                if !plan.badges.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(plan.badges, id: \.self) { badge in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(badgeTint(badge))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(language.text(badge))
                                    .font(APEXFont.body(12, weight: .semibold))
                                    .foregroundStyle(APEXColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("workout-day-badges")
                }

                if isDeload {
                    Label(
                        language.text("Deload prescription: one fewer set, lighter load, 3 to 4 reps in reserve."),
                        systemImage: "gauge.with.dots.needle.33percent"
                    )
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(APEXColor.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                ForEach(exercises) { planned in
                    let exercise = planned.exercise
                    GlassCard(radius: 24, padding: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    Text(language.text(exercise.name))
                                        .font(APEXFont.display(18))
                                    if planned.swapped {
                                        Text(language.text("SWAP"))
                                            .font(APEXFont.mono(8, weight: .bold))
                                            .foregroundStyle(APEXColor.amberDeep)
                                    }
                                    if exercise.optional {
                                        Text(language.text("OPTIONAL"))
                                            .font(APEXFont.mono(8, weight: .bold))
                                            .foregroundStyle(APEXColor.secondaryInk)
                                    }
                                }
                                Text(prescription(planned))
                                    .font(APEXFont.mono(11))
                                    .foregroundStyle(accent)
                                if !exercise.notes.isEmpty {
                                    Text(language.text(exercise.notes))
                                        .font(APEXFont.body(12, weight: .medium))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                            }
                            Spacer()
                            Text(language.format("%d s", exercise.restSeconds))
                                .font(APEXFont.mono(10))
                                .padding(8)
                                .background(accent.opacity(0.1), in: Capsule())
                        }
                    }
                }

                WorkoutSessionModeButtons(
                    preferred: session.workoutSessionMode(for: day),
                    accent: accent
                ) { mode in
                    session.rememberWorkoutSessionMode(mode)
                    switch mode {
                    case .guided: showGuidedPlayer = true
                    case .tracked: showTrackedWorkout = true
                    }
                }
                .accessibilityIdentifier("workout-start-session")
            }
            .padding(18)
            .padding(.bottom, 24)
            .dockClearance()
        }
        .navigationTitle(language.text(day.name))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showGuidedPlayer) {
            WorkoutPlayerView(
                day: day,
                exercises: sessionExercises,
                accent: accent,
                lite: lite
            )
        }
        .fullScreenCover(isPresented: $showTrackedWorkout) {
            TrackedWorkoutView(day: day, exercises: sessionExercises, accent: accent, lite: lite)
        }
    }

    /// Teal for recovery, amber for anything that removes work, accent otherwise,
    /// matching how the web colours the same chips.
    private func badgeTint(_ badge: String) -> Color {
        if badge.hasPrefix("Deload") || badge.hasPrefix("Return") || badge.hasPrefix("Scheduled deload") {
            return APEXColor.teal
        }
        if badge.contains("Taper") || badge.contains("Championship") || badge.contains("recovery") {
            return APEXColor.amberDeep
        }
        return accent
    }

    /// Reads the planned set count, which a taper or deload may have reduced.
    private func prescription(_ planned: PlannedExercise) -> String {
        let exercise = planned.exercise
        let reps = exercise.repUnit == "max" ? language.text("MAX") : exercise.repMin == exercise.repMax ? "\(exercise.repMax)" : "\(exercise.repMin)–\(exercise.repMax)"
        let unit = language.text(exercise.repUnit.uppercased())
        let movement = MovementTiming.movement(named: exercise.name)
        let noun = language.text(
            (planned.plannedSets == 1
                ? movement?.setNoun
                : movement?.setNounPlural)
            ?? MovementTiming.fallbackNoun(repUnit: exercise.repUnit)
        ).uppercased(with: language.language.locale)
        // Something performed once does not need a count in front of it.
        let lead = planned.plannedSets == 1 && movement?.showsSetCount == false
            ? noun
            : "\(planned.plannedSets) \(noun)"
        return exercise.perSide
            ? language.format("%@ · %@ %@ / SIDE", lead, reps, unit)
            : language.format("%@ · %@ %@", lead, reps, unit)
    }
}

private enum WorkoutPlayerPhase: String, Codable {
    case warmup
    case active
    case rest
    case complete
}

@MainActor
private final class WorkoutAudioCoach {
    static let shared = WorkoutAudioCoach()
    private let speaker = AVSpeechSynthesizer()

    func say(_ text: String, enabled: Bool) {
        guard enabled else { return }
        speaker.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.volume = 0.82
        speaker.speak(utterance)
    }
}

struct WorkoutPlayerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var language = LanguageState.shared
    let day: ProgramDay
    let exercises: [Exercise]
    let accent: Color
    let lite: Bool

    @State private var phase: WorkoutPlayerPhase = .warmup
    @State private var currentIndex = 0
    @State private var currentSet = 1
    @State private var actualReps = 0
    @State private var currentWeight = 0.0
    @State private var timerRemaining = 180
    @State private var timerTotal = 180
    @State private var paused = false
    @State private var setInputs: [WorkoutSetInput] = []
    @State private var startedAt = Date()
    @State private var showExit = false
    @State private var isSaving = false
    @State private var completedSession: FinishedSession?

    /* Automatic rep cadence, ported from the web player (playerTimeline.ts):
       APEX counts and paces every rep from the exercise's prescribed tempo.
       Nobody taps buttons mid-set. */
    @State private var repElapsed: Double = 0
    @State private var announcedRep = 0
    @State private var subSecond: Double = 0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var current: Exercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
    }

    /* Web parity: target is the middle of the rep range; "max" sets count up */
    private func targetReps(_ exercise: Exercise) -> Int? {
        exercise.repUnit == "max"
            ? nil
            : Int((Double(exercise.repMin + exercise.repMax) / 2).rounded(.toNearestOrAwayFromZero))
    }

    /* Web parity: seconds per rep from prescribed tempo, floor 1.6 s */
    private func repDuration(_ exercise: Exercise) -> Double {
        max(1.6, exercise.tempoUp + exercise.tempoDown + exercise.tempoPause + 0.4)
    }

    /* Timed holds and video blocks: dead hangs, stretches, T25 */
    private func timedSeconds(_ exercise: Exercise) -> Double? {
        let mid = Double((exercise.repMin + exercise.repMax) / 2)
        if exercise.repUnit == "seconds" { return mid }
        if exercise.repUnit == "minutes" { return mid * 60 }
        return nil
    }

    /* What governs this set, or nothing at all.
     *
     * This used to always claim "APEX paces you: 1s up, 2s down", which is
     * true of a barbell row and meaningless on an eleven minute stretch flow,
     * a plank, a loaded carry or a box jump. None of those have a repetition
     * whose halves can be timed, and printing a cadence on them is worse than
     * printing nothing: it tells the follower to do something the movement
     * does not contain. */
    /* What this movement's unit of work is called, so the controls stop
       saying "set" for things that have none. */
    /* "SET 1 OF 1" above something performed once is noise dressed as
       progress, and "SET" is the wrong word for a hold or a flow anyway. */
    /* Counting "total reps" across a session that included a stretch flow, a
       plank and a carry reported a number none of them contributed to. Only
       what was actually counted is summarised. */
    private var completionSummary: String {
        let recorded = setInputs.filter { !$0.skipped }
        let reps = recorded.compactMap(\.reps).reduce(0, +)
        if reps > 0 {
            return language.format("%d recorded · %d total reps", recorded.count, reps)
        }
        return language.format("%d recorded", recorded.count)
    }

    private func setCounterLine(_ exercise: Exercise) -> String? {
        let movement = MovementTiming.movement(named: exercise.name)
        if movement?.showsSetCount == false && exercise.sets <= 1 { return nil }
        let noun = language.text(
            movement?.setNoun ?? MovementTiming.fallbackNoun(repUnit: exercise.repUnit)
        ).uppercased(with: language.language.locale)
        return language.format("%@ %d OF %d", noun, currentSet, exercise.sets)
    }

    private func skipNoun(_ exercise: Exercise) -> String {
        let noun = MovementTiming.movement(named: exercise.name)?.setNoun ?? "set"
        return language.text(noun)
    }

    private func tempoLine(_ exercise: Exercise) -> String? {
        if !exercise.tempoNote.isEmpty { return language.text(exercise.tempoNote) }
        let movement = MovementTiming.movement(named: exercise.name)
        guard movement?.countsReps ?? (exercise.repUnit == "reps") else { return nil }
        let up = exercise.tempoUp.formatted(.number.precision(.fractionLength(0...1)))
        let down = exercise.tempoDown.formatted(.number.precision(.fractionLength(0...1)))
        return language.format("APEX paces you: %@s up, %@s down", up, down)
    }

    private var voiceOn: Bool { session.data.settings?.voiceOn ?? true }
    private var ticksOn: Bool { session.data.settings?.ticksOn ?? true }

    var body: some View {
        ZStack {
            APEXBackground()
            ScrollView {
                VStack(spacing: 16) {
                    playerHeader
                    progressStrip
                    phaseContent
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .interactiveDismissDisabled()
        .onReceive(timer) { _ in tick() }
        .onAppear {
            startedAt = Date()
            currentWeight = suggestedWeight
            WorkoutAudioCoach.shared.say(language.text("Warm-up started"), enabled: voiceOn)
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active { paused = true }
        }
        .confirmationDialog(language.text("Leave this workout?"), isPresented: $showExit, titleVisibility: .visible) {
            Button(language.text("Leave workout"), role: .destructive) { dismiss() }
            Button(language.text("Keep training"), role: .cancel) {}
        } message: {
            Text(language.text("Sets completed in this unfinished session have not been saved."))
        }
        /* The receipt is the task now, not a glance, so it takes the screen
           and closing it closes the finished session with it. */
        .fullScreenCover(item: $completedSession) { finished in
            WorkoutReceiptSheet(sessionID: finished.id) {
                completedSession = nil
                dismiss()
            }
            .environment(session)
        }
    }

    private var playerHeader: some View {
        VStack(spacing: 13) {
            HStack(spacing: 10) {
                Button {
                    showExit = true
                } label: {
                    Label(language.text("Exit"), systemImage: "arrow.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text(language.text(day.name))
                    .font(APEXFont.display(17))
                    .lineLimit(1)
                Spacer()

                Button {
                    Task { await session.updateSettings { $0.voiceOn.toggle() } }
                } label: {
                    Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 35, height: 35)
                        .background(.white.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await session.updateSettings { $0.ticksOn.toggle() } }
                } label: {
                    Image(systemName: ticksOn ? "metronome.fill" : "metronome")
                        .frame(width: 35, height: 35)
                        .background(.white.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(APEXColor.ink.opacity(0.08))
                    Capsule()
                        .fill(accent.gradient)
                        .frame(width: proxy.size.width * progressFraction)
                        .animation(.snappy, value: progressFraction)
                }
            }
            .frame(height: 6)
        }
    }

    /* The strip used to only report where you were. If the doorbell went and
       the set ran on without you, there was no way back to it -- the workout
       simply carried on past. Every pill is now a way in, so anything already
       reached can be returned to and redone. */
    private var progressStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    progressPill(
                        label: "W",
                        selected: phase == .warmup,
                        complete: phase != .warmup,
                        accessibilityName: language.text("Warm-up")
                    ) { returnToWarmup() }
                        .id("warmup")

                    ForEach(Array(exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                        ForEach(1...max(1, exercise.sets), id: \.self) { set in
                            let done = setInputs.contains { $0.exerciseID == exercise.id && $0.setNumber == set }
                            let noun = language.text(
                                MovementTiming.movement(named: exercise.name)?.setNoun
                                ?? MovementTiming.fallbackNoun(repUnit: exercise.repUnit)
                            )
                            progressPill(
                                label: exercise.perSide ? "\(exerciseIndex + 1)·\(set)" : "\(exerciseIndex + 1)\(set > 1 ? ".\(set)" : "")",
                                selected: phase != .warmup && exerciseIndex == currentIndex && set == currentSet,
                                complete: done,
                                accessibilityName: language.format(
                                    "%@, %@ %d", language.text(exercise.name), noun, set
                                )
                            ) { jump(toExercise: exerciseIndex, set: set) }
                                .id("\(exerciseIndex)-\(set)")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: currentIndex) { _, _ in scrollToCurrent(proxy) }
            .onChange(of: currentSet) { _, _ in scrollToCurrent(proxy) }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo("\(currentIndex)-\(currentSet)", anchor: .center) }
    }

    /// Go back to a set that was missed, or forward to one being skipped.
    ///
    /// Anything already recorded for the destination is cleared, because
    /// returning to a set means doing it again rather than viewing it: leaving
    /// the old numbers would silently double-count it on completion.
    private func jump(toExercise index: Int, set: Int) {
        guard exercises.indices.contains(index) else { return }
        let exercise = exercises[index]
        guard set >= 1, set <= max(1, exercise.sets) else { return }
        guard phase != .complete else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        setInputs.removeAll { $0.exerciseID == exercise.id && $0.setNumber == set }
        currentIndex = index
        currentSet = set
        beginActiveSet()
    }

    private func returnToWarmup() {
        guard phase != .complete else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        paused = false
        phase = .warmup
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .warmup:
            warmupCard
        case .active:
            activeSetCard
        case .rest:
            restCard
        case .complete:
            completionCard
        }
    }

    private var warmupCard: some View {
        GlassCard(radius: 34, padding: 24) {
            VStack(spacing: 22) {
                Text(language.text("WARM-UP"))
                    .font(APEXFont.mono(12))
                    .tracking(2)
                    .foregroundStyle(APEXColor.secondaryInk)
                Text(language.text(day.warmupNote))
                    .font(APEXFont.display(23))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Text(clock(timerRemaining))
                    .font(APEXFont.mono(54))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                HStack(spacing: 12) {
                    Button(language.text(paused ? "Resume" : "Pause")) { paused.toggle() }
                        .buttonStyle(.bordered)
                    Button(language.text("Skip")) { beginActiveSet() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("workout-skip-warmup")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-phase-warmup")
    }

    private var activeSetCard: some View {
        GlassCard(radius: 34, padding: 22) {
            VStack(spacing: 17) {
                if let current {
                    if let counter = setCounterLine(current) {
                        Text(counter)
                            .font(APEXFont.mono(12))
                            .tracking(2)
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Text(language.text(current.name))
                        .font(APEXFont.display(32))
                        .multilineTextAlignment(.center)

                    if let hold = timedSeconds(current) {
                        /* Timed hold: countdown ring, auto-completes */
                        ZStack {
                            Circle().stroke(APEXColor.ink.opacity(0.08), lineWidth: 12)
                            Circle()
                                .trim(from: 0, to: hold == 0 ? 0 : CGFloat(max(0, hold - repElapsed) / hold))
                                .stroke(accent.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(max(0, hold - repElapsed).rounded(.up)))")
                                .font(APEXFont.mono(48))
                                .foregroundStyle(accent)
                                .contentTransition(.numericText())
                        }
                        .frame(width: 170, height: 170)
                        Text(language.text(current.perSide ? "Hold · per side" : "Hold"))
                            .font(APEXFont.mono(13))
                            .foregroundStyle(APEXColor.secondaryInk)
                    } else {
                        /* Auto-paced rep counter */
                        Text("\(actualReps)")
                            .font(APEXFont.mono(84))
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())
                        if let target = targetReps(current) {
                            Text(language.format("of %d · counted for you", target))
                                .font(APEXFont.mono(13))
                                .foregroundStyle(APEXColor.secondaryInk)
                        } else {
                            Text(language.text("to failure · tap done when you stop"))
                                .font(APEXFont.mono(13))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(language.text(paused ? "Resume" : "Pause")) { paused.toggle() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("workout-pause-set")

                        Button {
                            endCurrentSet(skipped: false)
                        } label: {
                            Label(language.text("Done"), systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("workout-end-set")
                    }

                    HStack {
                        /* "Skip set" is wrong on a stretch flow you hold once
                           and on a carry you walk once. The movement says what
                           its unit of work is called. */
                        Button(language.format("Skip %@", skipNoun(current))) {
                            endCurrentSet(skipped: true)
                        }
                            .buttonStyle(.plain)
                            .foregroundStyle(APEXColor.secondaryInk)
                        Spacer()
                        if let line = tempoLine(current) {
                            Text(line)
                                .font(APEXFont.body(10, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-phase-active")
    }

    private var restCard: some View {
        GlassCard(radius: 34, padding: 22) {
            VStack(spacing: 18) {
                Text(language.text("REST"))
                    .font(APEXFont.mono(12))
                    .tracking(2)
                    .foregroundStyle(APEXColor.secondaryInk)

                ZStack {
                    Circle().stroke(APEXColor.ink.opacity(0.08), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: timerTotal == 0 ? 0 : CGFloat(timerRemaining) / CGFloat(timerTotal))
                        .stroke(accent.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(timerRemaining)")
                        .font(APEXFont.mono(48))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                }
                .frame(width: 180, height: 180)

                /* Only ask about what the movement actually has. A stretch
                   flow was being asked how many repetitions and how many
                   kilograms it took, which has no answer -- and offering zero
                   as the default made the question look answered. A hold is
                   asked nothing; a bodyweight movement is asked for reps but
                   not for load. */
                if let last = setInputs.last {
                    let movement = MovementTiming.movement(named: last.exerciseName)
                    let asksReps = movement?.countsReps ?? true
                    let asksLoad = movement?.recordsLoad ?? ((current?.incrementKG ?? 0) > 0)
                    if asksReps || asksLoad {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(language.text("LOG THIS SET DURING THE BREAK"))
                                .font(APEXFont.mono(10))
                                .tracking(1.5)
                                .foregroundStyle(APEXColor.violet)
                            Text(language.format(
                                "%@ · %@ %d",
                                language.text(last.exerciseName),
                                language.text(movement?.setNoun.capitalized ?? "Set"),
                                last.setNumber
                            ))
                                .font(APEXFont.display(19))
                            if asksReps {
                                restMetricRow(title: "Actual reps", value: Double(last.reps ?? 0), step: 1, unit: "") { delta in
                                    adjustLastInput(repsDelta: Int(delta), weightDelta: 0)
                                }
                            }
                            if asksLoad {
                                restMetricRow(title: "Weight used", value: last.weightKG ?? 0, step: current?.incrementKG ?? 1, unit: "kg") { delta in
                                    adjustLastInput(repsDelta: 0, weightDelta: delta)
                                }
                            }
                            reportedEffortRow(last.rir)
                        }
                        .padding(16)
                        .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    }
                }

                HStack(spacing: 12) {
                    Button(language.text("+30s")) {
                        timerRemaining += 30
                        timerTotal += 30
                    }
                    .buttonStyle(.bordered)
                    Button(language.text("Skip")) { advanceAfterRest() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("workout-skip-rest")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-phase-rest")
    }

    private var completionCard: some View {
        GlassCard(radius: 34, padding: 24) {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(accent)
                Text(language.text("Session complete"))
                    .font(APEXFont.display(31))
                Text(completionSummary)
                    .font(APEXFont.body(13, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                if let last = setInputs.last, !last.skipped {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text("LAST SET EFFORT"))
                            .font(APEXFont.mono(9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(APEXColor.violet)
                        reportedEffortRow(last.rir)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Button {
                    finishWorkout()
                } label: {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label(language.text("Save workout"), systemImage: "checkmark")
                    }
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                .disabled(isSaving)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-phase-complete")
    }

    private var progressFraction: CGFloat {
        let total = max(1, exercises.reduce(1) { $0 + max(1, $1.sets) })
        let done = setInputs.count + (phase == .warmup ? 0 : 1)
        return min(1, CGFloat(done) / CGFloat(total))
    }

    private var suggestedWeight: Double {
        guard let exercise = current else { return 0 }
        return session.data.workoutLogs
            .filter { $0.exerciseID == exercise.id && ($0.weightKG ?? 0) > 0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.weightKG ?? 0
    }

    private func progressPill(
        label: String,
        selected: Bool,
        complete: Bool,
        accessibilityName: String,
        tap: @escaping () -> Void
    ) -> some View {
        Button(action: tap) {
            Text(label)
                .font(APEXFont.mono(10))
                .foregroundStyle(selected ? .white : complete ? accent : APEXColor.secondaryInk)
                .frame(minWidth: 38, minHeight: 38)
                .background(selected ? accent : complete ? accent.opacity(0.12) : .white.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(complete ? accent.opacity(0.3) : APEXColor.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(language.text("Go to this part of the session"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func restMetricRow(
        title: String,
        value: Double,
        step: Double,
        unit: String,
        adjust: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(language.text(title))
                .font(APEXFont.body(12, weight: .bold))
            Spacer()
            Button { adjust(-step) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
            Text("\(value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))) \(language.text(unit))")
                .font(APEXFont.mono(15))
                .frame(minWidth: 76)
            Button { adjust(step) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
    }

    private func tick() {
        guard !paused else { return }
        switch phase {
        case .active:
            cadenceTick()
        case .warmup, .rest:
            subSecond += 0.1
            guard subSecond >= 0.999 else { return }
            subSecond = 0
            if timerRemaining > 0 {
                timerRemaining -= 1
                if timerRemaining == 30 {
                    WorkoutAudioCoach.shared.say(language.text("30 seconds"), enabled: voiceOn)
                }
            } else if phase == .warmup {
                beginActiveSet()
            } else {
                advanceAfterRest()
            }
        case .complete:
            break
        }
    }

    /* The friction killer: reps announce themselves on the prescribed tempo
       and the set advances on its own when the target is reached. */
    private func cadenceTick() {
        guard let current else { return }
        repElapsed += 0.1

        if let hold = timedSeconds(current) {
            if repElapsed >= hold {
                actualReps = Int(hold)
                endCurrentSet(skipped: false)
            }
            return
        }

        let duration = repDuration(current)
        let target = targetReps(current)
        let rep = Int(repElapsed / duration) + 1
        let capped = target.map { min($0, rep) } ?? rep
        if capped != announcedRep, repElapsed > 0.1 {
            announcedRep = capped
            actualReps = capped
            announceRep(capped)
        }
        if let target, repElapsed >= Double(target) * duration + 0.3 {
            endCurrentSet(skipped: false)
        }
    }

    private func announceRep(_ rep: Int) {
        if ticksOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1057)
        }
        if voiceOn, rep <= 30 {
            WorkoutAudioCoach.shared.say("\(rep)", enabled: true)
        }
    }

    private func beginActiveSet() {
        guard let exercise = current else {
            phase = .complete
            return
        }
        paused = false
        actualReps = 0
        repElapsed = 0
        announcedRep = 0
        currentWeight = suggestedWeight
        phase = .active
        WorkoutAudioCoach.shared.say(
            language.format(
                "%@. %@ %d of %d.",
                language.text(exercise.name),
                language.text(MovementTiming.movement(named: exercise.name)?.setNoun
                    ?? MovementTiming.fallbackNoun(repUnit: exercise.repUnit)).capitalized,
                currentSet,
                exercise.sets
            ),
            enabled: voiceOn
        )
    }

    private func endCurrentSet(skipped: Bool) {
        guard let current else { return }
        let input = WorkoutSetInput(
            exerciseID: current.id,
            exerciseName: current.name,
            setNumber: currentSet,
            weightKG: currentWeight > 0 ? currentWeight : nil,
            reps: skipped ? nil : actualReps,
            rir: nil,
            skipped: skipped
        )
        setInputs.removeAll { $0.exerciseID == current.id && $0.setNumber == currentSet }
        setInputs.append(input)

        let finalSet = currentIndex == exercises.count - 1 && currentSet >= current.sets
        subSecond = 0
        if finalSet {
            phase = .complete
            WorkoutAudioCoach.shared.say(language.text("Session complete"), enabled: voiceOn)
        } else {
            timerRemaining = max(15, current.restSeconds)
            timerTotal = timerRemaining
            paused = false
            phase = .rest
            WorkoutAudioCoach.shared.say(language.text("Rest"), enabled: voiceOn)
        }
    }

    private func advanceAfterRest() {
        guard let current else {
            phase = .complete
            return
        }
        if currentSet < max(1, current.sets) {
            currentSet += 1
        } else {
            currentIndex += 1
            currentSet = 1
        }
        if currentIndex >= exercises.count {
            phase = .complete
        } else {
            beginActiveSet()
        }
    }

    private func adjustLastInput(repsDelta: Int, weightDelta: Double) {
        guard !setInputs.isEmpty else { return }
        let index = setInputs.index(before: setInputs.endIndex)
        if repsDelta != 0 {
            setInputs[index].reps = max(0, (setInputs[index].reps ?? 0) + repsDelta)
        }
        if weightDelta != 0 {
            setInputs[index].weightKG = max(0, (setInputs[index].weightKG ?? 0) + weightDelta)
            currentWeight = setInputs[index].weightKG ?? 0
        }
    }

    private func reportedEffortRow(_ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.text("Reps in reserve"))
                .font(APEXFont.body(11, weight: .semibold))
            HStack(spacing: 6) {
                Button(language.text("Clear")) { setLastReportedEffort(nil) }
                    .buttonStyle(.bordered)
                    .tint(value == nil ? accent : APEXColor.secondaryInk)
                ForEach(0...5, id: \.self) { rir in
                    Button("\(rir)") { setLastReportedEffort(rir) }
                        .buttonStyle(.bordered)
                        .tint(value == rir ? accent : APEXColor.secondaryInk)
                }
            }
        }
    }

    private func setLastReportedEffort(_ rir: Int?) {
        guard !setInputs.isEmpty else { return }
        let index = setInputs.index(before: setInputs.endIndex)
        setInputs[index].rir = rir
    }

    /* The session used to save and vanish. Showing the receipt is the only
       moment the work reported during the workout is handed back. */
    private func finishWorkout() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let finished = await session.completeWorkout(
                day: day, setInputs: setInputs, lite: lite, startedAt: startedAt
            )
            isSaving = false
            if let finished {
                completedSession = FinishedSession(id: finished)
            } else {
                dismiss()
            }
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
