import SwiftUI

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

struct WorkoutPlayerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let day: ProgramDay
    let exercises: [Exercise]
    let accent: Color
    let lite: Bool
    @State private var currentIndex = 0
    @State private var completed: Set<UUID> = []
    @State private var showFinish = false

    private var current: Exercise? { exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil }

    var body: some View {
        ZStack {
            APEXBackground()
            VStack(spacing: 24) {
                HStack {
                    Button("Close") { dismiss() }
                    Spacer()
                    Text("\(min(currentIndex + 1, exercises.count)) / \(exercises.count)")
                        .font(APEXFont.mono(12))
                }
                .padding(.horizontal, 22)

                HolographicBodyView(dayType: day.dayType, accent: accent)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .padding(.horizontal, 18)

                if let current {
                    VStack(spacing: 10) {
                        Text(language.text(current.name))
                            .font(APEXFont.display(31))
                            .multilineTextAlignment(.center)
                        Text(language.format("%d sets · %d–%d · rest %d s", current.sets, current.repMin, current.repMax, current.restSeconds))
                            .font(APEXFont.mono(12))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    Button {
                        completed.insert(current.id)
                        if currentIndex + 1 < exercises.count {
                            withAnimation(.snappy) { currentIndex += 1 }
                        } else {
                            showFinish = true
                        }
                    } label: {
                        Label(language.text(currentIndex + 1 == exercises.count ? "Finish workout" : "Exercise complete"), systemImage: "checkmark")
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                    .padding(.horizontal, 22)
                } else {
                    Text("No exercises found").font(APEXFont.display(22))
                    Spacer()
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .confirmationDialog("Complete this session?", isPresented: $showFinish, titleVisibility: .visible) {
            Button("Complete workout") {
                Task {
                    await session.completeWorkout(day: day, exercises: exercises, lite: lite)
                    dismiss()
                }
            }
            Button("Keep training", role: .cancel) {}
        }
    }
}
