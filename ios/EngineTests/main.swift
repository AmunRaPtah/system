import Foundation

// Engine self-tests, compiled with swiftc in CI together with
// ios/System/Services/Engines/*.swift (Foundation only). Exits non-zero on failure.

var failures = 0
func check(_ ok: Bool, _ label: String) {
    print((ok ? "PASS " : "FAIL ") + label)
    if !ok { failures += 1 }
}

func fnv(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for c in s.utf8 { h ^= UInt64(c); h = h &* 0x100000001b3 }
    return h
}

// MARK: - Chess perft + SAN against python-chess

for ref in chessReference {
    guard var b = ChessBoard(fen: ref.fen) else { check(false, "\(ref.name): FEN parse"); continue }
    check(b.fen == ref.fen, "\(ref.name): FEN round-trip (\(b.fen))")
    let t0 = Date()
    let n = b.perft(ref.depth)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    check(n == ref.nodes, "\(ref.name): perft(\(ref.depth)) = \(n), expected \(ref.nodes) [\(ms) ms]")

    var lines: [String] = []
    let legal = b.legalMoves()
    for m in legal {
        lines.append("\(m.uci) \(b.san(m, legal: legal))")
        let u = b.make(m)
        let legal2 = b.legalMoves()
        for m2 in legal2 { lines.append("\(m.uci) \(m2.uci) \(b.san(m2, legal: legal2))") }
        b.unmake(u)
    }
    let joined = lines.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }.joined(separator: "\n")
    check(lines.count == ref.sanCount, "\(ref.name): SAN line count \(lines.count), expected \(ref.sanCount)")
    check(fnv(joined) == ref.sanHash, "\(ref.name): SAN hash match")
    check(b.fen == ref.fen, "\(ref.name): board restored after make/unmake")
}

// MARK: - Chess game rules

do {
    var g = ChessGame()
    for u in ["f2f3", "e7e5", "g2g4", "d8h4"] { if let m = g.board.move(uci: u) { g.play(m) } }
    check(g.result == .checkmate(whiteWins: false), "fool's mate is checkmate for black")
    check(g.sans == ["f3", "e5", "g4", "Qh4#"], "fool's mate SAN \(g.sans)")
    g.undo()
    check(g.result == .ongoing && g.moves.count == 3, "undo restores ongoing game")

    var r = ChessGame()
    for u in ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"] { if let m = r.board.move(uci: u) { r.play(m) } }
    check(r.result == .repetition, "threefold repetition detected")

    let st = ChessGame(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    check(st.result == .stalemate, "stalemate detected")
    let kn = ChessGame(fen: "8/8/4k3/8/8/3NK3/8/8 w - - 0 1")
    check(kn.result == .insufficient, "K+N v K is insufficient material")
    let fifty = ChessGame(fen: "8/8/4k3/8/8/3RK3/8/8 w - - 100 80")
    check(fifty.result == .fiftyMove, "fifty-move rule")
}

// MARK: - Chess engine sanity

do {
    let mateBoard = ChessBoard(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
    let m = ChessEngine(board: mateBoard).think(seconds: 1.0)
    check(m?.uci == "a1a8", "engine finds back-rank mate (got \(m?.uci ?? "nil"))")

    // Hanging queen.
    let hang = ChessBoard(fen: "4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")!
    let c = ChessEngine(board: hang).think(seconds: 1.0)
    check(c?.uci == "e4d5", "engine takes a hanging queen (got \(c?.uci ?? "nil"))")

    var rng = SystemRandomNumberGenerator()
    for lvl in 1...5 {
        let t0 = Date()
        let mv = ChessEngine(board: ChessBoard()).bestMove(level: .preset(lvl), rng: &rng)
        let s = Date().timeIntervalSince(t0)
        let ok = mv.map { ChessBoard().legalMoves().contains($0) } ?? false
        check(ok && s < ChessLevel.preset(lvl).seconds * 4 + 0.5, "level \(lvl) start move \(mv?.uci ?? "nil") in \(String(format: "%.2f", s))s")
    }

    // Self-play smoke test: MASTER-lite vs NOVICE, every engine move must be legal.
    var g = ChessGame()
    var plies = 0
    while !g.result.isOver && plies < 80 {
        let lvl: ChessLevel = g.board.whiteToMove ? ChessLevel(level: 4, maxDepth: 3, seconds: 0.05, blunderRate: 0, noise: 0) : .preset(1)
        guard let mv = ChessEngine(board: g.board, seenKeys: g.history).bestMove(level: lvl, rng: &rng),
              g.legalMoves.contains(mv) else { break }
        g.play(mv)
        plies += 1
    }
    check(g.result.isOver || plies == 80, "self-play ran \(plies) plies, result \(g.result.text)")
    print("     self-play: \(g.sans.joined(separator: " "))")
}

// MARK: - Go rules

func goBoard(_ rows: [String]) -> GoBoard {
    var b = GoBoard(size: rows.count)
    for (r, row) in rows.enumerated() {
        for (c, ch) in row.enumerated() {
            if ch == "X" { b.cells[r * rows.count + c] = GoStone.black }
            if ch == "O" { b.cells[r * rows.count + c] = GoStone.white }
        }
    }
    return b
}

do {
    // Capture in the corner.
    var b = goBoard([
        "OX.......",
        ".........",
        ".........", ".........", ".........", ".........", ".........", ".........", ".........",
    ])
    b.toPlay = GoStone.black
    check(b.isLegal(9, GoStone.black), "black may play the capturing move")
    let n = b.play(9)
    check(n == 1 && b.cells[0] == 0 && b.capturedBy[1] == 1, "corner stone captured")

    // Suicide is illegal; a capturing move into no liberties is legal.
    var s = goBoard([
        ".X.......",
        "X........",
        ".........", ".........", ".........", ".........", ".........", ".........", ".........",
    ])
    check(!s.isLegal(0, GoStone.white), "suicide is illegal")
    check(s.isLegal(0, GoStone.black), "filling own point is legal")

    // Ko: white captures at the ko, black may not retake immediately.
    var k = goBoard([
        "..XO.....",
        ".X.XO....",
        "..XO.....",
        ".........", ".........", ".........", ".........", ".........", ".........",
    ])
    // White plays (1,2): captures black (1,3)? (1,3) black has libs: (0,3)=O,(2,3)=O,(1,4)=O,(1,2) -> captured.
    k.toPlay = GoStone.white
    let cap = k.play(1 * 9 + 2)
    check(cap == 1, "ko capture takes one stone")
    check(k.ko == 1 * 9 + 3, "ko point set")
    check(!k.isLegal(1 * 9 + 3, GoStone.black), "immediate ko recapture is illegal")
    k.play(8 * 9 + 8)          // black plays elsewhere (ko threat)
    k.play(8 * 9 + 0)          // white answers elsewhere
    check(k.isLegal(1 * 9 + 3, GoStone.black), "ko may be retaken after an exchange")

    // Area scoring: black owns the left 4 columns, white the right 4, column e neutral split.
    let half = goBoard(Array(repeating: "...XO....", count: 9))
    let sc = half.areaScore()
    check(sc.black == 36 && sc.white == 45, "area score \(sc.black)-\(sc.white), expected 36-45")
    // A dead white stone inside black's area counts for black once removed.
    var withDead = half
    withDead.cells[0] = GoStone.white
    let sd = withDead.areaScore(dead: [0])
    check(sd.black == 36 && sd.white == 45, "dead stone removal gives \(sd.black)-\(sd.white)")
    let sn = withDead.areaScore()
    check(sn.black == 9 && sn.white == 46, "live invader neutralises black area (\(sn.black)-\(sn.white))")

    // Handicap points.
    check(GoBoard.handicapPoints(size: 9, count: 2) == [6 * 9 + 2, 2 * 9 + 6], "9x9 two-stone handicap points")

    // Two passes end the game.
    var g = GoGame(size: 9, handicap: 0)
    g.pass(); g.pass()
    check(g.isOver && g.margin(dead: []) == -7.5, "two passes end an empty game, white by komi")
}

// MARK: - Go engine sanity

do {
    // Black to play can capture a large white group in atari at (0,4).
    let b = goBoard([
        "XOOO.....",
        "XOOOX....",
        "XXXX.....",
        ".........", ".........", ".........", ".........", ".........", ".........",
    ])
    var bb = b
    bb.toPlay = GoStone.black
    let r = GoMCTS(board: bb, komi: 7.5, seed: 42).search(level: GoLevel(level: 3, playouts: 3000, seconds: 10), opponentPassed: false)
    check(r.move == 4, "MCTS captures the group in atari (got \(r.move.map(String.init) ?? "pass"), \(r.playouts) playouts)")

    for lvl in 1...5 {
        let t0 = Date()
        let res = GoMCTS(board: GoBoard(size: 9), komi: 7.5).search(level: .preset(lvl, size: 9), opponentPassed: false)
        let s = Date().timeIntervalSince(t0)
        check(res.move != nil && s < GoLevel.preset(lvl, size: 9).seconds + 1, "go level \(lvl) opening move \(res.move.map(String.init) ?? "pass") \(res.playouts) playouts in \(String(format: "%.2f", s))s")
    }

    // Self-play smoke test to the end on 9x9 with low playouts: game must terminate.
    var g = GoGame(size: 9, handicap: 0)
    var plies = 0
    while !g.isOver && plies < 200 {
        let res = GoMCTS(board: g.board, komi: g.komi, seed: UInt64(plies + 1)).search(level: GoLevel(level: 1, playouts: 150, seconds: 1), opponentPassed: g.lastWasPass)
        if let m = res.move { if g.play(m) == nil { break } } else { g.pass() }
        plies += 1
    }
    let dead = GoMCTS.suggestDead(g.board, komi: g.komi)
    check(g.isOver, "go self-play finished in \(plies) plies, margin \(g.margin(dead: dead)) with \(dead.count) dead")
}

print(failures == 0 ? "ALL ENGINE TESTS PASSED" : "\(failures) ENGINE TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
