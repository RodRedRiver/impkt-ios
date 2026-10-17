import Combine
import SwiftUI
import WebKit

/// The Beta tab: the next IMPKT app, the one being built in Lovable, running on the
/// real wraps before it replaces anything.
///
/// It is a web app bundled as files, like the Test tab's page, served by the same
/// BundleFiles handler at impkt://beta/. Its source is in beta/ and `sync-beta.sh` builds
/// it into Resources/Beta.
///
/// What it does not get is a Bluetooth stack of its own, and that is deliberate. A wrap
/// accepts one connection and the Test tab's page holds it, so this page is handed the
/// punches the app already reads off that link, the way the Leaderboard is, and when it
/// wants a wrap connected it asks the page to connect one, the way Devices does. Nothing
/// here competes for the radio, and a drill on the Test tab and a session here see the
/// same punches.
struct BetaPage: UIViewRepresentable {

    /// The host BundleFiles serves Resources/Beta under. A host of its own rather than a
    /// path under impkt://app: see vite.app.config.ts in beta/ for what a path did.
    static let host = "beta"

    func makeCoordinator() -> BetaBridge { BetaBridge() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.setURLSchemeHandler(BundleFiles(), forURLScheme: PilotPage.scheme)
        config.userContentController.add(context.coordinator, name: "impktBeta")

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = false
        // The beta app's own dark ground, so nothing white flashes before it paints.
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x0B / 255, green: 0x0C / 255, blue: 0x10 / 255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.alwaysBounceVertical = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        context.coordinator.attach(web)

        if Bundle.main.url(forResource: "index", withExtension: "html",
                           subdirectory: "Beta") != nil {
            // The root, not /index.html, which the app's router would read as a screen
            // called index.html. BundleFiles answers the root, and every other screen, with
            // index.html.
            web.load(URLRequest(url: URL(string: "\(PilotPage.scheme)://\(BetaPage.host)/")!))
        } else {
            web.loadHTMLString(
                "<h2 style='font:600 17px -apple-system;padding:24px'>The beta app is "
                + "not in the app bundle. Run sync-beta.sh and build again.</h2>", baseURL: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// The Beta page's line to the app.
///
/// Up into the page: `window.__impktBeta.punch` for every punch, and
/// `window.__impktBeta.state` with what is connected, pushed on a timer and after every
/// connect. Down from it: `connect`, `disconnect`, `hello` and `openTab`, each answered
/// through `window.__impktBeta.reply`. src/lib/band.ts in beta/ is the other end.
final class BetaBridge: NSObject, WKScriptMessageHandler {

    private weak var web: WKWebView?
    private var bag = Set<AnyCancellable>()
    private var ticker: Timer?

    /// How often what is connected is read off the Test tab's page. The same call the
    /// Devices and Leaderboard tabs poll, and as cheap: the page answers it synchronously.
    private static let stateInterval: TimeInterval = 1.5

    func attach(_ web: WKWebView) {
        self.web = web
        WrapCentral.shared.$lastPunch
            .compactMap { $0 }
            .sink { [weak self] punch in self?.send(punch) }
            .store(in: &bag)
        ticker = Timer.scheduledTimer(withTimeInterval: BetaBridge.stateInterval, repeats: true) {
            [weak self] _ in
            // Only while the tab is on screen. Off screen nobody is reading it, and the
            // next push lands the moment the tab is opened again.
            guard let self = self, self.web?.window != nil else { return }
            self.pushState()
        }
    }

    deinit { ticker?.invalidate() }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

        if op == "openTab" {
            NotificationCenter.default.post(name: .impktOpenTab, object: nil,
                                            userInfo: ["tab": (args["tab"] as? String) ?? ""])
            return
        }
        guard let id = body["id"] as? Int else { return }
        let reply: (Bool, [String: Any]) -> Void = { [weak self] ok, payload in
            self?.eval("window.__impktBeta && window.__impktBeta.reply(\(id), \(ok), \(Bridge.json(payload)))")
        }

        switch op {
        case "hello":
            pushState()
            reply(true, [:])

        case "connect":
            ConnectionLog.shared.add("beta asks: connect")
            guard WrapCentral.shared.poweredOn else { reply(false, ["why": "no bluetooth"]); return }
            // Asked of the page first, because the page is what connects, and it says no
            // to both of these without explaining itself to a caller that is not its own.
            PageControl.state { [weak self] state in
                guard let state = state else { reply(false, ["why": "no page"]); return }
                guard state.activated else { reply(false, ["why": "not activated"]); return }
                guard !state.running else { reply(false, ["why": "a drill is running"]); return }
                PageControl.search { result in
                    ConnectionLog.shared.add("  beta connect -> \(result.ok ? "ok" : result.why ?? "failed")")
                    self?.pushState()
                    reply(result.ok, result.ok ? [:] : ["why": result.why ?? "refused"])
                }
            }

        case "disconnect":
            ConnectionLog.shared.add("beta asks: disconnect")
            PageControl.disconnect(.left) { _ in
                PageControl.disconnect(.right) { [weak self] _ in
                    self?.pushState()
                    reply(true, [:])
                }
            }

        default:
            reply(false, ["why": "the app does not know \(op)"])
        }
    }

    // MARK: - up into the page

    private func send(_ punch: Punch) {
        var p: [String: Any] = ["power": punch.power, "peakG": punch.peak, "speed": punch.speed]
        if punch.hand != .unknown { p["hand"] = punch.hand.rawValue }
        eval("window.__impktBeta && window.__impktBeta.punch(\(Bridge.json(p)))")
    }

    private func pushState() {
        PageControl.state { [weak self] state in
            var wraps: [[String: Any]] = []
            for (hand, h) in [("L", state?.left), ("R", state?.right)] {
                guard let h = h, h.on else { continue }
                wraps.append(["hand": hand, "name": h.name, "battery": h.battery, "fw": h.fw])
            }
            let payload: [String: Any] = [
                "poweredOn": WrapCentral.shared.poweredOn,
                "activated": state?.activated ?? false,
                "running": state?.running ?? false,
                "wraps": wraps
            ]
            self?.eval("window.__impktBeta && window.__impktBeta.state(\(Bridge.json(payload)))")
        }
    }

    /// Everything interpolated here comes out of JSONSerialization, for the reason given
    /// on `Bridge.eval`: a wrap's name is remote input.
    private func eval(_ js: String) {
        if Thread.isMainThread { web?.evaluateJavaScript(js, completionHandler: nil) }
        else { DispatchQueue.main.async { self.web?.evaluateJavaScript(js, completionHandler: nil) } }
    }
}
