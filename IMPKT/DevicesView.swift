import SwiftUI

/// What the phone can hear, and what it remembers.
///
/// The Update tab has a list of wraps too and it is not this one. That list exists to
/// be pressed, and every row in it is a target for a firmware image, so it says as
/// little as it can get away with. This one answers the question that gets asked when
/// something is not working: whether the phone can hear the wrap at all, how well,
/// which hand it thinks it is on, and whether the app is sure it has met it before.
/// Nothing here changes anything on a wrap.
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

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(explainer).font(.footnote).foregroundColor(.secondary)
                } header: {
                    Text(state)
                }

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
                        }
                    }
                }

                Section("Remembered") {
                    if absent.isEmpty {
                        Text(remembered.isEmpty
                             ? "Nothing yet. A wrap is remembered the first time the Test "
                               + "tab connects to it, and stays remembered so it never has "
                               + "to be picked twice."
                             : "Every wrap this phone knows is in the list above.")
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

                Section {
                    Text("None of this goes over the internet. It is what the phone's own "
                         + "radio can hear in the room, and Bluetooth reaches a few metres. "
                         + "A wrap stops advertising while something is connected to it, so "
                         + "a wrap the Test tab is talking to is listed from the link "
                         + "itself rather than from the air.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .onCanvas()
            .navigationTitle("Devices")
            .onAppear {
                central.startScan()
                self.refresh()
            }
            .onDisappear {
                // Not while an update is running: the scan was stopped by the updater
                // for the duration, and stopping it again is harmless, but starting it
                // in onAppear was not, so the pair of them stay symmetrical and both
                // leave the radio alone. See WrapCentral.takeRadio.
                if !central.updating { central.stopScan() }
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
        return "A wrap sleeps until it is shaken, and stops advertising once something "
             + "connects to it. So this is what is awake and within a few metres right "
             + "now, not every wrap you own."
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
            parts.append("its last update stopped part way, so the Update tab is the only "
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
