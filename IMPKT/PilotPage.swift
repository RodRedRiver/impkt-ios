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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

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
        web.scrollView.bounces = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        context.coordinator.attach(web)

        if let index = Bundle.main.url(forResource: "index", withExtension: "html",
                                       subdirectory: "Web") {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else {
            web.loadHTMLString(
                "<h2 style='font:600 17px -apple-system;padding:24px'>The pilot page is "
                + "not in the app bundle. Run sync-web.sh and build again.</h2>", baseURL: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// Carries messages both ways: the page's calls down to CoreBluetooth, and
/// advertisements, notifications and disconnects back up into the page.
final class Bridge: NSObject, WKScriptMessageHandler {

    private weak var web: WKWebView?

    func attach(_ web: WKWebView) {
        self.web = web
        WrapCentral.shared.emit = { [weak self] event, payload in
            self?.call("window.__impkt.\(event)", payload)
        }
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let op = body["op"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

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
