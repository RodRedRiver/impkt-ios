import SwiftUI
import UIKit
import CoreBluetooth
import NordicDFU

/// Firmware updates over Bluetooth, from the phone, with no laptop involved.
///
/// This is the whole point of the app existing rather than a web page: the wraps
/// speak Nordic's legacy DFU protocol, Nordic ship the iOS implementation of it,
/// and a phone in the same room as a wrap can therefore do what previously
/// needed a Mac, a cable and this repository. Send somebody the app and they can
/// update wraps on another continent.
///
/// The image is bundled with the app, so a firmware release IS an app release.
/// That is deliberate for a pilot: it means a tester cannot mix a stale zip with
/// a current app, and there is exactly one answer to "what is on my wraps".
final class Updater: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle, connecting, sending, done, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var detail: String = ""
    @Published var target: FoundWrap?
    /// The DFU library's own running commentary, kept on the phone rather than
    /// only in NSLog, where nobody holding the phone can reach it.
    ///
    /// This is not a nicety. An update that fails part way has already erased the
    /// wrap's application, so the wrap is then stuck in its bootloader and the
    /// only question that matters is which step it died on. Without the log,
    /// "the update did not finish" is the whole of what anybody can report.
    @Published private(set) var log: [String] = []
    /// True once the library has told the wrap to jump into its bootloader. From
    /// that moment the wrap may be stranded, whether or not the phone can currently
    /// see it, and "it kept the firmware it had and still works" would be a lie.
    @Published private(set) var jumped = false
    /// True when the attempt never got a link at all. That one is either a wrap
    /// that went back to sleep or a wrap already sitting in its bootloader from an
    /// earlier attempt, and the advice for the two is different.
    @Published private(set) var neverConnected = false

    private var controller: DFUServiceController?
    /// Kept so the failed state can offer another go at the same wrap without
    /// making somebody find it in the list again, which on a wrap that is now
    /// sitting in its bootloader is not possible by shaking it.
    private(set) var lastTarget: FoundWrap?

    static var bundledZip: URL? {
        Bundle.main.url(forResource: "firmware", withExtension: "zip")
    }

    static var bundledVersion: String {
        guard let url = Bundle.main.url(forResource: "firmware-version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(_ wrap: FoundWrap) {
        guard let zip = Updater.bundledZip else {
            phase = .failed("no firmware is bundled with this build of the app")
            return
        }
        guard let peripheral = WrapCentral.shared.peripheral(wrap.id) else {
            phase = .failed("the phone cannot see that wrap any more")
            return
        }

        let firmware: DFUFirmware
        do {
            firmware = try DFUFirmware(urlToZipFile: zip)
        } catch {
            phase = .failed("the bundled firmware package would not open: \(error.localizedDescription)")
            return
        }

        target = wrap
        lastTarget = wrap
        phase = .connecting
        progress = 0
        log.removeAll()
        jumped = false
        neverConnected = true       // cleared by the first state past connecting
        detail = wrap.inBootloader ? "Picking the update back up" : "Waking the wrap's bootloader"

        let initiator = DFUServiceInitiator().with(firmware: firmware)
        initiator.delegate = self
        initiator.progressDelegate = self
        initiator.logger = self

        // The handoff, which is the part that was failing.
        //
        // The wrap leaves the conversation as itself and comes back as its
        // bootloader: a different name (AdaDFU), a different set of services, and
        // possibly a different Bluetooth address. Whether the address changes
        // depends on whether the firmware managed to hand its own address over
        // before jumping, so the library must not be told to expect one case or
        // the other. Scanning covers both, because the bootloader advertises
        // openly and says who it is.
        //
        // alternativeAdvertisingNameEnabled used to be set here instead. It is
        // ignored in Legacy DFU, which is what these wraps speak, so it did
        // nothing at all and the library sat waiting for a peripheral that had
        // already come back under another identity.
        initiator.forceScanningForNewAddressInLegacyDfu = true
        initiator.peripheralSelector = BootloaderSelector()
        // Ten seconds is the library's default and it is not enough here: a wrap
        // that has dropped a power tier advertises every 2.5 s, and the bootloader
        // takes a moment to come up after the jump.
        initiator.connectionTimeout = 25

        // EVERY link this app holds has to be gone first, not just the link to the
        // wrap being updated, and gone means the disconnect has landed rather than
        // been asked for.
        //
        // This was `release(wrap.id)` and that is why updates timed out. A wrap
        // accepts one connection and stops advertising while it has one. The
        // bootloader is a different peripheral identifier from the running
        // firmware, so on any update that targets the bootloader, releasing the
        // target released nothing: the pilot page's link to the application stayed
        // up, the wrap went quiet, and the DFU library spent twenty five seconds
        // failing to find a board that was connected to us the entire time.
        WrapCentral.shared.stopScan()
        WrapCentral.shared.releaseAll { [weak self] in
            self?.controller = initiator.start(target: peripheral)
        }
    }

    /// Picks the update back up. A wrap in bootloader mode is advertising on the
    /// board's Bluetooth address PLUS ONE, so iOS files it as a different
    /// peripheral, and the identifier this update started against stops answering
    /// the moment the jump succeeds.
    ///
    /// So a visible bootloader wins over the wrap that was originally chosen. This
    /// used to retry the original identifier, which after a successful jump and a
    /// failed transfer can only ever time out: twenty five seconds of waiting on a
    /// peripheral that no longer exists, reported as a wrap that will not connect,
    /// with the real one advertising every 25 ms in the same room. Pressing the
    /// button again did the same thing again.
    /// A bootloader only counts if it is on the air NOW. It advertises every 25 ms,
    /// so one that has not been heard for six seconds is not there, and aiming at it
    /// buys nothing but another timeout. The list used to be frozen the moment an
    /// update began, so this kept picking a bootloader that had been gone for
    /// minutes and reporting the healthy wrap next to it as stranded.
    static let bootloaderGrace: TimeInterval = 6

    func retry() {
        let live = WrapCentral.shared.found
        let boot = live.first {
            $0.inBootloader
                && Date().timeIntervalSince($0.seen) < Updater.bootloaderGrace
        }
        // The target must be a row in the LIVE list. It used to fall back to
        // `lastTarget` unconditionally, which is a value held in memory rather than
        // a thing on the air, so once the wrap it named had gone this spent twenty
        // five seconds connecting to nothing and reported a wrap that would not
        // connect. Pressing the button again did the same thing again. Nothing to
        // aim at is worth saying out loud in one second instead.
        guard let wrap = boot ?? live.first(where: { $0.id == lastTarget?.id }) else {
            phase = .failed("nothing is answering right now, so there is nothing to "
                          + "send this to. Shake the wrap, wait for it to appear "
                          + "below, and press Update on it.")
            detail = ""
            neverConnected = true
            WrapCentral.shared.startScan()
            return
        }
        start(wrap)
    }

    func cancel() {
        _ = controller?.abort()
        controller = nil
        phase = .idle
        detail = ""
        progress = 0
    }
}

/// Which peripheral the library may treat as "that wrap, in bootloader mode"
/// while it is scanning for the far side of the handoff.
///
/// The default selector takes the first thing advertising the DFU service UUID,
/// which is wrong in a room with two wraps in it: the running firmware mentions
/// the DFU service in its scan response as well, so the library could pick up the
/// pilot's other wrap and push a bootloader onto a board nobody chose. The
/// bootloader calls itself AdaDFU and the firmware never does, so the name is the
/// honest test, and it is read from the advertisement rather than from
/// peripheral.name, which iOS caches and will still be reporting the old one.
final class BootloaderSelector: DFUPeripheralSelector {
    override func select(_ peripheral: CBPeripheral,
                         advertisementData: [String: AnyObject],
                         RSSI: NSNumber,
                         hint name: String?) -> Bool {
        let advertised = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        return advertised.lowercased().hasPrefix("adadfu")
    }
}

extension Updater: DFUServiceDelegate {
    func dfuStateDidChange(to state: DFUState) {
        switch state {
        case .connecting:      phase = .connecting; detail = "Connecting"
        case .starting:
            phase = .connecting; detail = "Starting the update"
            neverConnected = false
        case .enablingDfuMode:
            phase = .connecting; detail = "Rebooting into the bootloader"
            neverConnected = false
            jumped = true
        case .uploading:       phase = .sending;    detail = "Sending the firmware"
        case .validating:      phase = .sending;    detail = "The wrap is checking the image"
        case .disconnecting:   phase = .sending;    detail = "Finishing"
        case .completed:
            phase = .done
            detail = "Updated. The wrap has restarted on the new firmware."
            progress = 1
            controller = nil
            // Scanning was stopped for the duration so the two scans did not
            // fight. Putting it back is what makes the wrap reappear in the list
            // on its new firmware, which is also the proof that it came back.
            WrapCentral.shared.startScan()
        case .aborted:
            phase = .idle
            detail = "Stopped. The wrap kept the firmware it had."
            controller = nil
            WrapCentral.shared.startScan()
        // The library adds states between releases, and a new one is not a
        // failure: the update is still running, so the screen says so rather
        // than showing stale text or claiming to be finished.
        default:
            detail = "Working"
        }
    }

    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        // Said in full, including the library's own message and the error case it
        // came from. An update that fails silently leaves somebody in another
        // country holding a board they think is broken, and "failed" on its own
        // does not distinguish a bootloader that was never found from an image
        // the bootloader rejected after writing all of it.
        phase = .failed("\(message) (\(error))")
        detail = ""
        log.append("ERROR \(error): \(message)")
        controller = nil
        // Back to scanning straight away, and this is not housekeeping: if the
        // jump succeeded and only the upload failed, the wrap is sitting in its
        // bootloader right now and the scan is the only thing that can find it.
        // It shows up as AdaDFU, with Finish update next to it.
        WrapCentral.shared.startScan()
    }
}

extension Updater: DFUProgressDelegate {
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to percentage: Int,
                              currentSpeedBytesPerSecond: Double,
                              avgSpeedBytesPerSecond: Double) {
        progress = Double(percentage) / 100.0
        detail = "Sending the firmware, \(percentage)%"
    }
}

extension Updater: LoggerDelegate {
    func logWith(_ level: LogLevel, message: String) {
        NSLog("DFU [\(level.rawValue)] \(message)")
        // loggerQueue defaults to the main queue, which is where every other
        // published property here is written from, so this needs no hop.
        // Trimmed from the front: the tail is the part that says what went wrong,
        // and an unbounded log on a retried update grows without limit.
        log.append(message)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

struct UpdateView: View {

    @ObservedObject private var central = WrapCentral.shared
    @StateObject private var updater = Updater()
    /// Set by tapping a wrap, cleared by answering the confirmation.
    ///
    /// An update is not a safe thing to start by accident on these wraps. The
    /// bootloader erases the application before a byte of the new image arrives,
    /// so an update that does not finish leaves a wrap that cannot punch, cannot
    /// be woken by shaking, and needs a computer and a cable to come back. It also
    /// loses the wrap's stored identity, which is a new random unit id and the hand
    /// assignment gone. Over the air is not reliable on these boards yet, so this
    /// tap says what it costs before it does it.
    @State private var confirming: FoundWrap?

    var body: some View {
        NavigationView {
            List {
                Section {
                    switch updater.phase {
                    case .idle:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Updating over Bluetooth is not reliable on these wraps "
                                 + "yet. It can leave a wrap that needs a computer and a "
                                 + "cable to come back, and it loses the wrap's hand "
                                 + "setting. Use a cable if you have one.")
                                .font(.footnote).foregroundColor(.orange)
                            Text("Wake a wrap by shaking it, pick it below, and it will be "
                                 + "updated over Bluetooth. Keep the phone next to it. A wrap "
                                 + "leaves the list when it goes back to sleep, so if it is not "
                                 + "there, shake it again.")
                                .font(.footnote).foregroundColor(.secondary)
                        }
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
                        // Two failures that look identical and need opposite
                        // advice. If the jump never happened the wrap is fine and
                        // wants shaking; if the jump happened and the upload did
                        // not, the wrap is sitting in its bootloader where shaking
                        // it does nothing at all, because the firmware that would
                        // feel the shake is not the thing that is running.
                        // `jumped` counts as stranded on its own. The phone cannot
                        // always see the bootloader at the moment it looks, and a
                        // wrap that was told to jump has already had its
                        // application erased, so promising it "still works" on the
                        // strength of an empty scan list is the one wrong answer.
                        // The bootloader half of this has to be a LIVE reading. It
                        // was any bootloader row at all, on a list that stopped
                        // ageing out the moment an update began, so one interrupted
                        // update in the past made this screen insist for ever that a
                        // healthy wrap was waiting in update mode and had to be left
                        // powered. The wrap was running its firmware, advertising,
                        // and connected to this very app while the screen said it.
                        let stranded = updater.jumped
                            || central.found.contains {
                                $0.inBootloader
                                    && Date().timeIntervalSince($0.seen)
                                        < Updater.bootloaderGrace
                            }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(stranded ? "That wrap is waiting in update mode"
                                           : "The update did not finish",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.footnote)
                            Text(why).font(.caption).foregroundColor(.secondary)
                            Text(stranded
                                 ? "Until an update finishes it cannot punch, and shaking it "
                                   + "will not wake it. Press Finish update with the phone next "
                                   + "to it. If that does not take, plug it into a computer and "
                                   + "put the firmware back over the cable, which always works."
                                 : updater.neverConnected
                                   ? "The phone never got a link at all, so either the wrap went "
                                     + "back to sleep, or it is already in update mode from an "
                                     + "earlier try and is answering on a different address. "
                                     + "Shake it and look for a wrap in update mode below."
                                   : "The wrap kept the firmware it had and still works. Shake it "
                                     + "awake, wait for it to appear below, and press Update again.")
                                .font(.caption).foregroundColor(.secondary)
                            if stranded {
                                Text("Leave it powered. If it loses power in this state it "
                                     + "comes back needing a cable instead of the app.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            if updater.lastTarget != nil {
                                Button(stranded ? "Finish update" : "Try again") { updater.retry() }
                                    .font(.footnote)
                            }
                            // The log, on the screen, because the phone is the only
                            // thing in the room when this fails and the step it died
                            // on is the whole diagnosis.
                            if !updater.log.isEmpty {
                                // Sixteen rather than six. Six lines is exactly the
                                // tail that every one of these failures shares, so
                                // every screenshot looked identical and none of them
                                // said which step it died on: whether the wrap was
                                // ever connected, whether it was told to jump, and
                                // whether a bootloader was found by scanning are all
                                // further up, and they are the whole diagnosis.
                                Text(updater.log.suffix(16).joined(separator: "\n"))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                Button("Copy the whole log") {
                                    UIPasteboard.general.string =
                                        updater.log.joined(separator: "\n")
                                }
                                .font(.footnote)
                            }
                        }
                    }
                } header: {
                    Text("Firmware in this app: \(Updater.bundledVersion)")
                }

                Section("Wraps nearby") {
                    if central.found.isEmpty {
                        Text(central.poweredOn
                             ? "Nothing yet. Shake a wrap to wake it."
                             : "Bluetooth is off for this app. Turn it on in Settings.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(central.found.sorted { $0.rssi > $1.rssi }) { wrap in
                        Button {
                            confirming = wrap
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wrap.inBootloader ? "A wrap in update mode" : wrap.name)
                                    // A connected wrap has no signal reading to
                                    // show: RSSI comes from advertisements and a
                                    // connected wrap has stopped sending them.
                                    // Printing "signal 0 dBm" would read as a
                                    // measurement, and a suspiciously good one.
                                    Text(wrap.inBootloader
                                         ? "Its last update stopped part way, signal \(wrap.rssi) dBm"
                                         : wrap.connected
                                           ? "Connected to this phone"
                                           : "signal \(wrap.rssi) dBm")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if updater.target?.id == wrap.id,
                                   updater.phase == .connecting || updater.phase == .sending {
                                    ProgressView()
                                } else {
                                    Text(wrap.inBootloader ? "Finish update" : "Update")
                                        .font(.footnote)
                                }
                            }
                        }
                        .disabled(updater.phase == .connecting || updater.phase == .sending)
                    }
                }

                Section {
                    Text("An update needs the phone and the wrap in the same room: "
                         + "Bluetooth reaches a few metres and nothing about this goes "
                         + "over the internet. It takes a minute or two per wrap.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Update")
            .onAppear { central.startScan() }
            .onDisappear {
                if updater.phase != .sending && updater.phase != .connecting {
                    central.stopScan()
                }
            }
            .alert("Update this wrap over Bluetooth?",
                   isPresented: Binding(get: { confirming != nil },
                                        set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { wrap in
                Button("Update anyway", role: .destructive) {
                    let target = wrap
                    confirming = nil
                    updater.start(target)
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: { _ in
                Text("The wrap's firmware is erased before any of the new firmware "
                   + "arrives, so an update that does not finish leaves a wrap that "
                   + "cannot punch and cannot be woken by shaking. Getting it back "
                   + "needs a computer and a cable. It also loses the wrap's hand "
                   + "setting and its unit id.\n\n"
                   + "Updates over Bluetooth are not reliable on these wraps yet. If "
                   + "you have a cable, use that instead.")
            }
        }
    }
}
