import SwiftUI

struct PortalShellView: View {
    @Environment(AppSession.self) private var session
    @State private var showLogout = false
    @State private var showBaselineCalibration = false

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
        .sheet(isPresented: $showBaselineCalibration) {
            BaselineCalibrationSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: PortalDestination) -> some View {
        switch destination {
        case .coachWorkspace:
            if session.coachContext.capabilities.coachWorkspace { CoachWorkspaceView() }
            else { CoachFeatureLockedView() }
        case .coachPlan: CoachPlanView()
        case .coachWorkouts:
            if session.coachClientPolicy.canFollowCoachPlan { TrainingProgramView(slug: "coach", accent: APEXColor.violet) }
            else { CoachFeatureLockedView() }
        case .nutrition:
            if session.coachClientPolicy.canUseNutrition { NutritionView() }
            else { CoachFeatureLockedView() }
        case .transition:
            if session.coachClientPolicy.canRebuildFitnessPlan { TrainingProgramView(slug: "transition", accent: APEXColor.teal) }
            else { CoachFeatureLockedView() }
        case .mainPhase:
            if session.coachClientPolicy.canRebuildFitnessPlan { TrainingProgramView(slug: "main", accent: APEXColor.violet) }
            else { CoachFeatureLockedView() }
        /* Web parity: custom workouts are the same section with its own programme. */
        case .customWorkouts:
            if session.coachClientPolicy.canCreateCustomWorkouts { TrainingProgramView(slug: "custom", accent: APEXColor.violet) }
            else { CoachFeatureLockedView() }
        case .orbit:
            if session.coachClientPolicy.canUseOrbit { OrbitHomeView() }
            else { CoachFeatureLockedView() }
        case .avatar:
            if session.coachClientPolicy.canUseAvatar {
                AvatarView { showBaselineCalibration = true }
            } else { CoachFeatureLockedView() }
        case .visualProgress:
            if session.coachClientPolicy.canViewVisualProgress { VisualProgressView() }
            else { CoachFeatureLockedView() }
        case .settings: SettingsView()
        }
    }
}

private struct CoachFeatureLockedView: View {
    @State private var language = LanguageState.shared
    var body: some View {
        ContentUnavailableView(
            language.text("Managed by your coach"),
            systemImage: "person.crop.circle.badge.checkmark",
            description: Text(language.text("Your sponsored account keeps nutrition, Avatar and the coach plan focused. An individual subscription restores personal builders and Orbit."))
        )
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
