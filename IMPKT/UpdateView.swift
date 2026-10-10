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
    /// Which of the two bundled releases the last attempt was installing, so that Try again means the same one.
    private(set) var lastWasPrevious = false
    /// The version the attempt in progress is installing, for the screen to say.
    @Published private(set) var installing = ""

    static var bundledZip: URL? {
        Bundle.main.url(forResource: "firmware", withExtension: "zip")
    }

    /// The release before the bundled one, kept so that an update which goes wrong, or a release that turns
    /// out worse than the one it replaced, can always be undone from the phone. Optional: a build without it
    /// simply offers no way back.
    static var previousZip: URL? {
        Bundle.main.url(forResource: "firmware-previous", withExtension: "zip")
    }

    static var previousVersion: String? {
        guard previousZip != nil,
              let url = Bundle.main.url(forResource: "firmware-previous-version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// See FirmwareVersion, which holds the comparison so it can be tested on its own.
    static func isNewer(_ a: String, than b: String) -> Bool {
        FirmwareVersion.isNewer(a, than: b)
    }

    static var bundledVersion: String {
        guard let url = Bundle.main.url(forResource: "firmware-version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(_ wrap: FoundWrap, previous: Bool = false) {
        guard let zip = previous ? Updater.previousZip : Updater.bundledZip else {
            phase = .failed("no firmware is bundled with this build of the app")
            return
        }
        lastWasPrevious = previous
        installing = previous ? (Updater.previousVersion ?? "") : Updater.bundledVersion
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
        //
        // The address does NOT change on this path, which is the opposite of what
        // this code assumed. Adafruit's BLEDfu stashes peer data in RAM at
        // 0x20007F80 before it resets, and the bootloader, finding that data valid,
        // skips the `addr.addr[0] += 1` it would otherwise apply. So the wrap comes
        // back in its bootloader on its own address, as the same iOS peripheral.
        //
        // Scanning is still what the library should do, because it is the only way
        // to know the bootloader is actually up and advertising before trying to
        // talk to it, and the selector matches on the advertised name. But nothing
        // here may assume a new identity, and the rest of the app no longer does.
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
        // takeRadio rather than stopScan, because stopping it is not the same as
        // keeping it stopped: the pilot page asks for a scan whenever it looks for a
        // wrap, and the Devices tab asks for one every time it appears. Either would
        // have started one underneath the transfer.
        WrapCentral.shared.takeRadio()
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

    /// `previous` picks the release to send: nil means the same one the last attempt was sending.
    func retry(previous: Bool? = nil) {
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
            // giveBackRadio and not startScan: nothing is being updated, so whatever
            // an earlier attempt left set has to come off before a scan is allowed.
            WrapCentral.shared.giveBackRadio()
            return
        }
        start(wrap, previous: previous ?? lastWasPrevious)
    }

    func cancel() {
        _ = controller?.abort()
        controller = nil
        phase = .idle
        detail = ""
        progress = 0
        // Also here, and not only in the .aborted state the library is expected to
        // report: an abort that never lands would otherwise leave the radio held for
        // the rest of the launch, with every scan in the app quietly refused.
        WrapCentral.shared.giveBackRadio()
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
            WrapCentral.shared.giveBackRadio()
        case .aborted:
            phase = .idle
            detail = "Stopped. The wrap kept the firmware it had."
            controller = nil
            WrapCentral.shared.giveBackRadio()
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
        WrapCentral.shared.giveBackRadio()
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
