import SwiftUI

struct CoachPlanView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var scopes: Set<CoachConsentScope> = []
    @State private var visualProgress = false
    @State private var busy = false
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let sponsorship = session.coachContext.sponsorship {
                    planHeader(sponsorship)
                    planCard
                    privacyCard(sponsorship)
                } else {
                    CoachInvitationAcceptanceCard()
                }
            }
            .padding(18)
            .padding(.bottom, 36)
            .dockClearance()
        }
        .navigationTitle(language.text("Your coach plan"))
        .navigationBarTitleDisplayMode(.inline)
        .task { syncPrivacyState() }
        .onChange(of: session.coachContext) { _, _ in syncPrivacyState() }
        .onChange(of: session.profile?.userID) { _, _ in
            busy = false
            syncPrivacyState()
        }
        .confirmationDialog(language.text("End coach access"), isPresented: $confirmEnd) {
            Button(language.text("End coach access"), role: .destructive) {
                guard let operation = session.accountOperationLease() else { return }
                Task { await endRelationship(operation: operation) }
            }
            Button(language.text("Cancel"), role: .cancel) {}
        }
    }

    private func planHeader(_ sponsorship: CoachSponsorshipSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(language.text("Provided by")) \(sponsorship.coachDisplayName)")
                .font(APEXFont.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.8))
            Text(language.text("Your coach plan"))
                .font(APEXFont.display(36))
                .foregroundStyle(.white)
            if session.coachClientPolicy.coachPlanReadOnly {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Read-only grace period")).font(APEXFont.body(14, weight: .bold))
                    Text(language.text("Your last valid plan stays visible, but it cannot be changed or activated."))
                        .font(APEXFont.body(11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [APEXColor.violet, Color.purple, APEXColor.amber], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .shadow(color: APEXColor.violet.opacity(0.28), radius: 24, y: 14)
    }

    @ViewBuilder
    private var planCard: some View {
        GlassCard {
            if let plan = session.coachContext.currentPlan {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(language.format("VERSION %d", plan.version))
                                .font(APEXFont.mono(8, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(APEXColor.violet)
                            Text(plan.title)
                                .font(APEXFont.display(29))
                                .foregroundStyle(APEXColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(plan.objective)
                                .font(APEXFont.body(13, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        if let date = plan.reviewDate {
                            Text(date)
                                .font(APEXFont.mono(9, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(APEXColor.violet.opacity(0.1), in: Capsule())
                        }
                    }

                    if !plan.coachNote.isEmpty {
                        Text(plan.coachNote)
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.ink)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(APEXColor.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    ForEach(plan.plan.sessions) { workout in
                        CoachPublishedSessionCard(session: workout)
                    }

                    if !session.coachClientPolicy.coachPlanReadOnly {
                        HStack(spacing: 9) {
                            Button {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await acknowledgeCoachPlan(plan.id, operation: operation) }
                            } label: {
                                Label(language.text("Acknowledge plan"), systemImage: plan.acknowledgedAt == nil ? "checkmark.circle" : "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy || plan.acknowledgedAt != nil)

                            Button {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await activateCoachPlan(plan.id, operation: operation) }
                            } label: {
                                Label(language.text("Activate plan"), systemImage: plan.activatedAt == nil ? "bolt.circle" : "checkmark.seal.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(APEXColor.violet)
                            .disabled(busy || plan.acknowledgedAt == nil || plan.activatedAt != nil)
                        }
                        .font(APEXFont.body(11, weight: .bold))
                    }

                    if plan.activatedAt != nil {
                        Button {
                            session.navigationPath.append(.coachWorkouts)
                        } label: {
                            Label(language.text("Open coach workouts"), systemImage: "figure.strengthtraining.traditional")
                                .font(APEXFont.body(14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(APEXColor.green, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(APEXColor.violet)
                    Text(language.text("Nothing has been published yet."))
                        .font(APEXFont.body(14, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 35)
            }
        }
    }

    private func privacyCard(_ sponsorship: CoachSponsorshipSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(language.text("Privacy controls"))
                    .font(APEXFont.display(24))
                    .foregroundStyle(APEXColor.ink)
                Text(language.text("You decide what your coach can see."))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)

                CoachScopeSelector(
                    scopes: $scopes,
                    visualProgress: $visualProgress,
                    offered: sponsorship.offeredScopes,
                    visualProgressOffered: sponsorship.offeredScopes.contains(.visualProgress)
                )
                .disabled(session.coachClientPolicy.coachPlanReadOnly)

                Button(language.text("Save sharing choices")) {
                    guard let operation = session.accountOperationLease() else { return }
                    Task { await updateCoachScopes(sponsorship.relationshipID, operation: operation) }
                }
                .font(APEXFont.body(14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(APEXColor.green, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .disabled(busy || session.coachClientPolicy.coachPlanReadOnly)

                Button(role: .destructive) { confirmEnd = true } label: {
                    Text(language.text("End coach access"))
                        .font(APEXFont.body(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .background(APEXColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private func syncPrivacyState() {
        scopes = session.coachContext.sponsorship?.consentedScopes ?? []
        scopes.remove(.visualProgress)
        visualProgress = session.coachContext.sponsorship?.consentedScopes.contains(.visualProgress) ?? false
    }

    @MainActor
    private func acknowledgeCoachPlan(_ id: UUID, operation: AccountOperationLease) async {
        await perform(operation: operation) {
            try await session.acknowledgeCoachPlan(planVersionID: id, operation: operation)
        }
    }

    @MainActor
    private func activateCoachPlan(_ id: UUID, operation: AccountOperationLease) async {
        await perform(operation: operation) {
            try await session.activateCoachPlan(planVersionID: id, operation: operation)
        }
    }

    @MainActor
    private func updateCoachScopes(_ relationshipID: UUID, operation: AccountOperationLease) async {
        await perform(operation: operation) {
            try await session.updateCoachScopes(
                relationshipID: relationshipID,
                scopes: scopes,
                visualProgressConsent: visualProgress,
                operation: operation
            )
        }
    }

    @MainActor
    private func endRelationship(operation: AccountOperationLease) async {
        guard let relationshipID = session.coachContext.sponsorship?.relationshipID else { return }
        await perform(operation: operation) {
            try await session.endCoachRelationship(
                relationshipID: relationshipID,
                operation: operation
            )
        }
    }

    @MainActor
    private func perform(
        operation: AccountOperationLease,
        _ action: @escaping () async throws -> Void
    ) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        busy = true
        defer {
            if session.accountOperationIsCurrent(operation) { busy = false }
        }
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }
}

/// Invitation acceptance is deliberately reusable from the locked access
/// boundary. A client who has not yet received an individual grant can accept
/// a coach-sponsored seat without briefly exposing any other private screen.
struct CoachInvitationAcceptanceCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var scopes: Set<CoachConsentScope> = []
    @State private var visualProgress = false
    @State private var busy = false
    @State private var invitationToken = ""
    @State private var invitationPreview: CoachInvitationPreview?

    var onAccepted: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                Text(language.text("Accept coach invitation"))
                    .font(APEXFont.display(29))
                    .foregroundStyle(APEXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("Paste the private invitation token from your coach."))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField(language.text("Invitation token"), text: $invitationToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(APEXFont.mono(11))
                    .padding(13)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let invitationPreview {
                    Text("\(language.text("Provided by")) \(invitationPreview.coachDisplayName)")
                        .font(APEXFont.body(14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    CoachScopeSelector(
                        scopes: $scopes,
                        visualProgress: $visualProgress,
                        offered: invitationPreview.requestedScopes,
                        visualProgressOffered: invitationPreview.visualProgressRequested
                    )
                    Button(language.text("Accept and continue")) {
                        guard let operation = session.accountOperationLease() else { return }
                        Task { await acceptInvitation(operation: operation) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.violet)
                    .frame(maxWidth: .infinity)
                    .disabled(busy || scopes.isEmpty)
                } else {
                    Button(language.text("Review invitation")) {
                        guard let operation = session.accountOperationLease() else { return }
                        Task { await previewInvitation(operation: operation) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.violet)
                    .disabled(busy || invitationToken.count != 48)
                }
            }
        }
        .onChange(of: invitationToken) { _, _ in invitationPreview = nil }
    }

    @MainActor
    private func previewInvitation(operation: AccountOperationLease) async {
        busy = true
        defer {
            if session.accountOperationIsCurrent(operation) { busy = false }
        }
        do {
            let preview = try await session.previewCoachInvitation(
                token: invitationToken,
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            invitationPreview = preview
            scopes = preview.requestedScopes.subtracting([.visualProgress])
            visualProgress = false
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func acceptInvitation(operation: AccountOperationLease) async {
        busy = true
        defer {
            if session.accountOperationIsCurrent(operation) { busy = false }
        }
        do {
            try await session.acceptCoachInvitation(
                token: invitationToken,
                scopes: scopes,
                visualProgressConsent: visualProgress,
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            onAccepted?()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct CoachPublishedSessionCard: View {
    @State private var language = LanguageState.shared
    let session: CoachSessionTemplate

    private var weekday: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.language.locale
        let symbols = calendar.weekdaySymbols
        let index = session.weekday == 7 ? 0 : session.weekday
        return symbols.indices.contains(index) ? symbols[index] : language.text("Session")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(weekday.uppercased(with: language.language.locale))
                        .font(APEXFont.mono(8, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(APEXColor.violet)
                    Text(session.name)
                        .font(APEXFont.body(17, weight: .bold))
                        .foregroundStyle(APEXColor.ink)
                }
                Spacer()
                Text(language.format("%d min", session.estimatedMinutes))
                    .font(APEXFont.mono(9, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.85), in: Capsule())
            }
            if !session.warmupNote.isEmpty {
                Text(session.warmupNote).font(APEXFont.body(11, weight: .semibold)).foregroundStyle(APEXColor.secondaryInk)
            }
            ForEach(session.exercises) { exercise in
                HStack(alignment: .top, spacing: 8) {
                    Text(exercise.name)
                        .font(APEXFont.body(12, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(exercise.sets) × \(exercise.targetMin == exercise.targetMax ? "\(exercise.targetMin)" : "\(exercise.targetMin)–\(exercise.targetMax)") \(exercise.unit)")
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(APEXColor.violet)
                }
                .padding(10)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .padding(13)
        .background(APEXColor.violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
