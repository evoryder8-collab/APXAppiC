/*
 * Bridges the app's DashboardData into the pure FitnessBrainEngine and back.
 * The phone computes its own snapshots now; Supabase receives only the
 * newest one, under the same deterministic per-user id the web client
 * writes, so both clients converge on identical rows.
 */
import Foundation

enum FitnessBrainService {
    // MARK: - Deterministic ids (port of src/lib/ids.ts scopedUuid)

    private static func hash32(_ value: String, seed: UInt32) -> UInt32 {
        var hash = seed
        for unit in value.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16777619
        }
        hash ^= hash >> 16
        hash = hash &* 0x7feb352d
        hash ^= hash >> 15
        return hash
    }

    static func scopedUuid(namespace: String, date: String, userID: String) -> String {
        let input = "\(namespace):\(userID):\(date)"
        let raw = [
            hash32(input, seed: 0x811c9dc5),
            hash32(input, seed: 0x9e3779b9),
            hash32(input, seed: 0x85ebca6b),
            hash32(input, seed: 0xc2b2ae35),
        ].map { String(format: "%08x", $0) }.joined()
        let chars = Array(raw)
        let variantNibble = (UInt8(String(chars[16]), radix: 16)! & 0x3) | 0x8
        let variant = String(variantNibble, radix: 16)
        let p1 = String(chars[0..<8])
        let p2 = String(chars[8..<12])
        let p3 = "4" + String(chars[13..<16])
        let p4 = variant + String(chars[17..<20])
        let p5 = String(chars[20..<32])
        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }

    static func rpgSnapshotId(date: String, userID: UUID) -> UUID {
        UUID(uuidString: scopedUuid(
            namespace: "rpg-snapshot", date: date,
            userID: userID.uuidString.lowercased()))!
    }

    // MARK: - DashboardData -> engine input

    static func engineInput(from data: DashboardData, timeZone: TimeZone = .current) -> FBEngineInput? {
        guard let storedProfile = data.profile else { return nil }
        let profile = RestingEnergyPolicy.applied(to: storedProfile, settings: data.settings)
        var fbProfile = FBProfile(
            userID: profile.userID.uuidString.lowercased(),
            persona: FBPersona(rawValue: profile.persona.rawValue) ?? .constantine,
            sex: profile.sex,
            weightKG: profile.weightKG,
            bodyFatPct: profile.bodyFatPercent,
            customBMR: profile.customBMR,
            heightCM: profile.heightCM,
            birthdate: profile.birthdate,
            activityLevel: FBActivityLevel(rawValue: profile.activityLevel.rawValue) ?? .moderate,
            goal: FBGoal(rawValue: profile.goal.rawValue) ?? .recomp,
            baselineDate: profile.baselineDate,
            profileKind: profile.profileKind?.rawValue,
            bespokeProtocolID: profile.bespokeProtocolID?.rawValue,
            bodyFatSource: profile.bodyFatSource?.rawValue
        )

        fbProfile.avatarStartingPoints = profile.avatarStartingPoints
        let hasChosenStart = ProfileIntegrityPolicy.authorizedProtocol(for: profile) == nil
            && AvatarStartingPoints.stats(profile.avatarStartingPoints) != nil
        let ownerID = profile.userID
        let programDays = data.programDays.compactMap { day -> FBProgramDayRef? in
            // A coach plan has no day category of its own. Its performed movements earn the
            // credit, exactly as a custom workout's do.
            guard day.userID == ownerID,
                  let type = FBDayType(rawValue: day.dayType == "coach" ? "custom" : day.dayType)
            else { return nil }
            return FBProgramDayRef(id: day.id.uuidString.lowercased(), dayType: type)
        }
        let exercises = data.exercises.filter { $0.userID == ownerID }.map {
            FBExerciseRef(
                id: $0.id.uuidString.lowercased(),
                programDayID: $0.programDayID.uuidString.lowercased())
        }
        let ownedSessions = StrengthProgress.withoutReplays(data.workoutSessions.filter { $0.userID == ownerID })
        let ownedSessionIDs = Set(ownedSessions.map(\.id))
        let sessions = ownedSessions.map {
            FBWorkoutSession(
                id: $0.id.uuidString.lowercased(),
                date: $0.date,
                programDayID: $0.programDayID.uuidString.lowercased(),
                isDeload: $0.isDeload,
                isEventRecovery: $0.isEventRecovery,
                completed: $0.completed,
                qualityScore: $0.qualityScore, notes: $0.notes)
        }
        let logs = data.workoutLogs
            .filter { $0.userID == ownerID && ownedSessionIDs.contains($0.sessionID) }
            .map {
            var log = FBWorkoutLog(
                id: $0.id.uuidString.lowercased(),
                sessionID: $0.sessionID.uuidString.lowercased(),
                exerciseID: $0.exerciseID?.uuidString.lowercased(),
                exerciseName: $0.exerciseName,
                weightKG: $0.weightKG,
                skipped: $0.skipped,
                overrideFlag: $0.overrideFlag,
                movementID: $0.movementID, reps: $0.reps,
                durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters,
                contacts: $0.contacts, rounds: $0.rounds, workSeconds: $0.workSeconds)
            log.performedTypes = MovementTiming.performedWorkoutTypes(for: log)
            return log
        }
        let dailyLogs = data.dailyLogs.filter { $0.userID == ownerID }.map {
            FBDailyLog(
                date: $0.date,
                kcal: $0.kcal.map(Double.init),
                proteinG: $0.proteinG.map(Double.init),
                waterL: $0.waterL)
        }
        // Older builds stamped the newest Health sample on every later day. A repeated value
        // is that one reading, so it anchors Endurance once.
        var lastVO2: Double?
        let metrics = data.healthMetrics.filter { $0.userID == ownerID }.sorted { $0.date < $1.date }.map { metric in
            let vo2 = metric.vo2Max == lastVO2 ? nil : metric.vo2Max
            lastVO2 = metric.vo2Max ?? lastVO2
            return FBHealthMetric(date: metric.date, vo2max: vo2, restingHR: metric.restingHeartRate)
        }
        let apexSessionIdentities = data.workoutSessions.compactMap {
            session -> ExternalWorkoutImport.APEXSessionIdentity? in
            guard session.userID == profile.userID,
                  let startedAt = ExternalWorkoutImport.parseTimestamp(
                    session.startedAt ?? session.completedAt
                  ) else { return nil }
            return .init(id: session.id, startedAt: startedAt)
        }
        let completedByDate = Dictionary(grouping: ownedSessions.filter(\.completed), by: \.date)
        let modesBySession = Dictionary(grouping: data.workoutLogs.filter { $0.userID == ownerID }, by: \.sessionID)
            .mapValues(TrainingProfile90.modes(of:))
        let imports = data.importedActivities.compactMap { activity -> FBImportedActivity? in
            guard activity.userID == profile.userID,
                  activity.isVisibleInAPEX,
                  activity.apexWorkoutSessionID == nil,
                  ExternalWorkoutImport.isAPEXMirror(
                    activity,
                    apexSessions: apexSessionIdentities
                  ) == false,
                  // An unlinked Watch recording of an app workout is that workout, not a second one.
                  completedByDate[activity.date]?.contains(where: {
                      TrainingProfile90.recordsSameWorkout(activity, as: $0, modes: modesBySession[$0.id] ?? [])
                  }) != true,
                  let kind = FBImportKind(rawValue: activity.kind) else { return nil }
            return FBImportedActivity(
                date: activity.date, kind: kind, durationMin: Double(activity.durationMinutes))
        }

        let nutritionPlanContext = NutritionGoalPolicy.context(from: data.settings)
        var input = FBEngineInput(
            profile: fbProfile,
            programDays: programDays,
            exercises: exercises,
            workoutSessions: sessions,
            workoutLogs: logs,
            dailyLogs: dailyLogs,
            healthMetrics: metrics,
            importedActivities: imports,
            capacityCalibrationEvidence: capacityCalibrationEvidence(
                from: (data.fitnessEvidence ?? []).filter { record in
                    !hasChosenStart
                        || record.protocol != "apex_onboarding_pulse_v1" || String(record.measuredAt.prefix(10)) > profile.baselineDate
                },
                ownerID: profile.userID
            ),
            recoveryHistory: recoveryHistory(from: data.settings?.addons),
            mealRhythmHistory: mealRhythmHistory(from: data.settings?.addons),
            trainingGoal: nutritionPlanContext?.trainingGoal,
            planWeeks: nutritionPlanContext?.planWeeks
        )
        if data.settings?.userID == ownerID { input.avatarCalibration = data.settings?.avatarCalibration }
        return input
    }

    /// Fold meals and the hydration ledger once when replaying many days of history.
    static func waterTotals(_ data: DashboardData, ownerID: UUID) -> [String: Int] {
        var mealDates: [UUID: String] = [:]
        for meal in data.loggedMeals where meal.userID == ownerID { mealDates[meal.id] = meal.localDate }
        var foodByDay: [String: Double] = [:]
        for entry in data.loggedFoodEntries where entry.userID == ownerID {
            guard let date = mealDates[entry.mealID],
                  let water = entry.waterML ?? FoodHydration.portionWater(entry.snapshotWaterML100, equivalentAmount: entry.equivalentAmount),
                  water.isFinite, water > 0 else { continue }
            foodByDay[date, default: 0] += water
        }
        let events = Dictionary(grouping: (data.hydrationEvents ?? []).filter { $0.userID == ownerID }, by: \.localDate)
        var drinks: [String: Double] = [:]
        for log in data.dailyLogs where log.userID == ownerID && log.waterL > 0 { drinks[log.date] = log.waterL }
        var totals: [String: Int] = [:]
        for day in Set(foodByDay.keys).union(events.keys).union(drinks.keys) {
            let ledger = HydrationLedger.resolve(ownerID: ownerID, date: day, events: events[day] ?? [], legacyDrinkLiters: drinks[day] ?? 0)
            totals[day] = ledger.drinkML + max(ledger.foodML, Int((foodByDay[day] ?? 0).rounded()))
        }
        return totals
    }

    // MARK: - addons JSON extraction

    static func capacityCalibrationEvidence(
        from records: [FitnessEvidenceRecord],
        ownerID: UUID,
        timeZone: TimeZone = .current
    ) -> [FBCapacityCalibrationEvidence] {
        let supportedProtocols: Set<String> = [
            "apex_onboarding_pulse_v1",
            "apex_baseline_calibration_v1",
        ]
        let metrics: [FitnessEvidenceMetric: FBCapacityCalibrationMetric] = [
            .cardioCapacityScore: .cardiorespiratory,
            .upperBodyStrengthScore: .upperStrength,
            .lowerBodyStrengthScore: .lowerStrength,
            .flexibilityScore: .flexibility,
        ]

        return records.compactMap { record in
            guard record.userID == ownerID,
                  record.source == .structuredSelfReport,
                  record.confidence == .low,
                  record.unit == "score_0_100",
                  record.value.isFinite,
                  (0...100).contains(record.value),
                  let protocolName = record.protocol,
                  supportedProtocols.contains(protocolName),
                  let metric = metrics[record.metric],
                  record.measuredAt.count >= 10 else { return nil }

            let measuredOn = String(record.measuredAt.prefix(10))
            guard measuredOn.count == 10,
                  measuredOn[measuredOn.index(measuredOn.startIndex, offsetBy: 4)] == "-",
                  measuredOn[measuredOn.index(measuredOn.startIndex, offsetBy: 7)] == "-" else {
                return nil
            }
            let declaredCoverage = record.metadata["coverage"]?.numberValue
            let answeredCount = record.metadata["answered_count"]?.numberValue
            let inferredCoverage = answeredCount.map { ($0 / 3) * 0.55 } ?? 0.35
            let coverage = min(0.55, max(0, declaredCoverage ?? inferredCoverage))
            guard coverage > 0 else { return nil }

            return FBCapacityCalibrationEvidence(
                id: record.id.uuidString.lowercased(),
                userID: record.userID.uuidString.lowercased(),
                metric: metric,
                value: record.value,
                measuredOn: measuredOn,
                importedAt: record.importedAt,
                coverage: coverage,
                supersedesID: record.supersedesID?.uuidString.lowercased()
            )
        }
    }

    static func recoveryHistory(from addons: [String: JSONValue]?) -> [FBRecoveryCheckin] {
        guard case let .array(items)? = addons?["recovery_history"] else { return [] }
        return items.compactMap { item in
            guard case let .object(fields) = item,
                  case let .string(date)? = fields["date"],
                  case let .string(sourceRaw)? = fields["source"],
                  let source = FBRecoverySource(rawValue: sourceRaw) else { return nil }
            return FBRecoveryCheckin(
                date: date,
                source: source,
                sleepScore: number(fields["sleep_score"]),
                recoveryPct: number(fields["recovery_pct"]))
        }
    }

    static func mealRhythmHistory(from addons: [String: JSONValue]?) -> [String: FBMealRhythmDayRaw] {
        guard case let .object(days)? = addons?["meal_rhythm_history"] else { return [:] }
        var out: [String: FBMealRhythmDayRaw] = [:]
        for (date, value) in days {
            guard case let .object(fields) = value else { continue }
            var verdict: String?
            if case let .string(v)? = fields["verdict"] { verdict = v }
            var finalized: Bool?
            if case let .bool(f)? = fields["finalized"] { finalized = f }
            out[date] = FBMealRhythmDayRaw(
                finalized: finalized,
                expectedMeals: number(fields["expected_meals"]),
                loggedMeals: number(fields["logged_meals"]),
                completionScore: number(fields["completion_score"]),
                rhythmScore: number(fields["rhythm_score"]),
                verdict: verdict)
        }
        return out
    }

    private static func number(_ value: JSONValue?) -> Double? {
        if case let .number(n)? = value { return n }
        return nil
    }

    // MARK: - engine output -> app rows

    static func appSnapshots(_ snapshots: [FBSnapshot], userID: UUID) -> [RPGSnapshot] {
        snapshots.map {
            RPGSnapshot(
                id: rpgSnapshotId(date: $0.date, userID: userID),
                userID: userID,
                date: $0.date,
                overall: $0.overall,
                health: $0.health,
                joint: $0.joint,
                flexibility: $0.flexibility,
                endurance: $0.endurance,
                strength: $0.strength,
                strengthUpper: $0.strengthUpper,
                strengthLower: $0.strengthLower)
        }
    }
}

/// The additional JSON column is independent of legacy scores older apps still update.
struct AvatarScorePublication: Encodable, Equatable, Sendable {
    let row: RPGSnapshot
    let verified: FBSnapshot?

    enum CodingKeys: String, CodingKey { case verified = "verified_avatar" }

    func encode(to encoder: Encoder) throws {
        try row.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let verified { try container.encode(verified, forKey: .verified) }
        else { try container.encodeNil(forKey: .verified) }
    }
}

/// A snapshot of the active plan and dated activity used by both the dashboard and history replay.
struct DailyWaterTargets {
    private let data: DashboardData
    private let phaseDays: [String: [ProgramDay]]
    private let activity: [String: [ActivityLog]]
    private let wearable: [String: WearableActivityRecord]
    private let coachManaged: Bool
    private let followsCoach: Bool
    private let includesCustom: Bool

    init(data: DashboardData, coachManaged: Bool, followsCoach: Bool, includeCustom: Bool) {
        self.data = data
        self.coachManaged = coachManaged
        self.followsCoach = followsCoach
        self.includesCustom = includeCustom
        let owner = data.profile?.userID
        let exercisedDays = Set(data.exercises.filter { $0.userID == owner && !$0.isLite }.map(\.programDayID))
        phaseDays = Dictionary(uniqueKeysWithValues: ["coach", "main", "transition", "custom"].map { slug in
            let days = TrainingInduction.visibleProgramDays(in: data, slug: slug).filter { exercisedDays.contains($0.id) }
            return (slug, days)
        })
        activity = Dictionary(grouping: data.activityLogs.filter { $0.userID == owner }, by: \.date)
        let history = data.settings?.userID == owner ? data.settings?.addons["watch_activity_history"] : nil
        wearable = Dictionary(WearableActivityRecord.history(from: history).map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func resolve(day: String, now: Date) -> HydrationTargetResolution {
        guard let profile = data.profile else { return HydrationTargetPolicy.resolve(sex: "male", weightKG: 87) }
        let preferences = data.hydrationPreferences.flatMap { $0.userID == profile.userID ? $0 : nil }
        if preferences?.effectiveTargetMode == .custom {
            return HydrationTargetPolicy.resolve(sex: profile.sex, weightKG: profile.weightKG, mode: .custom, customTargetML: preferences?.targetML)
        }
        let hasInduction = data.settings?.addons["training_induction"]?.objectValue != nil
        let main = phaseDays["main"]?.isEmpty == false
        let transition = phaseDays["transition"]?.isEmpty == false
        let slug = SimpleHomeLogic.guidedProgramSlug(persona: profile.persona, mainIsUsable: main, transitionIsUsable: transition,
            coachManaged: coachManaged, coachIsUsable: followsCoach && phaseDays["coach"]?.isEmpty == false,
            transitionInductionIsUsable: hasInduction && transition && TrainingPlanEngine.isInsideInductionWindow(data, slug: "transition", date: day),
            mainInductionIsUsable: hasInduction && main && TrainingPlanEngine.isInsideInductionWindow(data, slug: "main", date: day))
        let inside = TrainingPlanEngine.isInsideInductionWindow(data, slug: slug, date: day)
        let days = (inside ? (phaseDays[slug] ?? []) : []) + (includesCustom ? (phaseDays["custom"] ?? []) : [])
        let planned = days.filter { RecoveryPlanner.day($0, matches: day) }.reduce(0) { $0 + max(0, $1.estimatedMinutes) }
        let record = wearable[day]
        let logs = activity[day] ?? []
        let minutes = max(record?.exerciseMinutes ?? 0, logs.reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) })
        let today = now.apexDateKey
        return HydrationTargetPolicy.resolve(sex: profile.sex, weightKG: profile.weightKG, mode: .automatic,
            plannedExerciseMinutes: planned, recordedExerciseMinutes: minutes,
            activeCalories: EnergyEngine.resolvedActiveCalories(wearableActiveCalories: record?.activeCalories, logs: logs),
            steps: record?.steps, dateRelation: day < today ? .past : day > today ? .future : .today,
            localHour: Calendar.current.component(.hour, from: now))
    }
}
