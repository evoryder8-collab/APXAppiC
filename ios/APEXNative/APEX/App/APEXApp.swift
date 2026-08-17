import SwiftUI

@main
struct APEXApp: App {
    @State private var session = AppSession()
    @State private var language = LanguageState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(\.locale, language.language.locale)
                .preferredColorScheme(.light)
                .task { await session.bootstrap() }
                .onOpenURL { url in
                    Task { await session.handleAuthCallback(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.onAppBecameActive() }
            } else {
                OrbitLocationManager.shared.persistForAppTransition()
            }
        }
    }
}
