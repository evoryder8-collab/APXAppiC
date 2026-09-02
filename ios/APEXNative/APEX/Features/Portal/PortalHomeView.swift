import SwiftUI

struct PortalHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var nudges = NudgeCenter.shared
    @State private var showNudges = false
    @State private var showPaywall = false
    @State private var language = LanguageState.shared
    @State private var showingSyncIssues = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        /* Through the tables rather than a switch, so a language added later
           needs a table entry and nothing else. */
        let key = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return language.text(key)
    }

    private var greetingLine: String {
        let name = session.profile?.displayName ?? "APEX"
        /* Thai and Japanese do not punctuate a greeting the way the Latin
           languages do, so the comma and full stop are dropped rather than
           transplanted. */
        let latinPunctuation = ![.thai, .japanese].contains(language.language)
        return latinPunctuation ? "\(greeting),\n\(name)." : "\(greeting)\n\(name)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                APEXTopBar(
                    profile: session.profile,
                    onSettings: { session.navigationPath.append(.settings) },
                    nudges: nudges,
                    onOpenNudges: { showNudges = true },
                    onOpenPaywall: { showPaywall = true }
                )

                HStack {
                    PortalModeSwitcher()
                    Spacer()
                    Text(language.text("Full control"))
                        .font(APEXFont.mono(9))
                        .tracking(1)
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(language.language.locale)).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(11))
                        .tracking(2.2)
                        .foregroundStyle(APEXColor.secondaryInk)
                    Text(greetingLine)
                        .font(APEXFont.display(39))
                        .foregroundStyle(APEXColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 32)

                if session.coachClientPolicy.canUseAvatar { ProfilePortalTile() }
                if session.coachClientPolicy.canUseNutrition {
                    PortalTile(
                        title: language.text(.nutrition),
                        subtitle: language.text(.mealsSupplementsLog),
                        icon: "leaf",
                        color: APEXColor.amber,
                        destination: .nutrition
                    )
                }
                if session.coachContext.capabilities.coachWorkspace {
                    PortalTile(
                        title: language.text("Coach workspace"),
                        subtitle: language.text("Your clients, plans and reviews in one private place."),
                        icon: "person.2.badge.gearshape",
                        color: APEXColor.violet,
                        destination: .coachWorkspace
                    )
                }
                if session.coachContext.capabilities.sponsoredClient {
                    PortalTile(
                        title: language.text("Your coach plan"),
                        subtitle: language.format("Provided by %@", session.coachContext.sponsorship?.coachDisplayName ?? "APEX"),
                        icon: "person.crop.circle.badge.checkmark",
                        color: APEXColor.violet,
                        destination: .coachPlan
                    )
                }
                if session.coachClientPolicy.canRebuildFitnessPlan { FitnessPlanDisclosure() }
                if session.coachClientPolicy.canCreateCustomWorkouts,
                   session.data.programs.contains(where: { $0.slug == "custom" }) {
                    PortalTile(
                        title: language.text(.customWorkouts),
                        subtitle: language.text(.customWorkoutsSubtitle),
                        icon: "square.and.pencil",
                        color: APEXColor.violet,
                        destination: .customWorkouts
                    )
                }
                if session.coachClientPolicy.canUseOrbit {
                    PortalTile(
                        title: language.text(.orbit),
                        subtitle: language.text(.runIntelligence),
                        icon: "figure.run",
                        color: APEXColor.cyan,
                        destination: .orbit
                    )
                }

                HStack {
                    PortalLanguagePicker()
                    Spacer()
                    if session.failedSyncCount > 0 {
                        SyncIssuesButton(count: session.failedSyncCount) {
                            showingSyncIssues = true
                        }
                    } else if session.isRefreshing {
                        ProgressView().tint(APEXColor.teal)
                    } else if let sync = session.lastSyncAt {
                        Label(sync.formatted(.relative(presentation: .named).locale(language.language.locale)), systemImage: "checkmark.icloud")
                            .font(APEXFont.body(11, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 30)
.dockClearance()
        }
        .refreshable { await session.refresh() }
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
        .sheet(isPresented: $showingSyncIssues) {
            SyncIssuesSheet()
                .environment(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNudges) {
            NudgeSheet(nudges: nudges) { showNudges = false }
                .apexTransientSheet(.fraction(0.62))
        }
        .task { await session.refreshNudges() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FitnessPlanDisclosure: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var state = FitnessPlanDisclosureState()
    @State private var revealTask: Task<Void, Never>?

    private var introductionSeen: Bool {
        session.data.settings?.addons["fitness_plan_intro_seen"]?.boolValue ?? false
    }

    private var disclosureTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleDisclosure) {
                HStack(spacing: 17) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .background(
                            LinearGradient(
                                colors: [APEXColor.teal, APEXColor.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 23)
                        )
                        .shadow(color: APEXColor.violet.opacity(0.2), radius: 14, y: 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.shortText("Fitness Plan").uppercased(with: language.language.locale))
                            .font(APEXFont.display(20))
                            .tracking(2.3)
                            .foregroundStyle(APEXColor.ink)
                        Text("\(language.shortText("Transition Phase")) · \(language.shortText("Main Phase"))")
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 7) {
                            Capsule()
                                .fill(APEXColor.teal)
                                .frame(width: 22, height: 4)
                            Capsule()
                                .fill(APEXColor.violet)
                                .frame(width: 22, height: 4)
                        }
                        .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(16)
                .frame(minHeight: 112)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("portal.fitness-plan")
            .accessibilityLabel(language.text("Fitness Plan"))
            .accessibilityValue(language.text(state.expanded ? "Expanded" : "Collapsed"))
            .sensoryFeedback(.selection, trigger: state.expanded)

            if state.expanded {
                VStack(spacing: 12) {
                    FitnessPlanPhaseCard(
                        phase: .transition,
                        title: language.shortText("Transition Phase"),
                        titleAccessibility: language.text("Transition Phase"),
                        introduction: language.shortText("If you haven't trained in a long time."),
                        introductionAccessibility: language.text("If you haven't trained in a long time."),
                        information: language.text("Return here after a long break to rebuild consistency, movement quality and training tolerance."),
                        icon: "chevron.forward.2",
                        color: APEXColor.teal,
                        showsIntroduction: state.showsIntroduction,
                        introductionPresented: state.presentedIntroductionPhases.contains(.transition),
                        activeInfo: $state.activeInfo,
                        action: openTransition
                    )
                    FitnessPlanPhaseCard(
                        phase: .main,
                        title: language.shortText("Main Phase"),
                        titleAccessibility: language.text("Main Phase"),
                        introduction: language.shortText("Fit enough to start the main journey."),
                        introductionAccessibility: language.text("Fit enough to start the main journey."),
                        information: language.text("Choose this when regular training feels manageable and you're ready to build strength, muscle and performance."),
                        icon: "bolt.fill",
                        color: APEXColor.violet,
                        showsIntroduction: state.showsIntroduction,
                        introductionPresented: state.presentedIntroductionPhases.contains(.main),
                        activeInfo: $state.activeInfo,
                        action: openMainPhase
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(disclosureTransition)
            }
        }
        .background(.ultraThinMaterial.opacity(0.94), in: RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.95), APEXColor.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: APEXColor.violet.opacity(0.12), radius: 22, y: 12)
        .onDisappear(perform: cancelReveal)
    }

    private func toggleDisclosure() {
        cancelReveal()
        let opening = !state.expanded
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.86)) {
            state.toggle(introductionSeen: introductionSeen)
        }
        guard opening else { return }
        beginIntroductionReveal()
    }

    private func beginIntroductionReveal() {
        guard state.expanded, state.showsIntroduction else { return }
        guard let operation = session.accountOperationLease() else { return }
        revealTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(360))
            }
            guard !Task.isCancelled,
                  session.accountOperationIsCurrent(operation) else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) {
                _ = state.recordIntroductionPresented(for: .transition)
            }

            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled,
                  session.accountOperationIsCurrent(operation) else { return }
            let shouldPersist = withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) {
                state.recordIntroductionPresented(for: .main)
            }
            if shouldPersist {
                try? await session.updateSettings({ settings in
                    settings.addons["fitness_plan_intro_seen"] = .bool(true)
                }, operation: operation)
            }
        }
    }

    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
        state.selectInfo(nil)
    }

    private func openTransition() {
        state.selectInfo(nil)
        session.navigationPath.append(.transition)
    }

    private func openMainPhase() {
        state.selectInfo(nil)
        session.navigationPath.append(.mainPhase)
    }
}

private struct FitnessPlanPhaseCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: FitnessPlanPhase
    let title: String
    let titleAccessibility: String
    let introduction: String
    let introductionAccessibility: String
    let information: String
    let icon: String
    let color: Color
    let showsIntroduction: Bool
    let introductionPresented: Bool
    @Binding var activeInfo: FitnessPlanPhase?
    let action: () -> Void

    private var infoPresented: Binding<Bool> {
        Binding(
            get: { activeInfo == phase },
            set: { presented in
                if !presented, activeInfo == phase { activeInfo = nil }
            }
        )
    }

    private var destinationAccessibilityLabel: String {
        guard showsIntroduction, introductionPresented else { return titleAccessibility }
        return "\(titleAccessibility). \(introductionAccessibility)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 13) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(color.gradient, in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.uppercased())
                            .font(APEXFont.display(16))
                            .tracking(1.6)
                            .foregroundStyle(APEXColor.ink)
                        if showsIntroduction, introductionPresented {
                            Text(introduction)
                                .font(APEXFont.body(13, weight: .semibold))
                                .foregroundStyle(color)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(phase == .transition ? "portal.transition" : "portal.main")
            .accessibilityLabel(destinationAccessibilityLabel)

            if !showsIntroduction {
                GleamingPhaseInfoButton(
                    information: information,
                    color: color,
                    isPresented: infoPresented,
                    action: toggleInformation
                )
                .accessibilityIdentifier(
                    phase == .transition ? "fitness-plan.info.transition" : "fitness-plan.info.main"
                )
            }
        }
        .padding(12)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23).stroke(color.opacity(0.16))
        }
        .shadow(color: color.opacity(0.09), radius: 14, y: 7)
    }

    private func toggleInformation() {
        activeInfo = activeInfo == phase ? nil : phase
    }
}

private struct GleamingPhaseInfoButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let information: String
    let color: Color
    let isPresented: Binding<Bool>
    let action: () -> Void
    @State private var shine = false

    var body: some View {
        Button(information, systemImage: "info.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.1), in: Circle())
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.95), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 9, height: 52)
                .rotationEffect(.degrees(-24))
                .offset(x: shine ? 26 : -26)
                .mask(Circle().frame(width: 44, height: 44))
                .allowsHitTesting(false)
            }
            .popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                Text(information)
                    .font(.body)
                    .foregroundStyle(APEXColor.ink)
                    .padding()
                    .frame(idealWidth: 270, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
            .task(id: reduceMotion) {
                shine = false
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(4_500))
                    } catch {
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.75)) {
                        shine.toggle()
                    }
                }
            }
    }
}

private struct PortalTile: View {
    @Environment(AppSession.self) private var session
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let destination: PortalDestination

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            session.navigationPath.append(destination)
        } label: {
            HStack(spacing: 17) {
                Image(systemName: icon)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .shadow(color: color.opacity(0.24), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(APEXFont.display(20))
                        .tracking(2.3)
                        .foregroundStyle(APEXColor.ink)
                    Text(subtitle)
                        .font(APEXFont.body(15, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
            }
            .padding(16)
            .frame(minHeight: 112)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.9)))
            .shadow(color: color.opacity(0.12), radius: 22, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portal.\(destination.accessibilityID)")
    }
}

private struct ProfilePortalTile: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine = false

    var body: some View {
        Button {
            session.navigationPath.append(.avatar)
        } label: {
            HStack(spacing: 17) {
                ZStack {
                    PortraitImage(name: session.profile?.persona.portraitName ?? "constantine")
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                    LinearGradient(
                        colors: [.clear, .white.opacity(0.75), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 22, height: 110)
                    .rotationEffect(.degrees(-22))
                    .offset(x: shine ? 70 : -70)
                    .blendMode(.screen)
                    .mask(RoundedRectangle(cornerRadius: 23, style: .continuous).frame(width: 70, height: 70))
                }
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 6) {
                    Text((session.profile?.displayName ?? "PROFILE").uppercased())
                        .font(APEXFont.display(20))
                        .tracking(2.3)
                        .foregroundStyle(APEXColor.ink)
                    Text(LanguageState.shared.text(.statsBodyNeeds))
                        .font(APEXFont.body(15, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
            }
            .padding(16)
            .frame(minHeight: 112)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.9)))
            .shadow(color: APEXColor.green.opacity(0.14), radius: 22, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portal.avatar")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false).delay(1.2)) {
                shine = true
            }
        }
    }
}

private extension PortalDestination {
    var accessibilityID: String {
        switch self {
        case .coachWorkspace: "coach-workspace"
        case .coachPlan: "coach-plan"
        case .coachWorkouts: "coach-workouts"
        case .nutrition: "nutrition"
        case .transition: "transition"
        case .mainPhase: "main"
        case .customWorkouts: "custom"
        case .orbit: "orbit"
        case .avatar: "avatar"
        case .visualProgress: "visual-progress"
        case .settings: "settings"
        }
    }
}
