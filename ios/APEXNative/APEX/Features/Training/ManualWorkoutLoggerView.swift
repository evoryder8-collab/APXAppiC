import SwiftUI

/*
 * Quick log: what you actually did, when it was not what was planned.
 *
 * A port of src/components/workout/ManualWorkoutLogger.tsx. Movements come from
 * the same catalogue the studio searches, sets carry reps and load, and a
 * treadmill entry records distance, incline and duration instead of sets.
 */
struct ManualWorkoutLoggerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    var date: String = Date().apexDateKey
    var editing: WorkoutSession?
    var onSaved: () -> Void = {}

    @State private var title = ""
    @State private var day: String = Date().apexDateKey
    @State private var exercises: [ManualWorkout.ExerciseDraft] = []
    @State private var query = ""
    @State private var showSearch = false
    @State private var problem: String?

    private var canSave: Bool {
        exercises.contains { draft in
            if let treadmill = draft.treadmill { return treadmill.durationMinutes > 0 }
            return draft.sets.contains { $0.reps > 0 }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard(radius: 24, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(language.text("QUICK LOG"))
                                .font(APEXFont.mono(9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(APEXColor.cyan)
                            TextField(language.text("Workout name"), text: $title)
                                .font(APEXFont.display(19))
                                .textInputAutocapitalization(.words)
                                .accessibilityIdentifier("manual-workout-title")
                            Text(language.text("Log what you actually did. Every saved workout becomes a reusable smart preset."))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                            DatePicker(
                                language.text("Date"),
                                selection: Binding(
                                    get: { APEXDateMath.date(from: day) ?? .now },
                                    set: { day = APEXDateMath.key(from: $0) }
                                ),
                                displayedComponents: .date
                            )
                            .font(APEXFont.body(13, weight: .semibold))
                        }
                    }

                    ForEach($exercises) { $draft in
                        exerciseCard($draft)
                    }

                    Button {
                        showSearch = true
                    } label: {
                        Label(language.text("Add movement"), systemImage: "plus.circle.fill")
                            .font(APEXFont.body(15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(APEXColor.cyan.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manual-workout-add")

                    if exercises.isEmpty {
                        Text(language.text("Nothing logged yet. Add the movements you performed."))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(APEXBackground())
            .navigationTitle(language.text(editing == nil ? "Add Workout" : "Edit Workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save")) { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showSearch) {
                MovementPicker(query: $query) { item in
                    exercises.append(
                        ManualWorkout.ExerciseDraft(
                            catalogID: item.id,
                            name: item.name,
                            sets: [ManualWorkout.SetDraft(reps: item.reps, weightKG: 0)],
                            treadmill: item.category == "cardio"
                                ? ManualWorkout.TreadmillDraft(durationMinutes: 20)
                                : nil
                        )
                    )
                    showSearch = false
                }
            }
            .alert(problem ?? "", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) {
                Button(language.text("OK"), role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        day = date
        guard let editing else { return }
        title = ManualWorkout.hasAutomaticTitle(editing.notes)
            ? ""
            : (ManualWorkout.title(fromNotes: editing.notes) ?? "")
        day = editing.date
        exercises = draft(for: editing)
    }

    /// Rebuilds the editable draft from the rows a previous save wrote.
    private func draft(for workout: WorkoutSession) -> [ManualWorkout.ExerciseDraft] {
        let logs = WorkoutLogOrder.performedOrder(session.data, sessionID: workout.id)
        var drafts: [ManualWorkout.ExerciseDraft] = []
        for log in logs {
            if let treadmill = ManualWorkout.parseTreadmill(log.exerciseName) {
                drafts.append(
                    ManualWorkout.ExerciseDraft(
                        catalogID: nil,
                        name: treadmill.name,
                        sets: [],
                        treadmill: treadmill.metrics
                    )
                )
                continue
            }
            let set = ManualWorkout.SetDraft(reps: log.reps ?? 0, weightKG: log.weightKG ?? 0)
            if let index = drafts.lastIndex(where: { $0.name == log.exerciseName && $0.treadmill == nil }),
               log.setNumber > drafts[index].sets.count {
                drafts[index].sets.append(set)
            } else {
                drafts.append(
                    ManualWorkout.ExerciseDraft(catalogID: nil, name: log.exerciseName, sets: [set], treadmill: nil)
                )
            }
        }
        return drafts
    }

    @ViewBuilder
    private func exerciseCard(_ draft: Binding<ManualWorkout.ExerciseDraft>) -> some View {
        GlassCard(radius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.wrappedValue.name)
                        .font(APEXFont.body(15, weight: .bold))
                    Spacer(minLength: 6)
                    Button {
                        exercises.removeAll { $0.id == draft.wrappedValue.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(APEXColor.danger)
                            .frame(width: 26, height: 26)
                            .background(APEXColor.danger.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if draft.wrappedValue.treadmill != nil {
                    treadmillFields(draft)
                } else {
                    setFields(draft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func treadmillFields(_ draft: Binding<ManualWorkout.ExerciseDraft>) -> some View {
        let treadmill = Binding(
            get: { draft.wrappedValue.treadmill ?? ManualWorkout.TreadmillDraft() },
            set: { draft.wrappedValue.treadmill = $0 }
        )
        return HStack(spacing: 8) {
            numberField(language.text("KM"), value: Binding(
                get: { treadmill.wrappedValue.distanceKM },
                set: { treadmill.wrappedValue.distanceKM = $0 }
            ))
            numberField(language.text("INCLINE"), value: Binding(
                get: { treadmill.wrappedValue.inclineDegrees },
                set: { treadmill.wrappedValue.inclineDegrees = $0 }
            ))
            numberField(language.text("MIN"), value: Binding(
                get: { Double(treadmill.wrappedValue.durationMinutes) },
                set: { treadmill.wrappedValue.durationMinutes = Int($0) }
            ))
        }
    }

    private func setFields(_ draft: Binding<ManualWorkout.ExerciseDraft>) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, set in
                HStack(spacing: 8) {
                    Text(language.format("SET %d", index + 1))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(width: 44, alignment: .leading)
                    numberField(language.text("REPS"), value: Binding(
                        get: { Double(set.wrappedValue.reps) },
                        set: { set.wrappedValue.reps = Int($0) }
                    ))
                    numberField(language.text("KG"), value: Binding(
                        get: { set.wrappedValue.weightKG },
                        set: { set.wrappedValue.weightKG = $0 }
                    ))
                    if draft.wrappedValue.sets.count > 1 {
                        Button {
                            draft.wrappedValue.sets.removeAll { $0.id == set.wrappedValue.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                let last = draft.wrappedValue.sets.last
                draft.wrappedValue.sets.append(
                    ManualWorkout.SetDraft(reps: last?.reps ?? 10, weightKG: last?.weightKG ?? 0)
                )
            } label: {
                Label(language.text("Add set"), systemImage: "plus")
                    .font(APEXFont.body(11, weight: .bold))
                    .foregroundStyle(APEXColor.cyan)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func numberField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(APEXFont.mono(8, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(APEXFont.mono(13, weight: .bold))
                .padding(.horizontal, 9)
                .frame(height: 34)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        Task {
            let saved = await session.saveManualWorkout(
                date: day,
                title: title,
                exercises: exercises,
                editing: editing?.id
            )
            if saved {
                onSaved()
                dismiss()
            } else {
                problem = language.text("Add reps or cardio time before saving.")
            }
        }
    }
}

/// The same movement library the studio searches, in a picker.
private struct MovementPicker: View {
    @Binding var query: String
    @State private var language = LanguageState.shared
    let onPick: (ExerciseCatalogItem) -> Void

    var body: some View {
        NavigationStack {
            List(ExerciseCatalog.search(query, category: "all", language: language.language).prefix(60)) { item in
                Button {
                    onPick(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.localizedName(language.language))
                            .font(APEXFont.body(14, weight: .bold))
                            .foregroundStyle(APEXColor.ink)
                        Text("\(item.equipment) · \(item.muscles.joined(separator: ", "))")
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: language.text("Search movements"))
            .navigationTitle(language.text("Add movement"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
