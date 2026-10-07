import AVFoundation
import SwiftUI
import WebKit

/// The pilot page, unmodified, running inside the app with a real Bluetooth
/// radio underneath it.
///
/// The page is the product of a lot of careful work on wording and flow, and
/// rewriting it in SwiftUI would have meant reproducing all of that and then
/// maintaining two of them. So it is bundled as it ships on the web, and the one
/// thing iOS does not give it, Bluetooth, is supplied by Resources/bridge.js and
/// WrapCentral. The same file can keep serving impktband.com/test.
struct PilotPage: UIViewRepresentable {

    func makeCoordinator() -> Bridge { Bridge() }

    /// The page is served under a scheme of our own rather than from file://.
    ///
    /// Not a preference. On a file origin WKWebView refuses fetch as a cross
    /// origin request, and the gate on the first screen fetches ../pilots.json to
    /// check an activation code, so the page cannot get past its own front door.
    /// localStorage on a file origin is unreliable too, and Supabase calls later
    /// would hit the same wall. A custom scheme gives the page a real origin, and
    /// every relative path it already uses resolves inside the bundle.
    static let scheme = "impkt"

    /// The drill is guided by sound and by nothing else, so the ringer switch
    /// must not be able to turn it off.
    ///
    /// A WKWebView's audio goes out on this process's audio session, and the
    /// default category is `.ambient`: it obeys the silent switch and it ducks
    /// under anything else that is playing. A pilot who left the switch on would
    /// get a drill with no beat and no reason for it, which reads as broken
    /// firmware rather than as a switch on the side of the phone. `.playback` is
    /// the category for audio that is the point of the app.
    ///
    /// `mixWithOthers`, because a boxer training to their own music should keep
    /// it. The cues sit on top; they are short, and they are what is loud.
    private func openTheSpeaker() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Nothing to do about it and nothing to tell the pilot: the drill
            // still runs, and on a phone with the switch off it still sounds.
            NSLog("IMPKT: audio session refused: \(error)")
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        openTheSpeaker()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.setURLSchemeHandler(BundleFiles(), forURLScheme: PilotPage.scheme)

        // At document start, so the page never runs a line of its own script in a
        // window without navigator.bluetooth. Injected from the bundle rather than
        // pasted into a Swift string literal, so it stays lintable JavaScript.
        if let js = Bundle.main.url(forResource: "bridge", withExtension: "js"),
           let src = try? String(contentsOf: js, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController.add(context.coordinator, name: "impkt")

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = false
        // The canvas, on the view and on its scroller, for the two moments what is on
        // screen is not the page's own background: before the first paint, and in the
        // gutter that opens when a screen is dragged past its end. Both were white,
        // which is the same white that made the bands above and below the page read as
        // borders. Same hex as `body` in the page, which is the point.
        web.backgroundColor = UIColor(Color.pageCanvas)
        web.scrollView.backgroundColor = UIColor(Color.pageCanvas)
        // Bounce is on, which is the default and now the right default: the page
        // scrolls on a phone, and a scrolling view that stops dead at its ends is
        // the one part of this that would not feel like iOS. It was off while the
        // page was locked to the window, where rubber-banding a page that cannot
        // move only ever looked like something had broken.
        web.scrollView.bounces = true
        // Which is exactly why this is off. WKWebView bounces vertically whether
        // or not there is anything to scroll, and the first screen of the page is
        // the activation code: six short things that fit any phone with room to
        // spare. Dragging it made the whole screen slide and spring back, which
        // is the gesture that says "there is more below" on a screen where there
        // is nothing below. Now the bounce belongs to the screens that scroll, the
        // briefing and the drill list, and the ones that fit hold still.
        web.scrollView.alwaysBounceVertical = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        context.coordinator.attach(web)

        if Bundle.main.url(forResource: "index", withExtension: "html",
                           subdirectory: "Web") != nil {
            // Web/index.html, so ../css, ../fonts and ../pilots.json land on the
            // bundle root exactly as they land on the site root.
            web.load(URLRequest(url: URL(string: "\(PilotPage.scheme)://app/Web/index.html")!))
        } else {
            web.loadHTMLString(
                "<h2 style='font:600 17px -apple-system;padding:24px'>The pilot page is "
                + "not in the app bundle. Run sync-web.sh and build again.</h2>", baseURL: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// Serves the bundled copy of the site over the app's own URL scheme.
///
/// Read only, and rooted: a request is answered from inside the bundle's resource
/// directory or not at all. The check is on the resolved path, not on the text of
/// the request, because "/Web/../../.." is a perfectly ordinary looking URL and
/// standardising first is what makes the comparison mean anything.
final class BundleFiles: NSObject, WKURLSchemeHandler {

    private static let types = [
        "html": "text/html; charset=utf-8",
        "js":   "text/javascript; charset=utf-8",
        "css":  "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "svg":  "image/svg+xml",
        "png":  "image/png",
        "jpg":  "image/jpeg",
        "jpeg": "image/jpeg",
        "webp": "image/webp",
        "ico":  "image/x-icon",
        "woff2": "font/woff2",
        "zip":  "application/zip"
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root = Bundle.main.resourceURL?.standardizedFileURL,
              let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }

        let wanted = root.appendingPathComponent(url.path).standardizedFileURL
        guard wanted.path.hasPrefix(root.path),
              let data = try? Data(contentsOf: wanted) else {
            // 404 rather than an error: the page asks for a favicon that is not
            // bundled, and a failed task logs a warning on every load.
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404,
                                            httpVersion: nil, headerFields: nil)!)
            task.didFinish()
            return
        }

        let type = BundleFiles.types[wanted.pathExtension.lowercased()]
            ?? "application/octet-stream"
        let head = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": type,
                                                  "Content-Length": String(data.count),
                                                  "Cache-Control": "no-store"])!
        task.didReceive(head)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Carries messages both ways: the page's calls down to CoreBluetooth, and
/// advertisements, notifications and disconnects back up into the page.
final class Bridge: NSObject, WKScriptMessageHandler {

    private weak var web: WKWebView?

    func attach(_ web: WKWebView) {
        self.web = web
        // Also handed to PageStorage, which is how the Devices and Profile tabs read
        // what the page has written down without keeping a second copy of it.
        PageStorage.attach(web)
        WrapCentral.shared.emit = { [weak self] event, payload in
            self?.call("window.__impkt.\(event)", payload)
        }
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

        // Not Bluetooth and not a question: the page asking the app to show one of its own tabs,
        // which is how "Connect a wrap first" on the drills reaches the Devices tab. It has no id
        // because nothing waits for an answer, and it is handled before the id check for that reason.
        if op == "openTab" {
            NotificationCenter.default.post(name: .impktOpenTab, object: nil,
                                            userInfo: ["tab": (args["tab"] as? String) ?? ""])
            return
        }

        guard let id = body["id"] as? Int else { return }

        WrapCentral.shared.handle(op: op, args: args) { [weak self] ok, payload in
            guard let self = self else { return }
            let json = Bridge.json(payload)
            self.eval("window.__impkt.reply(\(id), \(ok), \(json))")
        }
    }

    private func call(_ fn: String, _ payload: [String: Any]) {
        eval("\(fn)(\(Bridge.json(payload)))")
    }

    /// Calls into the page. evaluateJavaScript is the only route native code has
    /// into a WKWebView, so this is not a choice between it and something safer.
    ///
    /// What matters is that everything interpolated into the string comes from
    /// JSONSerialization below, never from string building. That is load bearing:
    /// a wrap's advertised name is remote input, up to 29 bytes chosen by whoever
    /// holds the board, and pasting one into a JavaScript expression by hand would
    /// let a name containing a quote run code inside the page. JSON escaping is
    /// what makes a hostile name just a string with a quote in it.
    private func eval(_ js: String) {
        // Always on the main queue: WKWebView is not thread safe, and the
        // CoreBluetooth callbacks that get here already run on main, so this is
        // belt and braces rather than a hop.
        if Thread.isMainThread { web?.evaluateJavaScript(js, completionHandler: nil) }
        else { DispatchQueue.main.async { self.web?.evaluateJavaScript(js, completionHandler: nil) } }
    }

    /// A payload that will not serialise is a programming error here, not a
    /// runtime condition, so it becomes an empty object and says so in the log
    /// rather than taking the page down with a syntax error inside evaluate.
    static func json(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            NSLog("IMPKT bridge: payload would not serialise: \(payload)")
            return "{}"
        }
        return text
    }
}
