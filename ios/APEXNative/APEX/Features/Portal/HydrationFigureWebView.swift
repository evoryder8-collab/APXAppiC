import SwiftUI
import WebKit

/// Renders the supplied male/female hydration silhouettes as a lightweight,
/// self-contained SVG. The web view exists only while the quick-add sheet is
/// visible, keeping the main dashboard entirely native.
struct HydrationFigureWebView: UIViewRepresentable {
    let progress: Double
    let sex: String

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
        guard let url = Bundle.main.url(forResource: assetName, withExtension: "html") else { return }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func updateLevel(in view: WKWebView) {
        view.evaluateJavaScript("window.setHydrationLevel(\(normalizedProgress))")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var assetName = ""
        var loaded = false
        var pendingProgress = 0.0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            loaded = true
            webView.evaluateJavaScript("window.setHydrationLevel(\(max(0, min(1, pendingProgress))))")
        }
    }
}
