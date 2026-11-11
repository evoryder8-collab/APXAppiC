import Combine
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
                // Midnight with the app open: a screen left on today moves to the new day.
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                    session.followTodayAcrossMidnight()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.onAppBecameActive() }
            } else {
                if phase == .background { session.onAppEnteredBackground() }
                OrbitLocationManager.shared.persistForAppTransition()
            }
        }
    }
}
