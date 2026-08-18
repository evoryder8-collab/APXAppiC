import SwiftUI
import WebKit

/*
 * Myomap: the anatomical figure for a session's muscle engagement.
 *
 * The asset is Constantin's own three.js widget, the same one the web app
 * embeds, so both platforms show the identical figure rather than two
 * lookalikes that drift. It is bundled whole: three.js, the FBX and the
 * texture atlases all resolve from the app bundle, with no CDN and no
 * network, so it works on a plane and cannot break when a URL moves.
 *
 * Group ids are the widget's own and are stable; only this mapping needs
 * revisiting when the exercise library changes.
 */
struct MuscleMapView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dayType: String
    /// Optional exercise names, used to refine the mapping for a custom day.
    var exerciseNames: [String] = []
    var xray: Bool = true

    // MARK: - Session type to muscle groups

    static func groups(for dayType: String, exercises: [String] = []) -> (primary: [String], secondary: [String]) {
        switch dayType {
        case "legs_a":
            /* Heavy base: split squat, RDL, leg curl, calf raise */
            return (["glutes", "hamstrings", "quads", "calves"],
                    ["lowerback", "adductors", "abductors"])
        case "legs_b":
            /* Lunge day: quad bias with single-leg hinging */
            return (["quads", "glutes", "hamstrings", "calves"],
                    ["adductors", "abductors", "hipflexors"])
        case "push":
            return (["chest", "shoulders", "triceps"],
                    ["abs", "obliques", "upperback"])
        case "pull":
            return (["lats", "upperback", "biceps", "forearms"],
                    ["traps", "lowerback", "shoulders"])
        case "upper":
            return (["chest", "shoulders", "triceps", "lats", "upperback", "biceps"],
                    ["traps", "forearms", "abs"])
        case "mobility":
            /* Recovery and posture: hips and thoracic spine, gently */
            return (["hipflexors", "lowerback", "upperback"],
                    ["adductors", "hamstrings", "glutes", "neck"])
        case "fix":
            return (["upperback", "traps", "lowerback"],
                    ["shoulders", "neck", "abs"])
        case "t25":
            /* Conditioning: whole body, core-led */
            return (["abs", "obliques", "quads", "glutes", "calves"],
                    ["chest", "shoulders", "hamstrings", "lowerback"])
        default:
            return derived(from: exercises)
        }
    }

    /* A custom day has no fixed shape, so read the movements themselves. */
    private static func derived(from exercises: [String]) -> (primary: [String], secondary: [String]) {
        var hits: Set<String> = []
        for raw in exercises {
            let name = raw.lowercased()
            func match(_ needles: [String], _ groups: [String]) {
                if needles.contains(where: { name.contains($0) }) { hits.formUnion(groups) }
            }
            match(["push-up", "pushup", "press", "dip", "fly"], ["chest", "shoulders", "triceps"])
            match(["pull-up", "pullup", "row", "pulldown", "chin"], ["lats", "upperback", "biceps"])
            match(["curl"], ["biceps", "forearms"])
            match(["extension", "pushdown", "skull"], ["triceps"])
            match(["squat", "lunge", "leg press", "step-up", "extension"], ["quads", "glutes"])
            match(["deadlift", "rdl", "hinge", "leg curl", "good morning"], ["hamstrings", "glutes", "lowerback"])
            match(["calf", "raise"], ["calves"])
            match(["plank", "crunch", "ab ", "hollow", "bird-dog"], ["abs", "obliques"])
            match(["face pull", "pull-apart", "y-raise", "scapular"], ["upperback", "traps"])
            match(["hold", "carry", "suitcase", "gimbal"], ["obliques", "forearms", "lowerback"])
            match(["stretch", "mobility", "couch", "90/90"], ["hipflexors", "adductors"])
        }
        if hits.isEmpty { return (["abs", "quads", "chest"], ["glutes", "upperback"]) }
        return (Array(hits).sorted(), [])
    }

    // MARK: - Web view

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        /* The figure is drag-to-orbit, so it must not fight the page scroll:
           the widget only claims a touch once it is clearly a rotation. */
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let key = renderKey
        guard context.coordinator.renderKey != key else { return }
        context.coordinator.renderKey = key
        if context.coordinator.loaded {
            apply(to: view)
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        /* Stop the render loop the moment the view goes away. */
        view.evaluateJavaScript("window.MuscleMap && MuscleMap.spin(false)")
        view.stopLoading()
    }

    private var renderKey: String {
        let sets = Self.groups(for: dayType, exercises: exerciseNames)
        return "\(sets.primary.joined(separator: ","))|\(sets.secondary.joined(separator: ","))|\(xray)|\(reduceMotion)"
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        /* Xcode flattens bundled resources, so the widget and everything it
           imports sit side by side at the bundle root and every import is a
           sibling path. */
        guard let url = Bundle.main.url(forResource: "musclemap", withExtension: "html") else { return }
        coordinator.renderKey = renderKey
        coordinator.pendingScript = script
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private var script: String {
        let sets = Self.groups(for: dayType, exercises: exerciseNames)
        let primary = sets.primary.map { "'\($0)'" }.joined(separator: ",")
        let secondary = sets.secondary.map { "'\($0)'" }.joined(separator: ",")
        return """
        (function(){
          if (!window.MuscleMap) { return 'pending'; }
          MuscleMap.set([\(primary)], [\(secondary)]);
          MuscleMap.xray(\(xray ? "true" : "false"));
          MuscleMap.spin(\(reduceMotion ? "false" : "true"));
          return 'ok';
        })()
        """
    }

    private func apply(to view: WKWebView) {
        view.evaluateJavaScript(script)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var renderKey: String?
        var loaded = false
        var pendingScript: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            loaded = true
            guard let pendingScript else { return }
            /* The widget parses a 5 MB FBX before its API exists, so retry
               briefly rather than dropping the first highlight on the floor. */
            var attempts = 0
            func push() {
                webView.evaluateJavaScript(pendingScript) { result, _ in
                    let ready = (result as? String) == "ok"
                    if ready || attempts > 40 { return }
                    attempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { push() }
                }
            }
            push()
        }
    }
}
