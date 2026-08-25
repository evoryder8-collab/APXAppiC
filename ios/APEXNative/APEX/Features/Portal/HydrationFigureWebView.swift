import SwiftUI
import WebKit

struct HydrationFigureWebStop: Codable, Equatable, Sendable {
    let color: String
    let offset: Double
}

enum HydrationFigureWebPalette {
    private static let bodyFillHeight = 712.0

    static func stops(for bands: [HydrationCompositionBand]) -> [HydrationFigureWebStop] {
        HydrationCompositionLayout.stops(for: bands).map { stop in
            HydrationFigureWebStop(color: hex(stop.paletteToken), offset: stop.location)
        }
    }

    static func fillHeight(progress rawProgress: Double) -> Double {
        let progress = min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
        return progress * bodyFillHeight
    }

    static func encoded(_ stops: [HydrationFigureWebStop]) -> String {
        (try? JSONEncoder().encode(stops))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private static func hex(_ token: String) -> String {
        switch token {
        case "espresso": "#8C4A21"
        case "tea": "#3DAE57"
        case "citrus": "#FF850D"
        case "cocoa": "#A8643D"
        case "violet": "#8C57FA"
        case "food": "#1FA88F"
        case "external": "#E63D8C"
        case "legacy": "#5285B8"
        case "blue": "#1C64FA"
        default: "#14CCE8"
        }
    }
}

/// Renders the supplied male/female hydration silhouettes as a lightweight,
/// self-contained SVG. The web view exists only while the quick-add sheet is
/// visible, keeping the main dashboard entirely native.
struct HydrationFigureWebView: UIViewRepresentable {
    let progress: Double
    let sex: String
    let composition: [HydrationCompositionBand]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        loadAsset(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let asset = assetName
        if context.coordinator.assetName != asset {
            loadAsset(in: view, coordinator: context.coordinator)
        }
        context.coordinator.pendingProgress = normalizedProgress
        context.coordinator.pendingStops = HydrationFigureWebPalette.stops(for: composition)
        if context.coordinator.loaded {
            updateLevel(in: view)
        }
    }

    private var normalizedProgress: Double { max(0, min(1, progress)) }
    private var assetName: String { sex.lowercased().contains("female") ? "hydration-female" : "hydration-male" }

    private func loadAsset(in view: WKWebView, coordinator: Coordinator) {
        coordinator.assetName = assetName
        coordinator.loaded = false
        coordinator.pendingProgress = normalizedProgress
        coordinator.pendingStops = HydrationFigureWebPalette.stops(for: composition)
        guard let url = Bundle.main.url(forResource: assetName, withExtension: "html") else { return }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func updateLevel(in view: WKWebView) {
        let stops = HydrationFigureWebPalette.encoded(HydrationFigureWebPalette.stops(for: composition))
        let fillHeight = HydrationFigureWebPalette.fillHeight(progress: normalizedProgress)
        view.evaluateJavaScript("window.setHydrationState(\(normalizedProgress),\(stops),\(fillHeight))")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var assetName = ""
        var loaded = false
        var pendingProgress = 0.0
        var pendingStops: [HydrationFigureWebStop] = []

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            loaded = true
            let stops = HydrationFigureWebPalette.encoded(pendingStops)
            let fillHeight = HydrationFigureWebPalette.fillHeight(progress: pendingProgress)
            webView.evaluateJavaScript(
                "window.setHydrationState(\(max(0, min(1, pendingProgress))),\(stops),\(fillHeight))"
            )
        }
    }
}
