import SwiftUI

/// Identifies the session a receipt belongs to. A named type rather than
/// conforming UUID itself, which would be a retroactive conformance on a
/// standard library type.
struct FinishedSession: Identifiable, Hashable, Sendable {
    let id: UUID
}

/*
 * The end-of-workout receipt, matching the web's WorkoutStatsSheet.
 *
 * Until now a finished session on iOS saved and vanished, so the work done
 * was never shown back. This is the moment the kilograms actually reported
 * during the session become a number worth seeing, alongside what changed
 * since the last time the same movements were trained.
 */
struct WorkoutReceiptSheet: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let sessionID: UUID
    var onClose: () -> Void = {}

    private var logs: [WorkoutLog] {
        WorkoutLogOrder.performedOrder(session.data, sessionID: sessionID)
    }

    private var summary: WorkoutReceipt.Summary { WorkoutReceipt.summarize(logs) }

    private var insights: [StrengthProgress.SessionInsight] {
        StrengthProgress.sessionInsights(
            sessions: session.data.workoutSessions,
            logs: session.data.workoutLogs,
            sessionID: sessionID
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metrics
                if !insights.isEmpty { signal }
                breakdown
                Button(action: onClose) {
                    Text(language.text("Done"))
                        .font(APEXFont.body(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-receipt-done")
            }
            .padding(18)
        }
        .background(APEXBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.text("WORKOUT RECEIPT").uppercased())
                .font(APEXFont.mono(9))
                .tracking(1.6)
                .foregroundStyle(APEXColor.amberDeep)
            Text(language.text("Stats at a glance"))
                .font(APEXFont.display(24))
                .foregroundStyle(APEXColor.ink)
            Text(language.text("Every measured set stays editable here. Conditioning episodes carry no load to report."))
                .font(APEXFont.body(11))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        HStack(spacing: 9) {
            metric(language.text("Loaded volume"), value: volumeText)
            metric(language.text("Working sets"), value: String(summary.workingSets))
            metric(language.text("Movements"), value: String(summary.movements))
        }
    }

    private var volumeText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: summary.loadedVolumeKG.rounded())) ?? "0"
        return "\(number) kg"
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(APEXFont.mono(8))
                .tracking(0.9)
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(2, reservesSpace: true)
            Text(value)
                .font(APEXFont.display(19))
                .foregroundStyle(APEXColor.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /* The same three-line ceiling the web uses: a receipt is a glance, not a
       report, and the fourth movement never changes the decision. */
    private var signal: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(APEXColor.green).frame(width: 7, height: 7)
                Text(language.text("APEX strength signal").uppercased())
                    .font(APEXFont.mono(8))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.66))
            }
            ForEach(
                WorkoutReceipt.distinctInsightTexts(insights, language: language.language),
                id: \.self
            ) { text in
                Text(text)
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(red: 0.03, green: 0.07, blue: 0.11), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WorkoutReceipt.grouped(logs), id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(APEXFont.body(13, weight: .bold))
                        .foregroundStyle(APEXColor.ink)
                    ForEach(group.logs) { log in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(language.format("SET %d", log.setNumber))
                                    .font(APEXFont.mono(9, weight: .bold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                Spacer()
                                Toggle(language.text("Not completed"), isOn: skipped(log))
                                    .font(APEXFont.body(10, weight: .semibold))
                                    .tint(APEXColor.danger)
                                    .fixedSize()
                            }
                            if !(currentLog(log.id)?.skipped ?? log.skipped) {
                                ExerciseFactFieldsView(
                                    descriptor: ExerciseLogging.descriptor(
                                        movementNamed: log.exerciseName,
                                        movementID: log.movementID
                                    ),
                                    values: factValues(log)
                                )
                                if let current = currentLog(log.id),
                                   let progress = ProgressionEngine.latestProgress(session.data, current: current) {
                                    Text(language.text(progressLabel(progress)))
                                        .font(APEXFont.mono(9, weight: .bold))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                            } else {
                                Text(language.text("This set is excluded from volume and progression."))
                                    .font(APEXFont.body(10, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }
                        .padding(10)
                        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func currentLog(_ id: UUID) -> WorkoutLog? {
        session.data.workoutLogs.first { $0.id == id }
    }

    private func skipped(_ log: WorkoutLog) -> Binding<Bool> {
        Binding(
            get: { currentLog(log.id)?.skipped ?? log.skipped },
            set: { next in
                guard let current = currentLog(log.id) else { return }
                var draft = WorkoutReceipt.editInput(current)
                draft.skipped = next
                Task { await session.updateWorkoutLog(id: current.id, draft: draft) }
            }
        )
    }

    private func factValues(_ log: WorkoutLog) -> Binding<ExerciseFactValues> {
        Binding(
            get: {
                let current = currentLog(log.id) ?? log
                return ExerciseFactValues(
                    reps: current.reps,
                    signedLoadKG: current.weightKG,
                    rir: current.rir,
                    durationSeconds: current.durationSeconds,
                    distanceMeters: current.distanceMeters,
                    contacts: current.contacts,
                    rounds: current.rounds,
                    workSeconds: current.workSeconds,
                    recoverySeconds: current.recoverySeconds
                )
            },
            set: { values in
                guard let current = currentLog(log.id) else { return }
                var draft = WorkoutReceipt.editInput(current)
                draft.reps = values.reps
                draft.weightKG = values.signedLoadKG
                draft.rir = values.rir
                draft.durationSeconds = values.durationSeconds
                draft.distanceMeters = values.distanceMeters
                draft.contacts = values.contacts
                draft.rounds = values.rounds
                draft.workSeconds = values.workSeconds
                draft.recoverySeconds = values.recoverySeconds
                Task { await session.updateWorkoutLog(id: current.id, draft: draft) }
            }
        )
    }

    private func progressLabel(_ progress: ExerciseProgress) -> String {
        switch progress {
        case .improved: return "Improved from last time"
        case .maintained: return "Matched last time"
        case .regressed: return "Below last time"
        case .adherence: return "Completed"
        case .incomparable: return "Needs matching facts to compare"
        }
    }
}

/// A permanent, date-owned trail of finished work. The compact card is the
/// visual receipt; expanding it exposes the full receipt and corrections.
struct CompletedWorkoutHistoryCards: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var expanded: Set<UUID> = []
    @State private var receipt: FinishedSession?
    @State private var manualEdit: WorkoutSession?

    let date: String
    var accent: Color = APEXColor.teal

    private var history: [WorkoutReceipt.HistoryItem] {
        WorkoutReceipt.history(
            sessions: session.data.workoutSessions,
            days: session.data.programDays,
            date: date,
            ownerID: session.profile?.userID
        )
    }

    var body: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(language.text("FINISHED WORKOUTS"))
                        .font(APEXFont.mono(9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(APEXColor.green)
                    Spacer()
                    Text(language.format("%d sessions", history.count))
                        .font(APEXFont.mono(8, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .padding(.horizontal, 4)

                ForEach(history) { item in
                    historyCard(item)
                }
            }
            .sheet(item: $receipt) { finished in
                WorkoutReceiptSheet(sessionID: finished.id) { receipt = nil }
                    .environment(session)
            }
            .sheet(item: $manualEdit) { workout in
                ManualWorkoutLoggerView(date: date, editing: workout) {
                    manualEdit = nil
                }
                .environment(session)
            }
        }
    }

    private func historyCard(_ item: WorkoutReceipt.HistoryItem) -> some View {
        let isExpanded = expanded.contains(item.id)
        let logs = WorkoutLogOrder.performedOrder(session.data, sessionID: item.id)
        let summary = WorkoutReceipt.summarize(logs)
        let time = item.session.completedAt.flatMap(Self.timeText)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isExpanded { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(APEXColor.green, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(item.isQuickLog ? "QUICK LOG COMPLETE" : "TRACKED WORKOUT COMPLETE"))
                            .font(APEXFont.mono(8, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(APEXColor.green)
                        Text(language.text(item.title))
                            .font(APEXFont.display(17))
                            .foregroundStyle(APEXColor.ink)
                            .lineLimit(2)
                        Text([time, language.format("%d working sets", summary.workingSets), language.format("%d movements", summary.movements)].compactMap { $0 }.joined(separator: " · "))
                            .font(APEXFont.mono(8, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(APEXColor.green)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("completed-workout-\(item.id.uuidString.lowercased())")

            if isExpanded {
                Divider().overlay(.white.opacity(0.9))
                HStack(spacing: 8) {
                    historyMetric("Loaded volume", value: language.format("%.0f kg", summary.loadedVolumeKG))
                    historyMetric("Working sets", value: String(summary.workingSets))
                    historyMetric("Movements", value: String(summary.movements))
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                HStack(spacing: 8) {
                    Button {
                        receipt = FinishedSession(id: item.id)
                    } label: {
                        Text(language.text("View & edit receipt"))
                            .font(APEXFont.body(12, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(.white)
                            .background(accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if item.isQuickLog {
                        Button {
                            manualEdit = item.session
                        } label: {
                            Text(language.text("Edit workout"))
                                .font(APEXFont.body(12, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .foregroundStyle(accent)
                                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(15)
                .padding(.top, -4)
            }
        }
        .background(
            LinearGradient(
                colors: [APEXColor.green.opacity(0.10), .white.opacity(0.76), APEXColor.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if !isExpanded {
                LinearGradient(colors: [.clear, APEXColor.cyan.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .clipShape(.rect(bottomLeadingRadius: 25, bottomTrailingRadius: 25))
                    .allowsHitTesting(false)
            }
        }
    }

    private func historyMetric(_ label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(language.text(label).uppercased())
                .font(APEXFont.mono(7, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(2, reservesSpace: true)
            Text(value)
                .font(APEXFont.mono(12, weight: .bold))
                .foregroundStyle(APEXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func timeText(_ iso: String) -> String? {
        guard iso.count >= 16 else { return nil }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(start, offsetBy: 5)
        return String(iso[start..<end])
    }
}
