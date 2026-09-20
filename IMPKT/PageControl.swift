import Foundation
import WebKit

/// Asking the page to do something, from the tabs that are not the page.
///
/// PageStorage is the other half of this and reads what the page wrote down. This one
/// makes it act: connect a hand, drop a hand, look for wraps, change a measurement.
///
/// Every one of these could be done natively and none of them is. The page owns the
/// Bluetooth links, because the punches from a wrap have to arrive inside the drill
/// that is running in the web view, and a native tab holding the only link to a wrap
/// would be recording nothing into nothing. The page owns the profile for the same
/// reason PageStorage reads it rather than keeping a copy: two answers to "what is my
/// weight" is one answer too many. So these screens ask, and the page is still the one
/// thing that connects and the one thing that saves.
///
/// The page's side is `window.__impktApp`, which is the mirror image of bridge.js: the
/// bridge is the app answering the page, this is the page answering the app.
enum PageControl {

    // MARK: - what comes back

    /// One hand, as the page has it.
    struct Hand: Decodable {
        var on = false
        var id = ""
        var name = ""
        /// The line the page's own panel is showing for this hand. Shown as it comes,
        /// so "Connected, older firmware" is not reworded into something vaguer by the
        /// screen that happens to be displaying it.
        var status = ""
        var rssi: Int?
        var battery = ""
        var punches = 0
    }

    struct State: Decodable {
        /// False in a browser with no Bluetooth. Inside the app the bridge provides it,
        /// so this is false only while the page is still loading.
        var canPair = false
        /// Past the gate. Before that there is no pilot and nothing to record for.
        var activated = false
        /// A drill is on the clock, and connecting mid-drill is how a recording loses
        /// its second half. The buttons go quiet rather than doing it.
        var running = false
        var left = Hand()
        var right = Hand()
    }

    /// `ok`, or why not, in the page's words: "no bluetooth", "none found", "refused",
    /// "a drill is running". The screens turn each into their own sentence.
    struct Result: Decodable {
        var ok = false
        var why: String?
    }

    // MARK: - asking

    /// Reads the state of both hands. Cheap, synchronous on the page's side, and polled.
    static func state(then done: @escaping (State?) -> Void) {
        ask("window.__impktApp && window.__impktApp.state()", as: State.self, then: done)
    }

    /// Looks for wraps for a few seconds and connects anything that says which hand it
    /// is on, which for a returning pilot is the whole job with nothing pressed.
    ///
    /// Answers when the search is over rather than when it starts, so the screen knows
    /// when to stop spinning, which is why this one is `callAsyncJavaScript`.
    static func search(seconds: Double = 5, then done: @escaping (Result) -> Void) {
        callAsync("return await window.__impktApp.search(ms);",
                  arguments: ["ms": seconds * 1000], then: done)
    }

    static func connect(_ side: Side, then done: @escaping (Result) -> Void) {
        callAsync("return await window.__impktApp.connect(side);",
                  arguments: ["side": side.rawValue], then: done)
    }

    static func disconnect(_ side: Side, then done: @escaping (Bool) -> Void) {
        guard let page = PageStorage.page else { done(false); return }
        page.evaluateJavaScript("window.__impktApp.disconnect('\(side.rawValue)')") { value, _ in
            done((value as? Bool) ?? false)
        }
    }

    /// Changes some of the profile and leaves the rest alone.
    ///
    /// The page applies it to the setup screen's own sliders and radios and then saves
    /// what those hold, so a value out of range comes back clamped and a value it does
    /// not offer comes back refused, with the stored one still standing. What arrives
    /// here is therefore what is stored, not what was asked for, and it is what the
    /// screen should show: the alternative is a screen that says 200kg because that is
    /// what somebody typed.
    static func saveProfile(_ patch: [String: Any],
                            then done: @escaping (PageStorage.Measures?) -> Void) {
        guard let page = PageStorage.page,
              let body = try? JSONSerialization.data(withJSONObject: patch),
              let json = String(data: body, encoding: .utf8) else { done(nil); return }
        page.evaluateJavaScript("window.__impktApp.saveProfile(\(json))") { value, _ in
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let saved = try? JSONDecoder().decode(Saved.self, from: data),
                  saved.ok else { done(nil); return }
            done(saved.profile)
        }
    }

    private struct Saved: Decodable {
        var ok = false
        var profile: PageStorage.Measures?
    }

    /// Left or right, spelled the one way the page spells it.
    enum Side: String, CaseIterable, Identifiable {
        case left, right
        var id: String { rawValue }
        var word: String { self == .left ? "Left hand" : "Right hand" }
    }

    // MARK: - the two ways of asking

    /// For the entries that answer immediately.
    ///
    /// Every script in this file is a literal written here, and the only two things
    /// interpolated into one are a `Side`, which can only be the word left or the word
    /// right, and a patch serialised by JSONSerialization, which is by definition a
    /// valid JavaScript literal. Nothing a pilot types reaches these strings: what they
    /// type goes in as an argument to callAsyncJavaScript, which does not interpolate.
    private static func ask<T: Decodable>(_ js: String, as type: T.Type,
                                          then done: @escaping (T?) -> Void) {
        guard let page = PageStorage.page else { done(nil); return }
        page.evaluateJavaScript(js) { value, _ in
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(type, from: data) else {
                done(nil); return
            }
            done(decoded)
        }
    }

    /// For the entries that answer with a promise.
    ///
    /// evaluateJavaScript hands back the promise object itself and never waits for it,
    /// which for a connect means the screen is told the answer before the radio has
    /// been asked the question. callAsyncJavaScript awaits it. `.page` rather than a
    /// content world of our own, because `window.__impktApp` is defined by the page and
    /// an isolated world cannot see it.
    private static func callAsync(_ body: String, arguments: [String: Any],
                                  then done: @escaping (Result) -> Void) {
        guard let page = PageStorage.page else {
            done(Result(ok: false, why: "no page")); return
        }
        page.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { outcome in
            switch outcome {
            case .success(let value):
                guard let text = value as? String,
                      let data = text.data(using: .utf8),
                      let result = try? JSONDecoder().decode(Result.self, from: data) else {
                    done(Result(ok: false, why: "no answer")); return
                }
                done(result)
            case .failure:
                // The page threw, or there is no __impktApp because an older copy of
                // index.html is bundled. Either way the honest answer is that nothing
                // happened, and the screens say so in one sentence rather than two.
                done(Result(ok: false, why: "the page did not answer"))
            }
        }
    }
}
