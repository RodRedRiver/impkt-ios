import Foundation

/// Which wrap a punch came off.
///
/// The product is a pair and both hands are always instrumented, so this is never a
/// question put to anybody: the wrap knows, and it says so in the identity
/// characteristic. `unknown` is for a punch that arrived before that read landed, or
/// off a board too old to have an identity at all, and it is counted on the board but
/// left out of the left against right split rather than guessed into one side of it.
enum Hand: String, Codable {
    case left = "L", right = "R", unknown = "?"

    var word: String {
        switch self {
        case .left:    return "Left"
        case .right:   return "Right"
        case .unknown: return "Unknown"
        }
    }

    var other: Hand { self == .left ? .right : .left }
}

/// One punch, as the wrap reports it, plus the one number a gym wants off it.
///
/// The record is the firmware's `punch_packet_t`, twenty bytes, little endian, fixed
/// so it fits a default 23 byte ATT MTU without negotiating one. The pilot page reads
/// two of those bytes and ignores the rest, because a guided drill only needs to know
/// that a punch happened and roughly how hard. A leaderboard needs the rest.
struct Punch: Identifiable, Equatable {

    let id = UUID()
    let at = Date()

    /// The firmware's own power score, a weighted blend of peak acceleration and hand
    /// speed. Kept because it is what the page shows and the two screens should not
    /// disagree about the same punch.
    let score: Double
    /// Peak linear acceleration, in g, gravity already removed. Stops at the rail.
    let peakG: Double
    /// Peak raw acceleration magnitude, in g, gravity still in it.
    let rawG: Double
    /// Peak hand speed, in metres per second.
    let speed: Double
    /// Peak rotation rate, in degrees per second.
    let spin: Double
    /// The detector's extension window, in seconds.
    let window: Double
    /// Samples that reached the top of the accelerometer's range.
    let railed: Int
    /// The peak the firmware built its score from, in g. On v2.21 and later this is the
    /// reconstructed peak when the punch went off the top of the scale and a copy of
    /// `peakG` when it did not. Zero from anything older, which had a punch count here.
    let builtPeak: Double
    let seq: Int
    let flags: Int

    /// Which wrap threw it. Filled in by `WrapCentral`, which is the only thing that
    /// knows: the hand is a property of the board, not of the punch, so it is not in
    /// the packet and there is no room for it there anyway.
    var hand: Hand = .unknown

    /// A punch thrown while the link was down, arriving late.
    ///
    /// These are dropped by the leaderboard rather than counted. The board attributes a
    /// punch to whoever is standing at the bag when it lands, and a punch that was
    /// thrown a minute ago in someone else's turn would be credited to the person who
    /// is up now. A count that is one short is a smaller wrong than a name that did not
    /// earn its number.
    var replay: Bool { flags & 0x04 != 0 }

    /// The board rebuilt the top of this punch's curve, so `score` and `builtPeak` are
    /// the reconstruction and not the rail. Firmware v2.21 and later.
    var rebuilt: Bool { flags & 0x08 != 0 }

    // MARK: - reading the wire

    /// The twenty byte record. Nil for anything shorter, which is not this packet.
    static func record(_ data: Data) -> Punch? {
        guard data.count >= 20 else { return nil }
        let u16: (Int) -> Int = { at in
            Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8
        }
        // Offset 18 held a punch count up to v2.20, which was the same number as seq at
        // offset 0, so a board on the old firmware puts a punch count in builtPeak.
        // Nothing reads builtPeak unless `rebuilt` is set, and that flag bit did not
        // exist before the field did.
        return Punch(score:     Double(u16(2)) / 10,
                     peakG:     Double(u16(4)) / 1000,
                     rawG:      Double(u16(6)) / 1000,
                     speed:     Double(u16(8)) / 1000,
                     spin:      Double(u16(10)),
                     window:    Double(u16(12)) / 1000,
                     railed:    u16(14),
                     builtPeak: Double(u16(18)) / 1000,
                     seq:       u16(0),
                     flags:     Int(data[data.startIndex + 16]))
    }

    /// The four byte float on the score characteristic, which is all a wrap older than
    /// v2.2 offers.
    ///
    /// Here so that such a wrap lands on the leaderboard rather than landing nowhere.
    /// The page already falls back to this characteristic when the record is missing,
    /// and a board that punches into a screen that stays empty is the hardest kind of
    /// fault to report from a gym floor. Every field but the score is unknown, and
    /// unknown is written as zero rather than guessed at: `power` branches on it.
    static func bareScore(_ data: Data) -> Punch? {
        guard data.count >= 4 else { return nil }
        let bits = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let score = Double(Float(bitPattern: UInt32(littleEndian: bits)))
        guard score.isFinite, score > 0 else { return nil }
        return Punch(score: score, peakG: 0, rawG: 0, speed: 0, spin: 0,
                     window: 0, railed: 0, builtPeak: 0, seq: 0, flags: 0)
    }
}

// MARK: - the number on the board

extension Punch {

    /// The firmware's own weights, repeated here for one reason only: a board too old to
    /// rebuild a clipped peak has a score that cannot be trusted, and the rebuild below
    /// has to land on the same scale as the boards that can, or a gym running one of each
    /// would have two different ideas of what 90 means.
    static let accelWeight = 4.0
    static let velocityWeight = 6.0

    /// Where the part stops measuring, in g. The LSM6DS3TR is set to its widest range
    /// and that range ends at 15.99 g. There is no wider setting on this part.
    static let rail = 16.0

    /// Accelerometer sample rate during a punch, in hertz. Set in the firmware's
    /// CTRL1_XL, and the only way `railed` becomes a length of time.
    static let sampleRate = 833.0

    /// Nominal rise rate of the acceleration curve, in g per second, and the reference
    /// speed it is quoted at. Only the old-firmware path uses these. See `peak`.
    static let nominalRamp = 3200.0
    static let referenceSpeed = 6.0
    static let rampRange = 0.6 ... 1.8

    /// Power. The number on the board and the headline on the screen.
    ///
    /// Unitless on purpose. It is the firmware's own blend of how hard the hand was
    /// accelerating and how fast it was moving, which is a real measurement of a real
    /// punch, and putting a kilogram on it would be claiming a conversion to force at
    /// the glove that nothing here measures.
    ///
    /// Almost always straight off the board, because the board is the thing holding the
    /// samples. The exception is a punch that went off the top of the accelerometer's
    /// range on firmware older than v2.21, where the score was built from a peak pinned
    /// to the rail and is therefore too low by an amount that grows with how hard the
    /// punch was. That is the one case worth second-guessing the board about, and `peak`
    /// is how.
    var power: Int {
        if rebuilt || railed == 0 { return Int(score.rounded()) }
        return Int((Punch.accelWeight * peak + Punch.velocityWeight * speed).rounded())
    }

    /// Peak acceleration in g: the board's own number when it has one, and otherwise the
    /// top of the curve put back on here.
    ///
    /// From v2.21 the firmware does this itself and does it better, because it has the
    /// samples: it measures the rate the curve climbed onto the rail and the rate it came
    /// off, extends both edges, and takes the crossing. Everything in that is measured
    /// from the punch in hand. This version cannot be, because the only things that
    /// survive into the packet are how long the curve sat on the rail and how fast the
    /// hand was going, so the climb rate is a constant scaled by hand speed.
    ///
    /// Kept for the boards that are still on 2.16 and 2.20. What it has to be is
    /// monotonic, which it is in both of its terms: no two punches of different strengths
    /// can tie, and a harder one cannot score lower. Ranking a line of people at a bag is
    /// the whole job, and this ranks them.
    var peak: Double {
        if rebuilt, builtPeak > 0 { return builtPeak }
        let base = max(peakG, rawG - 1)
        guard railed > 0 else { return base }
        let scale = min(max(speed / Punch.referenceSpeed, Punch.rampRange.lowerBound),
                        Punch.rampRange.upperBound)
        let ramp = Punch.nominalRamp * scale
        let seconds = Double(railed) / Punch.sampleRate
        return max(base, Punch.rail) + ramp * seconds / 2
    }
}
