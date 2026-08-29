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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
    @State private var pendingDeletion: WorkoutReceipt.HistoryItem?
    @State private var pendingHide: ImportedActivity?
    @State private var revealedSessionID: UUID?
    @State private var swipingSessionID: UUID?
    @State private var liveRevealOffset: CGFloat = 0

    let date: String?
    var accent: Color = APEXColor.teal
    var limit: Int? = nil
    private let revealWidth: CGFloat = 82

    private var history: [WorkoutReceipt.FinishedHistoryItem] {
        WorkoutReceipt.finishedHistory(
            sessions: session.data.workoutSessions,
            days: session.data.programDays,
            importedActivities: session.data.importedActivities,
            date: date,
            ownerID: session.profile?.userID,
            limit: limit
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
                    switch item {
                    case let .apex(apex):
                        apexHistoryCard(apex)
                    case let .external(external):
                        externalHistoryCard(external)
                    }
                }
            }
            .sheet(item: $receipt) { finished in
                WorkoutReceiptSheet(sessionID: finished.id) { receipt = nil }
                    .environment(session)
            }
            .alert(
                language.text("Delete this finished workout?"),
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { item in
                Button(language.text("Delete workout"), role: .destructive) {
                    pendingDeletion = nil
                    revealedSessionID = nil
                    expanded.remove(item.id)
                    Task { await session.deleteCompletedWorkoutSession(id: item.id) }
                }
                Button(language.text("Cancel"), role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text(language.text("Its receipt and recorded sets will be removed from your history and progression."))
            }
            .alert(
                language.text("Hide this Apple Health workout from APEX?"),
                isPresented: Binding(
                    get: { pendingHide != nil },
                    set: { if !$0 { pendingHide = nil } }
                ),
                presenting: pendingHide
            ) { item in
                Button(language.text("Hide from APEX"), role: .destructive) {
                    pendingHide = nil
                    expanded.remove(item.id)
                    Task { await session.hideExternalWorkoutFromAPEX(id: item.id) }
                }
                Button(language.text("Cancel"), role: .cancel) { pendingHide = nil }
            } message: { _ in
                Text(language.text("The original workout stays in Apple Health."))
            }
        }
    }

    private func revealOffset(for id: UUID) -> CGFloat {
        if swipingSessionID == id { return liveRevealOffset }
        return revealedSessionID == id ? -revealWidth : 0
    }

    private func updateReveal(id: UUID, translation: CGSize, expanded: Bool) {
        guard !expanded, abs(translation.width) > abs(translation.height) else { return }
        let base: CGFloat = revealedSessionID == id ? -revealWidth : 0
        swipingSessionID = id
        liveRevealOffset = max(-revealWidth, min(0, base + translation.width))
    }

    private func finishReveal(id: UUID, translation: CGSize, expanded: Bool) {
        guard !expanded, abs(translation.width) > abs(translation.height) else {
            swipingSessionID = nil
            liveRevealOffset = 0
            return
        }
        let base: CGFloat = revealedSessionID == id ? -revealWidth : 0
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            revealedSessionID = base + translation.width < -revealWidth / 3 ? id : nil
            swipingSessionID = nil
            liveRevealOffset = 0
        }
    }

    private func apexHistoryCard(_ item: WorkoutReceipt.HistoryItem) -> some View {
        let isExpanded = expanded.contains(item.id)
        let logs = WorkoutLogOrder.performedOrder(session.data, sessionID: item.id)
        let summary = WorkoutReceipt.summarize(logs)
        let time = item.session.completedAt.flatMap(Self.timeText)
        let currentRevealOffset = revealOffset(for: item.id)

        return ZStack(alignment: .trailing) {
            if WorkoutReceipt.collapsedDeleteTrayVisible(
                isExpanded: isExpanded,
                revealOffset: currentRevealOffset
            ) {
                Button {
                    pendingDeletion = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .black))
                        Text(language.text("DELETE"))
                            .font(APEXFont.mono(7, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(APEXColor.danger)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("completed-workout-delete-\(item.id.uuidString.lowercased())")
            }

            VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if revealedSessionID == item.id {
                        revealedSessionID = nil
                    } else if isExpanded {
                        expanded.remove(item.id)
                    } else {
                        expanded.insert(item.id)
                    }
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
                        Text([
                            item.session.date,
                            time,
                            language.format("%d working sets", summary.workingSets),
                            language.format("%d movements", summary.movements),
                            item.linkedWearable == nil ? nil : language.shortText("Wearable linked"),
                        ].compactMap { $0 }.joined(separator: " · "))
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
            .accessibilityIdentifier(
                "completed-workout-\(isExpanded ? "expanded-" : "")\(item.id.uuidString.lowercased())"
            )
            .accessibilityValue(language.text(isExpanded ? "Expanded" : "Collapsed"))

            if isExpanded {
                Divider().overlay(.white.opacity(0.9))
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 8) {
                        historyMetric("Loaded volume", value: language.format("%.0f kg", summary.loadedVolumeKG))
                        historyMetric("Working sets", value: String(summary.workingSets))
                        historyMetric("Movements", value: String(summary.movements))
                    }
                    Button {
                        pendingDeletion = item
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(APEXColor.danger)
                            .frame(width: 38, height: 38)
                            .background(APEXColor.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(APEXColor.danger.opacity(0.20), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text("Delete workout"))
                    .accessibilityIdentifier("completed-workout-expanded-delete-\(item.id.uuidString.lowercased())")
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                if let linkedWearable = item.linkedWearable {
                    linkedWearableEvidence(linkedWearable)
                        .padding(.horizontal, 15)
                        .padding(.top, 10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(WorkoutReceipt.grouped(logs), id: \.name) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(language.text(group.name))
                                .font(APEXFont.body(13, weight: .bold))
                                .foregroundStyle(APEXColor.ink)
                            ForEach(group.logs) { log in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(language.format("SET %d", log.setNumber))
                                        .font(APEXFont.mono(8, weight: .bold))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                    Text(ExerciseLogging.factSummary(log).map(language.text).joined(separator: " · "))
                                        .font(APEXFont.mono(9, weight: .semibold))
                                        .foregroundStyle(APEXColor.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 2)

                Button {
                    receipt = FinishedSession(id: item.id)
                } label: {
                    Text(language.text("Edit receipt"))
                        .font(APEXFont.body(12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white)
                        .background(accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
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
        .offset(x: isExpanded ? 0 : currentRevealOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .highPriorityGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    updateReveal(id: item.id, translation: value.translation, expanded: isExpanded)
                }
                .onEnded { value in
                    finishReveal(id: item.id, translation: value.translation, expanded: isExpanded)
                }
        )
    }

    private func linkedWearableEvidence(_ item: ImportedActivity) -> some View {
        let title = language.language == .english
            ? item.activity
            : language.text(item.workoutNameKey ?? item.activity)
        let moment = WorkoutReceipt.externalDateText(
            item.startedAt ?? item.date,
            locale: language.language.locale
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Linked wearable effort"))
                .font(APEXFont.mono(8, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(APEXColor.cyan)
            Text(title)
                .font(APEXFont.display(15))
                .foregroundStyle(APEXColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text([
                moment,
                language.format("%d min", item.durationMinutes),
                item.source,
            ].filter { $0.isEmpty == false }.joined(separator: " · "))
                .font(APEXFont.mono(8, weight: .semibold))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if item.activeEnergyKcal != nil || item.distanceKM != nil {
                HStack(spacing: 8) {
                    if let energy = item.activeEnergyKcal {
                        historyMetric("Active energy", value: language.format("%d kcal", Int(energy.rounded())))
                    }
                    if let distance = item.distanceKM {
                        historyMetric("Distance", value: language.format("%.2f km", distance))
                    }
                }
            }
            Text(language.text("Device metrics are read-only and are not added to HealthKit energy twice."))
                .font(APEXFont.body(10, weight: .semibold))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(APEXColor.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(APEXColor.cyan.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("linked-wearable-evidence-\(item.id.uuidString.lowercased())")
    }

    private func externalHistoryCard(_ item: ImportedActivity) -> some View {
        let isExpanded = expanded.contains(item.id)
        let title = language.language == .english
            ? item.activity
            : language.text(item.workoutNameKey ?? item.activity)
        let dateText = WorkoutReceipt.externalDateText(
            item.startedAt ?? item.date,
            locale: language.language.locale
        )
        let metadata = [
            item.source,
            dateText,
            language.format("%d min", item.durationMinutes),
        ].filter { $0.isEmpty == false }.joined(separator: " · ")

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isExpanded { expanded.remove(item.id) }
                    else { expanded.insert(item.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(APEXColor.cyan.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.shortText("APPLE HEALTH"))
                            .font(APEXFont.mono(8, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(APEXColor.cyan)
                        Text(title)
                            .font(APEXFont.display(17))
                            .foregroundStyle(APEXColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(metadata)
                            .font(APEXFont.mono(8, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(APEXColor.cyan)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "external-workout-\(isExpanded ? "expanded-" : "")\(item.id.uuidString.lowercased())"
            )
            .accessibilityLabel(title)
            .accessibilityValue(language.text(isExpanded ? "Expanded" : "Collapsed"))

            if isExpanded {
                Divider().overlay(.white.opacity(0.9))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    historyMetric("Duration", value: language.format("%d min", item.durationMinutes))
                    if let energy = item.activeEnergyKcal {
                        historyMetric("Active energy", value: language.format("%d kcal", Int(energy.rounded())))
                    }
                    if let distance = item.distanceKM {
                        historyMetric("Distance", value: language.format("%.2f km", distance))
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text("READ-ONLY RECEIPT"))
                        .font(APEXFont.mono(8, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(APEXColor.cyan)
                    Text(language.text("Imported from Apple Health. This receipt is read-only in APEX."))
                        .font(APEXFont.body(12))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 12)

                Button {
                    pendingHide = item
                } label: {
                    Text(language.shortText("Hide from APEX"))
                        .font(APEXFont.body(12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(APEXColor.danger)
                        .background(
                            APEXColor.danger.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint(language.text("The original workout stays in Apple Health."))
                .accessibilityIdentifier("external-workout-hide-\(item.id.uuidString.lowercased())")
                .padding(15)
                .padding(.top, -4)
            }
        }
        .background(
            LinearGradient(
                colors: [APEXColor.cyan.opacity(0.11), .white.opacity(0.78), APEXColor.teal.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
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
                .fixedSize(horizontal: true, vertical: false)
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
