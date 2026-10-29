import Foundation

/// Difficulty presets for the chess engine. Levels 1-5.
struct ChessLevel: Sendable {
    let level: Int
    let maxDepth: Int
    let seconds: Double
    /// Probability of a deliberate non-best move (level 1-3 only).
    let blunderRate: Double
    /// Gaussian noise (centipawns) added to root move scores.
    let noise: Double

    static func preset(_ level: Int) -> ChessLevel {
        switch level {
        case ...1: return ChessLevel(level: 1, maxDepth: 1, seconds: 0.3, blunderRate: 0.35, noise: 220)
        case 2: return ChessLevel(level: 2, maxDepth: 2, seconds: 0.5, blunderRate: 0.18, noise: 110)
        case 3: return ChessLevel(level: 3, maxDepth: 3, seconds: 0.9, blunderRate: 0.07, noise: 45)
        case 4: return ChessLevel(level: 4, maxDepth: 5, seconds: 1.5, blunderRate: 0, noise: 0)
        default: return ChessLevel(level: 5, maxDepth: 64, seconds: 3.0, blunderRate: 0, noise: 0)
        }
    }

    static let names = ["NOVICE", "APPRENTICE", "ADEPT", "EXPERT", "MASTER"]
}

/// Alpha-beta searcher: iterative deepening, MVV-LVA + killers + history ordering,
/// quiescence search, piece-square tables, time limit. Not thread-safe; create one
/// per search (cheap) and run it off the main thread.
final class ChessEngine {
    static let mate = 100_000
    private static let inf = 1_000_000
    static let value: [Int] = [0, 100, 320, 330, 500, 900, 0]

    private var b: ChessBoard
    private var deadline: UInt64 = 0
    private var nodes = 0
    private var stopped = false
    private var killers = Array(repeating: [ChessMove?](repeating: nil, count: 2), count: 128)
    private var history = Array(repeating: 0, count: 64 * 64)
    private var rootBest: ChessMove?
    private let seenKeys: Set<String>
    private(set) var completedDepth = 0
    private(set) var lastScore = 0

    /// `seenKeys`: repetition keys of earlier positions in the game; the root
    /// avoids moves that repeat them when it is not losing.
    init(board: ChessBoard, seenKeys: [String] = []) {
        b = board
        self.seenKeys = Set(seenKeys)
    }

    // MARK: - Public API

    /// Best move under the given level. Returns nil only when there is no legal move.
    func bestMove<R: RandomNumberGenerator>(level: ChessLevel, rng: inout R) -> ChessMove? {
        let legal = b.legalMoves()
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return legal[0] }

        if level.level <= 3 {
            // Score every root move with a shallow full-window search, add noise, sometimes blunder.
            deadline = Self.now() + UInt64(level.seconds * 4 * 1_000_000_000)
            stopped = false
            var scored: [(ChessMove, Int)] = []
            for m in legal {
                let u = b.make(m)
                var s = -search(depth: level.maxDepth - 1, alpha: -Self.inf, beta: Self.inf, ply: 1)
                // Out of time: fall back to a static score for the rest.
                if stopped { s = -Self.evaluate(b) * (b.whiteToMove ? 1 : -1) }
                b.unmake(u)
                scored.append((m, s))
            }
            if Double.random(in: 0..<1, using: &rng) < level.blunderRate {
                // A "human" blunder: a random move that does not allow mate-in-one-ish disasters at level 3.
                let pool = level.level >= 3 ? scored.filter { $0.1 > -Self.mate / 2 } : scored
                if let pick = (pool.isEmpty ? scored : pool).randomElement(using: &rng) { return pick.0 }
            }
            let noisy = scored.map { (m, s) -> (ChessMove, Double) in
                // Never let noise hide a forced mate.
                if abs(s) > Self.mate / 2 { return (m, Double(s)) }
                return (m, Double(s) + gaussian(&rng) * level.noise)
            }
            return noisy.max { $0.1 < $1.1 }?.0
        }
        return think(seconds: level.seconds, maxDepth: level.maxDepth)
    }

    /// Plain iterative-deepening search, used for levels 4-5 and for hints.
    func think(seconds: Double, maxDepth: Int = 64) -> ChessMove? {
        let legal = b.legalMoves()
        guard !legal.isEmpty else { return nil }
        deadline = Self.now() + UInt64(seconds * 1_000_000_000)
        stopped = false
        var best = legal[0]
        rootBest = nil
        for depth in 1...max(1, maxDepth) {
            let s = searchRoot(depth: depth, legal: legal)
            if stopped { break }
            if let m = rootBest { best = m; lastScore = s; completedDepth = depth }
            if abs(s) > Self.mate / 2 { break }
            // Do not start an iteration we are unlikely to finish.
            if Self.now() + UInt64(seconds * 0.5 * 1_000_000_000) > deadline { break }
        }
        return best
    }

    /// Static evaluation from white's point of view (centipawns).
    static func evaluate(_ b: ChessBoard) -> Int {
        var score = 0
        var nonPawn = 0
        for s in 0..<64 {
            let t = Int(abs(b.sq[s]))
            if t == 2 || t == 3 || t == 4 || t == 5 { nonPawn += value[t] }
        }
        let endgame = nonPawn <= 2600
        for s in 0..<64 {
            let p = b.sq[s]
            if p == 0 { continue }
            let t = Int(abs(p))
            let idx = p > 0 ? (7 - (s >> 3)) * 8 + (s & 7) : s
            var v = value[t]
            switch t {
            case 1: v += PST.pawn[idx]
            case 2: v += PST.knight[idx]
            case 3: v += PST.bishop[idx]
            case 4: v += PST.rook[idx]
            case 5: v += PST.queen[idx]
            default: v += endgame ? PST.kingEnd[idx] : PST.kingMid[idx]
            }
            score += p > 0 ? v : -v
        }
        return score
    }

    // MARK: - Search

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private func checkTime() {
        nodes += 1
        if nodes & 1023 == 0 && Self.now() > deadline { stopped = true }
    }

    private func searchRoot(depth: Int, legal: [ChessMove]) -> Int {
        var alpha = -Self.inf
        let beta = Self.inf
        var ordered = order(legal, ply: 0)
        if let pv = rootBest, let i = ordered.firstIndex(of: pv) { ordered.remove(at: i); ordered.insert(pv, at: 0) }
        var bestMove: ChessMove?
        for m in ordered {
            let u = b.make(m)
            var s = -search(depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1)
            // Prefer not to repeat earlier positions unless losing.
            if s > -50 && seenKeys.contains(b.repetitionKey) { s = min(s, 0) - 1 }
            b.unmake(u)
            if stopped { return alpha }
            if s > alpha { alpha = s; bestMove = m }
        }
        if let m = bestMove { rootBest = m }
        return alpha
    }

    private func search(depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
        checkTime()
        if stopped { return 0 }
        if b.halfmove >= 100 { return 0 }
        if ply >= 60 { return Self.evaluate(b) * (b.whiteToMove ? 1 : -1) }
        let check = b.inCheck
        let d = check ? depth + 1 : depth   // check extension
        if d <= 0 { return quiesce(alpha: alpha, beta: beta, ply: ply) }
        var alpha = alpha
        var any = false
        for m in order(b.pseudoMoves(), ply: ply) {
            let u = b.make(m)
            if b.lastMoveIllegal { b.unmake(u); continue }
            any = true
            let s = -search(depth: d - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            b.unmake(u)
            if stopped { return 0 }
            if s >= beta {
                if u.captured == 0 && m.promo == 0 && ply < 128 {
                    if killers[ply][0] != m { killers[ply][1] = killers[ply][0]; killers[ply][0] = m }
                    history[m.from * 64 + m.to] += d * d
                }
                return beta
            }
            if s > alpha { alpha = s }
        }
        if !any { return check ? -Self.mate + ply : 0 }
        return alpha
    }

    private func quiesce(alpha: Int, beta: Int, ply: Int) -> Int {
        checkTime()
        if stopped { return 0 }
        let stand = Self.evaluate(b) * (b.whiteToMove ? 1 : -1)
        if stand >= beta { return beta }
        var alpha = max(alpha, stand)
        if ply > 40 { return alpha }
        for m in order(b.pseudoMoves(capturesOnly: true), ply: -1) {
            let u = b.make(m)
            if b.lastMoveIllegal { b.unmake(u); continue }
            let s = -quiesce(alpha: -beta, beta: -alpha, ply: ply + 1)
            b.unmake(u)
            if stopped { return 0 }
            if s >= beta { return beta }
            if s > alpha { alpha = s }
        }
        return alpha
    }

    /// MVV-LVA for captures and promotions, then killers, then history.
    private func order(_ moves: [ChessMove], ply: Int) -> [ChessMove] {
        let k0 = ply >= 0 && ply < 128 ? killers[ply][0] : nil
        let k1 = ply >= 0 && ply < 128 ? killers[ply][1] : nil
        let scored = moves.map { m -> (ChessMove, Int) in
            let victim = m.flag == .enPassant ? 1 : Int(abs(b.sq[m.to]))
            var s = 0
            if victim > 0 {
                s = 1_000_000 + Self.value[victim] * 10 - Self.value[Int(abs(b.sq[m.from]))] / 10
            } else if m == k0 {
                s = 900_000
            } else if m == k1 {
                s = 800_000
            } else {
                s = history[m.from * 64 + m.to]
            }
            if m.promo != 0 { s += 1_100_000 + Self.value[Int(m.promo)] }
            return (m, s)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func gaussian<R: RandomNumberGenerator>(_ rng: inout R) -> Double {
        let u1 = Double.random(in: 1e-9..<1, using: &rng), u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// Piece-square tables (Michniewski's simplified evaluation function), written
/// from white's side with rank 8 first.
enum PST {
    static let pawn = [
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]
    static let knight = [
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    ]
    static let bishop = [
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    ]
    static let rook = [
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0,
    ]
    static let queen = [
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20,
    ]
    static let kingMid = [
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20,
    ]
    static let kingEnd = [
        -50, -40, -30, -20, -20, -30, -40, -50,
        -30, -20, -10, 0, 0, -10, -20, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -30, 0, 0, 0, 0, -30, -30,
        -50, -30, -30, -30, -30, -30, -30, -50,
    ]
}
