import SwiftUI

struct CustomWorkoutMutationGate {
    private(set) var activeToken: UUID?

    var isActive: Bool { activeToken != nil }

    mutating func begin() -> UUID? {
        guard activeToken == nil else { return nil }
        let token = UUID()
        activeToken = token
        return token
    }

    mutating func finish(_ token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
    }

    mutating func reset() {
        activeToken = nil
    }
}

/*
 * Pure custom-workout mutations. Building the proposed dashboard separately
 * lets AppSession durably save it before publishing any observable state, and
 * makes an occupied weekday an explicit replacement instead of a silent one.
 */
enum CustomWorkoutLifecycle {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case missingWorkout
        case replacementConfirmationRequired(Set<UUID>)

        var errorDescription: String? {
            switch self {
            case .missingWorkout:
                return "That workout is no longer available."
            case .replacementConfirmationRequired:
                return "Choose whether to replace the workout already planned for that day."
            }
        }
    }

    struct EditorDraft {
        let name: String
        let weekday: Int
        let sessionMode: WorkoutSessionMode
        let picks: [CustomWorkoutBuilder.Pick]
    }

    struct SaveRequest {
        let name: String
        let weekday: Int
        let estimatedMinutes: Int
        let sessionMode: WorkoutSessionMode
        let picks: [CustomWorkoutBuilder.Pick]
        let editingDayID: UUID?
        let confirmedReplacementDayIDs: Set<UUID>
    }

    struct SaveChange {
        let dashboard: DashboardData
        let program: Program
        let day: ProgramDay
        let exercises: [Exercise]
        let staleExerciseIDs: [UUID]
        let deactivatedDays: [ProgramDay]

        @MainActor
        func merging(into current: DashboardData) -> DashboardData {
            var merged = current
            merged.programs.removeAll {
                $0.id == program.id && $0.userID == program.userID
            }
            merged.programs.append(program)

            for changedDay in deactivatedDays + [day] {
                merged.programDays.removeAll {
                    $0.id == changedDay.id && $0.userID == changedDay.userID
                }
                merged.programDays.append(changedDay)
            }

            /* The gate serializes edits to this custom day, so replacing only
               its exercise rows preserves every unrelated dashboard change
               that may have arrived while the durable write was suspended. */
            merged.exercises.removeAll {
                $0.userID == day.userID && $0.programDayID == day.id
            }
            merged.exercises.append(contentsOf: exercises)
            return merged
        }
    }

    enum SaveOutcome: Equatable {
        case saved
        case replacementConfirmationRequired(Set<UUID>)
        case denied
    }

    struct ArchiveChange {
        let dashboard: DashboardData
        let day: ProgramDay

        @MainActor
        func merging(into current: DashboardData) -> DashboardData {
            var merged = current
            merged.programDays.removeAll {
                $0.id == day.id && $0.userID == day.userID
            }
            merged.programDays.append(day)
            return merged
        }
    }

    @MainActor
    static func editorDraft(for day: ProgramDay, in data: DashboardData) -> EditorDraft? {
        guard day.isActive,
              data.programs.contains(where: {
                  $0.id == day.programID && $0.userID == day.userID && $0.slug == "custom"
              }) else { return nil }

        let exercises = data.exercises
            .filter { $0.userID == day.userID && $0.programDayID == day.id }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.id.uuidString < right.id.uuidString
                }
                return left.sortOrder < right.sortOrder
            }
        let picks = exercises.enumerated().map { index, exercise in
            let item = catalogItem(for: exercise)
            let next = exercises.indices.contains(index + 1) ? exercises[index + 1] : nil
            return CustomWorkoutBuilder.Pick(
                item: item,
                sets: exercise.sets,
                reps: exercise.repMax,
                rest: exercise.restSeconds,
                linkedToNext: exercise.workGroupID != nil
                    && exercise.workGroupID == next?.workGroupID
            )
        }
        return EditorDraft(
            name: day.name,
            weekday: day.weekday,
            sessionMode: WorkoutSessionMode(rawValue: day.sessionMode) ?? .guided,
            picks: picks
        )
    }

    @MainActor
    static func prepareSave(
        in data: DashboardData,
        ownerID: UUID,
        request: SaveRequest
    ) throws -> SaveChange {
        let editingDay: ProgramDay?
        if let editingDayID = request.editingDayID {
            guard let match = data.programDays.first(where: {
                $0.id == editingDayID && $0.userID == ownerID && $0.isActive
            }), data.programs.contains(where: {
                $0.id == match.programID && $0.userID == ownerID && $0.slug == "custom"
            }) else { throw Error.missingWorkout }
            editingDay = match
        } else {
            editingDay = nil
        }

        let program = editingDay.flatMap { edited in
            data.programs.first { $0.id == edited.programID && $0.userID == ownerID }
        } ?? data.programs.first { $0.userID == ownerID && $0.slug == "custom" }
            ?? Program(
                id: UUID(),
                userID: ownerID,
                slug: "custom",
                name: "Custom workouts",
                description: "Your searchable exercise studio, saved privately."
            )
        let conflicts = data.programDays.filter {
            $0.userID == ownerID
                && $0.programID == program.id
                && $0.isActive
                && $0.weekday == request.weekday
                && $0.id != request.editingDayID
        }
        let conflictIDs = Set(conflicts.map(\.id))
        if !conflictIDs.isEmpty,
           request.confirmedReplacementDayIDs != conflictIDs {
            throw Error.replacementConfirmationRequired(conflictIDs)
        }

        /* Only an explicit edit may retain a day identity. Reusing an
           occupied day's ID for a brand-new workout would make historical
           receipts resolve to the new name and exercises. */
        let dayID = request.editingDayID ?? UUID()
        let day = ProgramDay(
            id: dayID,
            userID: ownerID,
            programID: program.id,
            weekday: min(max(request.weekday, 1), 7),
            name: request.name,
            dayType: "custom",
            estimatedMinutes: request.estimatedMinutes,
            warmupNote: "Five minutes of pain-free joint preparation",
            sortOrder: min(max(request.weekday, 1), 7),
            sessionMode: request.sessionMode.rawValue
        )
        let rows = CustomWorkoutBuilder.exerciseRows(
            userID: ownerID,
            programDayID: dayID,
            picks: request.picks
        )
        let staleExercises = data.exercises.filter {
            $0.userID == ownerID && $0.programDayID == dayID
        }
        let deactivatedIDs = conflictIDs
        var deactivatedDays: [ProgramDay] = []
        var dashboard = data
        dashboard.programs.removeAll { $0.id == program.id && $0.userID == ownerID }
        dashboard.programs.append(program)
        dashboard.programDays = dashboard.programDays.map { existing in
            guard existing.userID == ownerID else { return existing }
            if existing.id == dayID { return day }
            guard deactivatedIDs.contains(existing.id) else { return existing }
            var archived = existing
            archived.isActive = false
            deactivatedDays.append(archived)
            return archived
        }
        if !dashboard.programDays.contains(where: { $0.id == dayID && $0.userID == ownerID }) {
            dashboard.programDays.append(day)
        }
        dashboard.exercises.removeAll {
            $0.userID == ownerID && $0.programDayID == dayID
        }
        dashboard.exercises.append(contentsOf: rows)

        return SaveChange(
            dashboard: dashboard,
            program: program,
            day: day,
            exercises: rows,
            staleExerciseIDs: staleExercises.map(\.id),
            deactivatedDays: deactivatedDays
        )
    }

    @MainActor
    static func prepareArchive(
        dayID: UUID,
        in data: DashboardData,
        ownerID: UUID
    ) throws -> ArchiveChange {
        guard let existing = data.programDays.first(where: {
            $0.id == dayID && $0.userID == ownerID && $0.isActive
        }), data.programs.contains(where: {
            $0.id == existing.programID && $0.userID == ownerID && $0.slug == "custom"
        }) else { throw Error.missingWorkout }

        var archived = existing
        archived.isActive = false
        var dashboard = data
        guard let index = dashboard.programDays.firstIndex(where: {
            $0.id == dayID && $0.userID == ownerID
        }) else { throw Error.missingWorkout }
        dashboard.programDays[index] = archived
        return ArchiveChange(dashboard: dashboard, day: archived)
    }

    @MainActor
    static func persistMutation(
        snapshot: @MainActor () -> (revision: UInt64, dashboard: DashboardData),
        merge: @MainActor (DashboardData) -> DashboardData,
        requireCurrent: @MainActor () throws -> Void,
        saveDashboard: @MainActor (DashboardData) async throws -> Void,
        enqueue: @MainActor () async throws -> Void
    ) async throws -> DashboardData {
        var didCommit = false
        do {
            // Stabilize the cache before creating executable remote work.
            var stableRevision: UInt64
            var committed: DashboardData
            while true {
                try requireCurrent()
                let base = snapshot()
                committed = merge(base.dashboard)
                try await saveDashboard(committed)
                try requireCurrent()
                if snapshot().revision == base.revision {
                    stableRevision = base.revision
                    break
                }
            }
            try await enqueue()
            didCommit = true
            try requireCurrent()

            // Enqueue is the durable commit point. A later cache refresh is
            // best effort: its failure cannot turn replayable work into an
            // "unsaved" result or undo the already committed cache contents.
            while snapshot().revision != stableRevision {
                let base = snapshot()
                committed = merge(base.dashboard)
                do {
                    try await saveDashboard(committed)
                } catch {
                    try requireCurrent()
                    return merge(snapshot().dashboard)
                }
                try requireCurrent()
                stableRevision = base.revision
            }
            return committed
        } catch {
            // Never read another account's observable state for rollback.
            try requireCurrent()
            if !didCommit {
                while true {
                    let base = snapshot()
                    do {
                        try await saveDashboard(base.dashboard)
                    } catch {
                        try requireCurrent()
                        break
                    }
                    try requireCurrent()
                    if snapshot().revision == base.revision { break }
                }
            }
            throw error
        }
    }

    @MainActor
    static func persistBeforePublishing(
        _ proposed: DashboardData,
        persist: @MainActor (DashboardData) async throws -> Void
    ) async throws -> DashboardData {
        try await persist(proposed)
        return proposed
    }

    @MainActor
    static func persistMergedBeforePublishing(
        snapshot: @MainActor () -> (revision: UInt64, dashboard: DashboardData),
        merge: @MainActor (DashboardData) -> DashboardData,
        persist: @MainActor (DashboardData) async throws -> Void
    ) async throws -> DashboardData {
        while true {
            let base = snapshot()
            let proposed = merge(base.dashboard)
            try await persist(proposed)
            guard snapshot().revision != base.revision else { return proposed }
        }
    }

    private static func catalogItem(for exercise: Exercise) -> ExerciseCatalogItem {
        if let movementID = exercise.movementID,
           let item = ExerciseCatalog.all.first(where: { $0.movementID == movementID || $0.id == movementID }) {
            return item
        }
        let detail = exercise.notes.split(separator: "·", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ExerciseCatalogItem(
            id: exercise.movementID ?? exercise.id.uuidString,
            movementID: exercise.movementID ?? exercise.id.uuidString,
            name: exercise.name,
            category: "all",
            categories: ["all"],
            equipment: detail.first ?? "",
            muscles: detail.count > 1 ? detail[1].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } : [],
            dayType: "custom",
            sets: exercise.sets,
            reps: exercise.repMax,
            rest: exercise.restSeconds,
            unit: exercise.repUnit,
            perSide: exercise.perSide,
            loadable: exercise.incrementKG > 0,
            incrementKG: exercise.incrementKG,
            names: [:],
            aliases: [:]
        )
    }
}

/*
 * Build a session from the movement library and save it as a custom day.
 *
 * Mirrors the web builder: name it, pick the weekday it belongs to, search
 * the catalogue, then tune sets, reps and rest per movement. Editing reuses
 * its identity; a fresh save on an occupied weekday requires confirmation.
 */
struct CustomWorkoutBuilder: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    @State private var name: String
    @State private var weekday: Int
    @State private var sessionMode: WorkoutSessionMode
    @State private var query = ""
    @State private var category = "all"
    @State private var picks: [Pick]
    @State private var showValidation = false
    @State private var showReplacementConfirmation = false
    @State private var pendingReplacementDayIDs: Set<UUID> = []
    @State private var isSaving = false
    @FocusState private var searchFocused: Bool
    private let editingDayID: UUID?

    /// Set as the sheet closes, so the presenter can react once it is gone.
    @Binding var didSave: Bool

    init(
        didSave: Binding<Bool>,
        editingDay: ProgramDay? = nil,
        data: DashboardData = .empty
    ) {
        _didSave = didSave
        editingDayID = editingDay?.id
        let draft = editingDay.flatMap { CustomWorkoutLifecycle.editorDraft(for: $0, in: data) }
        _name = State(initialValue: draft?.name ?? "")
        _weekday = State(initialValue: draft?.weekday ?? Self.isoWeekdayToday())
        _sessionMode = State(initialValue: draft?.sessionMode ?? .guided)
        _picks = State(initialValue: draft?.picks ?? [])
    }

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
            .navigationTitle(language.text(editingDayID == nil ? "Build a workout" : "Edit workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.shortText(editingDayID == nil ? "Save" : "Save changes")) { save() }
                        .fontWeight(.bold)
                        .disabled(
                            isSaving
                                || session.customWorkoutMutationIsActive
                                || name.trimmingCharacters(in: .whitespaces).isEmpty
                                || picks.isEmpty
                        )
                }
            }
            .alert(language.text("Name the workout and add at least one movement."), isPresented: $showValidation) {
                Button(language.text("OK"), role: .cancel) {}
            }
            .confirmationDialog(
                language.text("Saving another workout on the same weekday replaces that day's custom plan."),
                isPresented: $showReplacementConfirmation,
                titleVisibility: .visible
            ) {
                Button(language.shortText("Replace workout"), role: .destructive) {
                    save(confirming: pendingReplacementDayIDs)
                }
                .accessibilityIdentifier("custom-workout-replace-confirm")
                Button(language.text("Keep"), role: .cancel) {
                    pendingReplacementDayIDs = []
                }
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

    private func save(confirming replacementDayIDs: Set<UUID> = []) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !picks.isEmpty else {
            showValidation = true
            return
        }
        guard let operation = session.accountOperationLease() else { return }
        isSaving = true
        Task {
            defer {
                if session.accountOperationIsCurrent(operation) { isSaving = false }
            }
            do {
                let outcome = try await session.saveCustomWorkout(
                    name: trimmed,
                    weekday: weekday,
                    estimatedMinutes: estimatedMinutes,
                    sessionMode: sessionMode,
                    picks: picks,
                    editingDayID: editingDayID,
                    confirmedReplacementDayIDs: replacementDayIDs,
                    operation: operation
                )
                guard session.accountOperationIsCurrent(operation) else { return }
                switch outcome {
                case .saved:
                    didSave = true
                    dismiss()
                case .replacementConfirmationRequired(let dayIDs):
                    pendingReplacementDayIDs = dayIDs
                    showReplacementConfirmation = true
                case .denied:
                    break
                }
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                session.alertMessage = error.localizedDescription
            }
        }
    }
}
