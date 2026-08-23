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
        !exercises.isEmpty && exercises.allSatisfy { draft in
            if let treadmill = draft.treadmill {
                return treadmill.durationMinutes > 0 && treadmill.distanceKM > 0
            }
            let descriptor = ExerciseLogging.descriptor(
                movementNamed: draft.name,
                movementID: draft.movementID
            )
            return descriptor.isSupported && !draft.sets.isEmpty && draft.sets.allSatisfy {
                ManualWorkout.hasFacts($0, descriptor: descriptor)
            }
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
                    let descriptor = ExerciseLogging.descriptor(movementNamed: item.name)
                    let duration: Int? = descriptor.fields.contains(.duration)
                        ? (item.unit == "minutes" ? item.reps * 60 : item.unit == "seconds" ? item.reps : nil)
                        : nil
                    exercises.append(
                        ManualWorkout.ExerciseDraft(
                            catalogID: item.id,
                            name: item.name,
                            movementID: MovementTiming.movement(named: item.name)?.id,
                            sets: [ManualWorkout.SetDraft(
                                reps: descriptor.fields.contains(.reps) ? item.reps : 0,
                                weightKG: descriptor.kind == .bodyweight ? 0 : nil,
                                durationSeconds: duration,
                                contacts: descriptor.fields.contains(.contacts) ? item.reps : nil,
                                rounds: descriptor.fields.contains(.rounds) ? item.sets : nil,
                                workSeconds: descriptor.fields.contains(.work) && item.unit == "seconds"
                                    ? item.reps : nil
                            )],
                            treadmill: nil
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
        return ManualWorkout.drafts(from: logs)
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

                setFields(draft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setFields(_ draft: Binding<ManualWorkout.ExerciseDraft>) -> some View {
        let descriptor = ExerciseLogging.descriptor(
            movementNamed: draft.wrappedValue.name,
            movementID: draft.wrappedValue.movementID
        )
        return VStack(spacing: 8) {
            ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, set in
                HStack(alignment: .top, spacing: 8) {
                    Text(language.format("SET %d", index + 1))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(width: 44, alignment: .leading)
                    ExerciseFactFieldsView(
                        descriptor: descriptor,
                        values: factValues(set)
                    )
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
                var next = draft.wrappedValue.sets.last ?? ManualWorkout.SetDraft()
                next.id = UUID()
                draft.wrappedValue.sets.append(next)
            } label: {
                Label(language.text("Add set"), systemImage: "plus")
                    .font(APEXFont.body(11, weight: .bold))
                    .foregroundStyle(APEXColor.cyan)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func factValues(
        _ set: Binding<ManualWorkout.SetDraft>
    ) -> Binding<ExerciseFactValues> {
        Binding(
            get: {
                ExerciseFactValues(
                    reps: set.wrappedValue.reps > 0 ? set.wrappedValue.reps : nil,
                    signedLoadKG: set.wrappedValue.weightKG,
                    rir: set.wrappedValue.rir,
                    durationSeconds: set.wrappedValue.durationSeconds,
                    distanceMeters: set.wrappedValue.distanceMeters,
                    contacts: set.wrappedValue.contacts,
                    rounds: set.wrappedValue.rounds,
                    workSeconds: set.wrappedValue.workSeconds,
                    recoverySeconds: set.wrappedValue.recoverySeconds
                )
            },
            set: { values in
                set.wrappedValue.reps = values.reps ?? 0
                set.wrappedValue.weightKG = values.signedLoadKG
                set.wrappedValue.rir = values.rir
                set.wrappedValue.durationSeconds = values.durationSeconds
                set.wrappedValue.distanceMeters = values.distanceMeters
                set.wrappedValue.contacts = values.contacts
                set.wrappedValue.rounds = values.rounds
                set.wrappedValue.workSeconds = values.workSeconds
                set.wrappedValue.recoverySeconds = values.recoverySeconds
            }
        )
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
