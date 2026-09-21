import Foundation

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
    /// Peak linear acceleration, in g, gravity already removed.
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
    let seq: Int
    let flags: Int

    /// A punch thrown while the link was down, arriving late.
    ///
    /// These are dropped by the leaderboard rather than counted. The board attributes a
    /// punch to whoever is standing at the bag when it lands, and a punch that was
    /// thrown a minute ago in someone else's turn would be credited to the person who
    /// is up now. A count that is one short is a smaller wrong than a name that did not
    /// earn its number.
    var replay: Bool { flags & 0x04 != 0 }

    // MARK: - reading the wire

    /// The twenty byte record. Nil for anything shorter, which is not this packet.
    static func record(_ data: Data) -> Punch? {
        guard data.count >= 20 else { return nil }
        let u16: (Int) -> Int = { at in
            Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8
        }
        return Punch(score:  Double(u16(2)) / 10,
                     peakG:  Double(u16(4)) / 1000,
                     rawG:   Double(u16(6)) / 1000,
                     speed:  Double(u16(8)) / 1000,
                     spin:   Double(u16(10)),
                     window: Double(u16(12)) / 1000,
                     railed: u16(14),
                     seq:    u16(0),
                     flags:  Int(data[data.startIndex + 16]))
    }

    /// The four byte float on the score characteristic, which is all a wrap older than
    /// v2.2 offers.
    ///
    /// Here so that such a wrap lands on the leaderboard rather than landing nowhere.
    /// The page already falls back to this characteristic when the record is missing,
    /// and a board that punches into a screen that stays empty is the hardest kind of
    /// fault to report from a gym floor. Every field but the score is unknown, and
    /// unknown is written as zero rather than guessed at: `kilos` branches on it.
    static func bareScore(_ data: Data) -> Punch? {
        guard data.count >= 4 else { return nil }
        let bits = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let score = Double(Float(bitPattern: UInt32(littleEndian: bits)))
        guard score.isFinite, score > 0 else { return nil }
        return Punch(score: score, peakG: 0, rawG: 0, speed: 0, spin: 0,
                     window: 0, railed: 0, seq: 0, flags: 0)
    }
}

// MARK: - the number on the board

extension Punch {

    /// Effective striking mass, in kilograms.
    ///
    /// A punch is not the mass of a hand. It is whatever the shoulder, the hips and the
    /// back foot managed to put behind the hand at the moment of contact, and for a
    /// committed straight punch that lands around a tenth of body mass. Eight kilograms
    /// is the middle of that for an adult, and it is one number for everybody on
    /// purpose: the board is one band passed down a line of people whose names are all
    /// anyone has time to type, so a per person mass would be a number nobody entered.
    static let strikingMass = 8.0

    /// Where the part stops measuring, in g. The LSM6DS3TR is set to its widest range
    /// and that range ends at 15.99 g.
    static let rail = 16.0

    /// Accelerometer sample rate during a punch, in hertz. Set in the firmware's
    /// CTRL1_XL, and the only way `railed` becomes a length of time.
    static let sampleRate = 833.0

    /// Nominal rise rate of the acceleration curve, in g per second.
    ///
    /// A punch ramps to the rail in about five milliseconds, which is this. It is the
    /// term the recovery below is built on, and see that comment for why a rate is what
    /// it takes.
    static let nominalRamp = 3200.0

    /// The reference hand speed the ramp is quoted at, in metres per second, and the
    /// band the scaling is held inside. A faster hand ramps harder, but not without
    /// limit, and a wrap that reports no speed at all must not scale the ramp to zero.
    static let referenceSpeed = 6.0
    static let rampRange = 0.6 ... 1.8

    /// Kilograms of force. The number on the board and the only one on screen.
    var kilos: Int {
        // The old score-only path. Nothing in the field is on that firmware, and the
        // constant is the ratio the two models agree on for a punch at the rail thrown
        // at the reference speed, so a gym running one old band and one new one gets
        // one scale rather than two.
        if peakG == 0 && score > 0 { return Int((score * 1.3).rounded()) }
        return Int((Punch.strikingMass * peak).rounded())
    }

    /// Peak acceleration in g, with the top of the curve put back on.
    ///
    /// The part measures to 16 g and a thrown punch goes past that, so the samples at
    /// the top of a hard one all read the same number and the peak alone cannot tell a
    /// good punch from a great one. What still separates them is TIME: the harder the
    /// punch, the longer its curve spends above the rail, and the firmware counts those
    /// samples. So the peak is rebuilt from the rate of climb rather than read off the
    /// top, which is the only thing the rate of climb is for here.
    ///
    /// The curve rises at `ramp`, crosses the rail, turns over somewhere above it and
    /// comes back down. Taking the top as a corner, it spends half its time above the
    /// rail climbing and half falling, so the height it reached is the rail plus the
    /// climb rate times half the time it was up there. The ramp itself is scaled by
    /// hand speed, because a hand arriving faster loads the same tissue faster, and
    /// speed is the one thing in this record that no rail can clip.
    ///
    /// This is a pilot model and it is meant to be replaced. What it has to be is
    /// monotonic, which it is in both of its terms: no two punches of different
    /// strengths can tie, and a harder one cannot score lower. Ranking a line of people
    /// at a bag is the whole job, and this ranks them. Nothing on the screen hedges
    /// about it, and that is deliberate too: a number with an apology attached is worse
    /// than useless in a gym, and the consumer version gets the real model.
    var peak: Double {
        let base = max(peakG, rawG - 1)
        guard railed > 0 else { return base }
        let scale = min(max(speed / Punch.referenceSpeed, Punch.rampRange.lowerBound),
                        Punch.rampRange.upperBound)
        let ramp = Punch.nominalRamp * scale
        let seconds = Double(railed) / Punch.sampleRate
        return max(base, Punch.rail) + ramp * seconds / 2
    }
}
