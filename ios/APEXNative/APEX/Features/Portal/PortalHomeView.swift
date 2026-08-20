import SwiftUI

struct PortalHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var nudges = NudgeCenter.shared
    @State private var showNudges = false
    @State private var showPaywall = false
    @State private var language = LanguageState.shared

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
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 32)

                PortalTile(
                    title: language.text(.nutrition),
                    subtitle: language.text(.mealsSupplementsLog),
                    icon: "leaf",
                    color: APEXColor.amber,
                    destination: .nutrition
                )
                PortalTile(
                    title: language.text(.transition),
                    subtitle: language.text(.currentProgram),
                    icon: "chevron.forward.2",
                    color: APEXColor.teal,
                    destination: .transition
                )
                PortalTile(
                    title: language.text(.mainPhase),
                    subtitle: language.text(.eliteProgram),
                    icon: "bolt.fill",
                    color: APEXColor.violet,
                    destination: .mainPhase
                )
                if session.data.programs.contains(where: { $0.slug == "custom" }) {
                    PortalTile(
                        title: language.text(.customWorkouts),
                        subtitle: language.text(.customWorkoutsSubtitle),
                        icon: "square.and.pencil",
                        color: APEXColor.violet,
                        destination: .customWorkouts
                    )
                }
                PortalTile(
                    title: language.text(.orbit),
                    subtitle: language.text(.runIntelligence),
                    icon: "figure.run",
                    color: APEXColor.cyan,
                    destination: .orbit
                )
                ProfilePortalTile()

                HStack {
                    PortalLanguagePicker()
                    Spacer()
                    if session.isRefreshing {
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
        .sheet(isPresented: $showNudges) {
            NudgeSheet(nudges: nudges) { showNudges = false }
                .apexTransientSheet(.fraction(0.62))
        }
        .task { await session.refreshNudges() }
        .toolbar(.hidden, for: .navigationBar)
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
