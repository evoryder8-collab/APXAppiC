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
    @FocusState private var searchFocused: Bool

    /// Set as the sheet closes, so the presenter can react once it is gone.
    @Binding var didSave: Bool

    struct Pick: Identifiable, Hashable {
        let item: ExerciseCatalogItem
        var sets: Int
        var reps: Int
        var rest: Int
        var linkedToNext = false
        var id: String { item.id }
    }

    struct WorkGroupAssignment: Equatable {
        let workGroupID: UUID?
        let workGroupPosition: Int?
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
        case "metres": return "DISTANCE M"
        case "steps": return "STEPS"
        case "rounds": return "ROUNDS"
        default: return "REPS"
        }
    }

    static func workStep(for unit: String) -> Int {
        switch unit {
        case "seconds", "metres": 5
        case "steps": 10
        default: 1
        }
    }

    static func moving(_ picks: [Pick], at index: Int, by offset: Int) -> [Pick] {
        let destination = index + offset
        guard picks.indices.contains(index), picks.indices.contains(destination) else { return picks }
        var moved = picks
        moved.swapAt(index, destination)
        return moved
    }

    static func workGroupAssignments(
        for picks: [Pick],
        makeID: () -> UUID = { UUID() }
    ) -> [WorkGroupAssignment] {
        var assignments = Array(
            repeating: WorkGroupAssignment(workGroupID: nil, workGroupPosition: nil),
            count: picks.count
        )
        var index = 0
        while index < picks.count - 1 {
            guard picks[index].linkedToNext else {
                index += 1
                continue
            }
            let start = index
            var end = index + 1
            while end < picks.count - 1, picks[end].linkedToNext { end += 1 }
            let groupID = makeID()
            for member in start...end {
                assignments[member] = WorkGroupAssignment(
                    workGroupID: groupID,
                    workGroupPosition: member - start + 1
                )
            }
            index = end + 1
        }
        return assignments
    }

    static func groupLabels(for picks: [Pick]) -> [String?] {
        var labels = Array<String?>(repeating: nil, count: picks.count)
        var groupIndex = 0
        var index = 0
        while index < picks.count - 1 {
            guard picks[index].linkedToNext else {
                index += 1
                continue
            }
            let start = index
            var end = index + 1
            while end < picks.count - 1, picks[end].linkedToNext { end += 1 }
            let prefix = groupIndex < 26
                ? String(UnicodeScalar(65 + groupIndex)!)
                : "G\(groupIndex + 1)"
            for member in start...end {
                labels[member] = "\(prefix)\(member - start + 1)"
            }
            groupIndex += 1
            index = end + 1
        }
        return labels
    }

    static func exerciseRows(
        userID: UUID,
        programDayID: UUID,
        picks: [Pick],
        makeExerciseID: () -> UUID = { UUID() },
        makeGroupID: () -> UUID = { UUID() }
    ) -> [Exercise] {
        let workGroups = workGroupAssignments(for: picks, makeID: makeGroupID)
        return picks.enumerated().map { index, pick in
            Exercise(
                id: makeExerciseID(),
                userID: userID,
                programDayID: programDayID,
                name: pick.item.name,
                movementID: pick.item.movementID,
                workGroupID: workGroups[index].workGroupID,
                workGroupPosition: workGroups[index].workGroupPosition,
                sets: min(max(pick.sets, 1), 12),
                repMin: min(max(pick.reps, 1), 600),
                repMax: min(max(pick.reps, 1), 600),
                repUnit: pick.item.unit,
                perSide: pick.item.perSide,
                restSeconds: min(max(pick.rest, 0), 600),
                tempoUp: 1,
                tempoDown: 2,
                tempoPause: 0,
                tempoNote: "",
                notes: "\(pick.item.equipment) · \(pick.item.muscles.joined(separator: ", "))",
                incrementKG: pick.item.incrementKG,
                isLite: false,
                optional: false,
                sortOrder: index
            )
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
                            ForEach(picks.indices, id: \.self) { index in
                                pickRow($picks[index], index: index)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        TextField(language.text("Search movements"), text: $query)
                            .focused($searchFocused)
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

                        Text(language.format("%d movements", results.count))
                            .font(APEXFont.mono(9, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .accessibilityIdentifier("custom-workout-result-count")

                        if results.isEmpty {
                            Text(language.text("Nothing matches that search yet."))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .padding(.vertical, 10)
                        }

                        LazyVStack(spacing: 9) {
                            ForEach(results) { item in
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        picks.append(Pick(item: item, sets: item.sets, reps: item.reps, rest: item.rest))
                                    }
                                    searchFocused = false
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
                                .accessibilityIdentifier("custom-workout-item-\(item.id)")
                            }
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

    private func pickRow(_ pick: Binding<Pick>, index: Int) -> some View {
        let groupLabel = Self.groupLabels(for: picks)[index]
        return GlassCard(radius: 16, padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let groupLabel {
                        Text(groupLabel)
                            .font(APEXFont.mono(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(APEXColor.violet, in: Capsule())
                    }
                    Text(pick.wrappedValue.item.localizedName(language.language))
                        .font(APEXFont.body(14, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            picks = Self.moving(picks, at: index, by: -1)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.25 : 1)
                    .accessibilityLabel(language.text("Move up"))
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            picks = Self.moving(picks, at: index, by: 1)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == picks.count - 1)
                    .opacity(index == picks.count - 1 ? 0.25 : 1)
                    .accessibilityLabel(language.text("Move down"))
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            if index > 0 { picks[index - 1].linkedToNext = false }
                            picks.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(APEXColor.danger)
                            .frame(width: 44, height: 44)
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
                        step: Self.workStep(for: pick.wrappedValue.item.unit)
                    )
                    counter(language.text("REST"), value: pick.rest, range: 0...600, step: 15)
                }
                if index < picks.count - 1 {
                    Button {
                        pick.wrappedValue.linkedToNext.toggle()
                    } label: {
                        Label(
                            language.text(pick.wrappedValue.linkedToNext
                                ? "Linked into the same round"
                                : "Link with next movement"),
                            systemImage: pick.wrappedValue.linkedToNext ? "link" : "plus"
                        )
                        .font(APEXFont.mono(9, weight: .bold))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 44)
                        .foregroundStyle(pick.wrappedValue.linkedToNext ? .white : APEXColor.violet)
                        .background(
                            pick.wrappedValue.linkedToNext ? APEXColor.violet : APEXColor.violet.opacity(0.1),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("custom-workout-link-\(pick.wrappedValue.item.id)")
                }
            }
        }
        .accessibilityIdentifier("custom-workout-selected-\(pick.wrappedValue.item.id)")
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
        guard let operation = session.accountOperationLease() else { return }
        Task {
            do {
                try await session.saveCustomWorkout(
                    name: trimmed,
                    weekday: weekday,
                    estimatedMinutes: estimatedMinutes,
                    sessionMode: sessionMode,
                    picks: picks,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                didSave = true
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
