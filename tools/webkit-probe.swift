// Loads a page in a real WKWebView at a given size, then measures it.
//
// Why this exists: the app is a WKWebView, and the two engines available on this
// machine disagree about exactly the things the app was reported broken on.
// Headless Chrome is a different layout engine, it ignores --window-size here
// because it reuses the running browser's window, and driving Safari means
// turning on Apple Events and screenshotting the user's desktop. This is the
// same engine the app ships, in a window the size of a phone, with no browser
// chrome and nothing to click.
//
//   swiftc -O tools/webkit-probe.swift -o /tmp/webkit-probe
//   /tmp/webkit-probe <url> [390x844] [settle seconds] [js file] [png out]
//
// The JavaScript file's last expression is what gets printed. Default is a
// layout report: viewport, the two name sizes, and every box that can overflow.

import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: webkit-probe <url> [390x844] [seconds] [js file] [png out]")
    exit(2)
}
let url = URL(string: args[1])!
let size = args.count > 2 ? args[2] : "390x844"
let settle = args.count > 3 ? Double(args[3]) ?? 6 : 6
let jsFile = args.count > 4 ? args[4] : ""
let pngOut = args.count > 5 ? args[5] : ""

let parts = size.split(separator: "x").compactMap { Double($0) }
let w = parts.count == 2 ? parts[0] : 390
let h = parts.count == 2 ? parts[1] : 844

// Everything the page cannot tell you by looking at the DOM: what is taller than
// its box, what is wider than the window, and what size the two copies of the
// name ended up at after the page measured them itself.
let defaultJS = """
(function () {
  var el = function (id) { return document.getElementById(id); };
  var box = function (e) { return e ? e.clientWidth + 'x' + e.clientHeight
                                      + ' content ' + e.scrollWidth + 'x' + e.scrollHeight : null; };
  var n = el('name'), t = el('name-title'), hub = el('hub');
  var last = n && n.lastElementChild;
  return JSON.stringify({
    viewport: innerWidth + 'x' + innerHeight,
    fonts: document.fonts.status,
    docScroll: document.documentElement.scrollWidth + 'x' + document.documentElement.scrollHeight,
    canScroll: document.documentElement.scrollHeight > innerHeight
               || document.body.scrollHeight > innerHeight,
    nameFont: n ? getComputedStyle(n).fontSize : null,
    nameLines: n ? n.getClientRects().length : null,
    nameInk: last ? Math.round(last.offsetLeft + last.offsetWidth) : null,
    titleFont: t ? getComputedStyle(t).fontSize : null,
    titleLines: t ? t.getClientRects().length : null,
    titleInk: t ? t.scrollWidth : null,
    markShown: el('mark') ? getComputedStyle(el('mark')).display : null,
    hub: box(hub),
    brief: box(el('brief')),
    stage: box(el('stage'))
  }, null, 1);
})()
"""

let js = jsFile.isEmpty ? defaultJS
    : (try? String(contentsOfFile: jsFile, encoding: .utf8)) ?? defaultJS

final class Probe: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow

    override init() {
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        web = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        // A window, because a view outside one lays out at zero and paints
        // nothing.
        //
        // And a window that is genuinely on screen and genuinely in front, which
        // is not fussiness: WebKit stops the display link for a window it thinks
        // nobody can see, and a stopped display link means CSS transitions sit at
        // their start value forever and transitionend never fires. The pilot page
        // hangs the whole reveal off one transitionend, so an offscreen window
        // measures a page frozen on its first frame and reports it as broken.
        // Nearly transparent instead, so seven seconds of this is not seven
        // seconds of a white rectangle over whatever the user is doing.
        window = NSWindow(contentRect: frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        super.init()
        window.contentView = web
        window.alphaValue = 0.02
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderFrontRegardless()
        web.navigationDelegate = self
    }

    func webView(_ web: WKWebView, didFinish nav: WKNavigation!) {
        // Fixed wait rather than a readiness signal: what is being measured is a
        // choreographed reveal on its own timers, and there is nothing in the
        // page that says "the name has landed".
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { self.report() }
    }

    func webView(_ web: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write("load failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

    func report() {
        web.evaluateJavaScript(js) { value, error in
            if let error = error {
                FileHandle.standardError.write("javascript failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
            print(value.map { "\($0)" } ?? "null")
            guard !pngOut.isEmpty else { exit(0) }
            self.web.takeSnapshot(with: nil) { image, error in
                if let image = image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: pngOut))
                    FileHandle.standardError.write("wrote \(pngOut)\n".data(using: .utf8)!)
                } else {
                    FileHandle.standardError.write("no snapshot: \(String(describing: error))\n"
                        .data(using: .utf8)!)
                }
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
probe.web.load(URLRequest(url: url))
app.run()
