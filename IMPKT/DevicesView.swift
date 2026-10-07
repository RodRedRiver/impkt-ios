import SwiftUI
import UIKit

/// Connecting your wraps, and what the phone can hear.
///
/// Two jobs, in that order. The top of the screen is the connection page: one row per
/// hand, and one button that goes looking. The rest answers the question that gets
/// asked when something is not working, whether the phone can hear the wrap at all,
/// how well, which hand it thinks it is on, and whether the app has met it before.
///
/// Firmware updates happen here too, on the wrap in the list: Update beside each wrap
/// that is nearby, and an offer under a connected hand whose wrap reports older
/// firmware than the one inside this app.
///
/// Connecting happens in the page and not here. See PageControl: the punches from a
/// wrap have to arrive inside the drill running in the web view, so the page holds the
/// links and this screen asks it to. Which is also why the rows read the page's own
/// words for what a hand is doing rather than inventing a second set.
struct DevicesView: View {

    @ObservedObject private var central = WrapCentral.shared
    /// Which wrap is on which hand, as the page recorded it. Read from the page rather
    /// than kept here, because the wraps tell the page their own side over the link and
    /// the page is what writes it down. See PageStorage.
    @State private var hands: [String: String] = [:]
    /// Every wrap this phone has permission for, whether or not it is answering.
    @State private var remembered: [UUID] = []
    /// Set by pressing Forget, cleared by answering the question.
    @State private var forgetting: UUID?
    /// Firmware updates happen here, on the wrap in the list. Set by tapping Update, cleared by
    /// answering the confirmation.
    ///
    /// An update is not a safe thing to start by accident on these wraps. The bootloader erases
    /// the application before a byte of the new image arrives, so an update that does not finish
    /// leaves a wrap that cannot punch, cannot be woken by shaking, and needs a computer and a
    /// cable to come back. It also loses the wrap's stored identity. None of that is a reason not
    /// to update over the air, only a reason for the tap to say what it costs.
    @State private var confirming: FoundWrap?
    @StateObject private var updater = Updater()

    /// What the page says about both hands, re-read every second and a bit while this
    /// screen is up, because a wrap can drop on its own and a drill can start in the
    /// tab next door. Nil until the first answer arrives.
    @State private var page: PageControl.State?
    @State private var asked = false
    /// The hand with a press in flight, so one row can spin without the other going
    /// quiet, and so the same button cannot be pressed twice.
    @State private var busy: PageControl.Side?
    @State private var searching = false
    /// The last thing a press led to, when it led to nothing visible.
    @State private var note = ""
    @State private var ticker: Timer?

    var body: some View {
        NavigationView {
            List {
                Section {
                    if !explainer.isEmpty {
                        Text(explainer).font(.footnote).foregroundColor(.secondary)
                    }
                } header: {
                    Text(state)
                }

                if updater.phase != .idle {
                    Section { updateStatus } header: { Text("Update") }
                }

                wraps()

                Section("Nearby") {
                    if central.found.isEmpty {
                        Text(central.poweredOn
                             ? "Nothing yet. Shake a wrap to wake it."
                             : "Bluetooth is off for this app. Turn it on in Settings.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    // Strongest first, which on a bench is the one in your hand.
                    ForEach(central.found.sorted { $0.rssi > $1.rssi }) { wrap in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wrap.inBootloader ? "A wrap in update mode" : wrap.name)
                                Text(line(for: wrap)).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(strength(wrap.rssi)).font(.footnote).foregroundColor(.secondary)
                            if updater.target?.id == wrap.id,
                               updater.phase == .connecting || updater.phase == .sending {
                                ProgressView()
                            } else {
                                Button(wrap.inBootloader ? "Finish update" : "Update") { confirming = wrap }
                                    .font(.footnote)
                                    .disabled(updater.phase == .connecting || updater.phase == .sending)
                            }
                        }
                    }
                }

                Section("Remembered") {
                    if absent.isEmpty && remembered.isEmpty {
                        Text("Nothing yet. A wrap is remembered the first time it is "
                             + "connected, here or on the Test tab, and stays remembered "
                             + "so it never has to be picked twice.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(absent, id: \.self) { id in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: id))
                                Text("Not answering, so it is asleep, out of range or off. "
                                     + "This phone files it as \(short(id)).")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button("Forget") { forgetting = id }
                                .font(.footnote)
                        }
                    }
                }
            }
            .onCanvas()
            .navigationTitle("Devices")
            .onAppear {
                central.startScan()
                self.refresh()
                self.readPage()
                // A second and a bit, which is the page's own repaint interval for the
                // same two rows. Fast enough that a wrap dropping is news rather than
                // history, and slow enough to be a string of JSON.
                self.ticker?.invalidate()
                self.ticker = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                    self.readPage()
                }
            }
            .onDisappear {
                // Not while an update is running: the scan was stopped by the updater
                // for the duration, and stopping it again is harmless, but starting it
                // in onAppear was not, so the pair of them stay symmetrical and both
                // leave the radio alone. See WrapCentral.takeRadio.
                if !central.updating { central.stopScan() }
                self.ticker?.invalidate()
                self.ticker = nil
            }
            .alert("Update this wrap over Bluetooth?",
                   isPresented: Binding(get: { confirming != nil },
                                        set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { wrap in
                Button("Update", role: .destructive) {
                    let target = wrap
                    confirming = nil
                    updater.start(target)
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: { _ in
                Text("Keep the phone next to the wrap until it finishes. The wrap's "
                   + "firmware is erased before any of the new firmware arrives, so an "
                   + "update that stops part way leaves a wrap that needs a computer "
                   + "and a cable to come back. It also clears the wrap's hand setting, "
                   + "which the app asks for again afterwards.")
            }
            .alert("Forget this wrap?",
                   isPresented: Binding(get: { forgetting != nil },
                                        set: { if !$0 { forgetting = nil } }),
                   presenting: forgetting) { id in
                Button("Forget", role: .destructive) {
                    central.forget(id)
                    forgetting = nil
                    self.refresh()
                }
                Button("Cancel", role: .cancel) { forgetting = nil }
            } message: { _ in
                Text("Nothing on the wrap changes and nothing recorded is lost. The Test "
                   + "tab will pick it again the next time it needs it, which is one tap "
                   + "with the wrap awake. Worth doing for a wrap you no longer have, or "
                   + "for one this phone has an old idea of.")
            }
        }
    }

    // MARK: - the connection page

    /// One row per hand, one button, and a sentence when a press came to nothing.
    ///
    /// A pair and not a device list. The wraps are sold in twos, one per hand, and the
    /// thing a pilot wants to know before a drill is whether both hands are up: a list
    /// of radios sorted by strength answers that only if you already know which of two
    /// identical black wraps is which, and the wraps themselves know, so the rows are
    /// left and right and the matching is the page's job.
    @ViewBuilder private func wraps() -> some View {
        Section {
            if let page = page, page.canPair, page.activated {
                ForEach(PageControl.Side.allCases) { side in
                    hand(side, page)
                    // Offered the moment a connected wrap turns out to be running older firmware
                    // than the one inside this app, and not before: an update is never suggested
                    // for a version the wrap did not report.
                    let h = side == .left ? page.left : page.right
                    if h.on, Updater.isNewer(Updater.bundledVersion, than: h.fw) {
                        Button("Update to \(Updater.bundledVersion)") { startUpdate(h) }
                            .font(.footnote)
                            .disabled(updater.phase == .connecting || updater.phase == .sending)
                    }
                }
                Button(searchLabel) { search() }
                    .font(.footnote)
                    .disabled(searching || busy != nil || page.running)

                if !searchNote.isEmpty {
                    Text(searchNote)
                        .font(.caption).foregroundColor(.secondary)
                }
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.impktRed)
                }
            } else {
                Text(waiting)
                    .font(.footnote).foregroundColor(.secondary)
            }
        } header: {
            Text("Your wraps")
        }
    }

    /// The wrap the page reports as connected on this hand, as the app's own list knows it, so the
    /// update can be started on it. Matched by identifier, which both sides take from the same peripheral.
    private func startUpdate(_ h: PageControl.Hand) {
        if let wrap = central.found.first(where: { $0.id.uuidString.caseInsensitiveCompare(h.id) == .orderedSame }) {
            confirming = wrap
        } else {
            note = "The phone cannot see that wrap in the list below right now. Shake it, wait for it "
                 + "to appear under Nearby, and press Update there."
        }
    }

    /// Progress, success and failure of an update, shown at the top of the screen for as long as
    /// there is something to say about it.
    @ViewBuilder private var updateStatus: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .connecting, .sending:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: updater.progress)
                Text(updater.detail).font(.footnote).foregroundColor(.secondary)
                Text("Do not close the app or walk away with the phone.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Stop") { updater.cancel() }
                    .font(.footnote)
            }
        case .done:
            Label(updater.detail, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green).font(.footnote)
        case .failed(let why):
            let stranded = updater.jumped
                || central.found.contains {
                    $0.inBootloader && Date().timeIntervalSince($0.seen) < Updater.bootloaderGrace
                }
            VStack(alignment: .leading, spacing: 6) {
                Label(stranded ? "That wrap is waiting in update mode" : "The update did not finish",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange).font(.footnote)
                Text(why).font(.caption).foregroundColor(.secondary)
                Text(stranded
                     ? "Until an update finishes it cannot punch, and shaking it will not wake it. "
                       + "Press Finish update with the phone next to it. If that does not take, plug "
                       + "it into a computer and put the firmware back over the cable, which always "
                       + "works. Leave it powered in the meantime."
                     : updater.neverConnected
                       ? "The phone never got a link at all, so either the wrap went back to sleep, "
                         + "or it is already in update mode from an earlier try. Shake it and look "
                         + "for a wrap in update mode below."
                       : "The wrap kept the firmware it had and still works. Shake it awake, wait "
                         + "for it to appear below, and press Update again.")
                    .font(.caption).foregroundColor(.secondary)
                if updater.lastTarget != nil {
                    Button(stranded ? "Finish update" : "Try again") { updater.retry() }
                        .font(.footnote)
                }
                if !updater.log.isEmpty {
                    Button("Copy the whole log") {
                        UIPasteboard.general.string = updater.log.joined(separator: "\n")
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var searchLabel: String {
        searching ? "Looking for your wraps" : "Look for my wraps"
    }

    /// Which way round a wrap goes on, and what happens if it goes on the other way.
    ///
    /// Here because it is now the only place in the app that says it. The Test tab
    /// used to ask it as four steps between the profile and the drills and those
    /// steps are gone; the panel on that tab that says it in one line is hidden in
    /// the app, because this screen is the native version of that panel. So the
    /// fact moved with the panel rather than going out with the steps.
    ///
    /// It is worth its own paragraph and not a clause because of the second half.
    private var searchNote: String {
        if page?.running == true {
            return "A drill is running on the Test tab. Connecting or dropping a wrap now "
                 + "would cost that recording its second half, so this waits until the "
                 + "drill is finished."
        }
        return ""
    }

    private func hand(_ side: PageControl.Side, _ page: PageControl.State) -> some View {
        let h = side == .left ? page.left : page.right
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(side.word)
                Text(line(for: h)).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            if busy == side {
                ProgressView()
            } else {
                Button(h.on ? "Disconnect" : "Connect") { press(side, connected: h.on) }
                    .font(.footnote)
                    .disabled(busy != nil || searching || page.running)
            }
        }
        .font(.footnote)
    }

    /// The page's own line for this hand, with the two live numbers after it. Both come
    /// off the link rather than out of the air, which is the only place they exist once
    /// a wrap has stopped advertising.
    private func line(for h: PageControl.Hand) -> String {
        guard h.on else {
            return h.status.isEmpty ? "Not connected" : h.status
        }
        var parts = [h.status.isEmpty ? "Connected" : h.status]
        if !h.battery.isEmpty { parts.append("battery \(h.battery)") }
        if let rssi = h.rssi, rssi > -127 { parts.append("signal \(strength(rssi).lowercased())") }
        return parts.joined(separator: ", ")
    }

    /// Why there are no rows. Four answers, each wanting something different done about
    /// it, so none of them is allowed to look like one empty list.
    private var waiting: String {
        guard let page = page else {
            return asked
                ? "The Test tab has not finished loading, so there is nothing to ask yet. "
                  + "Open it once and come back."
                : "Reading the page."
        }
        if !page.activated {
            return "Enter your code on the Test tab first. Until the page is past its "
                 + "front door there is no pilot for a wrap to be recording for, and "
                 + "connecting one would record into nothing."
        }
        return "This build of the page cannot pair. Bluetooth belongs to the app and the "
             + "page reaches it through the app, so this means the two are out of step: "
             + "reinstalling is the fix."
    }

    private func press(_ side: PageControl.Side, connected: Bool) {
        note = ""
        busy = side
        if connected {
            PageControl.disconnect(side) { _ in
                self.busy = nil
                self.readPage()
            }
            return
        }
        PageControl.connect(side) { result in
            self.busy = nil
            self.readPage()
            self.note = result.ok ? "" : self.sentence(for: result.why, side: side)
        }
    }

    private func search() {
        note = ""
        searching = true
        PageControl.search { result in
            self.searching = false
            self.readPage()
            self.refresh()
            // The page's search and this screen's list are the same radio, and the page
            // stops the scan when it is finished with it. Started again here so the
            // Nearby list below carries on filling in.
            if !self.central.updating { self.central.startScan() }
            if !result.ok { self.note = self.sentence(for: result.why, side: nil) }
        }
    }

    /// The page answers with a reason and this screen decides what it means here, which
    /// is not what it means on the page: "none found" in the panel is answered by the
    /// panel's own list of what is already known, and on a screen that is a list of
    /// what is nearby the useful thing to say is what that list shows.
    private func sentence(for why: String?, side: PageControl.Side?) -> String {
        switch why {
        case "none found":
            let hand = side?.word.lowercased() ?? "either hand"
            return central.found.isEmpty
                ? "Nothing answered for your \(hand). The wraps sleep until they are "
                  + "shaken, so shake them and press Look for my wraps."
                : "Nothing free for your \(hand). There is a wrap nearby, and it is "
                  + "either already on the other hand or it says it belongs there."
        case "refused":
            return "It was there and would not connect. Shake it, wait a moment, and "
                 + "press Connect again. A wrap that has just been updated wants one."
        case "a drill is running":
            return "A drill is running on the Test tab, so the radio is busy recording it."
        case "no bluetooth":
            return "The page cannot reach Bluetooth. Check it is on for IMPKT in Settings."
        case "no page", "no answer", "the page did not answer":
            return "The Test tab has not finished loading, so there was nothing to ask. "
                 + "Open it once and come back."
        default:
            return "That did not work. The page says: \(why ?? "nothing")."
        }
    }

    private func readPage() {
        PageControl.state { state in
            if let state = state { self.page = state }
            self.asked = true
        }
    }

    // MARK: - the lists

    /// Remembered wraps that are not in the list above, so nothing is listed twice and
    /// the second section is only ever the ones that are not here.
    private var absent: [UUID] {
        remembered.filter { id in !central.found.contains { $0.id == id } }
    }

    /// The header of the first section, which is the one thing on this screen that is
    /// worth reading before anything else: whether the phone is listening at all.
    private var state: String {
        if !central.poweredOn { return "Bluetooth is off for this app" }
        if central.updating { return "An update has the radio" }
        return central.scanning ? "Listening" : "Not listening"
    }

    private var explainer: String {
        if !central.poweredOn {
            return "Turn it on for IMPKT in Settings. Until then nothing here can see a "
                 + "wrap, and neither can the Test tab."
        }
        if central.updating {
            return "The Update tab is sending firmware and has the radio to itself while "
                 + "it does. This list fills in again when it finishes."
        }
        return ""
    }

    /// The same four words and the same four thresholds the page uses, because a wrap
    /// that reads Good on one screen and Fair on the next reads as two wraps.
    private func strength(_ rssi: Int) -> String {
        if rssi <= -127 { return "Not known" }
        if rssi >= -55 { return "Strong" }
        if rssi >= -67 { return "Good" }
        if rssi >= -78 { return "Fair" }
        return "Weak"
    }

    private func line(for wrap: FoundWrap) -> String {
        var parts: [String] = []
        if let hand = handWord(wrap.id) { parts.append(hand) }
        if wrap.inBootloader {
            parts.append("its last update stopped part way, so updating it is the only "
                       + "thing it can do")
        }
        // A connected wrap has a live number: the link is read every two seconds, which
        // is the only reading that exists once it has stopped advertising. -127 is the
        // "not measured yet" sentinel and lasts about as long as it takes to say so.
        if wrap.connected {
            parts.append(wrap.rssi <= -127
                         ? "connected to this phone, signal not measured yet"
                         : "connected to this phone, signal \(wrap.rssi) dBm")
        } else {
            parts.append("signal \(wrap.rssi) dBm")
        }
        return parts.joined(separator: ", ")
    }

    /// A remembered wrap has no name to show. The app only ever learns a name from an
    /// advertisement, and these are the ones that are not advertising, so the hand is
    /// the only thing it can be called: which is also the thing somebody holding two
    /// identical black wraps wants to know.
    private func title(for id: UUID) -> String {
        guard let hand = handWord(id) else { return "A remembered wrap" }
        return "The wrap on your \(hand.lowercased())"
    }

    private func handWord(_ id: UUID) -> String? {
        switch hands[id.uuidString] {
        case "left":  return "Left hand"
        case "right": return "Right hand"
        default:      return nil
        }
    }

    /// Enough of the identifier to tell two silent rows apart, and to read out loud
    /// when something has to be reported. iOS makes this up per app and per phone, so
    /// it is not a serial number and it is not the wrap's Bluetooth address.
    private func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func refresh() {
        remembered = central.knownWraps
        PageStorage.read { snap in
            if let snap = snap { self.hands = snap.hands }
        }
    }
}
