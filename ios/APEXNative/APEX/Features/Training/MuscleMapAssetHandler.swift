import Foundation
import WebKit

/*
 * Serves the bundled Myomap widget over a real URL scheme.
 *
 * Loading it from file:// does not work: WKWebView gives file pages an opaque
 * origin, so the ES module graph is refused and, more visibly, the FBX fetch
 * is blocked outright. three.js reports that as a load stuck at 0% with no
 * error, which is exactly what it did. A scheme handler gives the page a
 * normal origin, so module imports and XHR behave like they do on the web.
 *
 * Only files that ship inside the app bundle are served, and only by leaf
 * name, so a crafted path cannot walk out of the bundle.
 */
final class MuscleMapAssetHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "apexasset"
    /* labels=0: the surrounding card already names the session, and the
   widget's own tags overlapped that header. */
    static let entryURL = URL(string: "\(scheme)://musclemap/musclemap.html?labels=0")!

    private static let mimeTypes: [String: String] = [
        "html": "text/html",
        "js": "text/javascript",
        "mjs": "text/javascript",
        "css": "text/css",
        "json": "application/json",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "fbx": "application/octet-stream",
        "bin": "application/octet-stream",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        /* The bundle is flat, so resolve by leaf name and refuse anything
           that is not actually in it. */
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        guard !base.isEmpty,
              let fileURL = Bundle.main.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mime = Self.mimeTypes[ext.lowercased()] ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": String(data.count),
                /* Same-origin by construction, but three.js requests the FBX
                   with a range-capable loader; be explicit rather than let the
                   default policy surprise us. */
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=31536000",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        /* Nothing to cancel: every response is delivered synchronously. */
    }
}
