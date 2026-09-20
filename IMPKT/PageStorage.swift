import Foundation
import WebKit

/// What the page has written down, read from the tabs that are not the page.
///
/// The pilot's identity, their code, their measurements and which wrap is on which
/// hand all live in the page's localStorage, because the page is where they are
/// entered and the same file has to work as a web page with no app around it. So
/// there is one copy of each, in there, and these screens read that rather than
/// keeping their own: a native copy would be a second answer to "what is my weight"
/// that disagrees with the page the first time somebody changes it on either side.
///
/// Reading it means asking the web view, because localStorage belongs to the page's
/// origin and nothing else on the phone can see inside it. The web view is the Test
/// tab's, and the Test tab is the one the app opens on, so by the time another tab can
/// be pressed there is a loaded page to ask.
enum PageStorage {

    /// Spelled exactly as index.html spells them. Rename one there without renaming it
    /// here and these screens go blank rather than wrong, which is the failure to
    /// prefer, and is why each one is written once.
    private static let codeKey    = "impkt.pilot.code"
    private static let profileKey = "impkt.pilot.profile.v1"
    private static let handsKey   = "impkt.wrap.hands"
    private static let outboxKey  = "impkt.pilot.outbox.v1"

    /// Everything the native screens read, in one round trip.
    struct Snapshot: Decodable {
        var name = ""
        var gym = ""
        var serial = ""
        var code = ""
        var measures: Measures?
        /// Wrap identifier, as an uppercase UUID string, to "left" or "right". The
        /// same identifier the bridge hands the page, so it matches `FoundWrap.id`.
        var hands: [String: String] = [:]
        /// Finished drills still waiting to go up.
        var outbox = 0

        /// True once the page is past its gate. Everything above is empty until then,
        /// and a screen of blanks is worth replacing with the reason for them.
        var activated: Bool { !name.isEmpty }

        private enum CodingKeys: String, CodingKey {
            case name, gym, serial, code, measures, hands, outbox
        }

        /// Every field decoded on its own, and every failure absorbed on its own.
        ///
        /// This is not defensive programming for its own sake. It is reading storage
        /// written by an older build of the page, or by a build that will be newer
        /// than this app, since the page is updated by copying a file and the app is
        /// updated through the App Store. One value of an unexpected shape should cost
        /// one row, never the whole screen with no way to tell what happened.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name    = (try? c.decode(String.self, forKey: .name)) ?? ""
            gym     = (try? c.decode(String.self, forKey: .gym)) ?? ""
            serial  = (try? c.decode(String.self, forKey: .serial)) ?? ""
            code    = (try? c.decode(String.self, forKey: .code)) ?? ""
            measures = try? c.decode(Measures.self, forKey: .measures)
            hands   = (try? c.decode([String: String].self, forKey: .hands)) ?? [:]
            outbox  = (try? c.decode(Int.self, forKey: .outbox)) ?? 0
        }
    }

    /// The profile as the page writes it, in the units the page holds it in, which are
    /// metric throughout. `units` says which of the two it is to be READ in, and
    /// nothing else in here changes with it.
    struct Measures: Decodable {
        var units: String?
        var weightKg: Double?
        var heightCm: Double?
        /// Null when the pilot left the reach slider at its "not set" notch, which is
        /// most of them: `reachEstimated` is then true and the page uses their height.
        var reachCm: Double?
        var reachEstimated: Bool?
        var stance: String?
        var gloveOz: Double?
        var level: String?
        var saved: String?
    }

    private(set) static weak var page: WKWebView?

    static func attach(_ web: WKWebView) { page = web }

    /// Reads the lot, or answers nil.
    ///
    /// Nil means there is no page to ask or it would not answer, which is a different
    /// thing from a page with nothing stored, and the screens say so differently.
    static func read(then done: @escaping (Snapshot?) -> Void) {
        guard let page = page else { done(nil); return }
        page.evaluateJavaScript(js) { value, error in
            guard error == nil,
                  let text = value as? String,
                  let data = text.data(using: .utf8),
                  let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                done(nil); return
            }
            done(snap)
        }
    }

    /// Throws away the profile and the code, and reloads the page so the app is in the
    /// state that was just asked for rather than one launch away from it.
    ///
    /// Two keys and not four. The outbox holds finished drills that have not reached us
    /// yet, and those are somebody's session rather than a setting. The hand memo is
    /// the wraps' own left and right, read off the boards themselves, so clearing it
    /// would only mean walking the fitting screen again for nothing.
    static func clearProfile(then done: @escaping (Bool) -> Void) {
        guard let page = page else { done(false); return }
        let script = """
        (function () {
          try {
            localStorage.removeItem('\(codeKey)');
            localStorage.removeItem('\(profileKey)');
            return true;
          } catch (err) { return false; }
        })()
        """
        page.evaluateJavaScript(script) { value, _ in
            let ok = (value as? Bool) ?? false
            // The page holds the pilot in memory once it is past its gate, so clearing
            // storage underneath it changes nothing on screen until it reloads. The
            // reload is what makes the button true.
            if ok { page.reload() }
            done(ok)
        }
    }

    /// Returned as one JSON string rather than as an object, so there is exactly one
    /// decode with one set of rules, and the JavaScript side is the only thing that
    /// ever touches localStorage.
    ///
    /// The identity comes out of the DOM and not out of storage, because it is not in
    /// storage: the page holds the pilot in memory, having decrypted their record out
    /// of pilots.json with their code. It is on screen in the briefing, so it is read
    /// from there. `dataset.full` first, because the name is set as two spans on a
    /// phone and textContent of those two is the name with the space missing.
    private static let js = """
    (function () {
      var text = function (id) {
        var e = document.getElementById(id);
        if (!e) return '';
        return ((e.dataset && e.dataset.full) || e.textContent || '').trim();
      };
      var item = function (k) {
        try { return localStorage.getItem(k) || ''; } catch (err) { return ''; }
      };
      var parsed = function (k, fallback) {
        try { return JSON.parse(localStorage.getItem(k)) || fallback; }
        catch (err) { return fallback; }
      };
      var hands = parsed('\(handsKey)', {}) || {};
      var sides = {};
      Object.keys(hands).forEach(function (id) {
        if (typeof hands[id] === 'string') sides[id] = hands[id];
      });
      var outbox = parsed('\(outboxKey)', []);
      return JSON.stringify({
        name:     text('name-title'),
        gym:      text('fact-gym'),
        serial:   text('fact-serial'),
        code:     item('\(codeKey)'),
        measures: parsed('\(profileKey)', null),
        hands:    sides,
        outbox:   (outbox && outbox.length) || 0
      });
    })()
    """
}
