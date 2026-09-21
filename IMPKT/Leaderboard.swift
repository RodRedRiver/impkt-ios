import Combine
import Foundation

/// One name on the board.
///
/// The best punch and nothing else is what ranks, which is the gym's own rule: everyone
/// gets the band for a minute and the number that counts is the one they are willing to
/// be remembered by. The count of punches thrown is carried alongside it because it is
/// free and because it is the difference between a big number landed once and a big
/// number landed six times, which is a thing people argue about.
struct Boxer: Codable, Identifiable, Equatable {

    /// Case folded, so "sofia" and "Sofia" are one person. Names are typed at a bag by
    /// somebody holding a phone in one hand, and two rows for one boxer is the first
    /// thing that would happen without this.
    var id: String { name.lowercased() }

    var name: String
    /// Kilograms of force, the best one.
    var best: Int
    var punches: Int
    /// When the best landed, not when the name was added. It is what a tie breaks on.
    var at: Date
}

/// The standings, and whose turn it is.
///
/// Two halves in one object, and only the first half is written down. The standings
/// outlive the app being closed, because a gym session runs over an hour and a phone
/// locks in somebody's pocket halfway through it. Whose turn it is does not: a turn is
/// somebody standing at a bag, and if the app was closed they are not standing there any
/// more.
///
/// A singleton, and it starts listening at launch rather than when its tab is first
/// opened. The gym's phone spends the session on this screen, but the Test tab is where
/// the wraps get connected, and a punch thrown to check the band is alive before anyone
/// has pressed Leaderboard should not vanish. See `listen`.
final class Leaderboard: ObservableObject {

    static let shared = Leaderboard()

    // MARK: - the standings

    /// Best first. Sorted on the way in rather than on the way out, so the rank a row
    /// has is the rank it had a moment ago and rows do not reshuffle under a finger.
    @Published private(set) var board: [Boxer] = []
    /// When the board was last cleared, so a gym can tell this morning's standings from
    /// last Tuesday's.
    @Published private(set) var since = Date()

    // MARK: - the turn

    /// Somebody at the bag. Nil between turns, which is most of the time.
    @Published private(set) var turn: Turn?
    /// The newest punch of the turn, which is the number in the middle of the screen.
    @Published private(set) var last: Punch?
    /// A punch that landed with nobody up.
    ///
    /// Not discarded and not counted either. Somebody walks up to the bag and hits it
    /// before anyone has typed a name, which is what actually happens, so the punch waits
    /// on screen with the question attached to it and the answer is one tap on a name
    /// that is already there.
    @Published private(set) var held: Punch?
    /// The last thing worth reacting to, for the haptics and the animation. Each one is a
    /// new value even when the kind and the number repeat.
    @Published private(set) var moment: Moment?

    struct Turn: Equatable {
        var name: String
        /// Kilograms, the best of this turn so far. Zero until the first punch.
        var best = 0
        var punches = 0
        var started = Date()
        /// What this name had on the board before the turn started, so the screen can say
        /// what there is to beat and know when it has been beaten.
        var previous = 0
    }

    struct Moment: Equatable {
        let id = UUID()
        let kind: Kind
        let kilos: Int
        enum Kind { case punch, personalBest, lead }
    }

    /// How long an unattributed punch waits before it stops being the punch that is
    /// on screen.
    ///
    /// It is the walk from the bag to the phone and back, which is this. Past it the
    /// question is stale: the honest failure is to stop asking, because a name typed
    /// against a punch from two minutes ago credits the wrong person and there is
    /// nothing on the screen that could show that had happened.
    static let holdFor: TimeInterval = 45

    private let key = "impkt.leaderboard.v1"
    private let sinceKey = "impkt.leaderboard.since"
    private var bag: Set<AnyCancellable> = []

    private init() { load() }

    // MARK: - punches arriving

    /// Subscribes to the punches WrapCentral taps off the page's own notifications.
    ///
    /// Called from the app's init, once. Idempotent, because a second subscription would
    /// count every punch twice and the symptom of that is a leaderboard that is exactly
    /// right about the ranking and exactly double about the counts, which is the sort of
    /// thing that gets noticed a week later.
    func listen() {
        guard bag.isEmpty else { return }
        WrapCentral.shared.$lastPunch
            .compactMap { $0 }
            .sink { [weak self] punch in self?.record(punch) }
            .store(in: &bag)
    }

    private func record(_ punch: Punch) {
        let kilos = punch.kilos
        guard var t = turn else {
            held = punch
            moment = Moment(kind: .punch, kilos: kilos)
            return
        }
        t.punches += 1
        let beat = kilos > t.best
        if beat { t.best = kilos }
        turn = t
        last = punch

        // Three things a punch can be, in the order that matters most to somebody who
        // just threw it. Taking the lead outranks a personal best, and a personal best
        // outranks being the best of this turn, so the phone reacts once and reacts to
        // the biggest of them.
        let leader = board.first?.best ?? 0
        if beat && kilos > leader && !isLeader(t.name) {
            moment = Moment(kind: .lead, kilos: kilos)
        } else if beat && kilos > t.previous && t.previous > 0 {
            moment = Moment(kind: .personalBest, kilos: kilos)
        } else {
            moment = Moment(kind: .punch, kilos: kilos)
        }
    }

    // MARK: - turns

    /// Puts somebody up. Their old best is remembered rather than cleared: a second turn
    /// is a chance to beat it, not a reset.
    ///
    /// A punch already waiting is folded into the turn, which is the point of holding it.
    /// It is only folded in while it is fresh, and `holdFor` is why.
    func put(up name: String) {
        let clean = Leaderboard.tidy(name)
        guard !clean.isEmpty else { return }
        let previous = board.first { $0.id == clean.lowercased() }?.best ?? 0
        turn = Turn(name: clean, previous: previous)
        last = nil
        if let waiting = held, Date().timeIntervalSince(waiting.at) < Leaderboard.holdFor {
            held = nil
            record(waiting)
        } else {
            held = nil
        }
    }

    /// Ends the turn and writes the best of it onto the board.
    ///
    /// A turn with nothing in it leaves no row. Somebody put up by mistake, or put up and
    /// called away, should not appear at the bottom of the standings on zero: a name with
    /// no punch behind it reads as a person who threw a punch too weak to register, which
    /// is a worse thing to say about somebody than saying nothing.
    func finish() {
        guard let t = turn else { return }
        turn = nil
        last = nil
        guard t.punches > 0 else { return }
        add(t.name, kilos: t.best, punches: t.punches)
    }

    /// Answers the question on a held punch: this is who threw it, and they are still at
    /// the bag, so the turn opens with that punch already in it.
    func claim(_ name: String) { put(up: name) }

    /// Throws away the punch nobody claimed. Its own button, because the alternative to
    /// having one is a number sitting on the screen with a question mark next to it for
    /// the rest of the session.
    func dropHeld() { held = nil }

    // MARK: - the board itself

    private func add(_ name: String, kilos: Int, punches: Int) {
        let key = name.lowercased()
        if let i = board.firstIndex(where: { $0.id == key }) {
            board[i].punches += punches
            if kilos > board[i].best {
                board[i].best = kilos
                board[i].at = Date()
            }
        } else {
            board.append(Boxer(name: name, best: kilos, punches: punches, at: Date()))
        }
        // Best first, and the earlier of two equal bests ahead of the later one: the
        // person who set the number is in front of the person who matched it.
        board.sort { $0.best == $1.best ? $0.at < $1.at : $0.best > $1.best }
        save()
    }

    func remove(_ boxer: Boxer) {
        board.removeAll { $0.id == boxer.id }
        save()
    }

    /// Clears the standings. The turn goes with them: finishing a turn onto a board that
    /// has just been emptied would put the first row back.
    func clearAll() {
        board = []
        turn = nil
        last = nil
        held = nil
        since = Date()
        save()
    }

    func isLeader(_ name: String) -> Bool {
        board.first?.id == name.lowercased()
    }

    func rank(of boxer: Boxer) -> Int {
        (board.firstIndex(of: boxer) ?? 0) + 1
    }

    /// The names offered as taps rather than as typing, most recent first.
    ///
    /// The board sorted by best is the wrong order for this: the person who just had the
    /// band is the person most likely to be handing it to the next one along, and they
    /// are somewhere in the middle of the standings.
    var recent: [Boxer] {
        board.sorted { $0.at > $1.at }
    }

    /// One line for sharing. Plain text, because what a coach does with the standings is
    /// paste them into the gym's group chat.
    var asText: String {
        var lines = ["IMPKT, hardest punch"]
        for (i, b) in board.enumerated() {
            lines.append("\(i + 1). \(b.name)  \(b.best) kg")
        }
        return lines.joined(separator: "\n")
    }

    /// Trimmed, collapsed and capped. A name is typed at a bag between rounds, so it
    /// arrives with a stray space on the end about half the time, and the cap is what
    /// stops one pasted paragraph from owning a row that no phone can draw.
    static func tidy(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        return String(parts.joined(separator: " ").prefix(24))
    }

    // MARK: - written down

    private func load() {
        let store = UserDefaults.standard
        if let data = store.data(forKey: key),
           let saved = try? JSONDecoder().decode([Boxer].self, from: data) {
            board = saved
        }
        if let stamp = store.object(forKey: sinceKey) as? Date { since = stamp }
    }

    private func save() {
        let store = UserDefaults.standard
        if let data = try? JSONEncoder().encode(board) { store.set(data, forKey: key) }
        store.set(since, forKey: sinceKey)
    }
}
