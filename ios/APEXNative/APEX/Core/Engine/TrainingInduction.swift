import Foundation

/*
 * Building a starter programme from a few answers.
 *
 * A port of src/lib/trainingInduction.ts. The answers decide a caution level,
 * which decides how many sessions a week and which template set is used, and
 * the generated ids are byte-compatible with the web so the same person's plan
 * is one plan on both platforms rather than two.
 */
enum TrainingInduction {
    // MARK: - Answers

    static let skippedMarkerKey = "training_induction_skipped"
    static let archivedMarkerKey = "training_induction_archived_day_ids"
    static let pendingMarkerKey = "training_induction_pending_day_ids"
    static let generationRevisionKey = "training_induction_generation_revision"
    static let supportedPlanWeeks = [4, 8, 12, 26]

    struct Input: Equatable, Sendable {
        var startDate: String
        var inactivity: String = "under_three_months"
        var venue: String = "home"
        var equipment: [String] = []
        var painAreas: [String] = []
        var recentOperation = false
        var chronicLowerBackPain = false
        var sessionsPerWeek = 3
        var planWeeks = 12
        var goal: String = "general"
    }

    static func input(
        from induction: [String: JSONValue]?,
        fallbackStartDate: String
    ) -> Input {
        guard let induction else { return Input(startDate: fallbackStartDate) }
        var restored = Input(
            startDate: induction["start_date"]?.stringValue ?? fallbackStartDate
        )
        switch induction["inactivity"]?.stringValue {
        case "currently_training", "under_1_month", "one_to_three_months", "under_three_months":
            restored.inactivity = "under_three_months"
        case "three_to_six_months", "six_to_twelve_months", "over_one_year":
            restored.inactivity = induction["inactivity"]?.stringValue ?? restored.inactivity
        default: break
        }
        if let venue = induction["venue"]?.stringValue,
           ["home", "gym", "outdoors"].contains(venue) {
            restored.venue = venue
        }
        restored.equipment = induction["equipment"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let painMap = [
            "knees": "knee", "shoulders": "shoulder", "elbows": "elbow",
            "hips": "hip", "ankles": "ankle", "wrists": "wrist",
        ]
        restored.painAreas = induction["pain_areas"]?.arrayValue?
            .compactMap(\.stringValue)
            .map { painMap[$0] ?? $0 }
            .filter { ["knee", "shoulder", "elbow", "hip", "ankle", "wrist"].contains($0) }
            ?? []
        restored.recentOperation = induction["recent_operation"]?.boolValue ?? false
        restored.chronicLowerBackPain = induction["chronic_lower_back_pain"]?.boolValue ?? false
        if let sessions = induction["sessions_per_week"]?.numberValue.map(Int.init) {
            restored.sessionsPerWeek = min(7, max(2, sessions))
        }
        if let weeks = induction["plan_weeks"]?.numberValue.map(Int.init),
           supportedPlanWeeks.contains(weeks) {
            restored.planWeeks = weeks
        }
        switch induction["goal"]?.stringValue {
        case "rebuild": restored.goal = "general"
        case "hypertrophy": restored.goal = "muscle"
        case "general", "muscle", "fat_loss", "strength", "endurance":
            restored.goal = induction["goal"]?.stringValue ?? restored.goal
        default: break
        }
        return restored
    }

    enum Submission: Equatable, Sendable {
        case answered(Input)
        case skipped

        var requiresProfile: Bool {
            if case .answered = self { return true }
            return false
        }

        var profileGoal: String? {
            switch self {
            case .answered(let input): goalColumn(for: input.goal)
            case .skipped: nil
            }
        }

        func generatedPlan(
            userID: UUID,
            existingPrograms: [Program],
            generationRevision: Int = 0
        ) -> GeneratedPlan? {
            switch self {
            case .answered(let input):
                TrainingInduction.generate(
                    userID: userID,
                    input: input,
                    existingPrograms: existingPrograms,
                    generationRevision: generationRevision
                )
            case .skipped:
                nil
            }
        }

        func applyingAccountMetadata(
            to settings: UserSettings,
            plan: GeneratedPlan?,
            existingData: DashboardData? = nil
        ) -> UserSettings {
            var updated = settings
            switch self {
            case .answered:
                guard let plan else { return settings }
                updated.addons.removeValue(forKey: TrainingInduction.skippedMarkerKey)
                updated.addons.removeValue(forKey: TrainingInduction.pendingMarkerKey)
                updated.addons["newbie_mode"] = .bool(true)
                updated.addons["training_induction"] = .object(plan.induction)
                updated.addons[TrainingInduction.generationRevisionKey] =
                    plan.induction["generation_revision"] ?? .number(0)
            case .skipped:
                var generatedDayIDs = TrainingInduction.pendingDayIDs(settings)
                if let existingData {
                    generatedDayIDs.formUnion(
                        TrainingInduction.legacyGeneratedDayIDs(
                            in: existingData,
                            userID: settings.userID
                        )
                    )
                }
                updated = TrainingInduction.invalidatingPlanMetadata(
                    settings,
                    additionalDayIDs: generatedDayIDs
                )
                updated.addons.removeValue(forKey: TrainingInduction.pendingMarkerKey)
                updated.addons["newbie_mode"] = .bool(false)
                updated.addons[TrainingInduction.skippedMarkerKey] = .bool(true)
            }
            return updated
        }
    }

    /// A skipped first run or a completed plan is account state, not a synthetic
    /// body profile. Server-owned settings let either account return to the
    /// portal on any device while every unanswered profile fact remains absent.
    static func shouldEnterPortal(profile: Profile?, settings: UserSettings?) -> Bool {
        guard profile == nil else { return true }
        guard let addons = settings?.addons else { return false }
        return addons[skippedMarkerKey]?.boolValue == true ||
            addons["training_induction"]?.objectValue != nil ||
            addons["newbie_mode"]?.boolValue == true ||
            addons[pendingMarkerKey]?.arrayValue != nil ||
            addons[archivedMarkerKey]?.arrayValue != nil ||
            addons[generationRevisionKey]?.numberValue != nil
    }

    static func belongsToAccount(_ data: DashboardData, userID: UUID) -> Bool {
        let owners = [data.profile?.userID, data.settings?.userID].compactMap { $0 }
        return !owners.isEmpty && owners.allSatisfy { $0 == userID }
    }

    /// A completed plan may intentionally have settings but no body profile.
    /// Its authored day and every available account row must agree on the owner
    /// before workout facts can be created for that account.
    static func workoutOwnerID(in data: DashboardData, day: ProgramDay) -> UUID? {
        guard let userID = data.profile?.userID ?? data.settings?.userID,
              day.userID == userID,
              belongsToAccount(data, userID: userID) else {
            return nil
        }
        return userID
    }

    /// Empty is a valid authenticated first run. Any rows that do exist must
    /// all belong to the authenticated account before they can be installed.
    static func isCompatibleDashboard(_ data: DashboardData, userID: UUID) -> Bool {
        [data.profile?.userID, data.settings?.userID]
            .compactMap { $0 }
            .allSatisfy { $0 == userID }
    }

    static func venueDisplayName(for venue: String) -> String {
        switch venue {
        case "gym": "Gym"
        case "outdoors": "Outdoors"
        default: "Home"
        }
    }

    static func invalidatingPlanMetadata(
        _ settings: UserSettings,
        additionalDayIDs: Set<UUID> = []
    ) -> UserSettings {
        var updated = settings
        var archivedIDs = archivedDayIDs(settings)
        var newlyArchived = additionalDayIDs
        if let induction = settings.addons["training_induction"]?.objectValue {
            newlyArchived.formUnion(claimedDayIDs(in: induction, slug: "transition"))
            newlyArchived.formUnion(claimedDayIDs(in: induction, slug: "main"))
        }
        archivedIDs.formUnion(newlyArchived)
        writeArchivedDayIDs(archivedIDs, to: &updated)

        let hasActiveMarker = settings.addons["training_induction"] != nil
        if hasActiveMarker || !additionalDayIDs.isEmpty {
            let activeInduction = settings.addons["training_induction"]?.objectValue
            let activeRevision = activeInduction?["generation_revision"]?.numberValue.map(Int.init) ?? 0
            let nextRevision = max(generationRevision(settings), activeRevision) + 1
            updated.addons[generationRevisionKey] = .number(Double(nextRevision))
        }
        updated.addons.removeValue(forKey: "training_induction")
        return updated
    }

    static func archivedDayIDs(_ settings: UserSettings) -> Set<UUID> {
        Set(
            settings.addons[archivedMarkerKey]?.arrayValue?
                .compactMap(\.stringValue)
                .compactMap(UUID.init(uuidString:)) ?? []
        )
    }

    static func pendingDayIDs(_ settings: UserSettings) -> Set<UUID> {
        Set(
            settings.addons[pendingMarkerKey]?.arrayValue?
                .compactMap(\.stringValue)
                .compactMap(UUID.init(uuidString:)) ?? []
        )
    }

    static func generationRevision(_ settings: UserSettings) -> Int {
        max(0, settings.addons[generationRevisionKey]?.numberValue.map(Int.init) ?? 0)
    }

    private static func writeArchivedDayIDs(_ ids: Set<UUID>, to settings: inout UserSettings) {
        guard !ids.isEmpty else { return }
        settings.addons[archivedMarkerKey] = .array(
            ids.map { $0.uuidString.lowercased() }
                .sorted()
                .map(JSONValue.string)
        )
    }

    /// Persisted before programme rows are written. Until the final induction
    /// marker claims these exact IDs, every planning surface treats them as an
    /// interrupted save rather than an authored prescription.
    static func markingPendingPlan(_ settings: UserSettings, plan: GeneratedPlan) -> UserSettings {
        var updated = settings
        let nextIDs = Set(plan.programDays.map(\.id))
        var archived = archivedDayIDs(settings)
        archived.formUnion(pendingDayIDs(settings).subtracting(nextIDs))
        writeArchivedDayIDs(archived, to: &updated)
        updated.addons[pendingMarkerKey] = .array(
            nextIDs.map { $0.uuidString.lowercased() }
                .sorted()
                .map(JSONValue.string)
        )
        updated.addons[generationRevisionKey] =
            plan.induction["generation_revision"] ?? .number(0)
        return updated
    }

    /// Revision-zero plans used deterministic IDs before archival existed.
    /// Recover only IDs that match that generator exactly; arbitrary authored
    /// rows are never inferred from a programme slug or weekday.
    static func legacyGeneratedDayIDs(in data: DashboardData, userID: UUID) -> Set<UUID> {
        let archived = data.settings.map(archivedDayIDs) ?? []
        let candidates = Set(["transition", "main"].flatMap { slug in
            (1...7).map {
                APEXStableID.inductionUUID(userID: userID, label: "\(slug):day:\($0)")
            }
        })
        return Set(data.programDays.lazy.filter {
            $0.userID == userID && candidates.contains($0.id) && !archived.contains($0.id)
        }.map(\.id))
    }

    static func activeProgramDays(in data: DashboardData, userID explicitUserID: UUID? = nil) -> [ProgramDay] {
        guard let userID = explicitUserID ?? data.profile?.userID ?? data.settings?.userID else {
            return []
        }
        if let settings = data.settings, settings.userID != userID { return [] }
        let archived = data.settings.map(archivedDayIDs) ?? []
        let pending = data.settings.map(pendingDayIDs) ?? []
        return data.programDays.filter {
            $0.userID == userID
                && !archived.contains($0.id)
                && !pending.contains($0.id)
        }
    }

    private static func scopedPhaseRows(
        in data: DashboardData,
        slug: String
    ) -> (dayIDs: Set<UUID>, fullExerciseDayIDs: Set<UUID>)? {
        guard let userID = data.profile?.userID ?? data.settings?.userID else { return nil }
        if let settings = data.settings, settings.userID != userID { return nil }
        let programIDs = Set(data.programs.lazy.filter {
            $0.userID == userID && $0.slug == slug
        }.map(\.id))
        let dayIDs = Set(activeProgramDays(in: data).lazy.filter {
            programIDs.contains($0.programID)
        }.map(\.id))
        let fullExerciseDayIDs = Set(data.exercises.lazy.filter {
            $0.userID == userID && !$0.isLite && dayIDs.contains($0.programDayID)
        }.map(\.programDayID))
        return (dayIDs, fullExerciseDayIDs)
    }

    private static func claimedDayIDs(
        in induction: [String: JSONValue],
        slug: String
    ) -> Set<UUID> {
        let key = slug == "transition" ? "transition_day_ids" : "main_day_ids"
        return Set(
            induction[key]?.arrayValue?
                .compactMap(\.stringValue)
                .compactMap(UUID.init(uuidString:)) ?? []
        )
    }

    /// The screen must resolve both programme metadata and rows through the
    /// current account. Same-slug rows from a stale account cache are never a
    /// valid fallback, including for accounts that skipped profile creation.
    static func ownedProgram(in data: DashboardData, slug: String) -> Program? {
        guard let userID = data.profile?.userID ?? data.settings?.userID else { return nil }
        if let settings = data.settings, settings.userID != userID { return nil }
        return data.programs.first { $0.userID == userID && $0.slug == slug }
    }

    /// A generated overlay shares its Program row with an authored programme.
    /// While the overlay marker is active, list only the exact generated days
    /// it claims rather than blending them with the preserved authored days.
    static func visibleProgramDays(in data: DashboardData, slug: String) -> [ProgramDay] {
        guard let program = ownedProgram(in: data, slug: slug) else { return [] }
        let userID = program.userID
        var rows = activeProgramDays(in: data).filter {
            $0.userID == userID && $0.programID == program.id
        }
        if slug == "transition" || slug == "main",
           let induction = data.settings?.addons["training_induction"]?.objectValue {
            guard generatedPlanIsComplete(in: data, slug: slug) else { return [] }
            let claimed = claimedDayIDs(in: induction, slug: slug)
            rows.removeAll { !claimed.contains($0.id) }
        }
        return rows.sorted { $0.weekday < $1.weekday }
    }

    struct Restoration {
        let dashboard: DashboardData
        let claimedProgramDayIDs: Set<UUID>
        let archivedProgramDays: [ProgramDay]
        let preservedExercises: [Exercise]
    }

    /// Remove only the rows claimed by the generated overlay. Authored rows
    /// and programme metadata remain byte-for-byte intact.
    static func restoration(in data: DashboardData, userID: UUID) -> Restoration? {
        guard var settings = data.settings,
              settings.userID == userID else {
            return nil
        }
        let hasInductionMarker: Bool = {
            guard let value = settings.addons["training_induction"] else { return false }
            if case .null = value { return false }
            return true
        }()
        let hasNewbieMode = settings.addons["newbie_mode"]?.boolValue == true
        var generatedDayIDs = pendingDayIDs(settings)
        if let induction = settings.addons["training_induction"]?.objectValue {
            generatedDayIDs.formUnion(claimedDayIDs(in: induction, slug: "transition"))
            generatedDayIDs.formUnion(claimedDayIDs(in: induction, slug: "main"))
        }
        generatedDayIDs.formUnion(legacyGeneratedDayIDs(in: data, userID: userID))
        guard !generatedDayIDs.isEmpty || hasInductionMarker || hasNewbieMode else { return nil }
        let archivedProgramDays = data.programDays.filter {
            $0.userID == userID && generatedDayIDs.contains($0.id)
        }
        let preservedExercises = data.exercises.filter {
            $0.userID == userID && generatedDayIDs.contains($0.programDayID)
        }

        var restored = data
        var archivedIDs = archivedDayIDs(settings)
        archivedIDs.formUnion(generatedDayIDs)
        writeArchivedDayIDs(archivedIDs, to: &settings)
        if hasInductionMarker || !generatedDayIDs.isEmpty {
            let activeInduction = settings.addons["training_induction"]?.objectValue
            let activeRevision = activeInduction?["generation_revision"]?.numberValue.map(Int.init) ?? 0
            settings.addons[generationRevisionKey] = .number(
                Double(max(generationRevision(settings), activeRevision) + 1)
            )
        }
        settings.addons["newbie_mode"] = .bool(false)
        settings.addons.removeValue(forKey: "training_induction")
        settings.addons.removeValue(forKey: pendingMarkerKey)
        restored.settings = settings
        return Restoration(
            dashboard: restored,
            claimedProgramDayIDs: generatedDayIDs,
            archivedProgramDays: archivedProgramDays,
            preservedExercises: preservedExercises
        )
    }

    static func hasRestorableOverlay(in data: DashboardData) -> Bool {
        guard let userID = data.profile?.userID ?? data.settings?.userID else { return false }
        return restoration(in: data, userID: userID) != nil
    }

    static func applyingGeneratedPlan(
        _ plan: GeneratedPlan,
        settings: UserSettings,
        to data: DashboardData
    ) -> DashboardData {
        var installed = data
        for program in plan.programs {
            if let index = installed.programs.firstIndex(where: { $0.id == program.id }) {
                installed.programs[index] = program
            } else {
                installed.programs.append(program)
            }
        }
        for day in plan.programDays {
            if let index = installed.programDays.firstIndex(where: { $0.id == day.id }) {
                installed.programDays[index] = day
            } else {
                installed.programDays.append(day)
            }
        }
        for exercise in plan.exercises {
            if let index = installed.exercises.firstIndex(where: { $0.id == exercise.id }) {
                installed.exercises[index] = exercise
            } else {
                installed.exercises.append(exercise)
            }
        }
        installed.settings = settings
        return installed
    }

    private static func generatedPlanIsComplete(in data: DashboardData, slug: String) -> Bool {
        guard let settings = data.settings,
              let induction = settings.addons["training_induction"]?.objectValue,
              let rows = scopedPhaseRows(in: data, slug: slug)
        else { return false }
        let claimed = claimedDayIDs(in: induction, slug: slug)
        let expectedCount = induction["sessions_per_week"]?.numberValue.map(Int.init)
        guard claimed.count >= 2,
              expectedCount.map({ claimed.count == $0 }) ?? true,
              claimed.isSubset(of: rows.dayIDs),
              claimed.isSubset(of: rows.fullExerciseDayIDs)
        else { return false }
        return true
    }

    static func hasCompleteGeneratedPlan(in data: DashboardData, slug: String) -> Bool {
        generatedPlanIsComplete(in: data, slug: slug)
    }

    static func hasUsablePrescription(in data: DashboardData, slug: String) -> Bool {
        guard let rows = scopedPhaseRows(in: data, slug: slug) else { return false }
        if data.settings?.addons["training_induction"]?.objectValue != nil {
            return generatedPlanIsComplete(in: data, slug: slug)
        }
        return !rows.dayIDs.intersection(rows.fullExerciseDayIDs).isEmpty
    }

    /// The builder remains reachable until this account has real generated
    /// rows for the phase. A stale settings marker or another account's rows
    /// cannot hide it.
    static func shouldOfferPlanBuilder(in data: DashboardData, slug: String) -> Bool {
        guard slug == "transition" || slug == "main" else { return false }
        return !hasCompleteGeneratedPlan(in: data, slug: slug)
    }

    struct Assessment: Equatable, Sendable {
        let caution: String
        let sessionsPerWeek: Int
        let reasons: [String]
    }

    struct HighFrequencyAdvisory: Equatable, Sendable {
        let days: Int
        let title: String
        let summary: String
        let adaptations: [String]
        let recoveryTips: [String]
        let disclaimer: String
    }

    /// Copy and behavior share one evidence-aware model. Frequency alone is not
    /// treated as progress; volume is redistributed (PMID 30558493), recovery
    /// signals are monitored (PMID 29345524), and sleep/hydration guidance stays
    /// individualized (PMIDs 33144349 and 28985128).
    static func highFrequencyAdvisory(for days: Int) -> HighFrequencyAdvisory? {
        guard days == 6 || days == 7 else { return nil }
        return HighFrequencyAdvisory(
            days: days,
            title: days == 7 ? "Seven days needs one low-load day" : "Six days needs distributed load",
            summary: "APEX will keep all \(days) training days while changing how stress is placed across the week.",
            adaptations: [
                "Upper and lower loading alternate so the same muscle group is not trained hard on consecutive days.",
                "Loaded movements are capped at two hard sets per exercise.",
                days == 7
                    ? "Mobility and conversational-pace capacity replace a seventh hard session."
                    : "A low-load mobility session separates repeated muscle-group work.",
            ],
            recoveryTips: [
                "Protect a consistent sleep window and aim for at least seven hours.",
                "Meet your APEX protein target across the day.",
                "Use your personal hydration target. More water is not always better.",
                "Reduce load if performance, soreness, sleep or motivation worsen.",
            ],
            disclaimer: "This lowers avoidable load stacking, but it cannot guarantee recovery or prevent overtraining."
        )
    }

    /// A recent operation stops loaded training until a clinician says otherwise;
    /// a long layoff, back pain or current joint discomfort softens the plan.
    static func assess(_ input: Input) -> Assessment {
        if input.recentOperation {
            return Assessment(
                caution: "clearance",
                sessionsPerWeek: 2,
                reasons: ["Recent operation reported", "Loaded training waits for clinician clearance"]
            )
        }
        let longLayoff = input.inactivity == "six_to_twelve_months" || input.inactivity == "over_one_year"
        let cautious = longLayoff || input.chronicLowerBackPain || !input.painAreas.isEmpty
        var reasons: [String] = []
        if longLayoff { reasons.append("Long training gap reported") }
        if input.chronicLowerBackPain { reasons.append("Chronic lower-back pain reported") }
        if !input.painAreas.isEmpty { reasons.append("Current joint discomfort reported") }
        return Assessment(
            caution: cautious ? "cautious" : "standard",
            sessionsPerWeek: cautious ? min(input.sessionsPerWeek, 3) : input.sessionsPerWeek,
            reasons: reasons
        )
    }

    /// Which of the three persisted energy slots is the safe default for a new
    /// training plan. The slot's visible meaning is resolved from the plan.
    static func goalColumn(for trainingGoal: String) -> String {
        NutritionGoalPolicy.recommendedGoal(for: trainingGoal).rawValue
    }

    // MARK: - Equipment

    struct EquipmentOption: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
    }

    static let equipmentCatalog: [EquipmentOption] = [
        EquipmentOption(id: "weighted_vest", label: "Weighted vest"),
        EquipmentOption(id: "weighted_backpack", label: "Weighted backpack"),
        EquipmentOption(id: "adjustable_dumbbells", label: "Adjustable dumbbells"),
        EquipmentOption(id: "fixed_dumbbells", label: "Fixed dumbbells"),
        EquipmentOption(id: "resistance_bands", label: "Resistance bands"),
        EquipmentOption(id: "bench", label: "Training bench"),
        EquipmentOption(id: "pullup_bar", label: "Pull-up bar"),
        EquipmentOption(id: "kettlebell", label: "Kettlebell"),
        EquipmentOption(id: "suspension_trainer", label: "Suspension trainer"),
        EquipmentOption(id: "barbell_plates", label: "Barbell and plates"),
        EquipmentOption(id: "rack", label: "Squat rack"),
        EquipmentOption(id: "cable_machine", label: "Cable machine"),
        EquipmentOption(id: "cardio_machine", label: "Cardio machine"),
        EquipmentOption(id: "mat", label: "Exercise mat"),
    ]

    // MARK: - Templates

    private struct ExerciseSpec {
        let name: String
        var sets: Int = 2
        let repMin: Int
        let repMax: Int
        var unit: String = "reps"
        var perSide = false
        var rest: Int = 60
        var increment: Double = 0
        var notes: String?
        var optional = false
        var workGroupKey: String?
        var workGroupPosition: Int?
    }

    private struct SessionSpec {
        let name: String
        let type: String
        let minutes: Int
        let warmup: String
        let exercises: [ExerciseSpec]
    }

    /// High frequency distributes work instead of multiplying it. Volume-equated
    /// reviews find no meaningful hypertrophy advantage from frequency alone
    /// (PMID 30558493), so loaded sessions use no more than two hard sets and
    /// alternate with low-load mobility and capacity work.
    private static func cappedHardSets(_ session: SessionSpec, at cap: Int = 2) -> SessionSpec {
        SessionSpec(
            name: session.name,
            type: session.type,
            minutes: session.minutes,
            warmup: session.warmup,
            exercises: session.exercises.map { exercise in
                var adjusted = exercise
                adjusted.sets = min(adjusted.sets, cap)
                return adjusted
            }
        )
    }

    private static func withoutWorkGroup(_ exercise: ExerciseSpec) -> ExerciseSpec {
        var standalone = exercise
        standalone.workGroupKey = nil
        standalone.workGroupPosition = nil
        return standalone
    }

    private static func mobilityAndCoreSession(prefix: String = "") -> SessionSpec {
        SessionSpec(
            name: "\(prefix)Mobility & Core",
            type: "mobility",
            minutes: 26,
            warmup: "Keep this session deliberately easy. Finish feeling better than you started.",
            exercises: [
                ExerciseSpec(name: "90/90 Hip Mobility", sets: 1, repMin: 60, repMax: 90, unit: "seconds", perSide: true, rest: 20),
                ExerciseSpec(name: "Cat-Cow", repMin: 6, repMax: 10, rest: 20),
                ExerciseSpec(name: "Thoracic Extension", repMin: 6, repMax: 10, rest: 20),
                ExerciseSpec(name: "Dead Bug", repMin: 6, repMax: 10, perSide: true, rest: 30),
                ExerciseSpec(name: "Walking", sets: 1, repMin: 10, repMax: 15, unit: "minutes", rest: 0),
            ]
        )
    }

    private static func recoverySession(prefix: String = "") -> SessionSpec {
        SessionSpec(
            name: "\(prefix)Recovery Session",
            type: "mobility",
            minutes: 30,
            warmup: "This is a training day, not another hard day. Keep breathing conversational and every movement pain-free.",
            exercises: [
                ExerciseSpec(name: "Walking", sets: 1, repMin: 18, repMax: 25, unit: "minutes", rest: 0),
                ExerciseSpec(name: "90/90 Hip Mobility", sets: 1, repMin: 60, repMax: 90, unit: "seconds", perSide: true, rest: 20),
                ExerciseSpec(name: "Diaphragmatic Breathing", sets: 1, repMin: 90, repMax: 120, unit: "seconds", rest: 0),
            ]
        )
    }

    private static func homeNames(_ equipment: [String]) -> [String: String] {
        let dumbbells = equipment.contains("adjustable_dumbbells") || equipment.contains("fixed_dumbbells")
        let bands = equipment.contains("resistance_bands")
        let pullup = equipment.contains("pullup_bar")
        let weightedVest = equipment.contains("weighted_vest")
        let weightedBackpack = equipment.contains("weighted_backpack")
        return [
            "squat": dumbbells ? "Goblet Squat" : (weightedVest ? "Weighted Vest Squat" : (weightedBackpack ? "Backpack Front Squat" : "Controlled Chair Squat")),
            "hinge": dumbbells ? "Dumbbell Romanian Deadlift" : (weightedBackpack ? "Backpack Romanian Deadlift" : (bands ? "Band Hip Hinge" : "Bodyweight Hip Hinge")),
            "push": dumbbells ? "Dumbbell Floor Press" : (weightedVest ? "Weighted Vest Push-Up" : "Incline Push-Up"),
            "row": dumbbells ? "One-Arm Dumbbell Row" : (weightedBackpack ? "Backpack Row" : (bands ? "Band Row" : "Towel Isometric Row")),
            "press": dumbbells ? "Seated Dumbbell Press" : (bands ? "Band Overhead Press" : "Incline Pike Press"),
            "pull": pullup ? "Assisted Pull-Up" : (bands ? "Band Lat Pulldown" : "Prone Lat Sweep"),
            "carry": dumbbells ? "Suitcase Carry" : (weightedBackpack ? "Loaded Backpack Carry" : (weightedVest ? "Weighted Vest March" : "March in Place")),
        ]
    }

    private static func clearanceSessions() -> [SessionSpec] {
        let warmup = "Begin only after the clinician managing the operation has cleared these movements. Use a pain-free range."
        return [
            SessionSpec(
                name: "Clearance Reset A", type: "mobility", minutes: 18, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Diaphragmatic Breathing", repMin: 60, repMax: 90, unit: "seconds"),
                    ExerciseSpec(name: "Pain-Free Joint Circles", repMin: 5, repMax: 8, perSide: true),
                    ExerciseSpec(name: "Supported Sit-to-Stand", repMin: 6, repMax: 10, rest: 60,
                                 notes: "Stop with pain, instability or unusual symptoms."),
                    ExerciseSpec(name: "Easy Walk", sets: 1, repMin: 8, repMax: 12, unit: "minutes"),
                ]
            ),
            SessionSpec(
                name: "Clearance Reset B", type: "mobility", minutes: 18, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Easy Walk", sets: 1, repMin: 10, repMax: 15, unit: "minutes"),
                    ExerciseSpec(name: "Wall Shoulder Slide", repMin: 6, repMax: 10, rest: 45),
                    ExerciseSpec(name: "Supported Calf Raise", repMin: 8, repMax: 12, rest: 45),
                    ExerciseSpec(name: "Gentle Mobility Flow", sets: 1, repMin: 4, repMax: 6, unit: "minutes"),
                ]
            ),
        ]
    }

    private static func gymSessions(phase: String, count: Int) -> [SessionSpec] {
        let main = phase == "main"
        let sets = main ? 3 : 2
        let warmup = "Five minutes easy cardio, then two gradual practice sets for the first loaded movement."
        let fullBody = [
            SessionSpec(
                name: "Full Body A", type: "upper", minutes: main ? 52 : 38, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Leg Press", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 5),
                    ExerciseSpec(name: "Machine Chest Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: "Seated Cable Row", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Seated Leg Curl", sets: sets, repMin: 10, repMax: 15, rest: 75, increment: 2.5),
                    ExerciseSpec(name: "Pallof Press", repMin: 8, repMax: 12, perSide: true, rest: 45),
                ]
            ),
            SessionSpec(
                name: "Full Body B", type: "legs_b", minutes: main ? 54 : 40, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Dumbbell Romanian Deadlift", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 2.5),
                    ExerciseSpec(name: "Lat Pulldown", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: "Machine Shoulder Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Supported Split Squat", sets: sets, repMin: 8, repMax: 10, perSide: true, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Farmer Carry", sets: 3, repMin: 30, repMax: 45, unit: "seconds", rest: 60, increment: 2.5),
                ]
            ),
            SessionSpec(
                name: "Full Body C", type: "upper", minutes: main ? 52 : 38, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Hack Squat", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 5),
                    ExerciseSpec(name: "Incline Dumbbell Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: "Chest-Supported Row", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Cable Lateral Raise", repMin: 12, repMax: 18, rest: 45, increment: 1),
                    ExerciseSpec(name: "Dead Bug", repMin: 8, repMax: 12, perSide: true, rest: 45),
                ]
            ),
        ]
        if count < 4 { return Array(fullBody.prefix(count)) }
        let split = [
            SessionSpec(name: "Upper A", type: "upper", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: Array(fullBody[0].exercises.dropFirst())),
            SessionSpec(name: "Lower A", type: "legs_a", minutes: main ? 50 : 36, warmup: warmup,
                        exercises: [fullBody[0].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[3], fullBody[2].exercises[4]]),
            SessionSpec(name: "Upper B", type: "upper", minutes: fullBody[2].minutes, warmup: warmup,
                        exercises: Array(fullBody[2].exercises.dropFirst())),
            SessionSpec(name: "Lower B", type: "legs_b", minutes: main ? 50 : 36, warmup: warmup,
                        exercises: [fullBody[2].exercises[0], fullBody[1].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[4]]),
        ]
        let capacity = SessionSpec(
            name: "Capacity & Core", type: "fix", minutes: main ? 38 : 28, warmup: warmup,
            exercises: [
                fullBody[1].exercises[1],
                fullBody[2].exercises[4],
                fullBody[1].exercises[4],
            ]
        )
        if count == 5 { return split + [capacity] }
        if count >= 6 {
            return Array([
                cappedHardSets(split[0]),
                cappedHardSets(split[1]),
                mobilityAndCoreSession(),
                cappedHardSets(split[2]),
                cappedHardSets(split[3]),
                cappedHardSets(capacity),
                recoverySession(),
            ].prefix(count))
        }
        return split
    }

    private static func homeSessions(
        phase: String,
        count: Int,
        equipment: [String],
        venueLabel: String
    ) -> [SessionSpec] {
        let main = phase == "main"
        let sets = main ? 3 : 2
        let names = homeNames(equipment)
        let warmup = "Five minutes of pain-free joint preparation, then one easy practice set."
        let row = names["row"] ?? "Band Row"
        let fullBody = [
            SessionSpec(
                name: "\(venueLabel) Full Body A", type: "upper", minutes: main ? 44 : 30, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: names["squat"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2),
                    ExerciseSpec(name: names["push"] ?? "", sets: sets, repMin: 8, repMax: 15, rest: 75, increment: 2, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: row, sets: sets, repMin: 8, repMax: 15, perSide: row.contains("One-Arm"), rest: 75, increment: 2, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Dead Bug", repMin: 8, repMax: 12, perSide: true, rest: 30),
                    ExerciseSpec(name: names["carry"] ?? "", sets: 3, repMin: 30, repMax: 45, unit: "seconds", perSide: true, rest: 45, increment: 2),
                ]
            ),
            SessionSpec(
                name: "\(venueLabel) Full Body B", type: "legs_b", minutes: main ? 46 : 32, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: names["hinge"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2),
                    ExerciseSpec(name: names["press"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 75, increment: 2, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: names["pull"] ?? "", sets: sets, repMin: 6, repMax: 12, rest: 90, increment: 1, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Supported Reverse Lunge", repMin: 8, repMax: 10, perSide: true, rest: 75),
                    ExerciseSpec(name: "Side Plank", repMin: 20, repMax: 35, unit: "seconds", perSide: true, rest: 30),
                ]
            ),
            SessionSpec(
                name: "\(venueLabel) Full Body C", type: "upper", minutes: main ? 44 : 30, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Step-Up", sets: sets, repMin: 8, repMax: 12, perSide: true, rest: 75, increment: 2),
                    ExerciseSpec(name: names["push"] ?? "", sets: sets, repMin: 8, repMax: 15, rest: 75, increment: 2, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 1),
                    ExerciseSpec(name: row, sets: sets, repMin: 8, repMax: 15, perSide: row.contains("One-Arm"), rest: 75, increment: 2, workGroupKey: main ? nil : "upper-pair", workGroupPosition: 2),
                    ExerciseSpec(name: "Hip Thrust", sets: sets, repMin: 10, repMax: 15, rest: 75, increment: 2),
                    ExerciseSpec(name: "Bird-Dog", repMin: 6, repMax: 10, perSide: true, rest: 30),
                ]
            ),
        ]
        if count < 4 { return Array(fullBody.prefix(count)) }
        let split = [
            SessionSpec(name: "\(venueLabel) Upper A", type: "upper", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: Array(fullBody[0].exercises.dropFirst())),
            SessionSpec(name: "\(venueLabel) Lower A", type: "legs_a", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: [fullBody[0].exercises[0], fullBody[1].exercises[0], fullBody[1].exercises[3], fullBody[0].exercises[3]]),
            SessionSpec(name: "\(venueLabel) Upper B", type: "upper", minutes: fullBody[2].minutes, warmup: warmup,
                        exercises: [fullBody[2].exercises[1], fullBody[2].exercises[2], withoutWorkGroup(fullBody[1].exercises[1]), fullBody[2].exercises[4]]),
            SessionSpec(name: "\(venueLabel) Lower B", type: "legs_b", minutes: fullBody[1].minutes, warmup: warmup,
                        exercises: [fullBody[2].exercises[0], fullBody[2].exercises[3], fullBody[1].exercises[0], fullBody[1].exercises[4]]),
        ]
        let capacity = SessionSpec(
            name: "\(venueLabel) Capacity & Core", type: "fix",
            minutes: main ? 34 : 24, warmup: warmup,
            exercises: [
                fullBody[0].exercises[4],
                fullBody[1].exercises[4],
                fullBody[2].exercises[4],
            ]
        )
        if count == 5 { return split + [capacity] }
        if count >= 6 {
            let prefix = "\(venueLabel) "
            return Array([
                cappedHardSets(split[0]),
                cappedHardSets(split[1]),
                mobilityAndCoreSession(prefix: prefix),
                cappedHardSets(split[2]),
                cappedHardSets(split[3]),
                cappedHardSets(capacity),
                recoverySession(prefix: prefix),
            ].prefix(count))
        }
        return split
    }

    private static func weekdays(for count: Int) -> [Int] {
        if count == 2 { return [1, 4] }
        if count == 3 { return [1, 3, 5] }
        if count == 4 { return [1, 2, 4, 6] }
        if count == 5 { return [1, 2, 4, 5, 7] }
        return Array(1...count)
    }

    // MARK: - Generation

    struct GeneratedPlan: Sendable {
        let programs: [Program]
        let programDays: [ProgramDay]
        let exercises: [Exercise]
        let induction: [String: JSONValue]
    }

    static func generate(
        userID: UUID,
        input: Input,
        existingPrograms: [Program] = [],
        generationRevision: Int = 0,
        completedAt: String = ISO8601DateFormatter().string(from: .now)
    ) -> GeneratedPlan {
        let assessment = assess(input)
        let count = assessment.sessionsPerWeek
        let planWeeks = supportedPlanWeeks.contains(input.planWeeks) ? input.planWeeks : 12
        let transitionWeeks = min(12, planWeeks)
        let mainStart = APEXDateMath.adding(days: transitionWeeks * 7, to: input.startDate)
        let endDate = APEXDateMath.adding(days: planWeeks * 7, to: input.startDate)
        let venue: String
        switch input.venue {
        case "gym": venue = "Gym"
        case "outdoors": venue = "Outdoor"
        default: venue = "Home"
        }

        func program(_ slug: String) -> Program {
            let generatedID = APEXStableID.inductionUUID(userID: userID, label: "program:\(slug)")
            if let existing = existingPrograms.first(where: {
                $0.userID == userID && $0.slug == slug
            }), existing.id != generatedID {
                return existing
            }
            return Program(
                id: generatedID,
                userID: userID,
                slug: slug,
                name: slug == "transition" ? "\(transitionWeeks)-Week \(venue) Foundation" : "Personal \(venue) Main Phase",
                description: slug == "transition"
                    ? (transitionWeeks == 4
                        ? "Weeks 1-4 restore consistency. A simple schedule built from your answers."
                        : transitionWeeks == 8
                            ? "Weeks 1-4 restore, weeks 5-8 build. A simple schedule built from your answers."
                            : "Weeks 1-4 restore, weeks 5-8 build, weeks 9-12 progress. A simple schedule built from your answers.")
                    : "Your follow-on strength and muscle phase, using the same equipment, recovery limits and weekly rhythm."
            )
        }

        let programs = [program("transition"), program("main")]
        var programDays: [ProgramDay] = []
        var exercises: [Exercise] = []
        var dayIDs: [String: [String]] = ["transition": [], "main": []]
        let revisionSuffix = generationRevision > 0 ? ":generation:\(generationRevision)" : ""

        for slug in ["transition", "main"] {
            guard let programme = programs.first(where: { $0.slug == slug }) else { continue }
            let sessions = assessment.caution == "clearance"
                ? clearanceSessions()
                : (input.venue == "gym"
                    ? gymSessions(phase: slug, count: count)
                    : homeSessions(
                        phase: slug,
                        count: count,
                        equipment: input.equipment,
                        venueLabel: venue
                    ))
            let days = weekdays(for: count)

            for (sessionIndex, spec) in sessions.enumerated() {
                let weekday = days[min(sessionIndex, days.count - 1)]
                let dayID = APEXStableID.inductionUUID(
                    userID: userID,
                    label: "\(slug):day:\(weekday)\(revisionSuffix)"
                )
                dayIDs[slug]?.append(dayID.uuidString.lowercased())
                programDays.append(
                    ProgramDay(
                        id: dayID,
                        userID: userID,
                        programID: programme.id,
                        weekday: weekday,
                        name: spec.name,
                        dayType: spec.type,
                        estimatedMinutes: spec.minutes,
                        warmupNote: assessment.caution == "cautious"
                            ? "\(spec.warmup) Start with 3-4 reps in reserve and keep every movement pain-free."
                            : spec.warmup,
                        sortOrder: sessionIndex
                    )
                )

                func add(_ spec: ExerciseSpec, index: Int, lite: Bool) {
                    exercises.append(
                        Exercise(
                            id: APEXStableID.inductionUUID(
                                userID: userID,
                                label: "\(slug):day:\(weekday):\(lite ? "lite" : "full"):\(index)\(revisionSuffix)"
                            ),
                            userID: userID,
                            programDayID: dayID,
                            name: spec.name,
                            workGroupID: spec.workGroupKey.map { key in
                                APEXStableID.inductionUUID(
                                    userID: userID,
                                    label: "\(slug):day:\(weekday):work-group:\(key)\(revisionSuffix)"
                                )
                            },
                            workGroupPosition: spec.workGroupKey == nil ? nil : spec.workGroupPosition,
                            sets: max(1, spec.sets - (lite ? 1 : 0)),
                            repMin: spec.repMin,
                            repMax: spec.repMax,
                            repUnit: spec.unit,
                            perSide: spec.perSide,
                            restSeconds: spec.rest,
                            tempoUp: 1,
                            tempoDown: assessment.caution == "standard" ? 2 : 3,
                            tempoPause: 0,
                            tempoNote: "",
                            notes: spec.notes ?? (assessment.caution == "cautious"
                                ? "Pain-free range. Stop with at least 3 reps in reserve."
                                : "Progress only after every rep is controlled."),
                            incrementKG: spec.increment,
                            isLite: lite,
                            optional: spec.optional,
                            sortOrder: index
                        )
                    )
                }

                for (index, exercise) in spec.exercises.enumerated() { add(exercise, index: index, lite: false) }
                for (index, exercise) in spec.exercises.prefix(3).enumerated() { add(exercise, index: index, lite: true) }

                let full = exercises
                    .filter { $0.programDayID == dayID && !$0.isLite }
                    .map { PlannedExercise(exercise: $0, plannedSets: $0.sets, swapped: false) }
                if let dayIndex = programDays.firstIndex(where: { $0.id == dayID }), !full.isEmpty {
                    var generatedDay = programDays[dayIndex]
                    generatedDay.estimatedMinutes = PlayerTimeline.estimatedMinutes(
                        PlannedDay(
                            programDay: generatedDay,
                            exercises: full,
                            warmup: generatedDay.warmupNote,
                            warmupDuration: 180
                        )
                    )
                    programDays[dayIndex] = generatedDay
                }
            }
        }

        var induction: [String: JSONValue] = [
            "version": .number(1),
            "generation_revision": .number(Double(generationRevision)),
            "completed_at": .string(completedAt),
            "start_date": .string(input.startDate),
            "main_start_date": .string(mainStart),
            "end_date": .string(endDate),
            "plan_weeks": .number(Double(planWeeks)),
            "transition_weeks": .number(Double(transitionWeeks)),
            "inactivity": .string(input.inactivity),
            "venue": .string(input.venue),
            "equipment": .array(input.equipment.map { .string($0) }),
            "pain_areas": .array(input.painAreas.map { .string($0) }),
            "recent_operation": .bool(input.recentOperation),
            "chronic_lower_back_pain": .bool(input.chronicLowerBackPain),
            "sessions_per_week": .number(Double(count)),
            "goal": .string(input.goal),
            "caution": .string(assessment.caution),
            "weekly_load_strategy": .string(
                count >= 7 ? "distributed_with_recovery" : (count >= 6 ? "distributed" : "standard")
            ),
            "transition_day_ids": .array((dayIDs["transition"] ?? []).map { .string($0) }),
            "main_day_ids": .array((dayIDs["main"] ?? []).map { .string($0) }),
        ]
        if count >= 6 { induction["hard_set_cap"] = .number(2) }

        return GeneratedPlan(
            programs: programs,
            programDays: programDays,
            exercises: exercises,
            induction: induction
        )
    }

    // MARK: - Post-generation briefing

    enum PlanBriefingSlideKind: String, Equatable, Sendable {
        case overview
        case safety
        case hydration
        case sleep
        case supplements
    }

    enum PlanBriefingBulletIcon: String, Equatable, Hashable, Sendable {
        case calendar
        case dumbbell = "dumbbell.fill"
        case trend = "chart.line.uptrend.xyaxis"
        case stop = "hand.raised.fill"
        case emergency = "phone.fill"
        case medical = "stethoscope"
        case water = "drop.fill"
        case electrolytes = "bolt.heart.fill"
        case sodium = "wave.3.right"
        case sleep = "bed.double.fill"
        case schedule = "alarm.fill"
        case recovery = "gauge.with.dots.needle.67percent"
        case food = "fork.knife"
        case creatine = "figure.strengthtraining.traditional"
        case omega3 = "fish.fill"
    }

    struct PlanBriefingBullet: Equatable, Hashable, Sendable {
        let text: String
        let icon: PlanBriefingBulletIcon
    }

    struct PlanBriefingSlide: Equatable, Sendable {
        let kind: PlanBriefingSlideKind
        let eyebrow: String
        let title: String
        let body: String
        let bullets: [PlanBriefingBullet]
        let assetName: String
        let evidenceLabel: String
        let evidenceURL: URL?
        let energyPresets: [NutritionGoalPreset]
        let recommendedGoal: Goal?
    }

    struct PlanBriefing: Equatable, Sendable {
        let hydrationTargetML: Int
        let slides: [PlanBriefingSlide]
    }

    /// Builds the induction deck from the same answers and hydration policy
    /// that produced the installed plan. It deliberately does not turn a
    /// vague "pinch of salt" into universal advice: sodium replacement is
    /// conditional on prolonged heat/sweat exposure and medical restrictions.
    static func planBriefing(
        input: Input,
        caution: String,
        sex: String,
        weightKG: Double,
        plannedExerciseMinutes: Int,
        hydrationMode: HydrationTargetMode,
        customHydrationTargetML: Int?,
        displayUnit: String
    ) -> PlanBriefing {
        let hydration = HydrationTargetPolicy.resolve(
            sex: sex,
            weightKG: weightKG,
            mode: hydrationMode,
            customTargetML: customHydrationTargetML,
            plannedExerciseMinutes: plannedExerciseMinutes
        )
        let duration = input.planWeeks == 26 ? "6-month" : "\(input.planWeeks)-week"
        let goal: String
        switch input.goal {
        case "muscle": goal = "muscle-building"
        case "fat_loss": goal = "fat-loss"
        case "strength": goal = "strength"
        case "endurance": goal = "endurance"
        default: goal = "general fitness"
        }
        let venue: String
        switch input.venue {
        case "gym": venue = "in the gym"
        case "outdoors": venue = "outdoors"
        default: venue = "at home"
        }
        let target: String
        if displayUnit == "gallons" {
            target = String(format: "%.2f US gal", Double(hydration.targetML) / 3_785.411_784)
        } else {
            target = String(format: "%.2f L", Double(hydration.targetML) / 1_000)
        }
        let safetyBody = caution == "clearance"
            ? "Your answers require clinical clearance before loaded training. Start only when the clinician managing your recovery approves it."
            : "Training effort is normal. Stop for sharp pain, chest pressure, fainting, or sudden breathlessness."
        let energyPresets = NutritionGoalPolicy.presets(
            context: NutritionPlanContext(trainingGoal: input.goal, planWeeks: input.planWeeks)
        )

        return PlanBriefing(
            hydrationTargetML: hydration.targetML,
            slides: [
                PlanBriefingSlide(
                    kind: .overview,
                    eyebrow: "WHY THIS PLAN FITS",
                    title: "\(duration) \(goal) · \(input.sessionsPerWeek) sessions/week",
                    body: "Your goal and answers set the training load, recovery spacing and energy choices. Built \(venue).",
                    bullets: [
                        PlanBriefingBullet(text: "Your calendar now has real start and end dates.", icon: .calendar),
                        PlanBriefingBullet(text: "Every session respects the equipment and recovery limits you selected.", icon: .dumbbell),
                        PlanBriefingBullet(text: "Log completed work; APEX adapts from measured training.", icon: .trend),
                    ],
                    assetName: "plan-briefing-overview",
                    evidenceLabel: "Your answers · APEX plan engine",
                    evidenceURL: nil,
                    energyPresets: energyPresets,
                    recommendedGoal: NutritionGoalPolicy.recommendedGoal(for: input.goal)
                ),
                PlanBriefingSlide(
                    kind: .safety,
                    eyebrow: "TRAIN SMART",
                    title: "Know when to stop",
                    body: safetyBody,
                    bullets: [
                        PlanBriefingBullet(text: "Stop immediately for sharp or escalating pain.", icon: .stop),
                        PlanBriefingBullet(text: "For chest pressure, fainting, or sudden breathlessness, call emergency services (144 in Switzerland).", icon: .emergency),
                        PlanBriefingBullet(text: "Persistent or worsening symptoms need medical assessment before your next session.", icon: .medical),
                    ],
                    assetName: "plan-briefing-safety",
                    evidenceLabel: "Swiss Heart Foundation",
                    evidenceURL: URL(string: "https://swissheart.ch/erkrankungen-und-notfall/notfall/verhalten-im-notfall"),
                    energyPresets: [],
                    recommendedGoal: nil
                ),
                PlanBriefingSlide(
                    kind: .hydration,
                    eyebrow: "HYDRATION",
                    title: "Your starting target: \(target)",
                    body: "This includes drinks and water in food. Recorded activity can adjust it later.",
                    bullets: [
                        PlanBriefingBullet(text: "Plain water and regular meals cover most shorter sessions.", icon: .water),
                        PlanBriefingBullet(text: "Long, hot, or very sweaty training may warrant a formulated electrolyte drink.", icon: .electrolytes),
                        PlanBriefingBullet(text: "If sodium-restricted, follow your clinician’s advice.", icon: .sodium),
                    ],
                    assetName: "plan-briefing-hydration",
                    evidenceLabel: "Swiss FSVO · APEX hydration policy",
                    evidenceURL: URL(string: "https://www.blv.admin.ch/dam/blv/en/dokumente/lebensmittel-und-ernaehrung/ernaehrung/Ernaehrungsempfehlungen/Schweizer%20Ern%C3%A4hrungsempfehlungen_Langversion_EN.pdf.download.pdf/Schweizer%20Ern%C3%A4hrungsempfehlungen_Langversion_EN.pdf"),
                    energyPresets: [],
                    recommendedGoal: nil
                ),
                PlanBriefingSlide(
                    kind: .sleep,
                    eyebrow: "RECOVERY",
                    title: "Make sleep repeatable",
                    body: "Consistent sleep and wake timing supports recovery better than chasing a perfect single night.",
                    bullets: [
                        PlanBriefingBullet(text: "Aim for at least seven hours when your schedule allows.", icon: .sleep),
                        PlanBriefingBullet(text: "Keep wake time steady and seek daylight early.", icon: .schedule),
                        PlanBriefingBullet(text: "If sleep and performance decline, reduce training load.", icon: .recovery),
                    ],
                    assetName: "plan-briefing-sleep",
                    evidenceLabel: "Swiss Society for Sleep Research (SSSSC)",
                    evidenceURL: URL(string: "https://swiss-sleep.ch/"),
                    energyPresets: [],
                    recommendedGoal: nil
                ),
                PlanBriefingSlide(
                    kind: .supplements,
                    eyebrow: "EVIDENCE FIRST",
                    title: "Start with what works",
                    body: "Food does the foundational work. Supplements are optional tools for specific gaps.",
                    bullets: [
                        PlanBriefingBullet(text: "Protein powder can help when meals miss your protein target.", icon: .food),
                        PlanBriefingBullet(text: "Creatine monohydrate supports repeated high-intensity and strength work.", icon: .creatine),
                        PlanBriefingBullet(text: "Fatty fish or algae-derived EPA/DHA can address omega-3 intake.", icon: .omega3),
                    ],
                    assetName: "plan-briefing-supplements",
                    evidenceLabel: "Swiss Sports Nutrition Society (SSNS)",
                    evidenceURL: URL(string: "https://www.ssns.ch/sportsnutrition/supplemente/supplementguide/"),
                    energyPresets: [],
                    recommendedGoal: nil
                ),
            ]
        )
    }
}
