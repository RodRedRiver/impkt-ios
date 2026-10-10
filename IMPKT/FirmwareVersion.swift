import Foundation

/// What pressing the update button on a wrap would do, given what the wrap says it runs.
///
/// Its own file, and Foundation only, so the logic can be tested with `swiftc` alone: no
/// Xcode, no simulator, no phone. See tools/test-app-logic.sh.
enum FirmwareAction: Equatable {
    /// The wrap runs something older than the bundled release.
    case update
    /// The wrap already runs the bundled release. Sending it again is allowed, because it is
    /// how a wrap is put right after a bad flash, but it must not read as an update.
    case reinstall
    /// The wrap runs something newer than the bundled release.
    case replace
    /// The wrap has not said, which is every wrap that is only being heard and not connected.
    case install

    func label(_ bundled: String) -> String {
        switch self {
        case .update:    return "Update to \(bundled)"
        case .reinstall: return "Reinstall \(bundled)"
        case .replace:   return "Install \(bundled)"
        case .install:   return "Install \(bundled)"
        }
    }
}

enum FirmwareVersion {

    /// True when `a` is a later release than `b`. Compared as numbers, field by field, so 2.9 is
    /// older than 2.10, and false whenever either side is missing: an update is only offered
    /// when the app can say why.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").compactMap { Int($0) }
        let y = b.split(separator: ".").compactMap { Int($0) }
        guard !x.isEmpty, !y.isEmpty else { return false }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// True when both parse and every field is equal. "2.24" and "2.24.0" are the same release.
    static func isSame(_ a: String, as b: String) -> Bool {
        let x = a.split(separator: ".").compactMap { Int($0) }
        let y = b.split(separator: ".").compactMap { Int($0) }
        guard !x.isEmpty, !y.isEmpty else { return false }
        return !isNewer(a, than: b) && !isNewer(b, than: a)
    }

    /// `reported` is "" when the wrap did not say.
    static func action(bundled: String, reported: String) -> FirmwareAction {
        if reported.isEmpty { return .install }
        if isSame(bundled, as: reported) { return .reinstall }
        return isNewer(bundled, than: reported) ? .update : .replace
    }
}
