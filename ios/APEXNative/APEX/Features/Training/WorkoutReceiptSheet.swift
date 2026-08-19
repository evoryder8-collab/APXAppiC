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
            Text(language.text("Every strength set is recorded. Conditioning episodes carry no load to report."))
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
            ForEach(insights.prefix(3), id: \.key) { insight in
                Text(WorkoutReceipt.insightText(insight, language: language.language))
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
                        HStack(spacing: 10) {
                            Text("S\(log.setNumber)")
                                .font(APEXFont.mono(9, weight: .bold))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .frame(width: 26, alignment: .leading)
                            if log.skipped {
                                Text(language.text("Not completed"))
                                    .font(APEXFont.body(11, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            } else {
                                setValue(log.weightKG.map { "\(formatted($0)) kg" } ?? "-")
                                setValue(log.reps.map { "\($0) \(language.text("reps"))" } ?? "-")
                                if let rir = log.rir { setValue("RIR \(rir)") }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func setValue(_ text: String) -> some View {
        Text(text)
            .font(APEXFont.mono(11, weight: .bold))
            .foregroundStyle(APEXColor.ink)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
