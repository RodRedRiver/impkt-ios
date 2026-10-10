import Foundation
import CoreBluetooth

/// One wrap the phone can currently see.
struct FoundWrap: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var seen: Date
    var connected: Bool = false
    /// True when this is not the wrap's firmware answering but its bootloader: an
    /// update was started and did not finish. It still speaks DFU, so it is still
    /// recoverable, but nothing else about it works and shaking it does nothing.
    var inBootloader: Bool = false
}

/// Every Bluetooth conversation in the app goes through here: the pilot page's
/// bridge, and the update screen's device list. One central manager, because iOS
/// gives an app one radio and two managers fighting over it is a class of bug
/// that only shows up on a bench with two wraps and a low battery.
///
/// Wraps are recognised by the punch service UUID in their advertisement, not by
/// name. Names are being handed out by the crate now (Impktband 1, 2, 3...), so
/// anything keyed on a name prefix would quietly stop finding boards the day one
/// was renamed. The service UUID is in the firmware and does not move.
final class WrapCentral: NSObject, ObservableObject {

    static let shared = WrapCentral()

    static let punchService  = CBUUID(string: "6e2a0001-b5a3-f393-e0a9-e50e24dcca9e")
    /// The twenty byte punch record, and the bare float score a wrap older than v2.2
    /// offers instead of it.
    ///
    /// Named here because the Leaderboard tab reads the punches off the same
    /// notifications the page is already subscribed to, rather than opening a second
    /// subscription of its own. See `lastPunch`.
    static let punchData     = CBUUID(string: "6e2a0002-b5a3-f393-e0a9-e50e24dcca9e")
    static let punchScore    = CBUUID(string: "6e2a0003-b5a3-f393-e0a9-e50e24dcca9e")
    /// Identity: which hand this wrap is on, and which pair it belongs to. Read by the
    /// page when it brings a wrap up, which is the only reason this is here: the read
    /// passes through this object on its way back, so the hand can be learned by
    /// watching rather than by asking the wrap a second time on a link somebody else
    /// owns. See `hands`.
    static let punchIdent    = CBUUID(string: "6e2a0009-b5a3-f393-e0a9-e50e24dcca9e")
    /// Nordic's legacy DFU service, which is what the Adafruit bootloader and the
    /// running firmware both speak. Its presence on a connected wrap is the proof
    /// that an over-the-air update will be accepted.
    static let dfuService    = CBUUID(string: "00001530-1212-efde-1523-785feabcd123")

    /// iOS has no connect timeout. `connect` is a standing request: if the wrap
    /// went to sleep between advertising and being tapped, CoreBluetooth waits
    /// for it to come back, for ever, saying nothing. That is the whole of "it
    /// says failed to connect" on one side and "it just sits on Connecting" on
    /// the other, so every connect this app makes gets a deadline of its own.
    static let connectTimeout: TimeInterval = 12
    /// How long a wrap stays in the nearby list after its last advertisement.
    /// The slowest thing the firmware does is a 5 s advertisement in its deepest
    /// idle tier, so this is that twice over plus a margin: long enough that a
    /// couple of missed packets do not make a row flicker, short enough that a
    /// wrap which has actually gone is gone from the screen. A row that outlives
    /// the wrap it names is a row that can only fail when pressed.
    static let staleAfter: TimeInterval = 15
    /// How often a connected wrap's signal strength is read off the link itself.
    ///
    /// A connected wrap stops advertising, so this is the only live reading that
    /// exists while the link is up. Without it the strength on screen keeps
    /// whatever number the last advertisement carried, which is a measurement of
    /// where the wrap was before it was picked up: a wrap connected from across
    /// the room still read "Fair" sitting on the desk next to the phone, and that
    /// looked like a range problem in the radio rather than a stale number.
    /// Two seconds is one link round trip against a wrap that is already sending
    /// punches, so it costs nothing worth counting, and it is slow enough that the
    /// bars settle instead of twitching.
    static let rssiInterval: TimeInterval = 2

    @Published private(set) var poweredOn = false
    @Published private(set) var found: [FoundWrap] = []
    @Published private(set) var scanning = false
    /// True while a firmware update owns the radio.
    ///
    /// An update stops the scan as its first act and the DFU library runs a scan of
    /// its own to find the bootloader; a second scan on top of that is the thing that
    /// used to make an update sit for twenty five seconds finding nothing. Stopping
    /// the scan is not enough on its own, because anything can start one again: the
    /// page does when it looks for a wrap, and a screen does when it appears. So the
    /// flag refuses them for the duration rather than trusting every caller to ask.
    @Published private(set) var updating = false

    /// The last punch any connected wrap reported, read off the notification on its way
    /// past to the page.
    ///
    /// A tap and not a second subscription. The page connects the wraps and subscribes
    /// to their punch characteristic, and a native screen that wanted its own link to
    /// the same wrap would be the one thing a wrap refuses: it accepts exactly one
    /// connection, and asking for a second is how a tab ends up staring at a board that
    /// is working perfectly and talking to somebody else. So the record is parsed where
    /// it already arrives and published, and both the page and the Leaderboard see every
    /// punch with nothing competing for the radio.
    ///
    /// Every punch is a new value, so this can be observed as a stream: the record
    /// carries a sequence number and the struct stamps its own identity and time.
    @Published private(set) var lastPunch: Punch?

    /// Which hand each wrap is on, learned by watching the page read the identity
    /// characteristic.
    ///
    /// Not from the advertised name, although the hand is in it: a board that has been
    /// given a label of its own advertises the label INSTEAD of the derived
    /// "BOXING-01L", so the name is right until somebody names a wrap and then it is
    /// silently wrong. The identity characteristic is the board answering the question
    /// directly, and the page reads it on every wrap it brings up.
    ///
    /// Empty until that read lands, which is a second or two after a connection. Punches
    /// in that window are counted with an unknown hand rather than being held back or
    /// guessed at.
    @Published private(set) var hands: [UUID: Hand] = [:]

    /// Set by the web view: (event name, payload) delivered into the page.
    var emit: ((String, [String: Any]) -> Void)?

    private var manager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var advNames: [UUID: String] = [:]
    /// Peripherals that have advertised the punch service at least once, so a later
    /// advertisement carrying only the scan response cannot be misread as a
    /// bootloader. See `note` for why that happens and what it broke.
    private var punchSeen: Set<UUID> = []

    private typealias Reply = (Bool, [String: Any]) -> Void

    private var connectWaiters: [UUID: Reply] = [:]
    private var connectTimers:  [UUID: DispatchWorkItem] = [:]
    private var releaseWaiters: [UUID: [() -> Void]] = [:]
    private var pruneTimer: Timer?
    private var rssiTimer: Timer?
    private var servicesLeft:   [UUID: Int] = [:]
    private var readWaiters:  [String: Reply] = [:]
    private var writeWaiters: [String: Reply] = [:]
    private var notifyWaiters: [String: Reply] = [:]
    private var pickWaiter: Reply?
    private var pickDeadline: Date?
    private var pickPreferredNames: [String] = []
    private var queued: [() -> Void] = []
    /// Wraps that came back from discovery without the punch service and are being asked for it by name,
    /// once, before the connect is called a failure. See `finishConnect`.
    private var askedForPunchService: Set<UUID> = []

    private let knownKey = "impkt.known.wraps"
    /// Identifiers that have completed a connect at least once. Kept so a stale
    /// remembered identifier can be thrown away on a timeout without also throwing
    /// away a wrap that is merely asleep, which would send the pilot back through
    /// the browser's grant dialog for no reason.
    private let provenKey = "impkt.proven.wraps"

    private override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - things the app's own screens use

    func startScan() {
        // Refused while an update is in flight, whoever is asking. See `updating`.
        guard !updating else { return }
        whenReady {
            // Both services, because a wrap whose update was interrupted is
            // sitting in its bootloader advertising the DFU service and nothing
            // else. Scanning only for the punch service is why such a wrap
            // vanishes from the app entirely: the one screen that could rescue it
            // could not see it, and no amount of shaking brings it back because
            // the firmware that would feel the shake is not running.
            self.manager.scanForPeripherals(
                withServices: [WrapCentral.punchService, WrapCentral.dfuService],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            self.scanning = true
            self.startPruning()
        }
    }

    func stopScan() {
        if manager.state == .poweredOn { manager.stopScan() }
        scanning = false
        // Pruning deliberately keeps running. It used to stop here, which froze
        // `found` as a snapshot of whatever happened to be on the air at the
        // moment the scan stopped, and an update stops the scan as its first act.
        // So a wrap that had once been seen in its bootloader stayed in the list
        // for ever: the update screen kept announcing "that wrap is waiting in
        // update mode" and telling somebody to leave a healthy board powered, and
        // Finish update kept aiming at an identifier that had stopped existing the
        // moment the wrap was repaired. Not scanning is a reason to trust the list
        // LESS, not to preserve it, so the rows age out either way.
        startPruning()
    }

    /// Handed to the updater for the length of an update, and handed back afterwards.
    ///
    /// Two calls rather than a flag the updater sets itself, so that taking the radio
    /// and stopping the scan cannot come apart, and so there is one place to read to
    /// find out what they mean.
    func takeRadio() {
        stopScan()
        updating = true
    }

    func giveBackRadio() {
        updating = false
        startScan()
    }

    /// Every wrap this phone has been given permission for, whether or not it is
    /// answering right now. The page's own list of wraps comes from the same place.
    var knownWraps: [UUID] {
        (UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
            .compactMap { UUID(uuidString: $0) }
    }

    /// Rows go away when the wrap they describe stops speaking. Without this the
    /// list is a history of everything the phone has ever heard, and the update
    /// screen offers wraps that went to sleep ten minutes ago: pressing one can
    /// only fail, and it fails slowly, which reads as a broken board.
    private func startPruning() {
        guard pruneTimer == nil else { return }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            self.found.removeAll {
                !$0.connected && now.timeIntervalSince($0.seen) > WrapCentral.staleAfter
            }
        }
    }

    /// Keeps the signal strength of every connected wrap current, and stops itself
    /// the moment nothing is connected, so an app sitting on a menu is not waking
    /// the radio every two seconds for a number nobody is looking at.
    private func startRssiPolling() {
        guard rssiTimer == nil else { return }
        rssiTimer = Timer.scheduledTimer(withTimeInterval: WrapCentral.rssiInterval,
                                         repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let live = self.peripherals.values.filter { $0.state == .connected }
            guard !live.isEmpty else {
                t.invalidate()
                self.rssiTimer = nil
                return
            }
            live.forEach { $0.readRSSI() }
        }
    }

    func peripheral(_ id: UUID) -> CBPeripheral? {
        if let p = peripherals[id] { return p }
        let found = manager.retrievePeripherals(withIdentifiers: [id]).first
        if let f = found { peripherals[id] = f }
        return found
    }

    /// Disconnect before handing a wrap to the DFU library, which connects to it
    /// itself. Two connections to one peripheral is not an error on iOS, it is
    /// worse: it works, and then the update stalls halfway with no reason given.
    /// `then` runs when the link is actually down, not when the cancel was asked
    /// for. The difference matters to the updater: it used to wait a fixed 0.6 s
    /// and hope, and on a busy link the disconnect lands later than that, so the
    /// DFU library opened its connection while ours was still closing.
    func release(_ id: UUID, then done: (() -> Void)? = nil) {
        guard let p = peripherals[id], p.state != .disconnected else { done?(); return }
        if let done = done {
            releaseWaiters[id, default: []].append(done)
            // A disconnect that never arrives must not strand the caller either.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.settleRelease(id)
            }
        }
        manager.cancelPeripheralConnection(p)
    }

    /// Drops every link this app is holding, and waits for the disconnects to land.
    ///
    /// Not `release(id)`, and the difference is the whole of why updates timed out.
    /// A wrap accepts exactly ONE connection and stops advertising while it has
    /// one. An update targets the bootloader, and whether that is the same
    /// peripheral identifier as the running firmware depends on how the board got
    /// there: a jump the app asked for hands over peer data and keeps the address,
    /// a jump over the cable or a restart after an erase does not. So releasing the
    /// target could release nothing at all, and did: the pilot page's link to the
    /// application stayed up, the
    /// wrap stayed silent and unconnectable, and the DFU library waited out its
    /// twenty five seconds against a board sitting a foot away, healthy, and busy
    /// talking to us the whole time. The bench tool said it plainly from the other
    /// side of the cable: "advertising: off, a central is connected".
    func releaseAll(then done: @escaping () -> Void) {
        let live = peripherals.values.filter { $0.state != .disconnected }
        guard !live.isEmpty else { done(); return }
        var left = live.count
        var fired = false
        let finish = {
            guard !fired else { return }
            fired = true
            done()
        }
        for p in live {
            release(p.identifier) {
                left -= 1
                if left == 0 { finish() }
            }
        }
        // release() backstops each peripheral at 3 s, but a link that never
        // reports its disconnect must not hold an update up for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish() }
    }

    private func settleRelease(_ id: UUID) {
        guard let waiters = releaseWaiters.removeValue(forKey: id) else { return }
        waiters.forEach { $0() }
    }

    private func whenReady(_ work: @escaping () -> Void) {
        if manager.state == .poweredOn { work() } else { queued.append(work) }
    }

    private func remember(_ id: UUID) {
        // A wrap in bootloader mode IS the wrap, and this used to refuse to
        // remember it on the belief that it was a foreign identifier.
        //
        // That belief was wrong for the only path the app ever takes. Adafruit's
        // BLEDfu, which is what the phone writes to when it asks a wrap to jump,
        // first stashes peer data in RAM at 0x20007F80: the phone's address, the
        // GATT sys_attr table and a CRC. The bootloader reads that back, and
        // finding it valid it SKIPS the `addr.addr[0] += 1` that would otherwise
        // move it off the board's own Bluetooth address. So the bootloader comes
        // up on the same address and iOS files it as the same peripheral.
        //
        // The address only changes when nothing handed over peer data, which means
        // a jump started from the cable, or a restart after the application was
        // already erased. In the second case the bootloader is in USB mode and not
        // advertising at all, so the app never sees it either way.
        var all = UserDefaults.standard.stringArray(forKey: knownKey) ?? []
        if !all.contains(id.uuidString) {
            all.append(id.uuidString)
            UserDefaults.standard.set(all, forKey: knownKey)
        }
    }

    /// Drops a wrap from the permitted list. Asked for by the page through the bridge,
    /// and by the Forget button on the Devices tab. Reversible: the wrap is picked
    /// again the next time something needs it, and nothing on the board changes.
    func forget(_ id: UUID) {
        let all = (UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
            .filter { $0 != id.uuidString }
        UserDefaults.standard.set(all, forKey: knownKey)
    }

    private func markProven(_ id: UUID) {
        var all = UserDefaults.standard.stringArray(forKey: provenKey) ?? []
        guard !all.contains(id.uuidString) else { return }
        all.append(id.uuidString)
        UserDefaults.standard.set(all, forKey: provenKey)
    }

    private func isProven(_ id: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: provenKey) ?? []).contains(id.uuidString)
    }

    private func note(_ p: CBPeripheral, rssi: Int?, name: String?, uuids: [CBUUID] = []) {
        if let n = name, !n.isEmpty { advNames[p.identifier] = n }
        let display = advNames[p.identifier] ?? p.name ?? "A wrap"
        // The running firmware advertises the punch service and mentions DFU in
        // its scan response, so DFU alone is not the test: the bootloader is the
        // one that offers DFU and no punch service. Its name settles it either
        // way, because the Adafruit bootloader calls itself AdaDFU and the
        // firmware never does.
        //
        // The absence of the punch service is only trustworthy ONCE, though, and
        // this row gets rewritten on every advertisement. The firmware splits its
        // identity across two packets because it has to: the punch UUID is 18 of a
        // 31 byte budget, so the name and the DFU UUID live in the scan response.
        // iOS usually merges the two before handing them over and is not obliged
        // to, and a callback carrying the scan response alone looks exactly like a
        // bootloader: DFU present, punch absent. One such callback used to flip a
        // healthy wrap to "in update mode" for good, and from there it was refused
        // a place in the pilot's list, never remembered, and offered to the
        // updater as a board needing rescue.
        //
        // So the punch service is remembered per peripheral. A wrap that has ever
        // shown it is not a bootloader unless it says so by name, and the name is
        // the reliable half: when the app asks the wrap to jump it hands the
        // bootloader its peer data, and a bootloader with valid peer data keeps the
        // board's own address, so the SAME identifier comes back calling itself
        // AdaDFU. Nothing here can lean on the address changing.
        if uuids.contains(WrapCentral.punchService) { punchSeen.insert(p.identifier) }
        let looksLikeDfuOnly = uuids.contains(WrapCentral.dfuService)
            && !uuids.contains(WrapCentral.punchService)
            && !punchSeen.contains(p.identifier)
        let boot = looksLikeDfuOnly || display.lowercased().hasPrefix("adadfu")
        let row = FoundWrap(id: p.identifier, name: display,
                            rssi: rssi ?? found.first(where: { $0.id == p.identifier })?.rssi ?? -127,
                            seen: Date(), connected: p.state == .connected,
                            inBootloader: boot)
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i] = row }
        else { found.append(row) }
    }

    // MARK: - the bridge

    /// One entry point for every op the page can ask for. Unknown ops are refused
    /// out loud: a bridge that answers a call it does not implement with an empty
    /// success is the hardest kind of bug to see from inside a web page.
    func handle(op: String, args: [String: Any], reply: @escaping (Bool, [String: Any]) -> Void) {
        // Scanning is asked for every few hundred milliseconds while a search runs, and logging it
        // would push the steps of a connect out of the log before anybody could copy them.
        guard op != "scan", op != "scanStop" else { perform(op: op, args: args, reply: reply); return }
        let what = ConnectionLog.describe(op: op, args: args)
        ConnectionLog.shared.add("page asks: \(what)")
        perform(op: op, args: args) { ok, out in
            ConnectionLog.shared.add("  \(what) -> \(ConnectionLog.outcome(ok: ok, out))")
            reply(ok, out)
        }
    }

    private func perform(op: String, args: [String: Any], reply: @escaping (Bool, [String: Any]) -> Void) {
        switch op {

        case "known":
            whenReady {
                let ids = (UserDefaults.standard.stringArray(forKey: self.knownKey) ?? [])
                    .compactMap { UUID(uuidString: $0) }
                var list = self.manager.retrievePeripherals(withIdentifiers: ids)
                list += self.manager.retrieveConnectedPeripherals(
                    withServices: [WrapCentral.punchService])
                var out: [[String: Any]] = []
                var seen = Set<UUID>()
                for p in list where !seen.contains(p.identifier) {
                    seen.insert(p.identifier)
                    // A wrap sitting in its bootloader cannot punch, so it is not
                    // offered to the pilot page. It is NOT forgotten, though, and it
                    // used to be: the bootloader keeps the board's own Bluetooth
                    // address when the app asked it to jump, so forgetting it threw
                    // away the real wrap. That is permanent, it survives putting the
                    // firmware back, and it is what made a repaired wrap still
                    // refuse to connect. Being in the bootloader is a state a wrap
                    // passes through, not a different wrap.
                    if self.found.first(where: { $0.id == p.identifier })?.inBootloader == true {
                        continue
                    }
                    self.peripherals[p.identifier] = p
                    var d: [String: Any] = ["id": p.identifier.uuidString]
                    if let n = self.advNames[p.identifier] ?? p.name { d["name"] = n }
                    out.append(d)
                }
                reply(true, ["devices": out])
            }

        case "scan":
            self.startScan()
            reply(true, [:])

        case "scanStop":
            self.stopScan()
            reply(true, [:])

        case "pick":
            // The page asks for a chooser. iOS has no system chooser for this, so
            // the app picks the strongest wrap it can see: on a bench that is the
            // one in the pilot's hand, which is the answer the dialog was asking
            // for anyway. Names from the page's filter are a preference, never a
            // requirement, because a renamed board must still be findable.
            self.pickPreferredNames = (args["names"] as? [String] ?? [])
                + (args["prefixes"] as? [String] ?? [])
            self.pickWaiter = reply
            self.pickDeadline = Date().addingTimeInterval(10)
            self.startScan()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.settlePick() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) { self.settlePick(force: true) }

        case "forget":
            if let id = uuid(args) { self.forget(id) }
            reply(true, [:])

        case "connect":
            // Inside whenReady, not around the connect call alone: retrieving a
            // peripheral by identifier returns nothing at all while the radio is
            // still starting, which would answer a perfectly good connect with
            // "this phone does not know that wrap" during the first second after
            // launch.
            whenReady {
                guard let id = self.uuid(args), let p = self.peripheral(id) else {
                    reply(false, ["name": "NotFoundError",
                                  "message": "this phone does not know that wrap any more"])
                    return
                }
                p.delegate = self
                self.remember(id)
                self.beginConnect(p, reply: reply)
            }

        case "disconnect":
            if let id = uuid(args) { release(id) }
            reply(true, [:])

        case "read":
            guard let (p, c) = target(args) else { reply(false, notThere); return }
            readWaiters[key(p, c)] = reply
            p.readValue(for: c)

        case "write":
            guard let (p, c) = target(args) else { reply(false, notThere); return }
            let data = Data(base64Encoded: args["data"] as? String ?? "") ?? Data()
            let wantsAck = (args["response"] as? Bool ?? true)
                && c.properties.contains(.write)
            if wantsAck {
                writeWaiters[key(p, c)] = reply
                p.writeValue(data, for: c, type: .withResponse)
            } else {
                p.writeValue(data, for: c, type: .withoutResponse)
                reply(true, [:])
            }

        case "notify":
            guard let (p, c) = target(args) else { reply(false, notThere); return }
            let on = args["on"] as? Bool ?? true
            guard c.properties.contains(.notify) || c.properties.contains(.indicate) else {
                reply(false, ["name": "NotSupportedError",
                              "message": "that characteristic does not notify"])
                return
            }
            notifyWaiters[key(p, c)] = reply
            p.setNotifyValue(on, for: c)

        default:
            reply(false, ["name": "NotSupportedError",
                          "message": "the app bridge has no \(op)"])
        }
    }

    /// Every connect goes through here, so there is one place that owns the
    /// deadline and one place that owns the promise.
    private func beginConnect(_ p: CBPeripheral, reply: @escaping Reply) {
        let id = p.identifier
        // A second connect for the same wrap used to overwrite the first one's
        // reply, leaving a caller waiting on an answer that could never arrive.
        // Told no, out loud, instead.
        if let older = connectWaiters.removeValue(forKey: id) {
            older(false, ["name": "NetworkError",
                          "message": "that connect was replaced by a newer one"])
        }
        connectTimers.removeValue(forKey: id)?.cancel()
        connectWaiters[id] = reply

        let job = DispatchWorkItem { [weak self] in self?.connectTimedOut(p) }
        connectTimers[id] = job
        DispatchQueue.main.asyncAfter(deadline: .now() + WrapCentral.connectTimeout, execute: job)
        ConnectionLog.shared.add("connecting to \(p.name ?? "?") \(ConnectionLog.short(id.uuidString)), "
                                 + "link state \(p.state.rawValue) (0 down, 1 connecting, 2 up)")
        manager.connect(p, options: nil)
    }

    private func connectTimedOut(_ p: CBPeripheral) {
        connectTimers[p.identifier] = nil
        guard let reply = connectWaiters.removeValue(forKey: p.identifier) else { return }
        ConnectionLog.shared.add("connect TIMED OUT after \(Int(WrapCentral.connectTimeout)) s, link state "
                                 + "\(p.state.rawValue), proven before: \(isProven(p.identifier))")
        // The pending request has to be withdrawn as well as answered. Left
        // standing, it completes minutes later when the wrap next wakes, and the
        // app connects to a wrap nobody asked for any more.
        manager.cancelPeripheralConnection(p)
        // An identifier that has never once connected and does not answer now is
        // almost certainly not a wrap at all: the usual way to acquire one is a
        // failed update, which leaves the bootloader's address remembered under a
        // peripheral that no longer exists. Dropped, so the page goes back to
        // scanning and finds the real board instead of retrying a ghost for ever.
        // A wrap that HAS connected before is kept: that one is merely asleep.
        if !isProven(p.identifier) { forget(p.identifier) }
        reply(false, ["name": "NetworkError",
                      "message": "the wrap did not answer within "
                               + "\(Int(WrapCentral.connectTimeout)) seconds, which usually "
                               + "means it went back to sleep. Shake it and try again."])
    }

    /// Hands back the reply for a connect that has reached its end, whichever end
    /// that was, and cancels its deadline on the way out.
    private func settleConnect(_ id: UUID) -> Reply? {
        connectTimers.removeValue(forKey: id)?.cancel()
        return connectWaiters.removeValue(forKey: id)
    }

    private let notThere: [String: Any] = [
        "name": "NotFoundError",
        "message": "that wrap is not connected, or has no such characteristic"
    ]

    private func uuid(_ args: [String: Any]) -> UUID? {
        UUID(uuidString: args["device"] as? String ?? "")
    }

    private func key(_ p: CBPeripheral, _ c: CBCharacteristic) -> String {
        "\(p.identifier.uuidString)|\(c.uuid.uuidString.lowercased())"
    }

    /// Characteristics are looked up by UUID across every discovered service,
    /// because the page identifies them that way and they are unique on this
    /// firmware.
    private func target(_ args: [String: Any]) -> (CBPeripheral, CBCharacteristic)? {
        guard let id = uuid(args), let p = peripherals[id],
              let wanted = args["characteristic"] as? String else { return nil }
        let want = CBUUID(string: wanted)
        for s in p.services ?? [] {
            for c in s.characteristics ?? [] where c.uuid == want { return (p, c) }
        }
        return nil
    }

    private func settlePick(force: Bool = false) {
        guard let waiter = pickWaiter else { return }
        // Bootloaders are excluded outright. The scan asks for the DFU service as
        // well as the punch service, because the update screen has to be able to
        // see a stranded wrap, and a bootloader advertises every 25 ms against the
        // firmware's 803 ms. So on strength it wins this pick every time, and it is
        // the one device in the room that cannot report a punch.
        let fresh = found.filter {
            Date().timeIntervalSince($0.seen) < 6 && !$0.inBootloader
        }
        if fresh.isEmpty {
            if force || (pickDeadline.map { Date() > $0 } ?? false) {
                pickWaiter = nil
                waiter(true, [:])          // no device: the page reads this as cancelled
            }
            return
        }
        let preferred = fresh.filter { w in
            pickPreferredNames.contains { !$0.isEmpty && w.name.lowercased().hasPrefix($0.lowercased()) }
        }
        let pool = preferred.isEmpty ? fresh : preferred
        guard let best = pool.max(by: { $0.rssi < $1.rssi }) else { return }
        pickWaiter = nil
        remember(best.id)
        waiter(true, ["device": ["id": best.id.uuidString, "name": best.name]])
    }
}

extension WrapCentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        poweredOn = central.state == .poweredOn
        ConnectionLog.shared.add("bluetooth state \(central.state.rawValue)"
                                 + (poweredOn ? " (on)" : " (not on: 4 off, 3 not allowed, 1 resetting)"))
        guard poweredOn else { return }
        let work = queued
        queued = []
        work.forEach { $0() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[p.identifier] = p
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        note(p, rssi: RSSI.intValue, name: name, uuids: uuids)
        // The pilot page is never told about a bootloader. It is in `found` because
        // the update screen needs it, but to the page it would be a wrap that can
        // be listed, chosen and connected to, and then reports no punches. The one
        // screen that can do anything with it already has it.
        if found.first(where: { $0.id == p.identifier })?.inBootloader == true { return }
        emit?("advertisement", [
            "id": p.identifier.uuidString,
            "name": advNames[p.identifier] ?? p.name ?? "",
            "rssi": RSSI.intValue,
            "uuids": uuids.map { $0.uuidString.lowercased() }
        ])
        if pickWaiter != nil { settlePick() }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        ConnectionLog.shared.add("link up to \(ConnectionLog.short(p.identifier.uuidString)), discovering services")
        // Everything is discovered up front, services and characteristics both,
        // and handed to the page in one reply. The page then does its lookups
        // locally, so a screen that reads five characteristics costs one round
        // trip instead of eleven.
        p.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral,
                        error: Error?) {
        ConnectionLog.shared.add("link FAILED to open: \(error.map { "\($0)" } ?? "no error given")")
        if let reply = settleConnect(p.identifier) {
            reply(false, ["name": "NetworkError",
                          "message": error?.localizedDescription ?? "the wrap would not connect"])
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        ConnectionLog.shared.add("link DOWN from \(ConnectionLog.short(p.identifier.uuidString)): "
                                 + (error.map { "\($0)" } ?? "closed by this app"))
        if let reply = settleConnect(p.identifier) {
            reply(false, ["name": "NetworkError",
                          "message": error?.localizedDescription ?? "the wrap dropped the link"])
        }
        if let i = found.firstIndex(where: { $0.id == p.identifier }) {
            found[i].connected = false
        }
        askedForPunchService.remove(p.identifier)
        settleRelease(p.identifier)
        emit?("disconnected", ["device": p.identifier.uuidString])
    }
}

extension WrapCentral: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        // A link whose GATT table cannot be read is not a usable connection, and
        // answering the page with an empty service list turns one honest failure
        // into a handful of baffling ones: every getPrimaryService afterwards
        // fails with NotFoundError, which reads as the wrong firmware rather than
        // as a discovery that never happened.
        ConnectionLog.shared.add("services: "
            + ((p.services ?? []).map { ConnectionLog.short($0.uuid.uuidString) }.joined(separator: ","))
            + (error.map { ", error \($0)" } ?? ""))
        if let e = error {
            failConnect(p, "the wrap connected but would not say what it offers: "
                         + e.localizedDescription)
            return
        }
        let services = p.services ?? []
        if services.isEmpty {
            failConnect(p, "the wrap connected but offered no services at all")
            return
        }
        servicesLeft[p.identifier] = services.count
        for s in services { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        ConnectionLog.shared.add("  \(ConnectionLog.short(service.uuid.uuidString)) has "
            + ((service.characteristics ?? []).map { ConnectionLog.short($0.uuid.uuidString) }.joined(separator: ","))
            + (error.map { ", error \($0)" } ?? ""))
        let left = (servicesLeft[p.identifier] ?? 1) - 1
        servicesLeft[p.identifier] = left
        if left <= 0 { finishConnect(p) }
    }

    /// Ends a connect badly, and puts the link down on the way out. A half-open
    /// link the page has been told nothing about is a link nothing will ever
    /// close, and the next connect to that wrap then fails for a second reason.
    private func failConnect(_ p: CBPeripheral, _ why: String) {
        ConnectionLog.shared.add("connect FAILED: \(why)")
        servicesLeft[p.identifier] = nil
        askedForPunchService.remove(p.identifier)
        guard let reply = settleConnect(p.identifier) else { return }
        manager.cancelPeripheralConnection(p)
        reply(false, ["name": "NetworkError", "message": why])
    }

    private func finishConnect(_ p: CBPeripheral) {
        servicesLeft[p.identifier] = nil
        // A wrap with no punch service on its list is either in its bootloader or is being
        // answered from a GATT table iOS cached while it WAS in its bootloader, which is what a
        // failed update leaves behind: the table is kept against the board's address, and the
        // bootloader and the firmware share that address. Asking for the punch service BY UUID is
        // the one thing the app can do about it, because a service the cache does not hold has to
        // be looked for on the wrap itself. Once only, with the connect still open, so a wrap that
        // really is a bootloader costs one extra round trip and then fails as it did before.
        let listed = (p.services ?? []).contains { $0.uuid == WrapCentral.punchService }
        if !listed, !askedForPunchService.contains(p.identifier),
           connectWaiters[p.identifier] != nil {
            askedForPunchService.insert(p.identifier)
            ConnectionLog.shared.add("no punch service listed: asking the wrap for it by UUID")
            p.discoverServices([WrapCentral.punchService])
            return
        }
        askedForPunchService.remove(p.identifier)
        guard let reply = settleConnect(p.identifier) else { return }
        // Characteristics are the whole point of the connection. A wrap that
        // listed services and then no characteristics under any of them is the
        // same failure as one that listed no services, and is worth saying once
        // rather than five times over as the page looks each one up.
        if (p.services ?? []).allSatisfy({ ($0.characteristics ?? []).isEmpty }) {
            manager.cancelPeripheralConnection(p)
            reply(false, ["name": "NetworkError",
                          "message": "the wrap connected but none of its services "
                                   + "would list what they can do"])
            return
        }
        // A link with no punch service on it cannot report a punch, and it is worth
        // naming rather than letting the page discover it as five separate
        // NotFoundErrors later. Two things produce it: a bootloader answering, and
        // iOS handing back a GATT table it cached while the wrap WAS a bootloader.
        // Both are fixed the same way, and neither is the board being broken.
        let hasPunch = (p.services ?? []).contains { $0.uuid == WrapCentral.punchService }
        if !hasPunch {
            manager.cancelPeripheralConnection(p)
            // Deliberately NOT forgotten. This is what a wrap in its bootloader
            // looks like, and the bootloader answers on the board's own address, so
            // forgetting it here threw away the real wrap for good and no amount of
            // putting the firmware back brought it back.
            reply(false, ["name": "NotFoundError",
                          "message": "that wrap connected but is not offering the punch "
                                   + "service, so it is either still in update mode or "
                                   + "this phone is holding a stale copy of its services. "
                                   + "In the iPhone's Settings, open Bluetooth, turn it off "
                                   + "and on (or restart the phone), then connect again."])
            return
        }
        markProven(p.identifier)
        var services: [[String: Any]] = []
        for s in p.services ?? [] {
            let chars: [[String: Any]] = (s.characteristics ?? []).map { c in
                ["uuid": c.uuid.uuidString.lowercased(),
                 "properties": [
                    "read":   c.properties.contains(.read),
                    "write":  c.properties.contains(.write),
                    "notify": c.properties.contains(.notify) || c.properties.contains(.indicate)
                 ]]
            }
            services.append(["uuid": s.uuid.uuidString.lowercased(), "characteristics": chars])
        }
        // A wrap this app is connected to has to BE in the list, not merely get
        // flagged if a row for it happens to exist already. It usually does not: on
        // a fresh launch the pilot page connects straight to a remembered wrap
        // through retrievePeripherals, so there is no advertisement and no row, and
        // a connected wrap stops advertising altogether. The update screen was
        // therefore empty, and no amount of shaking could change it, because the
        // one wrap in the room was invisible exactly BECAUSE the app was talking
        // to it. Pressing Update on this row works: it drops every link first.
        if let i = found.firstIndex(where: { $0.id == p.identifier }) {
            found[i].connected = true
            found[i].seen = Date()
        } else {
            // -127, not 0, and the difference is not cosmetic: 0 dBm is the reading
            // of a wrap pressed against the antenna, so a row that had never been
            // measured claimed the strongest signal the scale has and sorted itself
            // to the top of the update list. -127 is the same "not measured yet"
            // sentinel `note` uses, and the read below replaces it within a moment.
            found.append(FoundWrap(id: p.identifier,
                                   name: advNames[p.identifier] ?? p.name ?? "This wrap",
                                   rssi: -127,
                                   seen: Date(),
                                   connected: true))
        }
        // Once now and every two seconds after, because the first reading should not
        // wait on the timer: the screen that asked for this connection is on screen.
        p.readRSSI()
        startRssiPolling()
        var payload: [String: Any] = ["services": services]
        if let n = advNames[p.identifier] ?? p.name { payload["name"] = n }
        reply(true, payload)
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        // A read that failed leaves the previous number standing, which is exactly
        // where the screen was before this poll existed. Nothing to announce.
        guard error == nil else { return }
        if let i = found.firstIndex(where: { $0.id == p.identifier }) {
            found[i].rssi = RSSI.intValue
            // `seen` is deliberately not touched. It means "last heard advertising",
            // and the update screen reads it to decide whether a wrap is still
            // sitting in its bootloader. Refreshing it from a link we are holding
            // ourselves would keep that banner up for as long as the app stayed
            // connected.
        }
        emit?("rssi", ["device": p.identifier.uuidString, "rssi": RSSI.intValue])
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        let data = c.value ?? Data()
        if let reply = readWaiters.removeValue(forKey: key(p, c)) {
            if let e = error {
                reply(false, ["name": "NetworkError", "message": e.localizedDescription])
            } else {
                reply(true, ["data": data.base64EncodedString()])
            }
            // A read and a notification arrive through the same callback, so the
            // page is told about it either way: a value that answered a read is
            // still a new value, and the page's own handler expects to see it.
        }
        // Outside the notifying gate below, because identity is only ever read, never
        // subscribed to. Byte 1 of the record is 'L', 'R', or zero for a wrap that has
        // not been told which hand it is on.
        if c.uuid == WrapCentral.punchIdent, data.count >= 2 {
            switch data[data.startIndex + 1] {
            case UInt8(ascii: "L"): hands[p.identifier] = .left
            case UInt8(ascii: "R"): hands[p.identifier] = .right
            default: break
            }
        }

        guard c.isNotifying else { return }
        // Inside the notifying gate on purpose. The punch characteristic can be READ as
        // well as subscribed to, and what a read returns is the newest punch the board
        // has stored, which on a wrap that has been sitting on a shelf is a punch
        // somebody threw yesterday. Counting one of those onto a leaderboard would put
        // a number against a name that was not in the room.
        if c.uuid == WrapCentral.punchData {
            if var punch = Punch.record(data), !punch.replay {
                punch.hand = hands[p.identifier] ?? .unknown
                lastPunch = punch
            }
        } else if c.uuid == WrapCentral.punchScore {
            // Only when the record is not coming. A wrap with both would otherwise
            // report every punch twice, once as a record and once as a score, and the
            // count on the board would be double the count on the bag.
            let rich = (p.services ?? []).contains { s in
                (s.characteristics ?? []).contains { $0.uuid == WrapCentral.punchData }
            }
            if !rich, var punch = Punch.bareScore(data) {
                punch.hand = hands[p.identifier] ?? .unknown
                lastPunch = punch
            }
        }
        emit?("notify", ["device": p.identifier.uuidString,
                         "characteristic": c.uuid.uuidString.lowercased(),
                         "data": data.base64EncodedString()])
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic,
                    error: Error?) {
        guard let reply = notifyWaiters.removeValue(forKey: key(p, c)) else { return }
        if let e = error {
            reply(false, ["name": "NetworkError", "message": e.localizedDescription])
        } else {
            reply(true, [:])
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard let reply = writeWaiters.removeValue(forKey: key(p, c)) else { return }
        if let e = error {
            reply(false, ["name": "NetworkError", "message": e.localizedDescription])
        } else {
            reply(true, [:])
        }
    }
}
