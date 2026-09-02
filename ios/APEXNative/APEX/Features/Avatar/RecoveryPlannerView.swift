import SwiftUI

struct RecoveryPlannerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var source = RecoveryPlanner.Source.guided
    @State private var installing = false

    let target: RecoveryPlanner.Target
    private let startDate: String

    init(target: RecoveryPlanner.Target) {
        self.target = target
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        self.startDate = tomorrow.apexDateKey
    }

    private var ownerID: UUID? { session.profile?.userID ?? session.data.settings?.userID }

    private var proposal: RecoveryPlanner.Result? {
        guard let ownerID else { return nil }
        return RecoveryPlanner.build(
            data: session.data,
            ownerID: ownerID,
            startDate: startDate,
            target: target,
            source: source
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    sourceChoices
                    datePreview
                    safetyNote
                    if !session.coachClientPolicy.canCreateCustomWorkouts {
                        Text(language.text("Your coach manages this plan. Ask them to add the recovery rhythm for you."))
                            .font(APEXFont.body(13, weight: .bold))
                            .foregroundStyle(APEXColor.amberDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                }
                .padding(20)
                .padding(.bottom, 16)
            }
            .background(APEXColor.canvas.ignoresSafeArea())
            .navigationTitle(language.text("Recovery rhythm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Close")) { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("RECOVERY RHYTHM"))
                .font(APEXFont.mono(10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(APEXColor.green)
            Text(language.text(target == .joint ? "Plan joint care" : "Plan flexibility"))
                .font(APEXFont.display(32))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text("Four weeks, two short sessions each week. APEX favours lower-load days and never replaces your current programme."))
                .font(APEXFont.body(14, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("Session style"))
                .font(APEXFont.body(15, weight: .bold))
            choice(
                .guided,
                title: "APEX guided",
                detail: "A short follow-along routine using reviewed movements."
            )
            choice(
                .external,
                title: "My own session",
                detail: "Follow a mobility or recovery video or routine you trust, then log it honestly."
            )
        }
    }

    private func choice(_ value: RecoveryPlanner.Source, title: String, detail: String) -> some View {
        Button { source = value } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(source == value ? APEXColor.green : APEXColor.secondaryInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(title))
                        .font(APEXFont.display(18))
                    Text(language.text(detail))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(APEXColor.ink)
            .padding(15)
            .background(source == value ? APEXColor.green.opacity(0.10) : .white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(source == value ? APEXColor.green.opacity(0.5) : .white.opacity(0.9)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text(title))
        .accessibilityHint(language.text(detail))
        .accessibilityIdentifier("recovery-planner-source-\(value.rawValue)")
        .accessibilityAddTraits(source == value ? .isSelected : [])
    }

    private var datePreview: some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language.text("Your proposed dates"))
                        .font(APEXFont.display(20))
                    Spacer()
                    Text(language.format("%d sessions", proposal?.days.count ?? 0))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(APEXColor.violet)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(proposal?.days ?? []) { day in
                        Text(formatted(day.scheduledDate ?? ""))
                            .font(APEXFont.mono(10, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(APEXColor.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var safetyNote: some View {
        Text(language.text("General movement support, not diagnosis or injury treatment. Use a comfortable range, stop if pain worsens, and seek qualified care for persistent or new symptoms."))
            .font(APEXFont.body(12, weight: .medium))
            .foregroundStyle(APEXColor.secondaryInk)
            .lineSpacing(3)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(APEXColor.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(language.text("Cancel")) { dismiss() }
                .font(APEXFont.body(14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                guard let operation = session.accountOperationLease() else { return }
                installing = true
                Task {
                    do {
                        let count = try await session.installRecoveryPlan(
                            target: target,
                            source: source,
                            startDate: startDate,
                            operation: operation
                        )
                        guard session.accountOperationIsCurrent(operation) else { return }
                        installing = false
                        if count > 0 { dismiss() }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard session.accountOperationIsCurrent(operation) else { return }
                        installing = false
                        session.alertMessage = error.localizedDescription
                    }
                }
            } label: {
                if installing {
                    ProgressView().tint(.white)
                } else {
                    Text(language.shortText("Add sessions"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(APEXFont.body(14, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(APEXColor.green.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(installing || proposal?.days.isEmpty != false || !session.coachClientPolicy.canCreateCustomWorkouts)
            .opacity(proposal?.days.isEmpty == false && session.coachClientPolicy.canCreateCustomWorkouts ? 1 : 0.45)
            .accessibilityLabel(language.text("Add recovery sessions"))
            .accessibilityIdentifier("recovery-planner-add")
        }
        .buttonStyle(.plain)
    }

    private func formatted(_ key: String) -> String {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: key) else { return key }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(language.language.locale)
        )
    }
}
