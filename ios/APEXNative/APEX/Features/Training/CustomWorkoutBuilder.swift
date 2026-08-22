import SwiftUI

/*
 * Build a session from the movement library and save it as a custom day.
 *
 * Mirrors the web builder: name it, pick the weekday it belongs to, search
 * the catalogue, then tune sets, reps and rest per movement. Saving replaces
 * that weekday's custom day so editing is idempotent rather than additive.
 */
struct CustomWorkoutBuilder: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    @State private var name = ""
    @State private var weekday = CustomWorkoutBuilder.isoWeekdayToday()
    @State private var sessionMode = WorkoutSessionMode.guided
    @State private var query = ""
    @State private var category = "all"
    @State private var picks: [Pick] = []
    @State private var showValidation = false

    /// Set as the sheet closes, so the presenter can react once it is gone.
    @Binding var didSave: Bool

    struct Pick: Identifiable, Hashable {
        let item: ExerciseCatalogItem
        var sets: Int
        var reps: Int
        var rest: Int
        var id: String { item.id }
    }

    private static func isoWeekdayToday() -> Int {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func workLabel(for unit: String) -> String {
        switch unit {
        case "minutes": return "MIN"
        case "seconds": return "SEC"
        default: return "REPS"
        }
    }

    private var results: [ExerciseCatalogItem] {
        ExerciseCatalog.search(query, category: category, language: language.language)
            .filter { candidate in !picks.contains { $0.item.id == candidate.id } }
    }

    private var estimatedMinutes: Int { Self.estimatedMinutes(for: picks) }

    // Same arithmetic as the web builder so a session reads the same length
    // on either platform.
    static func estimatedMinutes(for picks: [Pick]) -> Int {
        let seconds = picks.reduce(0.0) { total, pick in
            let work: Double
            switch pick.item.unit {
            case "minutes": work = Double(pick.reps) * 60
            case "seconds": work = Double(pick.reps)
            default: work = max(20, Double(pick.reps) * 3)
            }
            return total + Double(pick.sets) * (work + Double(pick.rest))
        }
        return max(8, Int((seconds / 60).rounded()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard(radius: 24, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(language.text("Workout name"), text: $name)
                                .font(APEXFont.display(19))
                                .textInputAutocapitalization(.words)
                                .accessibilityIdentifier("custom-workout-name")

                            Text(language.text("WEEKDAY"))
                                .font(APEXFont.mono(9, weight: .bold))
                                .foregroundStyle(APEXColor.secondaryInk)
                            HStack(spacing: 5) {
                                ForEach(1...7, id: \.self) { day in
                                    Button {
                                        weekday = day
                                    } label: {
                                        Text(language.text(Self.weekdayNames[day - 1]))
                                            .font(APEXFont.mono(10, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                            .foregroundStyle(weekday == day ? .white : APEXColor.secondaryInk)
                                            .background(
                                                weekday == day
                                                    ? AnyShapeStyle(APEXColor.violet.gradient)
                                                    : AnyShapeStyle(Color.white.opacity(0.6)),
                                                in: RoundedRectangle(cornerRadius: 10)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(language.text("SESSION STYLE"))
                                .font(APEXFont.mono(9, weight: .bold))
                                .foregroundStyle(APEXColor.secondaryInk)
                            Picker("Session style", selection: $sessionMode) {
                                Text(language.text("Guided")).tag(WorkoutSessionMode.guided)
                                Text(language.text("Tracked")).tag(WorkoutSessionMode.tracked)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("custom-workout-session-mode")
                        }
                    }

                    if !picks.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(language.format("IN THIS WORKOUT · %d", picks.count))
                                    .font(APEXFont.mono(9, weight: .bold))
                                    .foregroundStyle(APEXColor.violet)
                                Spacer()
                                Text(language.format("~%d min", estimatedMinutes))
                                    .font(APEXFont.mono(9))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            ForEach($picks) { $pick in
                                pickRow($pick)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        TextField(language.text("Search movements"), text: $query)
                            .font(APEXFont.body(14, weight: .semibold))
                            .padding(.horizontal, 13)
                            .frame(height: 44)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("custom-workout-search")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(ExerciseCatalog.categories) { option in
                                    Button {
                                        category = option.id
                                    } label: {
                                        Text(language.text(option.label))
                                            .font(APEXFont.mono(9, weight: .bold))
                                            .padding(.horizontal, 11)
                                            .frame(height: 30)
                                            .foregroundStyle(category == option.id ? .white : APEXColor.secondaryInk)
                                            .background(
                                                category == option.id
                                                    ? AnyShapeStyle(APEXColor.violet)
                                                    : AnyShapeStyle(Color.white.opacity(0.6)),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if results.isEmpty {
                            Text(language.text("Nothing matches that search yet."))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .padding(.vertical, 10)
                        }

                        ForEach(results.prefix(24)) { item in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    picks.append(Pick(item: item, sets: item.sets, reps: item.reps, rest: item.rest))
                                }
                            } label: {
                                HStack(spacing: 11) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.localizedName(language.language))
                                            .font(APEXFont.body(14, weight: .bold))
                                            .foregroundStyle(APEXColor.ink)
                                            .lineLimit(1)
                                        Text("\(item.equipment) · \(item.muscles.joined(separator: ", "))")
                                            .font(APEXFont.mono(8))
                                            .foregroundStyle(APEXColor.secondaryInk)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(APEXColor.violet)
                                        .frame(width: 30, height: 30)
                                        .background(APEXColor.violet.opacity(0.12), in: Circle())
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Build a workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save")) { save() }
                        .fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || picks.isEmpty)
                }
            }
            .alert(language.text("Name the workout and add at least one movement."), isPresented: $showValidation) {
                Button(language.text("OK"), role: .cancel) {}
            }
        }
    }

    private func pickRow(_ pick: Binding<Pick>) -> some View {
        GlassCard(radius: 16, padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pick.wrappedValue.item.localizedName(language.language))
                        .font(APEXFont.body(14, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            picks.removeAll { $0.id == pick.wrappedValue.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(APEXColor.danger)
                            .frame(width: 26, height: 26)
                            .background(APEXColor.danger.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    counter(language.text("SETS"), value: pick.sets, range: 1...12)
                    counter(
                        language.text(Self.workLabel(for: pick.wrappedValue.item.unit)),
                        value: pick.reps,
                        range: 1...600,
                        step: pick.wrappedValue.item.unit == "seconds" ? 5 : 1
                    )
                    counter(language.text("REST"), value: pick.rest, range: 0...600, step: 15)
                }
            }
        }
    }

    private func counter(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(APEXFont.mono(8, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            HStack(spacing: 4) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                Text("\(value.wrappedValue)")
                    .font(APEXFont.mono(13, weight: .bold))
                    .frame(minWidth: 32)
                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !picks.isEmpty else {
            showValidation = true
            return
        }
        Task {
            await session.saveCustomWorkout(
                name: trimmed,
                weekday: weekday,
                estimatedMinutes: estimatedMinutes,
                sessionMode: sessionMode,
                picks: picks
            )
            didSave = true
            dismiss()
        }
    }
}
