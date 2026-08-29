import Foundation

/*
 * The numbers behind the end-of-workout receipt, matching the web's
 * WorkoutStatsSheet.
 *
 * Loaded volume is the honest measure of what a session cost: every working
 * set's positive external load multiplied by its reps. Added load on a
 * bodyweight movement counts; assistance is negative on that same axis and
 * therefore contributes zero. A skipped set contributes nothing, and Focus
 * T25 is excluded because a conditioning episode has no load to report.
 */
enum WorkoutReceipt {
    struct HistoryItem: Identifiable, Hashable, Sendable {
        let session: WorkoutSession
        let title: String
        let isQuickLog: Bool
        let linkedWearable: ImportedActivity?

        var id: UUID { session.id }

        func attachingWearable(_ activity: ImportedActivity?) -> HistoryItem {
            HistoryItem(
                session: session,
                title: title,
                isQuickLog: isQuickLog,
                linkedWearable: activity
            )
        }
    }

    struct Summary: Hashable, Sendable {
        /// Kilograms moved: the sum of weight times reps across working sets.
        let loadedVolumeKG: Double
        let workingSets: Int
        let movements: Int

        var hasLoad: Bool { loadedVolumeKG > 0 }
    }

    struct DeletionPlan: Equatable, Sendable {
        let sessionID: UUID
        let logIDs: [UUID]
    }

    /// A resting compact receipt has no destructive tray in its hierarchy.
    /// The tray exists only during or after a deliberate leftward reveal;
    /// expanded cards use their separate compact corner action.
    static func collapsedDeleteTrayVisible(isExpanded: Bool, revealOffset: CGFloat) -> Bool {
        !isExpanded && revealOffset < 0
    }

    /// Resolve deletion from the authenticated owner rather than trusting the
    /// id supplied by a card. Independently owner-check every child set row.
    static func deletionPlan(
        sessions: [WorkoutSession],
        logs: [WorkoutLog],
        sessionID: UUID,
        ownerID: UUID
    ) -> DeletionPlan? {
        guard let session = sessions.first(where: {
            $0.id == sessionID && $0.userID == ownerID && $0.completed
        }) else { return nil }
        return DeletionPlan(
            sessionID: session.id,
            logIDs: logs
                .filter { $0.sessionID == session.id && $0.userID == ownerID }
                .map(\.id)
        )
    }

    static func summarize(_ logs: [WorkoutLog]) -> Summary {
        let working = logs.filter { !FocusT25.isFocusName($0.exerciseName) }
        let volume = working.reduce(0.0) { total, log in
            let descriptor = ExerciseLogging.descriptor(
                movementNamed: log.exerciseName,
                movementID: log.movementID
            )
            guard !log.skipped,
                  descriptor.kind == .strength || descriptor.kind == .bodyweight else {
                return total
            }
            return total + max(0, log.weightKG ?? 0) * Double(max(0, log.reps ?? 0))
        }
        /* Movements count every exercise performed, conditioning included,
           because the session did contain them even without a load. */
        var names: [String] = []
        for log in logs where !names.contains(log.exerciseName) { names.append(log.exerciseName) }
        return Summary(
            loadedVolumeKG: volume,
            workingSets: working.filter { !$0.skipped }.count,
            movements: names.count
        )
    }

    /// Completed work belongs to its calendar date, not to whichever generated
    /// plan happens to be active now. That makes regenerated tracked sessions
    /// and ad-hoc Quick Logs equally discoverable afterwards.
    static func history(
        sessions: [WorkoutSession],
        days: [ProgramDay],
        date: String?,
        ownerID: UUID?,
        limit: Int? = nil
    ) -> [HistoryItem] {
        let dayNames = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.name) })
        let history = sessions
            .filter { item in
                item.completed
                    && (date == nil || item.date == date)
                    && (ownerID == nil || item.userID == ownerID)
            }
            .sorted { left, right in
                let leftTime = left.completedAt ?? left.startedAt ?? left.date
                let rightTime = right.completedAt ?? right.startedAt ?? right.date
                if leftTime == rightTime { return left.id.uuidString > right.id.uuidString }
                return leftTime > rightTime
            }
            .map { item in
                let quickTitle = ManualWorkout.title(fromNotes: item.notes)
                return HistoryItem(
                    session: item,
                    title: quickTitle ?? dayNames[item.programDayID] ?? "Completed workout",
                    isQuickLog: quickTitle != nil,
                    linkedWearable: nil
                )
            }
        guard let limit else { return history }
        return Array(history.prefix(max(0, limit)))
    }

    static func editInput(_ log: WorkoutLog) -> WorkoutSetInput {
        WorkoutSetInput(
            exerciseID: log.exerciseID,
            exerciseName: log.exerciseName,
            setNumber: log.setNumber,
            weightKG: log.weightKG,
            reps: log.reps,
            rir: log.rir,
            movementID: log.movementID,
            durationSeconds: log.durationSeconds,
            distanceMeters: log.distanceMeters,
            contacts: log.contacts,
            rounds: log.rounds,
            workSeconds: log.workSeconds,
            recoverySeconds: log.recoverySeconds,
            skipped: log.skipped
        )
    }

    /// Apply corrected measured facts without changing the durable identity or
    /// chronology of the recorded set.
    static func correctedLog(_ log: WorkoutLog, with draft: WorkoutSetInput) -> WorkoutLog {
        let value = draft.normalizedForPersistence()
        var updated = log
        updated.weightKG = value.weightKG
        updated.reps = value.reps
        updated.rir = value.rir
        updated.movementID = value.movementID
        updated.durationSeconds = value.durationSeconds
        updated.distanceMeters = value.distanceMeters
        updated.contacts = value.contacts
        updated.rounds = value.rounds
        updated.workSeconds = value.workSeconds
        updated.recoverySeconds = value.recoverySeconds
        updated.skipped = value.skipped
        return updated
    }

    /// One sentence per movement, in the language the app is running in.
    static func insightText(
        _ insight: StrengthProgress.SessionInsight,
        language: AppLanguage
    ) -> String {
        guard insight.reference != nil,
              let loadDelta = insight.loadDelta,
              let days = insight.daysCompared else {
            return firstBaseline(language)
        }
        let delta = formatted(abs(loadDelta))
        let estimated = String(format: "%.1f", abs(insight.estimated1RMDelta ?? 0))
        switch language {
        case .romanian:
            if loadDelta > 0 {
                return "Ai crescut greutatea de lucru pentru \(insight.name) cu \(delta) kg în \(days) zile. Forța estimată a urcat cu \(estimated) kg."
            }
            if loadDelta < 0 {
                return "\(insight.name) a fost cu \(delta) kg sub reperul de acum \(days) zile. Contextul de deload, repetările și RIR-ul contează înainte de următoarea creștere."
            }
            return "\(insight.name) a rămas stabil timp de \(days) zile. Următoarea creștere se câștigă prin repetări curate și RIR controlat."
        case .thai:
            if loadDelta > 0 {
                return "น้ำหนักฝึก \(insight.name) เพิ่มขึ้น \(delta) กก. ใน \(days) วัน ความแข็งแรงโดยประมาณเพิ่ม \(estimated) กก."
            }
            if loadDelta < 0 {
                return "\(insight.name) ต่ำกว่าค่าอ้างอิงเมื่อ \(days) วันก่อน \(delta) กก. ควรดูช่วงลดโหลด จำนวนครั้ง และ RIR ก่อนเพิ่มครั้งถัดไป"
            }
            return "\(insight.name) คงที่ตลอด \(days) วัน เพิ่มระดับเมื่อทำซ้ำได้คมชัดและควบคุม RIR ได้"
        /* English also serves the languages whose receipts are not written
           yet: these sentences are interpolated, so they cannot come from a
           table, and a half-translated sentence is worse than an English one. */
        default:
            if loadDelta > 0 {
                return "You increased \(insight.name) by \(delta) kg across \(days) days. Estimated strength rose \(estimated) kg."
            }
            if loadDelta < 0 {
                return "\(insight.name) was \(delta) kg below the \(days)-day reference. Deload context, reps and RIR matter before the next increase."
            }
            return "\(insight.name) held steady across \(days) days. The next increase is earned through clean reps and controlled RIR."
        }
    }

    static func distinctInsightTexts(
        _ insights: [StrengthProgress.SessionInsight],
        language: AppLanguage,
        limit: Int = 3
    ) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        for insight in insights {
            let text = insightText(insight, language: language)
            if seen.insert(text).inserted {
                result.append(text)
                if result.count == limit { break }
            }
        }
        return result
    }

    private static func firstBaseline(_ language: AppLanguage) -> String {
        switch language {
        case .romanian: "Primul reper curat a fost înregistrat. Acesta devine comparația pentru următoarea sesiune."
        case .thai: "บันทึกค่าฐานครั้งแรกแล้ว ค่านี้จะใช้เทียบกับการฝึกครั้งถัดไป"
        default: "First clean baseline recorded. This becomes the comparison point for your next session."
        }
    }

    /// Whole kilograms read better than 2.5000000001.
    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Grouped in the order the sets were actually performed.
    static func grouped(_ logs: [WorkoutLog]) -> [(name: String, logs: [WorkoutLog])] {
        var order: [String] = []
        var byName: [String: [WorkoutLog]] = [:]
        for log in logs {
            if byName[log.exerciseName] == nil { order.append(log.exerciseName) }
            byName[log.exerciseName, default: []].append(log)
        }
        return order.compactMap { name in
            byName[name].map { (name: name, logs: $0) }
        }
    }
}

extension WorkoutReceipt {
    static func externalDateText(
        _ value: String,
        locale: Locale,
        timeZone: TimeZone = .current
    ) -> String {
        if let date = ExternalWorkoutImport.parseTimestamp(value) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"
        guard let date = day.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    enum FinishedHistoryItem: Identifiable, Hashable, Sendable {
        case apex(HistoryItem)
        case external(ImportedActivity)

        var id: UUID {
            switch self {
            case let .apex(item): item.id
            case let .external(item): item.id
            }
        }

        fileprivate var chronologicalKey: String {
            switch self {
            case let .apex(item):
                item.session.completedAt ?? item.session.startedAt ?? item.session.date
            case let .external(item):
                item.startedAt ?? item.date
            }
        }
    }

    static func finishedHistory(
        sessions: [WorkoutSession],
        days: [ProgramDay],
        importedActivities: [ImportedActivity],
        date: String?,
        ownerID: UUID?,
        limit: Int?
    ) -> [FinishedHistoryItem] {
        let baseAPEXItems = history(
            sessions: sessions,
            days: days,
            date: date,
            ownerID: ownerID,
            limit: nil
        )

        let apexSessionIdentities = sessions.compactMap { session -> ExternalWorkoutImport.APEXSessionIdentity? in
            guard session.userID == ownerID,
                  let startedAt = ExternalWorkoutImport.parseTimestamp(
                    session.startedAt ?? session.completedAt
                  ) else { return nil }
            return .init(id: session.id, startedAt: startedAt)
        }

        let apexItems: [FinishedHistoryItem]
        let externalItems: [FinishedHistoryItem]
        if let ownerID {
            let visibleExternal = importedActivities
                .filter {
                    $0.userID == ownerID
                        && $0.healthKitWorkoutID != nil
                        && $0.isVisibleInAPEX
                        && ExternalWorkoutImport.isAPEXMirror(
                            $0,
                            apexSessions: apexSessionIdentities
                        ) == false
                        && (date == nil || $0.date == date)
                }
            var linkedBySession: [UUID: ImportedActivity] = [:]
            for activity in visibleExternal.sorted(by: {
                ($0.startedAt ?? $0.endedAt ?? $0.date)
                    > ($1.startedAt ?? $1.endedAt ?? $1.date)
            }) {
                if let sessionID = activity.apexWorkoutSessionID,
                   linkedBySession[sessionID] == nil {
                    linkedBySession[sessionID] = activity
                }
            }
            apexItems = baseAPEXItems.map {
                FinishedHistoryItem.apex(
                    $0.attachingWearable(linkedBySession[$0.session.id])
                )
            }
            let visibleAPEXSessionIDs = Set(baseAPEXItems.map(\.id))
            externalItems = visibleExternal
                .filter {
                    guard let linkedID = $0.apexWorkoutSessionID else { return true }
                    return visibleAPEXSessionIDs.contains(linkedID) == false
                }
                .map(FinishedHistoryItem.external)
        } else {
            apexItems = baseAPEXItems.map(FinishedHistoryItem.apex)
            externalItems = []
        }

        let merged = (apexItems + externalItems).sorted {
            if $0.chronologicalKey == $1.chronologicalKey {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.chronologicalKey > $1.chronologicalKey
        }
        guard let limit else { return merged }
        return Array(merged.prefix(max(0, limit)))
    }
}
