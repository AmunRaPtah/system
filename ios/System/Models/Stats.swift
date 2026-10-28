import SwiftUI

enum Pillar: String, Codable, CaseIterable, Identifiable {
    case body, mind, social, sovereign
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var symbol: String {
        switch self {
        case .body: return "figure.strengthtraining.traditional"
        case .mind: return "brain.head.profile"
        case .social: return "person.2.fill"
        case .sovereign: return "crown.fill"
        }
    }
    var stats: [Stat] { Stat.allCases.filter { $0.pillar == self } }
}

enum Stat: String, Codable, CaseIterable, Identifiable {
    case STR, END, AGI, VIT, PER, INT, WIL, CHA, SOV
    var id: String { rawValue }

    var pillar: Pillar {
        switch self {
        case .STR, .END, .AGI, .VIT: return .body
        case .PER, .INT, .WIL: return .mind
        case .CHA: return .social
        case .SOV: return .sovereign
        }
    }

    var name: String {
        switch self {
        case .STR: return "Strength"
        case .END: return "Endurance"
        case .AGI: return "Agility"
        case .VIT: return "Vitality"
        case .PER: return "Perception"
        case .INT: return "Intelligence"
        case .WIL: return "Willpower"
        case .CHA: return "Charisma"
        case .SOV: return "Sovereignty"
        }
    }

    static func parse(_ s: String) -> Stat { Stat(rawValue: s.uppercased()) ?? .WIL }
}

enum Rank: Int, CaseIterable, Identifiable, Comparable {
    case E = 0, D, C, B, A, S
    var id: Int { rawValue }
    var letter: String { ["E", "D", "C", "B", "A", "S"][rawValue] }
    /// Minimum player level before the rank-up trial opens.
    var minLevel: Int { [1, 5, 10, 18, 28, 40][rawValue] }
    /// Highest challenge difficulty (1-5) a hunter of this rank is assigned.
    var allowedDifficulty: Int { min(5, rawValue + 1) }
    var next: Rank? { Rank(rawValue: rawValue + 1) }
    var title: String {
        ["Awakened", "Initiate", "Hunter", "Veteran", "Elite", "Sovereign"][rawValue]
    }
    static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }

    /// Benchmark gate for entering this rank. E has none.
    var gate: RankGate? {
        switch self {
        case .E: return nil
        case .D: return RankGate(run1kSec: 450, pushups: 10, plankSec: 45, reactionMs: 380)
        case .C: return RankGate(run1kSec: 390, pushups: 20, plankSec: 75, reactionMs: 340)
        case .B: return RankGate(run1kSec: 345, pushups: 30, plankSec: 120, reactionMs: 310)
        case .A: return RankGate(run1kSec: 300, pushups: 40, plankSec: 180, reactionMs: 285)
        case .S: return RankGate(run1kSec: 260, pushups: 50, plankSec: 240, reactionMs: 265)
        }
    }
}

struct RankGate {
    var run1kSec: Int
    var pushups: Int
    var plankSec: Int
    var reactionMs: Int

    func passed(by b: Benchmarks) -> Bool {
        checks(b).allSatisfy { $0.ok }
    }

    func checks(_ b: Benchmarks) -> [(label: String, need: String, have: String, ok: Bool)] {
        [
            ("1 km run", "≤ " + Fmt.mmss(run1kSec), b.run1kSec.map(Fmt.mmss) ?? "—", (b.run1kSec ?? .max) <= run1kSec),
            ("Push-ups", "≥ \(pushups)", b.pushups.map(String.init) ?? "—", (b.pushups ?? 0) >= pushups),
            ("Plank", "≥ " + Fmt.mmss(plankSec), b.plankSec.map(Fmt.mmss) ?? "—", (b.plankSec ?? 0) >= plankSec),
            ("Reaction", "≤ \(reactionMs) ms", b.reactionMs.map { "\($0) ms" } ?? "—", (b.reactionMs ?? .max) <= reactionMs),
        ]
    }
}

/// Best recorded benchmark values across all assessments.
struct Benchmarks {
    var run1kSec: Int?
    var pushups: Int?
    var plankSec: Int?
    var reactionMs: Int?
}

enum Leveling {
    /// XP needed to go from `level` to `level + 1`. Gently rising.
    static func xpToNext(_ level: Int) -> Int { 80 + 20 * level }

    /// Cumulative XP at which `level` starts.
    static func floor(of level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for l in 1..<level { total += xpToNext(l) }
        return total
    }

    static func level(for xp: Int) -> Int {
        var level = 1
        var remaining = max(0, xp)
        while remaining >= xpToNext(level) {
            remaining -= xpToNext(level)
            level += 1
            if level > 999 { break }
        }
        return level
    }

    /// (xp into current level, xp span of current level)
    static func progress(for xp: Int) -> (into: Int, span: Int) {
        let l = level(for: xp)
        return (max(0, xp) - floor(of: l), xpToNext(l))
    }

    /// Displayed stat points: base 10 plus one point per 40 XP earned in that stat.
    static func statPoints(_ xp: Int) -> Int { 10 + max(0, xp) / 40 }

    static func rankByLevel(_ level: Int) -> Rank {
        Rank.allCases.last { level >= $0.minLevel } ?? .E
    }
}

enum Fmt {
    static func mmss(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
    static func kg(_ w: Double) -> String {
        w == w.rounded() ? String(format: "%.0f kg", w) : String(format: "%.1f kg", w)
    }
    static func num(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
