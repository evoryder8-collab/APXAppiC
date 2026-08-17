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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                APEXTopBar(profile: session.profile) {
                    session.navigationPath.append(.settings)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text(program?.name ?? (slug == "main" ? "Main Phase" : "Transition Phase")).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(11))
                        .tracking(2)
                        .foregroundStyle(accent)
                    Text(language.text(slug == "main" ? "Build what lasts." : "Prepare the system."))
                        .font(APEXFont.display(36))
                    Text(language.text(program?.description ?? "Your programme is syncing from APEX."))
                        .font(APEXFont.body(15, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)

                HolographicBodyView(dayType: days.first(where: { $0.weekday == todayWeekday })?.dayType ?? "upper", accent: accent)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TODAY'S SIGNAL")
                                .font(APEXFont.mono(9))
                                .tracking(1.4)
                            Text(language.text(muscleFocus))
                                .font(APEXFont.display(18))
                        }
                        .foregroundStyle(.white)
                        .padding(20)
                    }

                Picker("Mode", selection: $lite) {
                    Text("Full session").tag(false)
                    Text("Minimum effective").tag(true)
                }
                .pickerStyle(.segmented)

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
                            isDeload: day.weekday == todayWeekday && todayIsDeload
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
        }
        .navigationTitle(language.text(program?.name ?? "Training"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var muscleFocus: String {
        switch days.first(where: { $0.weekday == todayWeekday })?.dayType {
        case "legs_a", "legs_b": "Glutes · Quads · Hamstrings"
        case "push": "Chest · Delts · Triceps"
        case "pull": "Back · Biceps · Grip"
        case "mobility", "fix": "Mobility · Joint quality"
        case "t25": "Cardiovascular engine"
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
                            Text("TODAY")
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

struct WorkoutDayView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let day: ProgramDay
    let accent: Color
    let lite: Bool
    let isDeload: Bool
    @State private var showPlayer = false

    private var exercises: [Exercise] {
        let source = session.data.exercises
            .filter { $0.programDayID == day.id && $0.isLite == lite }
            .sorted { $0.sortOrder < $1.sortOrder }
        return TrainingAdjustmentEngine.adjustedExercises(source, isDeload: isDeload)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 17) {
                HolographicBodyView(dayType: day.dayType, accent: accent)
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

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

                ForEach(exercises) { exercise in
                    GlassCard(radius: 24, padding: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(language.text(exercise.name))
                                    .font(APEXFont.display(18))
                                Text(prescription(exercise))
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

                Button {
                    showPlayer = true
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("workout-start-session")
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .navigationTitle(language.text(day.name))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            WorkoutPlayerView(day: day, exercises: exercises, accent: accent, lite: lite)
        }
    }

    private func prescription(_ exercise: Exercise) -> String {
        let reps = exercise.repUnit == "max" ? language.text("MAX") : exercise.repMin == exercise.repMax ? "\(exercise.repMax)" : "\(exercise.repMin)–\(exercise.repMax)"
        let unit = language.text(exercise.repUnit.uppercased())
        return exercise.perSide
            ? language.format("%d SETS · %@ %@ / SIDE", exercise.sets, reps, unit)
            : language.format("%d SETS · %@ %@", exercise.sets, reps, unit)
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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var current: Exercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
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

    private var progressStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                progressPill(label: "W", selected: phase == .warmup, complete: phase != .warmup)
                ForEach(Array(exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                    ForEach(1...max(1, exercise.sets), id: \.self) { set in
                        let done = setInputs.contains { $0.exerciseID == exercise.id && $0.setNumber == set }
                        progressPill(
                            label: exercise.perSide ? "\(exerciseIndex + 1)·\(set)" : "\(exerciseIndex + 1)\(set > 1 ? ".\(set)" : "")",
                            selected: phase != .warmup && exerciseIndex == currentIndex && set == currentSet,
                            complete: done
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
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
                    Text(language.format("SET %d OF %d", currentSet, current.sets))
                        .font(APEXFont.mono(12))
                        .tracking(2)
                        .foregroundStyle(APEXColor.secondaryInk)
                    Text(language.text(current.name))
                        .font(APEXFont.display(32))
                        .multilineTextAlignment(.center)
                    Text("\(actualReps)")
                        .font(APEXFont.mono(84))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                    Text(language.format("of %d target reps", current.repMax))
                        .font(APEXFont.mono(13))
                        .foregroundStyle(APEXColor.secondaryInk)

                    HStack(spacing: 12) {
                        Button {
                            actualReps = max(0, actualReps - 1)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            countRep()
                        } label: {
                            Label(language.text("Count rep"), systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("workout-count-rep")

                        Button {
                            endCurrentSet(skipped: false)
                        } label: {
                            Image(systemName: "checkmark")
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("workout-end-set")
                    }

                    HStack {
                        Button(language.text("Skip set")) { endCurrentSet(skipped: true) }
                            .buttonStyle(.plain)
                            .foregroundStyle(APEXColor.secondaryInk)
                        Spacer()
                        Text(language.text(current.tempoNote.isEmpty ? "Tap once for every completed rep" : current.tempoNote))
                            .font(APEXFont.body(10, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
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

                if let last = setInputs.last {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(language.text("LOG THIS SET DURING THE BREAK"))
                            .font(APEXFont.mono(10))
                            .tracking(1.5)
                            .foregroundStyle(APEXColor.violet)
                        Text(language.format("%@ · Set %d", language.text(last.exerciseName), last.setNumber))
                            .font(APEXFont.display(19))
                        restMetricRow(title: "Actual reps", value: Double(last.reps ?? 0), step: 1, unit: "") { delta in
                            adjustLastInput(repsDelta: Int(delta), weightDelta: 0)
                        }
                        restMetricRow(title: "Weight used", value: last.weightKG ?? 0, step: current?.incrementKG ?? 1, unit: "kg") { delta in
                            adjustLastInput(repsDelta: 0, weightDelta: delta)
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button("+30s") {
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
                Text(language.format("%d sets recorded · %d total reps", setInputs.filter { !$0.skipped }.count, setInputs.compactMap(\.reps).reduce(0, +)))
                    .font(APEXFont.body(13, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
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

    private func progressPill(label: String, selected: Bool, complete: Bool) -> some View {
        Text(label)
            .font(APEXFont.mono(10))
            .foregroundStyle(selected ? .white : complete ? accent : APEXColor.secondaryInk)
            .frame(minWidth: 38, minHeight: 38)
            .background(selected ? accent : complete ? accent.opacity(0.12) : .white.opacity(0.55), in: Circle())
            .overlay(Circle().stroke(complete ? accent.opacity(0.3) : APEXColor.ink.opacity(0.06)))
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
        guard !paused, phase == .warmup || phase == .rest else { return }
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
    }

    private func beginActiveSet() {
        guard current != nil else {
            phase = .complete
            return
        }
        paused = false
        actualReps = 0
        currentWeight = suggestedWeight
        phase = .active
        WorkoutAudioCoach.shared.say(language.text(current?.name ?? "Begin"), enabled: voiceOn)
    }

    private func countRep() {
        actualReps += 1
        if ticksOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if voiceOn, actualReps <= 20 {
            WorkoutAudioCoach.shared.say("\(actualReps)", enabled: true)
        }
    }

    private func endCurrentSet(skipped: Bool) {
        guard let current else { return }
        let input = WorkoutSetInput(
            exerciseID: current.id,
            exerciseName: current.name,
            setNumber: currentSet,
            weightKG: currentWeight > 0 ? currentWeight : nil,
            reps: skipped ? nil : actualReps,
            rir: skipped ? nil : 2,
            skipped: skipped
        )
        setInputs.removeAll { $0.exerciseID == current.id && $0.setNumber == currentSet }
        setInputs.append(input)

        let finalSet = currentIndex == exercises.count - 1 && currentSet >= current.sets
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

    private func finishWorkout() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await session.completeWorkout(day: day, setInputs: setInputs, lite: lite, startedAt: startedAt)
            dismiss()
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
