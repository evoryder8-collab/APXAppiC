import SwiftUI

@main
struct APEXWaterWatchApp: App {
    @StateObject private var hydration = WatchHydrationStore()

    var body: some Scene {
        WindowGroup {
            WatchHydrationView()
                .environmentObject(hydration)
        }
    }
}
