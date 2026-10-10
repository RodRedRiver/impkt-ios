import Foundation

/// Every Bluetooth step the app takes for the page, and every answer it gets, in order, with the
/// time. Kept so a connect that fails on somebody's phone can be copied off the Devices tab and
/// read somewhere else, because "would not connect" on its own says nothing about which step it was.
///
/// Foundation only, like FirmwareVersion, so tools/test-app-logic.sh can test it with swiftc.
final class ConnectionLog {

    static let shared = ConnectionLog()

    /// Enough for several attempts at a connect, each of which is a few dozen lines, and small
    /// enough to paste into a message.
    let limit: Int
    private(set) var lines: [String] = []
    private let clock: () -> Date
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(limit: Int = 400, clock: @escaping () -> Date = Date.init) {
        self.limit = limit
        self.clock = clock
    }

    func add(_ line: String) {
        let write = {
            self.lines.append("\(self.stamp.string(from: self.clock()))  \(line)")
            if self.lines.count > self.limit { self.lines.removeFirst(self.lines.count - self.limit) }
        }
        // CoreBluetooth calls back on the main queue in this app, but a line must never be lost
        // or torn because one arrived from somewhere else.
        if Thread.isMainThread { write() } else { DispatchQueue.main.async(execute: write) }
    }

    func clear() { lines.removeAll() }

    /// What gets copied: a header that says which build and which firmware, then the lines.
    func text(header: [String]) -> String {
        (header + ["", lines.isEmpty ? "(nothing logged yet)" : lines.joined(separator: "\n")])
            .joined(separator: "\n")
    }

    /// A UUID as its first eight characters, which is unique for everything this app talks to and
    /// keeps a line readable: 6e2a0002 is the punch record, 00002a26 the firmware version.
    static func short(_ uuid: String) -> String {
        String(uuid.lowercased().prefix(8))
    }

    /// One bridge request, as a line.
    static func describe(op: String, args: [String: Any]) -> String {
        var parts = [op]
        if let d = args["device"] as? String { parts.append("wrap \(short(d))") }
        if let c = args["characteristic"] as? String { parts.append("char \(short(c))") }
        if let on = args["on"] as? Bool { parts.append(on ? "on" : "off") }
        return parts.joined(separator: " ")
    }

    /// One bridge answer, as a line. Failures carry the error's name and message in full.
    static func outcome(ok: Bool, _ out: [String: Any]) -> String {
        if ok {
            if let d = out["data"] as? String, let bytes = Data(base64Encoded: d) {
                return "ok, \(bytes.count) bytes"
            }
            if let s = out["services"] as? [[String: Any]] {
                let ids = s.compactMap { $0["uuid"] as? String }.map(short)
                return "ok, services \(ids.joined(separator: ","))"
            }
            if let list = out["devices"] as? [[String: Any]] { return "ok, \(list.count) wrap(s)" }
            return "ok"
        }
        let name = out["name"] as? String ?? "Error"
        let message = out["message"] as? String ?? "no message"
        return "FAILED \(name): \(message)"
    }
}
