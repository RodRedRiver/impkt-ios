import SwiftUI
import UIKit

/// The gym screen. One band, a line of people, and the hardest punch of the day.
///
/// This is the tab a coach leaves the phone on. It is not a drill and it does not record
/// anything for anybody's session: it is one band passed down a queue, a name typed
/// against whoever is holding it, and the best punch each of them landed. Only the best
/// one, which is the gym's own rule and the reason the screen can stay this simple.
///
/// It reads punches straight off the notifications the page is already receiving, so the
/// band is connected on the Test tab or on Devices exactly as it always was, and this
/// screen never competes for the radio. See `WrapCentral.lastPunch`.
///
/// Built natively rather than as a second page in the web view for the same reason the
/// other three tabs are: there is one web view, it holds the Bluetooth links, and a
/// second one would want them too.
struct LeaderboardView: View {

    @ObservedObject private var board = Leaderboard.shared
    @ObservedObject private var central = WrapCentral.shared

    /// What is being typed into the name field, wherever the field currently is.
    @State private var typing = ""
    @FocusState private var editing: Bool
    /// Scale of the big number, pushed on every punch and let go.
    @State private var pulse: CGFloat = 1
    /// The page's view of the wraps, so the screen can say when there is no band to
    /// punch with instead of sitting there looking broken.
    @State private var page: PageControl.State?
    @State private var searching = false
    @State private var note = ""
    @State private var ticker: Timer?
    @State private var clearing = false
    @State private var sharing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if !connected { bandBanner }
                    stage
                    standings
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.pageCanvas)
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            sharing = true
                        } label: {
                            Label("Share the standings", systemImage: "square.and.arrow.up")
                        }
                        .disabled(board.board.isEmpty)

                        Button(role: .destructive) {
                            clearing = true
                        } label: {
                            Label("Start a new board", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(board.board.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                central.startScan()
                readPage()
                ticker?.invalidate()
                ticker = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                    readPage()
                }
            }
            .onDisappear {
                if !central.updating { central.stopScan() }
                ticker?.invalidate()
                ticker = nil
            }
            // The punch lands here as well as on the board, because a number that
            // changes silently on a screen across the room is a number nobody sees
            // arrive. The phone taps, the figure jumps, and how hard it taps is the
            // difference between a punch, a personal best and taking the lead.
            .onChange(of: board.moment) { moment in
                guard let moment = moment else { return }
                react(to: moment)
            }
            .alert("Start a new board?", isPresented: $clearing) {
                Button("Start a new board", role: .destructive) { board.clearAll() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Every name and every number goes, and there is no way back to them. "
                   + "Worth doing at the start of a session, and not worth doing halfway "
                   + "through one. Sharing the standings first puts them somewhere they "
                   + "survive this.")
            }
            .sheet(isPresented: $sharing) {
                ShareText(text: board.asText)
            }
        }
    }

    // MARK: - is there a band

    /// True when the page has a wrap up on either hand. Either is enough: the gym runs
    /// one band down a queue, and which hand it happens to be filed under is the page's
    /// business rather than this screen's.
    private var connected: Bool {
        page?.left.on == true || page?.right.on == true
    }

    private var bandBanner: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(central.poweredOn ? "No band connected" : "Bluetooth is off for IMPKT",
                      systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote.weight(.medium))
                if !bandNote.isEmpty {
                    Text(bandNote)
                        .font(.caption).foregroundColor(.secondary)
                }
                if central.poweredOn && page?.activated == true {
                    Button {
                        search()
                    } label: {
                        if searching {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Looking for a band")
                            }
                        } else {
                            Text("Connect a band")
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .disabled(searching)
                }
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.impktRed)
                }
            }
        }
    }

    private var bandNote: String {
        if !central.poweredOn {
            return "Turn it on for IMPKT in Settings. Nothing can reach a band until then."
        }
        if page?.activated != true {
            return "Enter the activation code on the Test tab first. The band connects "
                 + "through the page, and the page is behind its front door."
        }
        return ""
    }

    // MARK: - the middle of the screen

    @ViewBuilder private var stage: some View {
        if let turn = board.turn {
            live(turn)
        } else if let waiting = board.held {
            question(waiting)
        } else {
            idle
        }
    }

    /// Somebody is up. The number is the punch they just threw, and under it is the one
    /// that counts.
    private func live(_ turn: Leaderboard.Turn) -> some View {
        Card {
            VStack(spacing: 14) {
                HStack {
                    Label(turn.name, systemImage: "figure.boxing")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(turn.punches) thrown")
                        .font(.caption).foregroundColor(.secondary)
                }

                figure(board.last?.power, speed: board.last?.speed,
                       quiet: board.last == nil)

                if turn.best > 0 {
                    VStack(spacing: 6) {
                        Text("Best of this turn, \(turn.best)")
                            .font(.subheadline.weight(.medium))
                        chase(turn)
                        hands(turn.balance)
                    }
                } else {
                    Text("Hit the bag. Every punch shows up here and the hardest one is "
                       + "the one that goes on the board.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    editing = false
                    board.finish()
                } label: {
                    Text(turn.best > 0 ? "Done, put \(turn.best) on the board"
                                       : "Done")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(FrostedButtonStyle())
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// How far off the thing worth beating, which is the leader's number unless the
    /// leader is the person throwing, in which case it is their own.
    @ViewBuilder private func chase(_ turn: Leaderboard.Turn) -> some View {
        let target = board.isLeader(turn.name) ? turn.previous : (board.board.first?.best ?? 0)
        if target > 0 && turn.best >= target {
            Label(board.isLeader(turn.name) ? "Past your own best" : "Top of the board",
                  systemImage: "crown.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.impktRed)
        } else if target > 0 {
            VStack(spacing: 5) {
                ProgressView(value: Double(turn.best), total: Double(target))
                    .tint(.impktRed)
                Text("\(target - turn.best) off \(chaseWho(turn))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func chaseWho(_ turn: Leaderboard.Turn) -> String {
        if board.isLeader(turn.name) { return "your own best" }
        guard let leader = board.board.first else { return "the top" }
        return leader.name
    }

    /// A punch landed with nobody up. The number is on screen and the only thing missing
    /// is whose it is, so that is the only thing asked for.
    private func question(_ waiting: Punch) -> some View {
        Card {
            VStack(spacing: 14) {
                Text("Who threw that?")
                    .font(.headline)
                figure(waiting.power, speed: waiting.speed, quiet: false)
                Text("Tap a name and it counts for them, and they stay up for the rest of "
                   + "their turn.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                nameEntry(label: "Count it")
                Button("Nobody, drop it") { board.dropHeld() }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Nothing is happening. The board's own top number is the thing worth looking at,
    /// and under it is the way in.
    private var idle: some View {
        Card {
            VStack(spacing: 14) {
                if let leader = board.board.first {
                    Text("Hardest so far")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    figure(leader.best, speed: leader.bestSpeed, quiet: false)
                    Label(leader.name, systemImage: "crown.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.impktRed)
                } else {
                    Text("Nobody has hit it yet")
                        .font(.headline)
                }
                nameEntry(label: "Put them up")
            }
        }
    }

    /// The big figure. One number and nothing next to it that qualifies it.
    ///
    /// Labelled power, not kilograms. The board's number is how hard the hand was
    /// accelerating blended with how fast it was moving, both measured at the wrap, and
    /// a kilogram would be claiming a conversion to force at the glove that nothing in
    /// this system measures. Power is what it is.
    ///
    /// Hand speed goes underneath when there is one, small. It is the second thing
    /// anybody asks after the number, it needs no explaining, and it is the one figure
    /// here that is a plain physical measurement in its own units.
    private func figure(_ power: Int?, speed: Double? = nil, quiet: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(power.map { "\($0)" } ?? "0")
                    .font(.system(size: 80, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundColor(quiet ? Color.secondary.opacity(0.35) : .impktRed)
                Text("power")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            if let speed, speed > 0 {
                Text(String(format: "%.1f m/s at the hand", speed))
                    .font(.caption).foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .scaleEffect(pulse)
        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: pulse)
    }

    /// Left against right, which is the thing Sofia asked for in a percentage.
    ///
    /// A bar split at the share of the two bests, the harder hand named, and by how much.
    /// Nothing when only one hand has landed something: see `Balance`.
    @ViewBuilder private func hands(_ balance: Balance?) -> some View {
        if let b = balance {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(b.strong == .left ? Color.impktRed
                                                    : Color.impktRed.opacity(0.28))
                            .frame(width: max(3, (geo.size.width - 2) * b.leftShare))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(b.strong == .right ? Color.impktRed
                                                     : Color.impktRed.opacity(0.28))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Left \(b.left)")
                    Spacer(minLength: 8)
                    Text("\(b.strong.word) \(b.percent)% harder")
                        .fontWeight(.semibold)
                        .foregroundColor(.impktRed)
                    Spacer(minLength: 8)
                    Text("Right \(b.right)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            }
        }
    }

    // MARK: - putting a name up

    /// The field, and the names that are already on the board as taps.
    ///
    /// The taps are the point. Typing a name at a bag with a glove half off is the slow
    /// part of a session, and after the first round every name in the room is already in
    /// this list, most recent first, because the person who just finished is usually the
    /// one handing the band on.
    @ViewBuilder private func nameEntry(label: String) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Name", text: $typing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($editing)
                    .onSubmit { putUp(typing) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.pageCanvas,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(label) { putUp(typing) }
                    .font(.subheadline.weight(.semibold))
                    .disabled(Leaderboard.tidy(typing).isEmpty)
            }
            if !board.recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(board.recent) { boxer in
                            Button { putUp(boxer.name) } label: {
                                Text(boxer.name)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.pageCanvas,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func putUp(_ name: String) {
        let clean = Leaderboard.tidy(name)
        guard !clean.isEmpty else { return }
        typing = ""
        editing = false
        board.put(up: clean)
    }

    // MARK: - the standings

    @ViewBuilder private var standings: some View {
        if !board.board.isEmpty {
            Card {
                VStack(spacing: 0) {
                    HStack {
                        Text("Standings")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(board.board.count == 1 ? "1 boxer"
                                                    : "\(board.board.count) boxers")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)

                    ForEach(board.board) { boxer in
                        if boxer.id != board.board.first?.id { Divider() }
                        row(board.rank(of: boxer), boxer)
                    }
                }
            }
        }
    }

    private func row(_ place: Int, _ boxer: Boxer) -> some View {
        HStack(spacing: 12) {
            medal(place)
            VStack(alignment: .leading, spacing: 2) {
                Text(boxer.name)
                    .font(.subheadline.weight(place == 1 ? .semibold : .regular))
                    .lineLimit(1)
                Text(rowNote(boxer))
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(boxer.best)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(place == 1 ? .impktRed : .primary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button { putUp(boxer.name) } label: {
                Label("Put \(boxer.name) up", systemImage: "figure.boxing")
            }
            Button(role: .destructive) { board.remove(boxer) } label: {
                Label("Take \(boxer.name) off the board", systemImage: "trash")
            }
        }
    }

    /// The second line of a row. Punch count always, then whatever else there is room
    /// for: the hand split when both hands have thrown, and the speed of the best punch.
    ///
    /// One line and not three. A row is read from four feet away by somebody deciding
    /// whether to argue, and the number on the right is what they are arguing about.
    private func rowNote(_ boxer: Boxer) -> String {
        var parts = [boxer.punches == 1 ? "1 punch" : "\(boxer.punches) punches"]
        if let b = boxer.balance {
            parts.append("\(b.strong.word.lowercased()) +\(b.percent)%")
        }
        if boxer.bestSpeed > 0 {
            parts.append(String(format: "%.1f m/s", boxer.bestSpeed))
        }
        return parts.joined(separator: "  ·  ")
    }

    /// The top three get a filled disc and the rest get their number. Three, because a
    /// gym reads the top of a board and argues about the top of a board.
    private func medal(_ place: Int) -> some View {
        let fill: Color = place == 1 ? .impktRed
                        : place == 2 ? Color.secondary.opacity(0.55)
                        : place == 3 ? Color.secondary.opacity(0.3)
                        : .clear
        return Text("\(place)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundColor(place <= 3 ? .white : .secondary)
            .frame(width: 26, height: 26)
            .background(fill, in: Circle())
            .overlay(
                Circle().strokeBorder(Color.secondary.opacity(place <= 3 ? 0 : 0.25),
                                      lineWidth: 1)
            )
    }

    // MARK: - the phone reacting

    private func react(to moment: Leaderboard.Moment) {
        pulse = moment.kind == .lead ? 1.22 : moment.kind == .personalBest ? 1.14 : 1.08
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { self.pulse = 1 }
        switch moment.kind {
        case .lead:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .personalBest:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .punch:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - the page

    private func readPage() {
        PageControl.state { state in
            if let state = state { self.page = state }
        }
    }

    private func search() {
        note = ""
        searching = true
        PageControl.search { result in
            self.searching = false
            self.readPage()
            if !self.central.updating { self.central.startScan() }
            guard !result.ok else { return }
            self.note = result.why == "none found"
                ? "Nothing answered. A band sleeps until it is shaken, so shake it and "
                  + "press Connect again."
                : "That did not connect. The page says: \(result.why ?? "nothing")."
        }
    }
}

/// A white card on the page's canvas, which is the one shape every panel on this screen
/// is. Here rather than as a modifier because it also owns the padding, and a card whose
/// inside edge is set by whatever it contains is a screen of cards that do not line up.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Color.white,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The system share sheet, for the one thing on this screen that leaves the phone, and
/// only when somebody presses the button that sends it.
private struct ShareText: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
