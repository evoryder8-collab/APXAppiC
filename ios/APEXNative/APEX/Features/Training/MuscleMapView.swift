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
/*
 * Warm pool for the figure's web views.
 *
 * Parsing the 5 MB FBX and welding 367 meshes costs several seconds, and it
 * is the page load that pays it, not the fetch. A fresh web view per visit
 * meant that price was charged again every time the screen was opened.
 * Finished views are parked here with their scene intact, so a second visit
 * only re-applies the highlight, which is a single call.
 */
@MainActor
enum MuscleMapWarmPool {
    private struct Parked {
        let webView: WKWebView
        let isLoaded: Bool
    }

    /* Two, because a day sheet can sit above the phase screen. */
    private static let capacity = 2
    private static var parked: [Parked] = []

    static func take() -> (view: WKWebView, isLoaded: Bool)? {
        guard !parked.isEmpty else { return nil }
        let next = parked.removeFirst()
        next.webView.removeFromSuperview()
        return (next.webView, next.isLoaded)
    }

    static func give(_ webView: WKWebView, isLoaded: Bool) {
        guard parked.count < capacity else { return }
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        parked.append(Parked(webView: webView, isLoaded: isLoaded))
    }
}

struct MuscleMapView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dayType: String
    /// Optional exercise names, used to refine the mapping for a custom day.
    var exerciseNames: [String] = []
    var xray: Bool = true
    /* The page paints its own pale background, which becomes a hard rectangle
       on any screen that is not also pale. Overriding the variable lets the
       figure sit directly on whatever is behind it. */
    var transparentBackground = false
    /// Lets the surrounding card turn the figure and flip its modes.
    var controller: MuscleMapController? = nil

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
        case "welcome":
            /* Nothing has been trained yet, so nothing lights up. The figure is
               there to be looked at, not read. */
            return ([], [])
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
        /* Reuse a parked view when one is free: its scene is already built,
           so the highlight applies immediately instead of after a reload. */
        /* The pool parks views that already loaded the opaque page, so a
           transparent screen must not borrow one: it would inherit the pale
           rectangle this flag exists to avoid. */
        if !transparentBackground, let warm = MuscleMapWarmPool.take() {
            warm.view.navigationDelegate = context.coordinator
            warm.view.isUserInteractionEnabled = false
            context.coordinator.webView = warm.view
            controller?.attach(warm.view)
            context.coordinator.renderKey = renderKey
            context.coordinator.pendingScript = script
            if warm.isLoaded {
                context.coordinator.loaded = true
                apply(to: warm.view)
            }
            return warm.view
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        /* Served over a real scheme so the module graph and the FBX fetch are
           not blocked by the opaque origin a file:// page gets. */
        configuration.setURLSchemeHandler(context.coordinator.assetHandler,
                                          forURLScheme: MuscleMapAssetHandler.scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        /* The web view renders and nothing more. WebKit consumes any touch it
           is offered, which trapped the scroll of the card around it, so the
           figure is turned from Swift instead. */
        view.isUserInteractionEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        controller?.attach(view)
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
        /* Park it with the scene intact rather than paying the parse again on
           the next visit. The turntable stops so a hidden view costs nothing. */
        view.evaluateJavaScript("window.MuscleMap && MuscleMap.spin(false)")
        guard !coordinator.isTransparent else { return }
        MuscleMapWarmPool.give(view, isLoaded: coordinator.loaded)
    }

    private var renderKey: String {
        let sets = Self.groups(for: dayType, exercises: exerciseNames)
        return "\(sets.primary.joined(separator: ","))|\(sets.secondary.joined(separator: ","))|\(xray)|\(reduceMotion)"
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        /* Xcode flattens bundled resources, so the widget and everything it
           imports sit side by side at the bundle root and every import is a
           sibling path, resolved by the asset handler. */
        coordinator.renderKey = renderKey
        coordinator.pendingScript = script
        coordinator.isTransparent = transparentBackground
        view.load(URLRequest(
            url: transparentBackground
                ? MuscleMapAssetHandler.transparentEntryURL
                : MuscleMapAssetHandler.entryURL
        ))
    }

    private var script: String {
        let sets = Self.groups(for: dayType, exercises: exerciseNames)
        let primary = sets.primary.map { "'\($0)'" }.joined(separator: ",")
        let secondary = sets.secondary.map { "'\($0)'" }.joined(separator: ",")
        /* Set on the document rather than in the file, so the shared page stays
           one page and only the screens that need it go transparent. */
        let background = transparentBackground
            ? "document.documentElement.style.setProperty('--mm-bg', 'transparent');"
              + "document.body.style.background = 'transparent';"
            : ""
        return """
        (function(){
          \(background)
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
        let assetHandler = MuscleMapAssetHandler()
        weak var webView: WKWebView?
        var renderKey: String?
        var loaded = false
        var pendingScript: String?
        /* Only opaque views may be parked: the pool has no way to tell the two
           pages apart afterwards, and handing a transparent one to the training
           screen would put the figure on nothing. */
        var isTransparent = false

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
