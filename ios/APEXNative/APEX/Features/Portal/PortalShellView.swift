import SwiftUI

struct PortalShellView: View {
    @Environment(AppSession.self) private var session
    @State private var showLogout = false

    var body: some View {
        @Bindable var session = session

        NavigationStack(path: $session.navigationPath) {
            Group {
                if session.interfaceMode == .simple {
                    SimpleHomeView()
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                } else {
                    PortalHomeView()
                        .transition(.opacity.combined(with: .scale(scale: 1.01)))
                }
            }
                .animation(.snappy(duration: 0.32), value: session.interfaceMode)
                .navigationDestination(for: PortalDestination.self) { destination in
                    destinationView(destination)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ProfileDockButton(showConfirmation: $showLogout)
                .padding(.horizontal, 18)
                .padding(.bottom, 5)
        }
        .confirmationDialog(
            LanguageState.shared.text(.logoutWarning),
            isPresented: $showLogout,
            titleVisibility: .visible
        ) {
            Button(LanguageState.shared.text(.yesLogout), role: .destructive) {
                Task { await session.signOut() }
            }
            Button(LanguageState.shared.text(.cancel), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: PortalDestination) -> some View {
        switch destination {
        case .nutrition: NutritionView()
        case .transition: TrainingProgramView(slug: "transition", accent: APEXColor.teal)
        case .mainPhase: TrainingProgramView(slug: "main", accent: APEXColor.violet)
        /* Web parity: custom workouts are the same section with its own programme. */
        case .customWorkouts: TrainingProgramView(slug: "custom", accent: APEXColor.violet)
        case .orbit: OrbitHomeView()
        case .avatar: AvatarView()
        case .visualProgress: VisualProgressView()
        case .settings: SettingsView()
        }
    }
}

private struct ProfileDockButton: View {
    @Environment(AppSession.self) private var session
    @Binding var showConfirmation: Bool
    @State private var language = LanguageState.shared

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Persona.allCases) { persona in
                PortraitImage(name: persona.portraitName)
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .opacity(session.profile?.persona == persona ? 1 : 0.72)
            }
            Text(language.text(.profiles).uppercased())
                .font(APEXFont.mono(11))
                .tracking(1.5)
                .padding(.leading, 14)
            Spacer(minLength: 10)
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(APEXColor.ink)
        .padding(.horizontal, 15)
        .frame(height: 58)
        .background(.ultraThinMaterial.opacity(0.97), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.95)))
        .shadow(color: .black.opacity(0.09), radius: 18, y: 8)
        .contentShape(Capsule())
        .onTapGesture { showConfirmation = true }
    }
}
