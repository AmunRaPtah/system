import Foundation

// MARK: - Cards

enum Suit: Int, CaseIterable, Codable {
    case spades, hearts, diamonds, clubs
    var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    var letter: String { ["s", "h", "d", "c"][rawValue] }
}

/// A playing card. Rank 2...14 (ace high). `bit` places the card in a 64-bit
/// hand mask at `suit * 16 + rank`, so each suit owns one 16-bit lane.
struct Card: Hashable, Identifiable, Codable, CustomStringConvertible {
    let rank: Int
    let suit: Suit

    init(rank: Int, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    init(index: Int) {
        rank = index / 4 + 2
        suit = Suit(rawValue: index % 4) ?? .spades
    }

    /// Parses "As", "Td", "9c".
    init?(_ s: String) {
        let chars = Array(s)
        guard chars.count == 2,
              let r = Card.rankChars.firstIndex(of: chars[0].uppercased().first ?? " "),
              let su = Suit.allCases.first(where: { $0.letter == String(chars[1]).lowercased() })
        else { return nil }
        rank = r + 2
        suit = su
    }

    var id: Int { (rank - 2) * 4 + suit.rawValue }
    var bit: UInt64 { 1 << UInt64(suit.rawValue * 16 + rank) }
    var description: String { Card.rankChar(rank) + suit.letter }

    static let rankChars: [Character] = Array("23456789TJQKA")
    static func rankChar(_ r: Int) -> String { String(rankChars[max(0, min(12, r - 2))]) }
    static func rankName(_ r: Int) -> String {
        ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"][max(0, min(12, r - 2))]
    }
    static let deck: [Card] = (0..<52).map { Card(index: $0) }
    static func parse(_ s: String) -> [Card] { s.split(separator: " ").compactMap { Card(String($0)) } }
    static func mask(_ cards: [Card]) -> UInt64 { cards.reduce(0) { $0 | $1.bit } }
    static func cards(in mask: UInt64) -> [Card] { deck.filter { mask & $0.bit != 0 } }
}

// MARK: - Hand evaluation

enum HandCategory: Int, CaseIterable, Comparable {
    case highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush
    static func < (a: HandCategory, b: HandCategory) -> Bool { a.rawValue < b.rawValue }
    var name: String {
        ["High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"][rawValue]
    }
}

/// Best-5-of-N evaluator (N = 5...7) over rank bitmasks. The value packs the
/// category in bits 20+ and up to five tie-break ranks in 4-bit nibbles, so a
/// larger value is a stronger hand and equal values split the pot.
/// tools/check_poker_eval.py is a line-for-line port checked against `treys`.
enum HandEvaluator {
    static func evaluate(_ cards: [Card]) -> Int { evaluate(mask: Card.mask(cards)) }
    static func category(_ value: Int) -> HandCategory { HandCategory(rawValue: value >> 20) ?? .highCard }

    static func describe(_ value: Int) -> String {
        let cat = category(value)
        let r1 = (value >> 16) & 0xF, r2 = (value >> 12) & 0xF
        switch cat {
        case .highCard: return "\(Card.rankName(r1)) high"
        case .pair: return "Pair of \(plural(r1))"
        case .twoPair: return "Two pair, \(plural(r1)) and \(plural(r2))"
        case .trips: return "Three \(plural(r1))"
        case .straight: return "Straight, \(Card.rankName(r1)) high"
        case .flush: return "Flush, \(Card.rankName(r1)) high"
        case .fullHouse: return "Full house, \(plural(r1)) full of \(plural(r2))"
        case .quads: return "Four \(plural(r1))"
        case .straightFlush: return r1 == 14 ? "Royal flush" : "Straight flush, \(Card.rankName(r1)) high"
        }
    }

    static func plural(_ r: Int) -> String { r == 6 ? "Sixes" : Card.rankName(r) + "s" }

    static func evaluate(mask m: UInt64) -> Int {
        let s0 = Int(m & 0xFFFF), s1 = Int((m >> 16) & 0xFFFF)
        let s2 = Int((m >> 32) & 0xFFFF), s3 = Int((m >> 48) & 0xFFFF)
        let any = s0 | s1 | s2 | s3
        let quads = s0 & s1 & s2 & s3
        let trips = (s0 & s1 & s2) | (s0 & s1 & s3) | (s0 & s2 & s3) | (s1 & s2 & s3)
        let pairs = (s0 & s1) | (s0 & s2) | (s0 & s3) | (s1 & s2) | (s1 & s3) | (s2 & s3)

        var flush = 0
        for s in [s0, s1, s2, s3] where s.nonzeroBitCount >= 5 {
            let sf = straightHigh(s)
            if sf > 0 { return pack(8, [sf]) }
            flush = s
        }
        if quads != 0 {
            let q = highest(quads)
            return pack(7, [q] + top(any & ~(1 << q), 1))
        }
        if trips != 0 {
            let t = highest(trips)
            let rest = pairs & ~(1 << t)
            if rest != 0 { return pack(6, [t, highest(rest)]) }
        }
        if flush != 0 { return pack(5, top(flush, 5)) }
        let st = straightHigh(any)
        if st > 0 { return pack(4, [st]) }
        if trips != 0 {
            let t = highest(trips)
            return pack(3, [t] + top(any & ~(1 << t), 2))
        }
        if pairs != 0 {
            let p1 = highest(pairs)
            let rest = pairs & ~(1 << p1)
            if rest != 0 {
                let p2 = highest(rest)
                return pack(2, [p1, p2] + top(any & ~(1 << p1) & ~(1 << p2), 1))
            }
            return pack(1, [p1] + top(any & ~(1 << p1), 3))
        }
        return pack(0, top(any, 5))
    }

    /// Highest card of a straight in a rank mask (bits 2...14), 5 for the wheel, 0 if none.
    static func straightHigh(_ ranks: Int) -> Int {
        var m = ranks
        if m & (1 << 14) != 0 { m |= 1 << 1 }
        var high = 14
        while high >= 5 {
            let w = 0x1F << (high - 4)
            if m & w == w { return high }
            high -= 1
        }
        return 0
    }

    static func highest(_ m: Int) -> Int { Int.bitWidth - 1 - m.leadingZeroBitCount }

    static func top(_ m: Int, _ n: Int) -> [Int] {
        var out: [Int] = []
        var r = 14
        while r >= 2 && out.count < n {
            if m & (1 << r) != 0 { out.append(r) }
            r -= 1
        }
        return out
    }

    static func pack(_ cat: Int, _ ranks: [Int]) -> Int {
        var v = 0
        for i in 0..<5 { v = v << 4 | (i < ranks.count ? ranks[i] : 0) }
        return cat << 20 | v
    }
}

// MARK: - Random

/// Small fast seeded generator for Monte Carlo loops.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Ranges

/// A preflop range in standard shorthand: "22+, A2s+, KTs+, ATo+, KQo, 76s".
struct HandRange {
    let name: String
    let classes: Set<String>

    init(_ name: String, _ notation: String) {
        self.name = name
        var set = Set<String>()
        for raw in notation.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespaces)
            let plus = token.hasSuffix("+")
            let body = Array(plus ? String(token.dropLast()) : token)
            guard body.count >= 2,
                  let a = Card.rankChars.firstIndex(of: body[0]),
                  let b = Card.rankChars.firstIndex(of: body[1]) else { continue }
            let hi = a + 2, lo = b + 2
            if hi == lo {
                for r in hi...(plus ? 14 : hi) { set.insert(HandRange.label(r, r, suited: false)) }
            } else if body.count == 3 {
                let suited = body[2] == "s"
                for k in lo...(plus ? hi - 1 : lo) { set.insert(HandRange.label(hi, k, suited: suited)) }
            }
        }
        classes = set
    }

    static func label(_ a: Int, _ b: Int, suited: Bool) -> String {
        let hi = max(a, b), lo = min(a, b)
        if hi == lo { return Card.rankChar(hi) + Card.rankChar(lo) }
        return Card.rankChar(hi) + Card.rankChar(lo) + (suited ? "s" : "o")
    }

    static func label(_ a: Card, _ b: Card) -> String { label(a.rank, b.rank, suited: a.suit == b.suit) }

    func contains(_ a: Card, _ b: Card) -> Bool { classes.contains(HandRange.label(a, b)) }

    /// All two-card masks in the range that avoid `dead`.
    func combos(excluding dead: UInt64 = 0) -> [UInt64] {
        var out: [UInt64] = []
        for i in 0..<52 {
            for j in (i + 1)..<52 {
                let a = Card.deck[i], b = Card.deck[j]
                guard (a.bit | b.bit) & dead == 0, contains(a, b) else { continue }
                out.append(a.bit | b.bit)
            }
        }
        return out
    }

    var percent: Double {
        let n = classes.reduce(0) { $0 + ($1.count == 2 ? 6 : ($1.hasSuffix("s") ? 4 : 12)) }
        return Double(n) / 1326 * 100
    }

    /// All 169 starting-hand classes.
    static let allClasses: [String] = {
        var out: [String] = []
        for hi in stride(from: 14, through: 2, by: -1) {
            out.append(label(hi, hi, suited: false))
            for lo in stride(from: hi - 1, through: 2, by: -1) {
                out.append(label(hi, lo, suited: true))
                out.append(label(hi, lo, suited: false))
            }
        }
        return out
    }()
}

// MARK: - Equity

enum Equity {
    /// Hero's share of the pot (wins + half of ties) against one opponent holding
    /// a random hand, or a random combo from `range` when given.
    static func monteCarlo(hero: [Card], board: [Card], range: HandRange?, iterations: Int = 4000, seed: UInt64 = 0x5EED) -> Double {
        var rng = SplitMix64(seed: seed)
        let heroMask = Card.mask(hero), boardMask = Card.mask(board)
        let dead = heroMask | boardMask
        var pool = Card.deck.map(\.bit).filter { $0 & dead == 0 }
        let combos = range?.combos(excluding: dead) ?? []
        let need = 5 - board.count
        var share = 0.0
        for _ in 0..<iterations {
            var pos = 0
            func draw() -> UInt64 {
                let j = pos + Int(rng.next() % UInt64(pool.count - pos))
                pool.swapAt(pos, j)
                pos += 1
                return pool[pos - 1]
            }
            let villain = combos.isEmpty ? (draw() | draw()) : combos[Int(rng.next() % UInt64(combos.count))]
            var runout = boardMask
            var left = need
            while left > 0 {
                let c = draw()
                if c & villain != 0 { continue }
                runout |= c
                left -= 1
            }
            let h = HandEvaluator.evaluate(mask: heroMask | runout)
            let v = HandEvaluator.evaluate(mask: villain | runout)
            share += h > v ? 1 : (h == v ? 0.5 : 0)
        }
        return share / Double(max(1, iterations))
    }

    /// Exact equity against a face-up hand by enumerating every runout.
    static func exact(hero: [Card], villain: [Card], board: [Card]) -> Double {
        let h = Card.mask(hero), v = Card.mask(villain), b = Card.mask(board)
        let pool = Card.deck.map(\.bit).filter { $0 & (h | v | b) == 0 }
        var share = 0.0, n = 0.0
        func score(_ runout: UInt64) {
            let a = HandEvaluator.evaluate(mask: h | runout), c = HandEvaluator.evaluate(mask: v | runout)
            share += a > c ? 1 : (a == c ? 0.5 : 0)
            n += 1
        }
        switch 5 - board.count {
        case 0: score(b)
        case 1: for x in pool { score(b | x) }
        case 2:
            for i in 0..<pool.count { for j in (i + 1)..<pool.count { score(b | pool[i] | pool[j]) } }
        default: return monteCarlo(hero: hero, board: board, range: HandRange("face-up", HandRange.label(villain[0], villain[1])))
        }
        return n > 0 ? share / n : 0
    }

    /// Next-card outs: unseen cards (villain's hand known) after which hero is strictly ahead.
    static func outs(hero: [Card], villain: [Card], board: [Card]) -> [Card] {
        let h = Card.mask(hero), v = Card.mask(villain), b = Card.mask(board)
        return Card.deck.filter { c in
            guard c.bit & (h | v | b) == 0 else { return false }
            return HandEvaluator.evaluate(mask: h | b | c.bit) > HandEvaluator.evaluate(mask: v | b | c.bit)
        }
    }
}

// MARK: - Self-test

/// Hand-verified cases. Evaluated via `assert` so Debug builds check them and
/// Release still type-checks them. Each row: stronger, weaker ("=" for a split).
enum PokerSelfTest {
    static let cases: [(String, String, String)] = [
        ("As Ks Qs Js Ts 2d 3c", ">", "9s 9h 9d 9c Ks 2d 3c"),
        ("5h 4h 3h 2h Ah Kd Kc", ">", "Ac Ad As Ah Kd 2c 3c"),
        ("6d 5d 4d 3d 2d Ad Kd", ">", "Ad Kd Qd Jd 9d 2c 3c"),
        ("Ah 2d 3c 4s 5h Kd Qc", "<", "2d 3c 4s 5h 6h Kd Qc"),
        ("Ah 2d 3c 4s 5h Kd Qc", ">", "Ah Ad Ac Kd Qc 2s 7h"),
        ("2h 5h 7h 9h Jh Ac Ad", ">", "Ac Kd Qh Js Th 2c 3c"),
        ("Kh Kd Kc 2s 2h Ac Qd", ">", "Ah Kh Qh Jh 9h 2c 3d"),
        ("Kh Kd Kc 2s 2h 2c Qd", "<", "Kh Kd Kc 2s 2h Qc Qd"),
        ("Ah Ad Kc Kd Qh Qs 2c", "=", "Ah Ad Kc Kd Qh 3s 2c"),
        ("Ah Ad Kc Kd 7h 7s 2c", "<", "Ah Ad Kc Kd Qh 3s 2c"),
        ("Ah Ad 9c 8d 6h 4s 2c", "<", "Ah Ad Tc 8d 6h 4s 2c"),
        ("Ah Kd 9c 8d 6h 4s 3c", "=", "Ah Kd 9c 8d 6h 2s 3c"),
        ("Ah Kd Qc Jd 9h 3s 2c", ">", "Ah Kd Qc Jd 8h 3s 2c"),
        ("Th Jd Qc Kd Ah 2s 2c", "=", "Th Jd Qc Kd Ah 3s 3c"),
        ("9h 9d 9c Ad Kh 2s 3c", ">", "9h 9d 9c Ad Qh 2s 3c"),
        ("7h 7d 7c 7s Ah 2s 3c", ">", "7h 7d 7c 7s Kh Qs Jc"),
        ("Ah Kh Qh Jh 9h 8h 7h", ">", "Ah Kh Qh Jh 8h 7h 6h"),
        ("Ah Kh Qh Jh Th 9h 8h", ">", "Kh Qh Jh Th 9h 8h 7h"),
        ("6h 7h 8h 9h Th Js Qs", ">", "5h 6h 7h 8h 9h Js Qs"),
        ("2c 3c 4c 5c 6d 7d Ac", "<", "2c 3c 4c 5c 6c Ad Kd"),
        ("Qh Qd Jc Jd Th Ts 9c", ">", "Qh Qd Jc Jd 8h 8s 9c"),
        ("Ah Ad Ac Kh Kd Kc 2s", ">", "Kh Kd Kc Ah Ad Qc 2s"),
    ]

    /// Returns failing rows; empty means all pass.
    static func run() -> [String] {
        var fails: [String] = []
        for (a, op, b) in cases {
            let x = HandEvaluator.evaluate(Card.parse(a)), y = HandEvaluator.evaluate(Card.parse(b))
            let ok = op == ">" ? x > y : (op == "<" ? x < y : x == y)
            if !ok { fails.append("\(a) \(op) \(b)") }
        }
        return fails
    }
}
