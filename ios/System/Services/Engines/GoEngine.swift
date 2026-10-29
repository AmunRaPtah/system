import Foundation

// Go rules and a Monte Carlo tree search player. Foundation only, so it also
// compiles into the CI self-test runner (ios/EngineTests).
//
// Points are indexed p = row * n + col, row 0 at the top. Colours: 1 black, 2 white.

enum GoStone {
    static let empty: Int8 = 0, black: Int8 = 1, white: Int8 = 2
    static func other(_ c: Int8) -> Int8 { 3 - c }
}

/// Small fast PRNG for playouts (xorshift64*).
struct FastRNG: RandomNumberGenerator, Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return state &* 2685821657736338717
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

struct GoBoard: Sendable, Equatable {
    let n: Int
    var cells: [Int8]
    var toPlay: Int8 = GoStone.black
    /// Point that may not be played this turn (simple ko), or -1.
    var ko = -1
    var consecutivePasses = 0
    /// Stones captured by black / white.
    var capturedBy: [Int] = [0, 0, 0]
    let nbr: [[Int]]
    let diag: [[Int]]

    // Scratch space for flood fills (not part of the position).
    private var mark: [Int32]
    private var stamp: Int32 = 0
    private var stack: [Int] = []

    static func == (a: GoBoard, b: GoBoard) -> Bool {
        a.n == b.n && a.cells == b.cells && a.toPlay == b.toPlay && a.ko == b.ko
    }

    init(size: Int) {
        n = size
        cells = Array(repeating: 0, count: size * size)
        mark = Array(repeating: 0, count: size * size)
        nbr = (0..<(size * size)).map { p in
            let r = p / size, c = p % size
            return [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
                .filter { $0.0 >= 0 && $0.0 < size && $0.1 >= 0 && $0.1 < size }
                .map { $0.0 * size + $0.1 }
        }
        diag = (0..<(size * size)).map { p in
            let r = p / size, c = p % size
            return [(r - 1, c - 1), (r - 1, c + 1), (r + 1, c - 1), (r + 1, c + 1)]
                .filter { $0.0 >= 0 && $0.0 < size && $0.1 >= 0 && $0.1 < size }
                .map { $0.0 * size + $0.1 }
        }
    }

    var points: Int { n * n }

    /// Standard handicap points (up to 9 on 13x13, 5 on 9x9).
    static func handicapPoints(size: Int, count: Int) -> [Int] {
        let lo = size >= 13 ? 3 : 2, hi = size - 1 - lo, mid = size / 2
        let order = [(hi, lo), (lo, hi), (hi, hi), (lo, lo), (mid, mid), (mid, lo), (mid, hi), (lo, mid), (hi, mid)]
        let cap = size >= 13 ? 9 : 5
        var pts = order.prefix(min(count, cap)).map { $0.0 * size + $0.1 }
        // With 6 or 8 stones the centre is left empty.
        if count == 6 || count == 8, size >= 13 { pts = pts.filter { $0 != mid * size + mid } + [order[count].0 * size + order[count].1] }
        return pts
    }

    // MARK: - Groups

    private mutating func nextStamp() -> Int32 {
        stamp &+= 1
        if stamp == Int32.max { stamp = 1; for i in mark.indices { mark[i] = 0 } }
        return stamp
    }

    /// Liberty count of the group at p, stopping early once `limit` is reached.
    mutating func liberties(_ p: Int, limit: Int = Int.max) -> Int {
        let colour = cells[p]
        let s = nextStamp()
        stack.removeAll(keepingCapacity: true)
        stack.append(p)
        mark[p] = s
        var libs = 0
        // Liberties are stamped with -s so they are counted once.
        while let q = stack.popLast() {
            for x in nbr[q] {
                let v = cells[x]
                if v == 0 {
                    if mark[x] != -s { mark[x] = -s; libs += 1; if libs >= limit { return libs } }
                } else if v == colour && mark[x] != s {
                    mark[x] = s
                    stack.append(x)
                }
            }
        }
        return libs
    }

    /// Stones of the group at p.
    mutating func group(_ p: Int) -> [Int] {
        let colour = cells[p]
        let s = nextStamp()
        var out = [p]
        var st = [p]
        mark[p] = s
        while let q = st.popLast() {
            for x in nbr[q] where cells[x] == colour && mark[x] != s {
                mark[x] = s
                out.append(x)
                st.append(x)
            }
        }
        return out
    }

    /// The single liberty of a group in atari, if any.
    mutating func lastLiberty(_ p: Int) -> Int? {
        var found: Int?
        for q in group(p) {
            for x in nbr[q] where cells[x] == 0 {
                if let f = found, f != x { return nil }
                found = x
            }
        }
        return found
    }

    // MARK: - Moves

    mutating func isLegal(_ p: Int, _ c: Int8) -> Bool {
        guard p >= 0 && p < points, cells[p] == 0, p != ko else { return false }
        for x in nbr[p] where cells[x] == 0 { return true }
        let o = GoStone.other(c)
        for x in nbr[p] {
            let v = cells[x]
            if v == c && liberties(x, limit: 2) >= 2 { return true }
            if v == o && liberties(x, limit: 2) == 1 { return true }
        }
        return false   // suicide
    }

    /// True if p is a one-point eye of colour c (filling it is never useful in playouts).
    func isEye(_ p: Int, _ c: Int8) -> Bool {
        for x in nbr[p] where cells[x] != c { return false }
        let o = GoStone.other(c)
        var bad = 0
        for x in diag[p] where cells[x] == o { bad += 1 }
        return diag[p].count < 4 ? bad == 0 : bad < 2
    }

    /// Plays a legal move for the side to move. Returns stones captured.
    @discardableResult
    mutating func play(_ p: Int) -> Int {
        let c = toPlay, o = GoStone.other(c)
        cells[p] = c
        var captured = 0
        var lastCaptured = -1
        for x in nbr[p] where cells[x] == o {
            if liberties(x, limit: 1) == 0 {
                let g = group(x)
                for q in g { cells[q] = 0 }
                captured += g.count
                lastCaptured = x
            }
        }
        capturedBy[Int(c)] += captured
        // Simple ko: a lone stone that captured exactly one stone and now has one liberty.
        ko = -1
        if captured == 1 && !nbr[p].contains(where: { cells[$0] == c }) && liberties(p, limit: 2) == 1 {
            ko = lastCaptured
        }
        consecutivePasses = 0
        toPlay = o
        return captured
    }

    mutating func pass() {
        ko = -1
        consecutivePasses += 1
        toPlay = GoStone.other(toPlay)
    }

    // MARK: - Scoring

    /// Area (Chinese) score: stones plus empty regions bordered by one colour only.
    /// Stones in `dead` are treated as captured. Returns (black, white) points before komi.
    func areaScore(dead: Set<Int> = []) -> (black: Int, white: Int) {
        var c = cells
        for p in dead { c[p] = 0 }
        var black = 0, white = 0
        var seen = [Bool](repeating: false, count: points)
        for p in 0..<points {
            if c[p] == GoStone.black { black += 1; continue }
            if c[p] == GoStone.white { white += 1; continue }
            if seen[p] { continue }
            var region: [Int] = [], st = [p]
            seen[p] = true
            var touchB = false, touchW = false
            while let q = st.popLast() {
                region.append(q)
                for x in nbr[q] {
                    if c[x] == 0 { if !seen[x] { seen[x] = true; st.append(x) } }
                    else if c[x] == GoStone.black { touchB = true }
                    else { touchW = true }
                }
            }
            if touchB && !touchW { black += region.count }
            if touchW && !touchB { white += region.count }
        }
        return (black, white)
    }

    /// Owner of each point under area scoring (0 = neutral), for territory display.
    func ownership(dead: Set<Int> = []) -> [Int8] {
        var c = cells
        for p in dead { c[p] = 0 }
        var owner = c
        var seen = [Bool](repeating: false, count: points)
        for p in 0..<points where c[p] == 0 && !seen[p] {
            var region: [Int] = [], st = [p]
            seen[p] = true
            var touchB = false, touchW = false
            while let q = st.popLast() {
                region.append(q)
                for x in nbr[q] {
                    if c[x] == 0 { if !seen[x] { seen[x] = true; st.append(x) } }
                    else if c[x] == GoStone.black { touchB = true }
                    else { touchW = true }
                }
            }
            let o: Int8 = touchB && !touchW ? GoStone.black : (touchW && !touchB ? GoStone.white : 0)
            for q in region { owner[q] = o }
        }
        return owner
    }

    // MARK: - Playouts

    /// Random playout to the end. Avoids filling own eyes and prefers captures next to
    /// the last move. Records (point, colour) for AMAF and returns the final board.
    mutating func playout(rng: inout FastRNG, record: inout [(Int, Int8)], lastMove: Int) {
        var last = lastMove
        let limit = points * 3
        var empties: [Int] = []
        empties.reserveCapacity(points)
        var moves = 0
        while consecutivePasses < 2 && moves < limit {
            moves += 1
            let c = toPlay
            var chosen = -1
            // Capture heuristic: take an opponent group next to the last move that is in atari.
            if last >= 0 && rng.below(10) < 8 {
                for x in nbr[last] where cells[x] == GoStone.other(c) {
                    if liberties(x, limit: 2) == 1, let l = lastLiberty(x), isLegal(l, c) { chosen = l; break }
                }
            }
            if chosen < 0 {
                empties.removeAll(keepingCapacity: true)
                for p in 0..<points where cells[p] == 0 { empties.append(p) }
                while !empties.isEmpty {
                    let i = rng.below(empties.count)
                    let p = empties[i]
                    if !isEye(p, c) && isLegal(p, c) { chosen = p; break }
                    empties.swapAt(i, empties.count - 1)
                    empties.removeLast()
                }
            }
            if chosen < 0 { pass(); last = -1; continue }
            record.append((chosen, c))
            play(chosen)
            last = chosen
        }
    }

    /// Black wins under Tromp-Taylor area scoring with this komi?
    func blackWins(komi: Double) -> Bool {
        let s = areaScore()
        return Double(s.black) - Double(s.white) - komi > 0
    }
}

/// Difficulty presets for the go engine. Levels 1-5.
struct GoLevel: Sendable {
    let level: Int
    let playouts: Int
    let seconds: Double

    static func preset(_ level: Int, size: Int) -> GoLevel {
        let scale = size >= 13 ? 0.5 : 1.0
        switch level {
        case ...1: return GoLevel(level: 1, playouts: 60, seconds: 1)
        case 2: return GoLevel(level: 2, playouts: 300, seconds: 1.5)
        case 3: return GoLevel(level: 3, playouts: Int(1500 * scale), seconds: 2.5)
        case 4: return GoLevel(level: 4, playouts: Int(5000 * scale), seconds: 4)
        default: return GoLevel(level: 5, playouts: Int(15000 * scale), seconds: 7)
        }
    }

    static let names = ["NOVICE", "APPRENTICE", "ADEPT", "EXPERT", "MASTER"]
}

/// UCT with RAVE over light playouts.
final class GoMCTS {
    final class Node {
        let move: Int          // point, or pass (= n * n); -1 at root
        let colour: Int8       // colour that played `move`
        weak var parent: Node?
        var children: [Node] = []
        var expanded = false
        var visits = 0
        var wins = 0.0
        var raveVisits = 0
        var raveWins = 0.0
        init(move: Int, colour: Int8, parent: Node?) {
            self.move = move; self.colour = colour; self.parent = parent
        }
    }

    struct Result: Sendable {
        /// Point to play, or nil to pass.
        var move: Int?
        var winRate: Double
        var playouts: Int
        /// Per point: fraction of playouts ending black-owned minus white-owned (-1...1).
        var ownership: [Double]
    }

    let root: GoBoard
    let komi: Double
    private var rng: FastRNG
    private let passMove: Int
    private var ownTally: [Int]
    private var ownCount = 0

    init(board: GoBoard, komi: Double, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        root = board
        self.komi = komi
        rng = FastRNG(seed: seed)
        passMove = board.points
        ownTally = Array(repeating: 0, count: board.points)
    }

    func search(level: GoLevel, opponentPassed: Bool) -> Result {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(level.seconds * 1_000_000_000)
        let me = root.toPlay
        let top = Node(move: -1, colour: GoStone.other(me), parent: nil)
        var done = 0
        var record: [(Int, Int8)] = []
        var firstColour = [Int8](repeating: 0, count: root.points + 1)
        while done < level.playouts {
            if done & 31 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { break }
            done += 1
            var b = root
            var node = top
            var path = [top]
            var treeMoves: [(Int, Int8)] = []
            // Selection.
            while node.expanded && !node.children.isEmpty && b.consecutivePasses < 2 {
                node = select(node)
                if node.move == passMove { b.pass() } else { b.play(node.move) }
                treeMoves.append((node.move, node.colour))
                path.append(node)
            }
            // Expansion.
            if b.consecutivePasses < 2 && !node.expanded {
                expand(node, &b)
            }
            // Simulation.
            record.removeAll(keepingCapacity: true)
            let last = node.move >= 0 && node.move < passMove ? node.move : -1
            if b.consecutivePasses < 2 { b.playout(rng: &rng, record: &record, lastMove: last) }
            let blackWon = b.blackWins(komi: komi)
            tallyOwnership(b)
            // Backpropagation with AMAF.
            for i in firstColour.indices { firstColour[i] = 0 }
            for (p, c) in record.reversed() { firstColour[p] = c }
            for d in stride(from: path.count - 1, through: 0, by: -1) {
                let nd = path[d]
                nd.visits += 1
                let ndWon = (nd.colour == GoStone.black) == blackWon
                if ndWon { nd.wins += 1 }
                for ch in nd.children where ch.move != passMove && firstColour[ch.move] == ch.colour {
                    ch.raveVisits += 1
                    if (ch.colour == GoStone.black) == blackWon { ch.raveWins += 1 }
                }
                if d > 0 {
                    let (m, c) = treeMoves[d - 1]
                    if m != passMove { firstColour[m] = c }
                }
            }
        }
        let own = (0..<root.points).map { ownCount > 0 ? Double(ownTally[$0]) / Double(ownCount) : 0 }
        guard let best = top.children.max(by: { $0.visits < $1.visits }), best.visits > 0 else {
            return Result(move: nil, winRate: 0.5, playouts: done, ownership: own)
        }
        let wr = best.wins / Double(best.visits)
        var move: Int? = best.move == passMove ? nil : best.move

        // Pass when the game is settled: the opponent passed and we are ahead on the
        // estimated final position, or every point is decided and our move is inside our own area.
        let sign: Double = me == GoStone.black ? 1 : -1
        let estimate = own.reduce(0) { $0 + ($1 > 0.0 ? 1 : ($1 < 0.0 ? -1 : 0)) }
        let myLead = sign * (Double(estimate) - komi)
        if opponentPassed && myLead > 0 { move = nil }
        if let m = move, own.allSatisfy({ abs($0) > 0.9 }), sign * own[m] > 0.9 { move = nil }
        return Result(move: move, winRate: wr, playouts: done, ownership: own)
    }

    private func tallyOwnership(_ b: GoBoard) {
        let o = b.ownership()
        for p in 0..<o.count {
            if o[p] == GoStone.black { ownTally[p] += 1 } else if o[p] == GoStone.white { ownTally[p] -= 1 }
        }
        ownCount += 1
    }

    private func expand(_ node: Node, _ b: inout GoBoard) {
        node.expanded = true
        let c = b.toPlay
        for p in 0..<b.points where b.cells[p] == 0 && !b.isEye(p, c) && b.isLegal(p, c) {
            node.children.append(Node(move: p, colour: c, parent: node))
        }
        node.children.append(Node(move: passMove, colour: c, parent: node))
    }

    private func select(_ node: Node) -> Node {
        let k = 600.0
        let logN = log(Double(max(1, node.visits)))
        var best = node.children[0]
        var bestScore = -Double.infinity
        for ch in node.children {
            var score: Double
            if ch.visits == 0 && ch.raveVisits == 0 {
                score = ch.move == passMove ? 0.4 : 1.1 + Double(rng.below(1000)) * 1e-6
            } else {
                let q = ch.visits > 0 ? ch.wins / Double(ch.visits) : 0.5
                let r = ch.raveVisits > 0 ? ch.raveWins / Double(ch.raveVisits) : q
                let beta = ch.raveVisits > 0 ? sqrt(k / (3 * Double(ch.visits) + k)) : 0
                score = (1 - beta) * q + beta * r + 0.35 * sqrt(logN / Double(ch.visits + 1))
            }
            if score > bestScore { bestScore = score; best = ch }
        }
        return best
    }

    /// Dead-stone suggestion at game end: stones whose point is usually owned by the
    /// opponent in playouts from this position.
    static func suggestDead(_ board: GoBoard, komi: Double, playouts: Int = 300) -> Set<Int> {
        var rng = FastRNG(seed: 0xD1CE)
        var tally = [Int](repeating: 0, count: board.points)
        var record: [(Int, Int8)] = []
        for i in 0..<playouts {
            var b = board
            b.consecutivePasses = 0
            b.toPlay = i % 2 == 0 ? GoStone.black : GoStone.white
            record.removeAll(keepingCapacity: true)
            b.playout(rng: &rng, record: &record, lastMove: -1)
            let o = b.ownership()
            for p in 0..<o.count {
                if o[p] == GoStone.black { tally[p] += 1 } else if o[p] == GoStone.white { tally[p] -= 1 }
            }
        }
        var dead = Set<Int>()
        for p in 0..<board.points {
            let f = Double(tally[p]) / Double(playouts)
            if board.cells[p] == GoStone.black && f < -0.5 { dead.insert(p) }
            if board.cells[p] == GoStone.white && f > 0.5 { dead.insert(p) }
        }
        return dead
    }
}

/// A go game with history, for the UI and save/resume.
struct GoGame: Sendable {
    let size: Int
    let handicap: Int
    let komi: Double
    private(set) var board: GoBoard
    /// Moves after the handicap setup: point, or -1 for pass.
    private(set) var moves: [Int] = []
    private var snapshots: [GoBoard] = []

    init(size: Int, handicap: Int) {
        self.size = size
        self.handicap = handicap >= 2 ? handicap : 0
        komi = self.handicap >= 2 ? 0.5 : 7.5
        var b = GoBoard(size: size)
        if self.handicap >= 2 {
            for p in GoBoard.handicapPoints(size: size, count: self.handicap) { b.cells[p] = GoStone.black }
            b.toPlay = GoStone.white
        }
        board = b
    }

    var isOver: Bool { board.consecutivePasses >= 2 }
    var lastMove: Int? { moves.last.flatMap { $0 >= 0 ? $0 : nil } }
    var lastWasPass: Bool { moves.last == -1 }

    mutating func canPlay(_ p: Int) -> Bool { !isOver && board.isLegal(p, board.toPlay) }

    @discardableResult
    mutating func play(_ p: Int) -> Int? {
        guard canPlay(p) else { return nil }
        snapshots.append(board)
        let n = board.play(p)
        moves.append(p)
        return n
    }

    mutating func pass() {
        guard !isOver else { return }
        snapshots.append(board)
        board.pass()
        moves.append(-1)
    }

    mutating func undo() {
        guard let b = snapshots.popLast() else { return }
        board = b
        moves.removeLast()
    }

    /// Final margin for black (positive = black wins) with dead stones removed.
    func margin(dead: Set<Int>) -> Double {
        let s = board.areaScore(dead: dead)
        return Double(s.black) - Double(s.white) - komi
    }
}
