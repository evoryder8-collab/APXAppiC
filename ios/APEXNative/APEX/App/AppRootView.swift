import SwiftUI

struct AppRootView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var entitlements = EntitlementStore.shared

    var body: some View {
        ZStack {
            APEXBackground()

            switch session.route {
            case .launching:
                APEXLaunchView()
                    .transition(.opacity)
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
            case .emailAuth(let signUp):
                EmailAuthView(signUp: signUp)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .induction:
                accessProtected { InductionView() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .consent:
                accessProtected { ConsentView() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .persona:
                PersonaSelectorView()
                    .transition(.opacity.combined(with: .scale(scale: 1.025)))
            case .login(let persona):
                LoginView(persona: persona)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .portal:
                accessProtected { PortalShellView() }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: Binding(
            get: { session.previewAccessRecovery },
            set: { session.previewAccessRecovery = $0 }
        )) {
            AccessRecoveryView { session.previewAccessRecovery = false }
        }
        .overlay {
            if let persona = session.greetingPersona {
                PersonaGreetingOverlay(persona: persona) {
                    withAnimation(.smooth(duration: 0.5)) { session.greetingPersona = nil }
                }
                .transition(.opacity)
            }
        }
        /* Access is resolved independently of profile/onboarding. A pending or
           locked account never flashes private content underneath recovery. */
        .sheet(isPresented: Binding(
            get: {
                accessGateEnabled
                    && protectedRoute
                    && entitlements.resolution != .resolving
                    && !entitlements.isUnlocked
            },
            set: { _ in }
        )) {
            AccessRecoveryView()
                .interactiveDismissDisabled()
        }
        .animation(.snappy(duration: 0.42, extraBounce: 0.04), value: session.route)
        .alert("APEX", isPresented: Binding(
            get: { session.alertMessage != nil },
            set: { if !$0 { session.alertMessage = nil } }
        )) {
            Button(language.text("OK"), role: .cancel) { session.alertMessage = nil }
        } message: {
            Text(language.text(session.alertMessage ?? ""))
        }
    }

    private var accessGateEnabled: Bool {
        session.isAuthenticated && !APEXRuntimeEnvironment.usesLocalUITestFixture()
    }

    private var protectedRoute: Bool {
        switch session.route {
        case .induction, .consent, .portal: return true
        default: return false
        }
    }

    @ViewBuilder
    private func accessProtected<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if !accessGateEnabled || entitlements.isUnlocked {
            content()
        } else if entitlements.resolution == .resolving {
            APEXLaunchView()
        } else {
            Color.clear
        }
    }
}

private struct APEXLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 22) {
            APEXMark(size: 74)
                .scaleEffect(breathing ? 1.04 : 0.96)
                .shadow(color: APEXColor.violet.opacity(0.25), radius: 30)
            Text("APEX")  // brand name, never translated
                .font(APEXFont.display(34))
                .tracking(9)
                .foregroundStyle(APEXColor.ink)
            ProgressView()
                .tint(APEXColor.amber)
        }
        .onAppear {
            /* Repeating without end is the shape of animation that Reduce
               Motion exists for: there is no moment when it settles, so it
               cannot be waited out. Left still when the setting is on. */
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
