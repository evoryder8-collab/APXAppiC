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
            HStack {
                Spacer()
                LogoutDockButton(showConfirmation: $showLogout)
            }
                .padding(.horizontal, 20)
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

/// The compact sign-out action still needs a little bottom breathing room,
/// but no longer covers a full row of otherwise tappable content.
enum APEXDock {
    static let height: CGFloat = 52
    static let clearance: CGFloat = 62
}

extension View {
    /// Bottom room for the compact sign-out action, on top of screen padding.
    func dockClearance() -> some View { padding(.bottom, APEXDock.clearance) }
}

private struct LogoutDockButton: View {
    @Binding var showConfirmation: Bool

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 18, weight: .bold))
                .frame(width: APEXDock.height, height: APEXDock.height)
                .foregroundStyle(APEXColor.ink)
                .background(.ultraThinMaterial.opacity(0.97), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.95)))
                .shadow(color: .black.opacity(0.09), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LanguageState.shared.text(.logoutWarning))
        .accessibilityIdentifier("portal-logout")
    }
}
