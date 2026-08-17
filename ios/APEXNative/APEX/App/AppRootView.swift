import SwiftUI

struct AppRootView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    var body: some View {
        ZStack {
            APEXBackground()

            switch session.route {
            case .launching:
                APEXLaunchView()
                    .transition(.opacity)
            case .persona:
                PersonaSelectorView()
                    .transition(.opacity.combined(with: .scale(scale: 1.025)))
            case .login(let persona):
                LoginView(persona: persona)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .portal:
                PortalShellView()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.42, extraBounce: 0.04), value: session.route)
        .alert("APEX", isPresented: Binding(
            get: { session.alertMessage != nil },
            set: { if !$0 { session.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { session.alertMessage = nil }
        } message: {
            Text(language.text(session.alertMessage ?? ""))
        }
    }
}

private struct APEXLaunchView: View {
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 22) {
            APEXMark(size: 74)
                .scaleEffect(breathing ? 1.04 : 0.96)
                .shadow(color: APEXColor.violet.opacity(0.25), radius: 30)
            Text("APEX")
                .font(APEXFont.display(34))
                .tracking(9)
                .foregroundStyle(APEXColor.ink)
            ProgressView()
                .tint(APEXColor.amber)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
