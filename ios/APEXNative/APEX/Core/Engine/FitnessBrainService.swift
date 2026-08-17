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

    static func engineInput(from data: DashboardData) -> FBEngineInput? {
        guard let profile = data.profile else { return nil }
        let fbProfile = FBProfile(
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
            baselineDate: profile.baselineDate
        )

        let programDays = data.programDays.compactMap { day -> FBProgramDayRef? in
            guard let type = FBDayType(rawValue: day.dayType) else { return nil }
            return FBProgramDayRef(id: day.id.uuidString.lowercased(), dayType: type)
        }
        let exercises = data.exercises.map {
            FBExerciseRef(
                id: $0.id.uuidString.lowercased(),
                programDayID: $0.programDayID.uuidString.lowercased())
        }
        let sessions = data.workoutSessions.map {
            FBWorkoutSession(
                id: $0.id.uuidString.lowercased(),
                date: $0.date,
                programDayID: $0.programDayID.uuidString.lowercased(),
                isDeload: $0.isDeload,
                isEventRecovery: $0.isEventRecovery,
                completed: $0.completed,
                qualityScore: $0.qualityScore)
        }
        let logs = data.workoutLogs.map {
            FBWorkoutLog(
                id: $0.id.uuidString.lowercased(),
                sessionID: $0.sessionID.uuidString.lowercased(),
                exerciseID: $0.exerciseID?.uuidString.lowercased(),
                exerciseName: $0.exerciseName,
                weightKG: $0.weightKG,
                skipped: $0.skipped,
                overrideFlag: $0.overrideFlag)
        }
        let dailyLogs = data.dailyLogs.map {
            FBDailyLog(
                date: $0.date,
                kcal: $0.kcal.map(Double.init),
                proteinG: $0.proteinG.map(Double.init),
                waterL: $0.waterL)
        }
        let metrics = data.healthMetrics.map {
            FBHealthMetric(date: $0.date, vo2max: $0.vo2Max, restingHR: $0.restingHeartRate)
        }
        let imports = data.importedActivities.compactMap { activity -> FBImportedActivity? in
            guard let kind = FBImportKind(rawValue: activity.kind) else { return nil }
            return FBImportedActivity(
                date: activity.date, kind: kind, durationMin: Double(activity.durationMinutes))
        }

        return FBEngineInput(
            profile: fbProfile,
            programDays: programDays,
            exercises: exercises,
            workoutSessions: sessions,
            workoutLogs: logs,
            dailyLogs: dailyLogs,
            healthMetrics: metrics,
            importedActivities: imports,
            recoveryHistory: recoveryHistory(from: data.settings?.addons),
            mealRhythmHistory: mealRhythmHistory(from: data.settings?.addons)
        )
    }

    // MARK: - addons JSON extraction

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
