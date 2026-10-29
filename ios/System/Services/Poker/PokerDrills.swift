import Foundation
import SwiftData

// MARK: - Drill catalogue

enum PokerDrill: String, CaseIterable, Identifiable, Codable {
    case potOdds, equity, preflop, outs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .potOdds: return "Pot Odds"
        case .equity: return "Equity Sense"
        case .preflop: return "Preflop Ranges"
        case .outs: return "Outs Counting"
        }
    }

    var symbol: String {
        switch self {
        case .potOdds: return "percent"
        case .equity: return "chart.pie.fill"
        case .preflop: return "tablecells.fill"
        case .outs: return "number.square.fill"
        }
    }

    var blurb: String {
        switch self {
        case .potOdds: return "Villain is all in. Compare the price of a call with your chance to hit, then call or fold."
        case .equity: return "Estimate how often your hand wins against a range. Checked by Monte Carlo simulation."
        case .preflop: return "Open or fold from a 6-max seat, judged against a standard static opening chart."
        case .outs: return "Villain's hand is face up. Count the cards that put you ahead, then apply the rule of 2 and 4."
        }
    }

    /// Primary stat gets the full award, secondary a third.
    var stats: (Stat, Stat) {
        switch self {
        case .potOdds: return (.INT, .WIL)
        case .equity: return (.INT, .PER)
        case .preflop: return (.WIL, .INT)
        case .outs: return (.PER, .INT)
        }
    }

    static let hands = 10
    static let maxLevel = 10

    /// Same pattern as DefaultsKey.drillLevel, namespaced so it never collides with DrillKind.
    var levelKey: String { "system.drillLevel.poker-\(rawValue)" }

    func level(_ d: UserDefaults = .standard) -> Int { max(1, d.integer(forKey: levelKey)) }
    func setLevel(_ v: Int, _ d: UserDefaults = .standard) { d.set(max(1, min(PokerDrill.maxLevel, v)), forKey: levelKey) }
    static func resetLevels(_ d: UserDefaults = .standard) { for k in allCases { d.removeObject(forKey: k.levelKey) } }

    static func nextLevel(_ level: Int, pct: Double) -> Int {
        let n = pct >= 80 ? level + 1 : (pct < 50 ? level - 1 : level)
        return max(1, min(maxLevel, n))
    }
}

/// One finished session, kept so achievements can count sessions, hands and accuracy.
@Model
final class PokerDrillRecord {
    var drill: String
    var date: Date
    var dayKey: String
    var level: Int
    var correct: Int
    var total: Int
    var score: Double
    var detail: String

    init(drill: PokerDrill, dayKey: String, level: Int, correct: Int, total: Int, detail: String) {
        self.drill = drill.rawValue
        self.date = .now
        self.dayKey = dayKey
        self.level = level
        self.correct = correct
        self.total = total
        self.score = total > 0 ? Double(correct) / Double(total) * 100 : 0
        self.detail = detail
    }
}

struct PokerReview: Identifiable {
    let id = UUID()
    var correct: Bool
    var headline: String
    var hero: [Card] = []
    var villain: [Card] = []
    var board: [Card] = []
    var lines: [String]
}

struct PokerOutcome {
    var reviews: [PokerReview]
    var correct: Int { reviews.filter(\.correct).count }
    var total: Int { reviews.count }
    var pct: Double { total > 0 ? Double(correct) / Double(total) * 100 : 0 }
}

func pctText(_ x: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f%%", x * 100) }

private func deal(_ n: Int, excluding dead: UInt64 = 0) -> [Card] {
    Array(Card.deck.filter { $0.bit & dead == 0 }.shuffled().prefix(n))
}

// MARK: - Opening chart

enum Seat: String, CaseIterable, Identifiable {
    case UTG, HJ, CO, BTN, SB
    var id: String { rawValue }
    var name: String {
        switch self {
        case .UTG: return "Under the gun"
        case .HJ: return "Hijack"
        case .CO: return "Cutoff"
        case .BTN: return "Button"
        case .SB: return "Small blind"
        }
    }
}

/// Static 6-max raise-first-in chart (100bb, no ante), close to common solver-derived charts.
enum OpeningChart {
    static let notation: [Seat: String] = [
        .UTG: "55+, A2s+, K9s+, Q9s+, J9s+, T9s, 98s, 87s, 76s, ATo+, KJo+, QJo",
        .HJ: "44+, A2s+, K8s+, Q9s+, J9s+, T8s+, 97s+, 86s+, 75s+, 65s, A9o+, KTo+, QTo+, JTo",
        .CO: "22+, A2s+, K5s+, Q8s+, J8s+, T8s+, 97s+, 86s+, 75s+, 64s+, 54s, A8o+, A5o, K9o+, Q9o+, J9o+, T9o",
        .BTN: "22+, A2s+, K2s+, Q4s+, J6s+, T6s+, 96s+, 85s+, 74s+, 63s+, 53s+, 43s, A2o+, K8o+, Q9o+, J9o+, T8o+, 98o, 87o",
        .SB: "22+, A2s+, K4s+, Q7s+, J7s+, T7s+, 97s+, 86s+, 75s+, 64s+, 54s, A4o+, K9o+, Q9o+, J9o+, T9o",
    ]
    static let ranges: [Seat: HandRange] = Dictionary(uniqueKeysWithValues: notation.map { ($0.key, HandRange("\($0.key.rawValue) open", $0.value)) })
    static func range(_ s: Seat) -> HandRange { ranges[s] ?? HandRange(s.rawValue, "") }

    /// Earliest seat (in table order) that opens this class, nil if none do.
    static func earliest(_ label: String) -> Seat? {
        [Seat.UTG, .HJ, .CO, .BTN].first { range($0).classes.contains(label) }
    }

    /// Hands whose answer depends on the seat, plus near misses just outside the button range.
    static let edge: [String] = {
        let union = Seat.allCases.reduce(Set<String>()) { $0.union(range($1).classes) }
        let misses = ["K7o", "Q8o", "J8o", "T7o", "97o", "86o", "76o", "Q3s", "J5s", "T5s", "95s", "84s", "73s", "62s", "52s", "42s", "32s"]
        return Array(union.subtracting(range(.UTG).classes)) + misses
    }()
}

// MARK: - Pot odds

struct PotOddsQuestion {
    var street: String
    var draw: String
    var outs: Int
    var pot: Int
    var bet: Int

    var cardsToCome: Int { street == "flop" ? 2 : 1 }
    /// Pot before villain's bet; a call risks `bet` to win `pot + bet`.
    var required: Double { Double(bet) / Double(pot + 2 * bet) }
    var equity: Double {
        if cardsToCome == 1 { return Double(outs) / 46 }
        return 1 - Double((47 - outs) * (46 - outs)) / Double(47 * 46)
    }
    var rule: Int { outs * (cardsToCome == 2 ? 4 : 2) }
    var shouldCall: Bool { equity >= required }

    static let draws: [(String, Int)] = [
        ("gutshot straight draw", 4), ("pair to two pair or trips", 5), ("two overcards", 6),
        ("open-ended straight draw", 8), ("flush draw", 9), ("flush draw + overcard", 12),
        ("flush draw + gutshot", 12), ("open-ender + flush draw", 15),
    ]

    static func make(_ level: Int) -> PotOddsQuestion {
        let margin = max(0.015, 0.12 - 0.012 * Double(level - 1))
        var sizes = [0.25, 0.33, 0.5, 0.66, 0.75, 1.0]
        if level >= 5 { sizes += [1.5, 2.0] }
        var q = PotOddsQuestion(street: "turn", draw: "flush draw", outs: 9, pot: 100, bet: 50)
        for _ in 0..<300 {
            let d = draws.randomElement()!
            let pot = Int.random(in: 4...40) * 5
            let bet = max(5, Int((Double(pot) * sizes.randomElement()! / 5).rounded()) * 5)
            q = PotOddsQuestion(street: Bool.random() ? "flop" : "turn", draw: d.0, outs: d.1, pot: pot, bet: bet)
            let gap = abs(q.equity - q.required)
            if gap >= margin && (level < 4 || gap <= margin + 0.07) { break }
        }
        return q
    }

    func review(call: Bool) -> PokerReview {
        let right = call == shouldCall
        return PokerReview(correct: right,
                           headline: "\(call ? "CALL" : "FOLD") · \(right ? "correct" : "should \(shouldCall ? "call" : "fold")")",
                           lines: [
                               "Price: call \(bet) to win \(pot + bet). Need \(bet) / (\(pot) + \(bet) + \(bet)) = \(pctText(required)).",
                               "Equity: \(outs) outs, \(cardsToCome) card\(cardsToCome == 2 ? "s" : "") to come = \(pctText(equity)) (rule of \(cardsToCome == 2 ? 4 : 2): ~\(rule)%).",
                               "\(pctText(equity)) \(shouldCall ? "≥" : "<") \(pctText(required)), so \(shouldCall ? "calling wins money on average" : "folding saves money on average").",
                           ])
    }
}

// MARK: - Equity estimation

struct EquityQuestion {
    var hero: [Card]
    var board: [Card]
    var range: HandRange?
    var equity: Double
    var buckets: [ClosedRange<Double>]

    var opponent: String {
        guard let r = range else { return "a random hand" }
        return "\(r.name) (\(Int(r.percent.rounded()))% of hands)"
    }

    static let villainRanges: [HandRange] = [
        OpeningChart.range(.UTG), OpeningChart.range(.CO), OpeningChart.range(.BTN),
        HandRange("a 3-bet range", "QQ+, AKs, AKo, A5s, A4s, KQs"),
        HandRange("a calling range", "JJ, TT, 99, 88, 77, 66, 55, 44, 33, 22, ATs, AJs, AQs, KTs+, QTs+, JTs, T9s, 98s, 87s, AJo, AQo, KQo"),
    ]

    static func make(_ level: Int) -> EquityQuestion {
        let range: HandRange? = level <= 2 ? nil : villainRanges.randomElement()
        let boardCount = level <= 4 ? 0 : (level <= 6 ? 3 : [3, 4].randomElement()!)
        let cards = deal(2 + boardCount)
        let hero = Array(cards.prefix(2)), board = Array(cards.dropFirst(2))
        let eq = Equity.monteCarlo(hero: hero, board: board, range: range, iterations: 5000,
                                   seed: UInt64.random(in: 1...UInt64.max))
        let step = level >= 7 ? 0.1 : 0.2
        let buckets = stride(from: 0.0, to: 0.999, by: step).map { $0...min(1, $0 + step) }
        return EquityQuestion(hero: hero, board: board, range: range, equity: eq, buckets: buckets)
    }

    /// Monte Carlo with 5000 runs has ~0.7% standard error; answers within 2% of an edge count.
    func review(_ b: ClosedRange<Double>) -> PokerReview {
        let right = b.contains(equity) || abs(equity - b.lowerBound) < 0.02 || abs(equity - b.upperBound) < 0.02
        let hit = buckets.first { $0.contains(equity) } ?? b
        var lines = ["Monte Carlo (5000 runouts) vs \(opponent): \(pctText(equity)).",
                     "You picked \(Int(b.lowerBound * 100))-\(Int(b.upperBound * 100))%, answer \(Int(hit.lowerBound * 100))-\(Int(hit.upperBound * 100))%."]
        if board.isEmpty {
            let pair = hero[0].rank == hero[1].rank, suited = hero[0].suit == hero[1].suit
            lines.append(pair ? "Pairs are ahead of most unpaired hands before the flop, about 80% vs two undercards." :
                (suited ? "Suited adds only ~2-3% equity over offsuit." : "Offsuit unpaired hands rarely run far ahead preflop; kickers decide many pots."))
        } else {
            lines.append("Your hand now: \(HandEvaluator.describe(HandEvaluator.evaluate(hero + board))).")
        }
        return PokerReview(correct: right, headline: "\(pctText(equity)) · \(right ? "in range" : "missed")",
                           hero: hero, board: board, lines: lines)
    }
}

// MARK: - Preflop

struct PreflopQuestion {
    var seat: Seat
    var hand: [Card]
    var label: String { HandRange.label(hand[0], hand[1]) }
    var shouldOpen: Bool { OpeningChart.range(seat).classes.contains(label) }

    static func make(_ level: Int) -> PreflopQuestion {
        let seats: [Seat] = level <= 2 ? [.UTG, .BTN] : Seat.allCases
        let seat = seats.randomElement()!
        let edgeShare = min(0.85, 0.4 + 0.05 * Double(level))
        if Double.random(in: 0..<1) < edgeShare, let label = OpeningChart.edge.randomElement() {
            return PreflopQuestion(seat: seat, hand: cards(for: label))
        }
        return PreflopQuestion(seat: seat, hand: deal(2))
    }

    static func cards(for label: String) -> [Card] {
        let chars = Array(label)
        let hi = (Card.rankChars.firstIndex(of: chars[0]) ?? 12) + 2
        let lo = (Card.rankChars.firstIndex(of: chars[1]) ?? 0) + 2
        let s1 = Suit.allCases.randomElement()!
        var s2 = Suit.allCases.filter { $0 != s1 }.randomElement()!
        if chars.count == 3 && chars[2] == "s" { s2 = s1 }
        return [Card(rank: hi, suit: s1), Card(rank: lo, suit: s2)]
    }

    func review(open: Bool) -> PokerReview {
        let right = open == shouldOpen
        let r = OpeningChart.range(seat)
        var lines: [String] = []
        if let e = OpeningChart.earliest(label) {
            lines.append(e == .UTG ? "\(label) opens from every seat." : "\(label) opens from \(e.rawValue) and later seats.")
        } else if r.classes.contains(label) {
            lines.append("\(label) is a small-blind-only open: heads-up against the big blind it plays profitably.")
        } else {
            lines.append("\(label) is outside every opening range here. Fold it.")
        }
        lines.append("\(seat.rawValue) opens about \(Int(r.percent.rounded()))% of hands: \(OpeningChart.notation[seat] ?? "").")
        if seat == .UTG || seat == .HJ { lines.append("Early seats have more players left to act, so ranges are tight.") }
        return PokerReview(correct: right, headline: "\(open ? "OPEN" : "FOLD") \(label) from \(seat.rawValue) · \(right ? "correct" : "should \(shouldOpen ? "open" : "fold")")",
                           hero: hand, lines: lines)
    }
}

// MARK: - Outs

struct OutsQuestion {
    var hero: [Card]
    var villain: [Card]
    var board: [Card]
    var outs: [Card]
    var exact: Double
    var tolerance: Int

    var cardsToCome: Int { 5 - board.count }
    var rule: Int { outs.count * (cardsToCome == 2 ? 4 : 2) }

    static func make(_ level: Int) -> OutsQuestion {
        let boardCount = level <= 3 ? 3 : [3, 4].randomElement()!
        let lo = level <= 2 ? 4 : 1, hi = level <= 2 ? 15 : 20
        var hero: [Card] = [], villain: [Card] = [], board: [Card] = [], outs: [Card] = []
        for _ in 0..<3000 {
            let c = deal(4 + boardCount)
            hero = Array(c[0..<2]); villain = Array(c[2..<4]); board = Array(c[4...])
            guard HandEvaluator.evaluate(hero + board) < HandEvaluator.evaluate(villain + board) else { continue }
            outs = Equity.outs(hero: hero, villain: villain, board: board)
            if (lo...hi).contains(outs.count) { break }
        }
        let ex = Equity.exact(hero: hero, villain: villain, board: board)
        return OutsQuestion(hero: hero, villain: villain, board: board, outs: outs, exact: ex, tolerance: level <= 2 ? 1 : 0)
    }

    func review(_ guess: Int) -> PokerReview {
        let n = outs.count
        let right = abs(guess - n) <= tolerance
        let byRank = outs.sorted { ($0.rank, $0.suit.rawValue) > ($1.rank, $1.suit.rawValue) }
        let factor = cardsToCome == 2 ? 4 : 2
        var lines = [
            "You said \(guess), true outs \(n)\(tolerance > 0 ? " (±\(tolerance) accepted)" : "").",
            "Outs: " + byRank.map { Card.rankChar($0.rank) + $0.suit.symbol }.joined(separator: " "),
            "Rule of \(factor): \(n) × \(factor) ≈ \(rule)%. Exact vs his hand, all runouts: \(pctText(exact)).",
        ]
        lines.append("Now: you \(HandEvaluator.describe(HandEvaluator.evaluate(hero + board))) vs \(HandEvaluator.describe(HandEvaluator.evaluate(villain + board))).")
        if cardsToCome == 2 && n > 8 { lines.append("The rule of 4 overstates big draws; subtract (outs - 8) for a closer figure.") }
        return PokerReview(correct: right, headline: "\(guess) outs · \(right ? "correct" : "answer \(n)")",
                           hero: hero, villain: villain, board: board, lines: lines)
    }
}
