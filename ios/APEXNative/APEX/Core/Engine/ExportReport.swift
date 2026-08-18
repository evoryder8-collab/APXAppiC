import Foundation

/*
 * The Markdown export an assessment can be pasted into.
 *
 * A port of src/lib/exportReport.ts, covering the sections that exist natively:
 * the calendar overview with its event windows, every logged session in the
 * order it was performed, the daily nutrition log, the closed-day meal rhythm
 * verdicts and the current stat line. The web build also folds in a meal-timing
 * analysis; that module has no native counterpart yet, so its section is
 * omitted rather than half-written.
 */
enum ExportReport {
    static func build(
        _ data: DashboardData,
        slug: String,
        from: String,
        to: String,
        now: Date = .now
    ) -> String {
        let program = data.programs.first { $0.slug == slug }
        let dayByID = Dictionary(
            data.programDays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let exerciseByID = Dictionary(
            data.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var lines: [String] = []

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm"

        lines.append("# APEX training report: \(program?.name ?? slug)")
        lines.append("Range: \(from) to \(to). Generated \(stamp.string(from: now)).")
        lines.append("")

        lines.append("## Calendar overview")
        let sessions = data.workoutSessions
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
        let deloads = Set((data.deloadMarks ?? []).map(\.date))
        for workout in sessions {
            let day = dayByID[workout.programDayID]
            var flags = [workout.isLite ? "Lite" : "Full"]
            if workout.isDeload || deloads.contains(workout.date) { flags.append("DELOAD") }
            if workout.isEventRecovery { flags.append("EVENT RECOVERY") }
            if TrainingPlanEngine.approachRamp(for: workout.date, events: data.events) != nil {
                flags.append("event window")
            }
            flags.append(
                workout.completed
                    ? "completed, quality \(Int((workout.qualityScore * 100).rounded()))%"
                    : "planned only"
            )
            lines.append("- \(workout.date): \(day?.name ?? "?") (\(flags.joined(separator: ", ")))")
        }
        if !data.events.isEmpty {
            lines.append("")
            lines.append("### Events")
            for event in data.events {
                lines.append("- \(event.name) (\(event.type)), \(event.startDate) to \(event.endDate)")
            }
        }
        lines.append("")

        lines.append("## Logged sessions")
        for workout in sessions where workout.completed {
            let day = dayByID[workout.programDayID]
            lines.append("### \(workout.date): \(day?.name ?? "?")\(workout.isLite ? " (Lite)" : "")")
            if !workout.notes.isEmpty { lines.append("Notes: \(workout.notes)") }
            var currentName = ""
            for log in WorkoutLogOrder.performedOrder(data, sessionID: workout.id) {
                let name = log.exerciseName.isEmpty
                    ? (log.exerciseID.flatMap { exerciseByID[$0]?.name } ?? "Exercise")
                    : log.exerciseName
                if name != currentName {
                    lines.append("- **\(name)**")
                    currentName = name
                }
                if log.skipped {
                    lines.append("  - Set \(log.setNumber): skipped")
                } else {
                    var bits = [log.weightKG.map { "\(number($0)) kg" } ?? "bodyweight"]
                    if let reps = log.reps { bits.append("\(reps) reps") }
                    if let rir = log.rir { bits.append("RIR \(rir)") }
                    if log.overrideFlag { bits.append("guardian override") }
                    lines.append("  - Set \(log.setNumber): \(bits.joined(separator: ", "))")
                }
            }
            lines.append("")
        }

        lines.append("## Daily logs")
        let dailies = data.dailyLogs
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
        for day in dailies {
            lines.append(
                "- \(day.date): \(day.kcal.map(String.init) ?? "?") kcal, "
                    + "P \(day.proteinG.map(String.init) ?? "?") g, "
                    + "F \(day.fatG.map(String.init) ?? "?") g, "
                    + "C \(day.carbsG.map(String.init) ?? "?") g, "
                    + "water \(number(day.waterL)) L"
            )
        }
        lines.append("")

        lines.append("## Closed-day meal consistency")
        let rhythm = rhythmDays(data, from: from, to: to)
        for day in rhythm {
            lines.append(
                "- \(day.date): \(day.loggedMeals)/\(day.expectedMeals) configured meals, "
                    + "completion \(day.completionScore)/100, "
                    + "timing \(day.timingScore.map(String.init) ?? "?") / 100, "
                    + "combined rhythm \(day.rhythmScore)/100, "
                    + "verdict \(day.verdict.replacingOccurrences(of: "_", with: " "))."
            )
        }
        if rhythm.isEmpty {
            lines.append("- No closed-day meal verdicts were available in this range.")
        }
        lines.append("")

        /* Meal timing and its pre and post workout context. */
        let timing = MealTimingEngine.analyze(
            meals: data.loggedMeals.filter { $0.localDate >= from && $0.localDate <= to },
            entries: data.loggedFoodEntries,
            sessions: sessions,
            timeZone: TimeZone.current.identifier
        )
        lines.append("## Meal timing and pre-workout context")
        lines.append("Timezone: \(TimeZone.current.identifier).")
        lines.append(
            "Meal finishes recorded: \(timing.recordedMeals). "
                + "Scheduled times without a recorded finish: \(timing.estimatedMeals)."
        )
        if let variation = timing.typicalVariationMinutes {
            lines.append(
                "Typical within-slot timing variation: \(variation) minutes. "
                    + "Rhythm score: \(timing.rhythmScore.map(String.init) ?? "?") / 100."
            )
        }
        if timing.workoutsWithContext > 0 {
            lines.append(
                "Workout starts with meal context: \(timing.workoutsWithContext). "
                    + "Comfort window \(timing.readyStarts), "
                    + "tradeoff window \(timing.transitionStarts), "
                    + "settling window \(timing.settlingStarts)."
            )
            lines.append(
                "Average interval from the latest completed meal to training: "
                    + "\(timing.averageWaitMinutes.map(String.init) ?? "?") minutes."
            )
        }
        lines.append("")

        lines.append("### Workout timing relative to meals")
        for relation in timing.workoutRelations {
            if let name = relation.mealName, let waited = relation.waitedMinutes, let zone = relation.zone {
                lines.append("- \(relation.date): started \(waited) minutes after \(name). Zone: \(zone.rawValue).")
            } else {
                lines.append("- \(relation.date): no reliably recorded earlier meal on this day.")
            }
        }
        if timing.workoutRelations.isEmpty {
            lines.append("- No workout start timestamps were available in this range.")
        }
        lines.append("")

        lines.append("### Post-workout nutrition timing")
        lines.append(
            "Completed workouts with timestamps: \(timing.completedWorkouts). "
                + "Post-workout meal finishes recorded: \(timing.recoveryMealsRecorded)."
        )
        if let score = timing.recoveryTimingScore {
            lines.append(
                "Average post-workout timing context: \(score) / 100. "
                    + "Average workout-to-meal-finish gap: "
                    + "\(timing.averageRecoveryGapMinutes.map(String.init) ?? "?") minutes."
            )
        }
        for relation in timing.postWorkoutRelations {
            if relation.source == "recorded_finish", let gap = relation.gapMinutes {
                lines.append(
                    "- \(relation.date): \(relation.mealName ?? "next meal") finished \(gap) minutes later; "
                        + "timing context \(relation.timingScore.map(String.init) ?? "?") / 100."
                )
            } else {
                lines.append("- \(relation.date): no post-workout meal finish was recorded.")
            }
        }
        if timing.postWorkoutRelations.isEmpty {
            lines.append("- No completed workout timestamps were available in this range.")
        }
        lines.append("")

        /* What the watch said about the nights in this range. */
        let checkins = RecoveryAssessment.history(from: data.settings?.addons)
            .filter { $0.date >= from && $0.date <= to }
        if !checkins.isEmpty {
            lines.append("## Recovery readiness")
            for checkin in checkins {
                let verdict = RecoveryAssessment.assess(checkin)
                let reading = checkin.source == "apple"
                    ? "sleep score \(checkin.sleepScore.map(String.init) ?? "?")"
                    : "recovery \(checkin.recoveryPercent.map(String.init) ?? "?")%"
                lines.append("- \(checkin.date): \(reading) (\(checkin.source)) → \(verdict.state.rawValue). \(verdict.title).")
            }
            lines.append("")
        }

        if let snapshot = data.snapshots.max(by: { $0.date < $1.date }) {
            lines.append("## Current RPG stats")
            lines.append("- Overall: \(number(snapshot.overall))")
            lines.append("- Health: \(number(snapshot.health))")
            lines.append("- Joint Health Balance: \(number(snapshot.joint))")
            lines.append("- Flexibility: \(number(snapshot.flexibility))")
            lines.append("- Endurance & VO2max: \(number(snapshot.endurance))")
            lines.append(
                "- Strength: \(number(snapshot.strength)) "
                    + "(upper \(number(snapshot.strengthUpper)) / lower \(number(snapshot.strengthLower)))"
            )
        }
        return lines.joined(separator: "\n")
    }

    private struct RhythmDay {
        let date: String
        let loggedMeals: Int
        let expectedMeals: Int
        let completionScore: Int
        let timingScore: Int?
        let rhythmScore: Int
        let verdict: String
    }

    private static func rhythmDays(_ data: DashboardData, from: String, to: String) -> [RhythmDay] {
        guard let history = data.settings?.addons["meal_rhythm_history"]?.objectValue else { return [] }
        return history.values
            .compactMap { value -> RhythmDay? in
                guard let entry = value.objectValue,
                      let date = entry["date"]?.stringValue,
                      date >= from, date <= to
                else { return nil }
                return RhythmDay(
                    date: date,
                    loggedMeals: Int(entry["logged_meals"]?.numberValue ?? 0),
                    expectedMeals: Int(entry["expected_meals"]?.numberValue ?? 0),
                    completionScore: Int(entry["completion_score"]?.numberValue ?? 0),
                    timingScore: entry["timing_score"]?.numberValue.map { Int($0) },
                    rhythmScore: Int(entry["rhythm_score"]?.numberValue ?? 0),
                    verdict: entry["verdict"]?.stringValue ?? "unknown"
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Writes the report where a share sheet can pick it up.
    static func writeTemporaryFile(_ markdown: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
