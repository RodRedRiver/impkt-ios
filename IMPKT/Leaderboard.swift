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
    /// Power, the best one.
    var best: Int
    var punches: Int
    /// When the best landed, not when the name was added. It is what a tie breaks on.
    var at: Date

    /// The best from each hand, and how many each hand threw.
    ///
    /// Kept separately rather than derived, because `best` is the better of the two and
    /// which hand it came off is exactly the thing being asked about. A hand with no
    /// punches stays at zero and `Balance` refuses to compare it.
    var bestLeft: Int = 0
    var bestRight: Int = 0
    var punchesLeft: Int = 0
    var punchesRight: Int = 0
    /// Hand speed of their best punch, in metres per second.
    var bestSpeed: Double = 0

    init(name: String, best: Int, punches: Int, at: Date,
         bestLeft: Int = 0, bestRight: Int = 0,
         punchesLeft: Int = 0, punchesRight: Int = 0, bestSpeed: Double = 0) {
        self.name = name
        self.best = best
        self.punches = punches
        self.at = at
        self.bestLeft = bestLeft
        self.bestRight = bestRight
        self.punchesLeft = punchesLeft
        self.punchesRight = punchesRight
        self.bestSpeed = bestSpeed
    }

    /// Spelled out rather than synthesised so that a board written by the build before
    /// this one still loads. The five fields below did not exist then, and the generated
    /// decoder throws on a missing key rather than defaulting it, which would have
    /// emptied a gym's standings at the moment they installed the update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name         = try c.decode(String.self, forKey: .name)
        best         = try c.decode(Int.self,    forKey: .best)
        punches      = try c.decode(Int.self,    forKey: .punches)
        at           = try c.decode(Date.self,   forKey: .at)
        bestLeft     = try c.decodeIfPresent(Int.self,    forKey: .bestLeft)     ?? 0
        bestRight    = try c.decodeIfPresent(Int.self,    forKey: .bestRight)    ?? 0
        punchesLeft  = try c.decodeIfPresent(Int.self,    forKey: .punchesLeft)  ?? 0
        punchesRight = try c.decodeIfPresent(Int.self,    forKey: .punchesRight) ?? 0
        bestSpeed    = try c.decodeIfPresent(Double.self, forKey: .bestSpeed)    ?? 0
    }

    var balance: Balance? { Balance.between(left: bestLeft, right: bestRight) }
}

/// How the two hands compare, which is what a coach looks at second, after the number.
///
/// Nil unless both hands have landed something. One hand on the board is not a
/// nine-to-nothing split, it is a hand that has not had its turn, and a screen that
/// says "your left is 100% harder" about a right hand that never threw would be
/// reporting the app's own gap as the boxer's.
struct Balance: Equatable {
    /// The harder hand.
    let strong: Hand
    /// How much harder, as a percentage of the weaker hand. A left of 120 against a
    /// right of 100 is 20: the left hits 20% harder.
    let percent: Int
    let left: Int
    let right: Int

    /// The left hand's share of the pair, for drawing a bar. 0.5 is level.
    var leftShare: Double {
        let total = left + right
        return total > 0 ? Double(left) / Double(total) : 0.5
    }

    static func between(left: Int, right: Int) -> Balance? {
        guard left > 0, right > 0 else { return nil }
        let strong = left >= right ? Hand.left : .right
        let high = max(left, right), low = min(left, right)
        let pct = Int(((Double(high) / Double(low)) - 1) * 100)
        return Balance(strong: strong, percent: pct, left: left, right: right)
    }
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
        /// Power, the best of this turn so far. Zero until the first punch.
        var best = 0
        var punches = 0
        var started = Date()
        /// What this name had on the board before the turn started, so the screen can say
        /// what there is to beat and know when it has been beaten.
        var previous = 0

        /// This turn's hands. The split is shown live, because it is the one number on
        /// the screen that a person can do something about while they are still standing
        /// there: a right that is 30% down on the left is a reason to throw more rights.
        var bestLeft = 0
        var bestRight = 0
        var punchesLeft = 0
        var punchesRight = 0
        /// Hand speed of the best punch of the turn, in metres per second.
        var bestSpeed = 0.0

        var balance: Balance? { Balance.between(left: bestLeft, right: bestRight) }
    }

    struct Moment: Equatable {
        let id = UUID()
        let kind: Kind
        let power: Int
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
        let power = punch.power
        guard var t = turn else {
            held = punch
            moment = Moment(kind: .punch, power: power)
            return
        }
        t.punches += 1
        switch punch.hand {
        case .left:
            t.punchesLeft += 1
            if power > t.bestLeft { t.bestLeft = power }
        case .right:
            t.punchesRight += 1
            if power > t.bestRight { t.bestRight = power }
        case .unknown:
            // Counted in the total, left out of the split. A wrap whose identity has not
            // been read yet is one that will be in a second or two, and putting its
            // punches on a side at random is how a boxer ends up being told their left is
            // stronger by an app that could not tell which hand it was looking at.
            break
        }
        let beat = power > t.best
        if beat {
            t.best = power
            t.bestSpeed = punch.speed
        }
        turn = t
        last = punch

        // Three things a punch can be, in the order that matters most to somebody who
        // just threw it. Taking the lead outranks a personal best, and a personal best
        // outranks being the best of this turn, so the phone reacts once and reacts to
        // the biggest of them.
        let leader = board.first?.best ?? 0
        if beat && power > leader && !isLeader(t.name) {
            moment = Moment(kind: .lead, power: power)
        } else if beat && power > t.previous && t.previous > 0 {
            moment = Moment(kind: .personalBest, power: power)
        } else {
            moment = Moment(kind: .punch, power: power)
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
        add(t)
    }

    /// Answers the question on a held punch: this is who threw it, and they are still at
    /// the bag, so the turn opens with that punch already in it.
    func claim(_ name: String) { put(up: name) }

    /// Throws away the punch nobody claimed. Its own button, because the alternative to
    /// having one is a number sitting on the screen with a question mark next to it for
    /// the rest of the session.
    func dropHeld() { held = nil }

    // MARK: - the board itself

    /// Folds a finished turn into the standings. Takes the whole turn rather than a
    /// handful of numbers, because there are nine of them now and a call site listing
    /// nine arguments in the right order is a bug waiting for the tenth.
    ///
    /// Everything is a running maximum except the counts, which add. A second turn can
    /// improve any of the four bests independently: somebody whose left was already on
    /// the board comes back and beats it with their right, and both numbers should be the
    /// best that hand has done all session.
    private func add(_ t: Turn) {
        let key = t.name.lowercased()
        if let i = board.firstIndex(where: { $0.id == key }) {
            board[i].punches      += t.punches
            board[i].punchesLeft  += t.punchesLeft
            board[i].punchesRight += t.punchesRight
            if t.bestLeft  > board[i].bestLeft  { board[i].bestLeft  = t.bestLeft }
            if t.bestRight > board[i].bestRight { board[i].bestRight = t.bestRight }
            if t.best > board[i].best {
                board[i].best      = t.best
                board[i].bestSpeed = t.bestSpeed
                board[i].at        = Date()
            }
        } else {
            board.append(Boxer(name: t.name, best: t.best, punches: t.punches, at: Date(),
                               bestLeft: t.bestLeft, bestRight: t.bestRight,
                               punchesLeft: t.punchesLeft, punchesRight: t.punchesRight,
                               bestSpeed: t.bestSpeed))
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
            var line = "\(i + 1). \(b.name)  \(b.best) power"
            if let bal = b.balance {
                line += "  (\(bal.strong.word.lowercased()) \(bal.percent)% harder)"
            }
            lines.append(line)
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
