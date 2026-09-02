import SwiftUI

struct MarathonCampaignView: View {
    @Environment(AppSession.self) private var session
    @State private var missedCandidate: OrbitCampaignSession?
    @State private var language = LanguageState.shared

    private var campaign: OrbitCampaign? {
        session.data.orbitCampaigns.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let campaign {
                    campaignContent(campaign)
                } else {
                    emptyCampaign
                }

                Text(language.text("APEX Orbit Marathon Campaign provides personalized fitness training, educational guidance and performance tracking for adults preparing for endurance events. It does not diagnose, treat, monitor, predict or prevent disease or injury and does not determine medical fitness for exercise."))
                    .font(APEXFont.body(9, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle(language.text("Marathon Campaign"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Mark this session missed?",
            isPresented: Binding(
                get: { missedCandidate != nil },
                set: { if $0 == false { missedCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(language.text("Mark missed and rebalance")) {
                guard let item = missedCandidate else { return }
                guard let operation = session.accountOperationLease() else { return }
                missedCandidate = nil
                Task { await markMissed(item, operation: operation) }
            }
            Button(language.text("Cancel"), role: .cancel) { missedCandidate = nil }
        } message: {
            Text(language.text("Orbit continues forward without stacking catch-up work. The original prescription stays visible."))
        }
    }

    private var emptyCampaign: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color(red: 0.09, green: 0.04, blue: 0.22), Color(red: 0.02, green: 0.16, blue: 0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                CelestialField()
                    .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                VStack(alignment: .leading, spacing: 16) {
                    Text(language.text("PERSONAL · PRIVATE · ADAPTIVE"))
                        .font(APEXFont.mono(9))
                        .tracking(1.4)
                        .foregroundStyle(APEXColor.cyan)
                    Text(language.text("Build the credible path to 42.195 km."))
                        .font(APEXFont.display(33))
                    Text(language.text("Orbit reuses your APEX profile, strength week, activity history and calendar. It asks only what it does not already know, then assigns a readiness outcome before creating a campaign."))
                        .font(APEXFont.body(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    NavigationLink {
                        MarathonInductionView()
                    } label: {
                        Label(language.text("Begin induction"), systemImage: "arrow.right")
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                }
                .foregroundStyle(.white)
                .padding(26)
            }
            .frame(minHeight: 430)

            GlassCard(radius: 29, padding: 19) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text("Not every runner receives a twelve-week plan."))
                        .font(APEXFont.display(19))
                    Text(language.text("A credible recent base may enter marathon-specific training. A newer or returning runner receives Foundation first. A timeline that is too close is explained instead of compressed."))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder
    private func campaignContent(_ campaign: OrbitCampaign) -> some View {
        if campaign.status == "review_required" {
            outcomeCard(
                kicker: "FITNESS-READINESS OUTCOME",
                title: "Professional review recommended before strenuous marathon preparation",
                body: campaign.assignmentReason,
                warning: "This is not a diagnosis and APEX has not medically cleared or rejected you. General Orbit remains available, subject to any existing professional restriction."
            )
        } else if campaign.status == "paused" {
            outcomeCard(
                kicker: "TIMELINE CHECK",
                title: "More information needed",
                body: campaign.assignmentReason,
                warning: campaign.timelineWarning
            )
        } else {
            activeCampaign(campaign)
        }
    }

    private func outcomeCard(kicker: String, title: String, body: String, warning: String) -> some View {
        GlassCard(radius: 32, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text(kicker))
                    .font(APEXFont.mono(9))
                    .tracking(1.3)
                    .foregroundStyle(APEXColor.amber)
                Text(language.text(title))
                    .font(APEXFont.display(27))
                Text(language.text(body))
                    .font(APEXFont.body(13, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                if warning.isEmpty == false {
                    Text(language.text(warning))
                        .font(APEXFont.body(11, weight: .semibold))
                        .padding(13)
                        .background(APEXColor.amber.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
                }
                NavigationLink("Review induction") { MarathonInductionView() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func activeCampaign(_ campaign: OrbitCampaign) -> some View {
        let sessions = campaignSessions(campaign)
        let next = nextSession(sessions)
        let currentPhase = next?.phase ?? campaign.phase
        let readiness = OrbitCampaignEngine.readiness(
            runs: session.data.orbitRuns,
            sessions: sessions,
            campaign: campaign
        )

        return VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text(campaign.outcome == "foundation" ? "FOUNDATION FIRST" : "MARATHON-SPECIFIC CAMPAIGN"))
                    .font(APEXFont.mono(9))
                    .tracking(1.3)
                    .foregroundStyle(campaign.outcome == "foundation" ? APEXColor.violet : APEXColor.cyan)
                Text(campaign.raceName)
                    .font(APEXFont.display(34))
                Text(language.format(
                    "%d days remaining · %@",
                    max(0, daysUntil(campaign.raceDate)),
                    language.text(OrbitCampaignEngine.campaignFamilyLabel(campaign.family))
                ))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OrbitalJourneyView(phase: currentPhase, sessions: sessions)

            if let next {
                sessionCard(next, campaign: campaign)
            } else {
                GlassCard(radius: 30, padding: 21) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text("Post-marathon recovery"))
                            .font(APEXFont.display(24))
                        Text(language.text("No demanding session is waiting. Orbit preserves a gradual return before another campaign."))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
            }

            if currentPhase == "race_week" { RaceWeekCommandCentre(campaign: campaign) }

            GlassCard(radius: 30, padding: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(language.text("CURRENT PHASE"))
                        .font(APEXFont.mono(9))
                        .foregroundStyle(APEXColor.violet)
                    Text(language.text(OrbitCampaignEngine.phaseLabel(currentPhase)))
                        .font(APEXFont.display(24))
                    Text(language.text(campaign.assignmentReason))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                    Text(campaign.planVersion)
                        .font(APEXFont.mono(8))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(APEXColor.violet.opacity(0.1), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Text(language.text("Marathon readiness"))
                    .font(APEXFont.display(24))
                Text(language.text("No mysterious score. Every conclusion keeps its reason visible."))
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                ForEach(readiness) { component in
                    ReadinessRow(component: component)
                }
            }

            CampaignWeekView(sessions: sessions)

            DisclosureGroup("View remaining campaign") {
                VStack(spacing: 7) {
                    ForEach(sessions.filter { $0.date >= Date().apexDateKey }.prefix(80)) { item in
                        HStack {
                            Text(language.format(
                                "%@ · %@",
                                language.dateKey(item.date),
                                language.text(item.adapted["title"]?.stringValue ?? "Run")
                            ))
                                .font(APEXFont.body(10, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(language.format("%d min", Int(item.adapted["duration_min"]?.numberValue ?? 0)))
                                .font(APEXFont.mono(8))
                        }
                        .padding(10)
                        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 10)
            }
            .font(APEXFont.body(12, weight: .bold))
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))

            if campaign.adaptations.isEmpty == false {
                RecentAdaptationsView(campaign: campaign)
            }

            GlassCard(radius: 28, padding: 19) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(language.text("Why this plan is built this way"))
                        .font(APEXFont.display(19))
                    Text(language.text("Predominantly controlled running, progressive exposure, purposeful quality, long-run development, recovery, strength coordination, fueling rehearsal and tapering. The rules are versioned and their limitations remain visible."))
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                    NavigationLink("Open Science Ledger") { OrbitScienceView() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionCard(_ item: OrbitCampaignSession, campaign: OrbitCampaign) -> some View {
        let mission = item.adapted["mission"]?.stringValue ?? "easy"
        let duration = Int(item.adapted["duration_min"]?.numberValue ?? 0)
        let minimum = Int(item.adapted["minimum_version_min"]?.numberValue ?? 0)
        return GlassCard(radius: 32, padding: 21) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(item.date == Date().apexDateKey ? language.text("TODAY") : language.dateKey(item.date))
                        .font(APEXFont.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(item.date == Date().apexDateKey ? APEXColor.amber : APEXColor.cyan)
                    Spacer()
                    Text(language.text(OrbitCampaignEngine.phaseLabel(item.phase)).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(8))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Text(language.text(item.adapted["title"]?.stringValue ?? "Campaign run"))
                    .font(APEXFont.display(27))
                Text(language.format("%d minutes · %@", duration, language.text(item.adapted["intensity"]?.stringValue ?? "Controlled effort")))
                    .font(APEXFont.body(12, weight: .bold))
                    .foregroundStyle(APEXColor.cyan)

                detail("PURPOSE", item.adapted["purpose"]?.stringValue ?? "")
                detail("ROUTE", item.adapted["route_characteristics"]?.stringValue ?? "")

                DisclosureGroup("Why?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text(item.adapted["why"]?.stringValue ?? ""))
                        detail("WARM-UP", item.adapted["warmup"]?.stringValue ?? "")
                        detail("MAIN WORK", item.adapted["main_work"]?.stringValue ?? "")
                        detail("COOLDOWN", item.adapted["cooldown"]?.stringValue ?? "")
                        detail("FUELING", item.adapted["fueling_note"]?.stringValue ?? "")
                    }
                    .padding(.top, 8)
                }
                .font(APEXFont.body(12, weight: .bold))

                if item.adaptationReason.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text("PLAN ADAPTATION"))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.violet)
                        Text(language.text(item.adaptationReason))
                            .font(APEXFont.body(11, weight: .semibold))
                        Text(language.format(
                            "Original: %@ · %d min. Adapted: %@ · %d min.",
                            missionLabel(item.original),
                            Int(item.original["duration_min"]?.numberValue ?? 0),
                            missionLabel(item.adapted),
                            duration
                        ))
                            .font(APEXFont.body(9, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                        HStack {
                            Button(language.text("Use adapted")) {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await chooseVersion(item, useOriginal: false, operation: operation) }
                            }
                                .buttonStyle(.borderedProminent)
                                .tint(APEXColor.violet)
                            Button(language.text("Keep original")) {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await chooseVersion(item, useOriginal: true, operation: operation) }
                            }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(13)
                    .background(APEXColor.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 19))
                }

                NavigationLink {
                    RoutePlannerView(initialMission: mission, campaignSessionID: item.id)
                } label: {
                    Label(language.text("Choose route"), systemImage: "map")
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))

                HStack {
                    NavigationLink {
                        LiveRunView(mission: mission.replacingOccurrences(of: "_", with: " ").capitalized, campaignSessionID: item.id)
                    } label: {
                        Label(language.text("Start session"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.cyan)

                    if minimum > 0 {
                        NavigationLink {
                            LiveRunView(mission: mission.replacingOccurrences(of: "_", with: " ").capitalized, campaignSessionID: item.id)
                        } label: {
                            Text(language.format("%d-minute minimum", minimum))
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button(language.text("Mark missed")) { missedCandidate = item }
                    .font(APEXFont.body(11, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private func detail(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(title)).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text(language.text(body)).font(APEXFont.body(11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 17))
    }

    private func campaignSessions(_ campaign: OrbitCampaign) -> [OrbitCampaignSession] {
        session.data.orbitCampaignSessions.filter { $0.campaignID == campaign.id }.sorted { $0.date < $1.date }
    }

    private func nextSession(_ items: [OrbitCampaignSession]) -> OrbitCampaignSession? {
        items.first { $0.date == Date().apexDateKey && $0.status == "planned" }
            ?? items.first { $0.date >= Date().apexDateKey && $0.status == "planned" }
    }

    private func missionLabel(_ prescription: [String: JSONValue]) -> String {
        language.text((prescription["mission"]?.stringValue ?? "run").replacingOccurrences(of: "_", with: " ").capitalized)
    }

    @MainActor
    private func markMissed(
        _ item: OrbitCampaignSession,
        operation: AccountOperationLease
    ) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            try await session.markOrbitCampaignSessionMissed(item, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func chooseVersion(
        _ item: OrbitCampaignSession,
        useOriginal: Bool,
        operation: AccountOperationLease
    ) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        do {
            try await session.chooseOrbitCampaignVersion(
                item,
                useOriginal: useOriginal,
                operation: operation
            )
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    private func daysUntil(_ value: String) -> Int {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: value) else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0
    }
}

private struct OrbitalJourneyView: View {
    @State private var language = LanguageState.shared
    let phase: String
    let sessions: [OrbitCampaignSession]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(OrbitCampaignEngine.phaseOrder.enumerated()), id: \.element) { index, item in
                    let activeIndex = OrbitCampaignEngine.phaseOrder.firstIndex(of: phase) ?? 0
                    let active = index == activeIndex
                    let completed = sessions.filter { $0.phase == item && $0.status == "completed" }.count
                    HStack(spacing: 0) {
                        VStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(active ? APEXColor.amber : index < activeIndex ? APEXColor.cyan.opacity(0.22) : .white.opacity(0.07))
                                    .frame(width: 42, height: 42)
                                    .shadow(color: active ? APEXColor.amber.opacity(0.65) : .clear, radius: 18)
                                Text(completed > 0 ? "\(completed)" : "·")
                                    .font(APEXFont.mono(10))
                                    .foregroundStyle(active ? .black : .white)
                            }
                            Text(language.text(OrbitCampaignEngine.phaseLabel(item)).uppercased(with: language.language.locale))
                                .font(APEXFont.mono(7))
                                .foregroundStyle(active ? APEXColor.amber : .white.opacity(0.42))
                                .frame(width: 82)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        if index < OrbitCampaignEngine.phaseOrder.count - 1 {
                            Rectangle()
                                .fill(index < activeIndex ? APEXColor.cyan.opacity(0.5) : .white.opacity(0.12))
                                .frame(width: 28, height: 1)
                                .offset(y: -12)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(colors: [.black, Color(red: 0.07, green: 0.04, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 31)
        )
        .overlay(alignment: .bottomLeading) {
            Text(language.text("Missed sessions reorganise the path. They do not break it."))
                .font(APEXFont.body(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(15)
        }
        .padding(.bottom, 28)
    }
}

private struct ReadinessRow: View {
    @State private var language = LanguageState.shared
    let component: OrbitReadinessComponent

    var body: some View {
        GlassCard(radius: 23, padding: 15) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(language.text(component.label)).font(APEXFont.display(17))
                    Spacer()
                    Text(language.text(component.state.replacingOccurrences(of: "_", with: " ").capitalized).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(7))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(color.opacity(0.12), in: Capsule())
                        .foregroundStyle(color)
                }
                Text(language.text(component.reason))
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private var color: Color {
        ["strong", "on_track"].contains(component.state) ? .green : component.state == "needs_attention" ? APEXColor.amber : APEXColor.cyan
    }
}

private struct CampaignWeekView: View {
    @State private var language = LanguageState.shared
    let sessions: [OrbitCampaignSession]

    private var window: [OrbitCampaignSession] {
        let lower = Calendar.current.date(byAdding: .day, value: -3, to: .now)?.apexDateKey ?? ""
        let upper = Calendar.current.date(byAdding: .day, value: 4, to: .now)?.apexDateKey ?? ""
        return sessions.filter { $0.date >= lower && $0.date <= upper }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("Current week"))
                .font(APEXFont.display(23))
            if window.isEmpty {
                Text(language.text("No prescribed run falls in the current calendar window."))
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            ForEach(window) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.format(
                            "%@ · %@",
                            language.dateKey(item.date),
                            language.text(item.adapted["title"]?.stringValue ?? "Run")
                        ))
                            .font(APEXFont.body(12, weight: .bold))
                        Text(language.format(
                            "%d min · %@",
                            Int(item.adapted["duration_min"]?.numberValue ?? 0),
                            language.text(item.status.capitalized)
                        ))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: item.status == "completed" ? "checkmark.circle.fill" : item.adapted["demanding"]?.boolValue == true ? "bolt.circle.fill" : "leaf.circle.fill")
                        .foregroundStyle(item.status == "completed" ? .green : item.adapted["demanding"]?.boolValue == true ? APEXColor.amber : APEXColor.cyan)
                }
                .padding(13)
                .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

private struct RecentAdaptationsView: View {
    @State private var language = LanguageState.shared
    let campaign: OrbitCampaign

    var body: some View {
        GlassCard(radius: 28, padding: 19) {
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("Recent adaptations"))
                    .font(APEXFont.display(21))
                ForEach(Array(campaign.adaptations.suffix(5).reversed().enumerated()), id: \.offset) { _, value in
                    if case .object(let object) = value {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.text(object["reason"]?.stringValue ?? "Campaign adjusted"))
                                .font(APEXFont.body(10, weight: .semibold))
                            Text(language.text(object["accepted"]?.boolValue == nil ? "AWAITING YOUR CHOICE" : object["accepted"]?.boolValue == true ? "ADAPTED VERSION ACCEPTED" : "ORIGINAL KEPT"))
                                .font(APEXFont.mono(7))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        .padding(11)
                        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }
}

private struct RaceWeekCommandCentre: View {
    @State private var language = LanguageState.shared
    let campaign: OrbitCampaign

    private let items = [
        ("Taper status", "Volume reduced while familiar rhythm remains."),
        ("Primary pacing", "Begin conservatively and settle into rehearsed marathon effort."),
        ("Fallback strategy", "Use controlled perceived effort if weather or course conditions differ."),
        ("Fueling", "Use only products and timing already tolerated in long-run rehearsals."),
        ("Breakfast", "Use a familiar saved breakfast. Do not introduce a new race-day product."),
        ("Equipment", "Shoes, clothing, route, transport and start details checked."),
        ("Weather decision", "Review an authoritative forecast close to the race."),
        ("After the finish", "Begin the scheduled recovery phase instead of returning immediately to hard training.")
    ]

    var body: some View {
        GlassCard(radius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("RACE WEEK COMMAND CENTRE"))
                    .font(APEXFont.mono(9))
                    .foregroundStyle(APEXColor.amber)
                Text(language.text("Calm, rehearsed, decisive."))
                    .font(APEXFont.display(25))
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(item.0)).font(APEXFont.body(11, weight: .bold))
                        Text(language.text(item.1)).font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    }
                    .padding(11)
                    .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                }
                Text(language.text("Orbit does not promise a finish time. The pacing strategy remains adjustable to conditions and how the body responds."))
                    .font(APEXFont.body(9, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }
}

struct OrbitScienceView: View {
    @State private var language = LanguageState.shared
    private let ledger = [
        ("Controlled low-intensity running", "Most campaign sessions remain conversational. Quality work is limited and purposeful.", "Broad endurance evidence and coaching consensus", "High", "Intensity boundaries depend on the quality of available pace, heart-rate and perceived-effort data."),
        ("Progressive exposure", "Duration grows conservatively, with slower progression for new or returning runners and periodic cutbacks.", "Recreational marathon preparation", "Moderate to high", "Population rules cannot perfectly predict individual tolerance."),
        ("Strength coordination", "Hybrid campaigns separate demanding lower-body work and quality running where the calendar permits.", "APEX users maintaining strength", "Moderate", "Real-world work and travel can still require manual adjustment."),
        ("Fueling rehearsal", "Long runs progressively practise familiar pre-run and during-run nutrition before race week.", "Runs long enough to require rehearsal", "High", "Individual gastrointestinal tolerance varies."),
        ("Tapering", "Volume reduces before race day while familiar movement rhythm remains.", "Marathon-specific campaigns", "High", "The exact taper response differs between runners."),
        ("Fitness-readiness boundary", "Current concerning symptoms or an existing restriction lead to professional review before strenuous assignment. Old resolved history does not automatically block training.", "All induction outcomes", "Policy boundary", "This is not medical clearance or diagnosis.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                ForEach(Array(ledger.enumerated()), id: \.offset) { _, item in
                    GlassCard(radius: 27, padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language.text(item.0)).font(APEXFont.display(20))
                            Text(language.text(item.1)).font(APEXFont.body(11, weight: .semibold))
                            ledgerLine("INTENDED FOR", item.2)
                            ledgerLine("CONFIDENCE", item.3)
                            ledgerLine("LIMITATION", item.4)
                        }
                    }
                }
                Text(language.format("Plan version %@ · review date 15 January 2027", OrbitCampaignEngine.planVersion))
                    .font(APEXFont.mono(8))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .padding(18)
        }
        .navigationTitle(language.text("Science Ledger"))
    }

    private func ledgerLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language.text(title)).font(APEXFont.mono(7)).foregroundStyle(APEXColor.cyan)
            Text(language.text(value)).font(APEXFont.body(9, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
        }
    }
}

private struct CelestialField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<38 {
                let x = Double((index * 71) % 101) / 100 * size.width
                let y = Double((index * 43) % 97) / 100 * size.height
                let radius = index.isMultiple(of: 7) ? 1.8 : 0.8
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(index.isMultiple(of: 5) ? 0.8 : 0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}
