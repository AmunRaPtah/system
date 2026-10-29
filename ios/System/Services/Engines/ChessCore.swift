import Foundation

// Full-rules chess board for play-vs-engine. Foundation only, so the same file
// compiles into the app and into the CI perft runner (ios/EngineTests).
//
// Squares: 0 = a1, 7 = h1, 56 = a8, 63 = h8. Pieces: 1 P, 2 N, 3 B, 4 R, 5 Q, 6 K,
// positive for white, negative for black, 0 empty.

enum CP {
    static let pawn: Int8 = 1, knight: Int8 = 2, bishop: Int8 = 3, rook: Int8 = 4, queen: Int8 = 5, king: Int8 = 6
}

struct ChessMove: Hashable, Sendable {
    enum Flag: UInt8, Sendable { case normal, double, enPassant, castleKing, castleQueen }
    var from: Int
    var to: Int
    /// Promotion piece type (2...5), 0 if none.
    var promo: Int8 = 0
    var flag: Flag = .normal

    var uci: String {
        var s = ChessBoard.squareName(from) + ChessBoard.squareName(to)
        if promo != 0 { s += String(Array("..nbrq")[Int(promo)]) }
        return s
    }
}

struct ChessUndo: Sendable {
    var move: ChessMove
    var captured: Int8
    var castling: Int
    var ep: Int
    var halfmove: Int
}

struct ChessBoard: Sendable, Equatable {
    var sq: [Int8] = Array(repeating: 0, count: 64)
    var whiteToMove = true
    /// Bits: 1 = K, 2 = Q, 4 = k, 8 = q.
    var castling = 0
    var ep = -1
    var halfmove = 0
    var fullmove = 1
    var kingSq = [4, 60]   // [white, black]

    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    init() { self.init(fen: ChessBoard.startFEN)! }

    init?(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        guard let placement = parts.first else { return nil }
        let rows = placement.split(separator: "/")
        guard rows.count == 8 else { return nil }
        var wk = -1, bk = -1
        for (i, row) in rows.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue { file += n; continue }
                guard file < 8, let p = ChessBoard.piece(from: ch) else { return nil }
                let s = rank * 8 + file
                sq[s] = p
                if p == CP.king { wk = s }
                if p == -CP.king { bk = s }
                file += 1
            }
        }
        guard wk >= 0, bk >= 0 else { return nil }
        kingSq = [wk, bk]
        whiteToMove = parts.count < 2 || parts[1] != "b"
        castling = 0
        if parts.count > 2 {
            for c in parts[2] {
                switch c {
                case "K": castling |= 1
                case "Q": castling |= 2
                case "k": castling |= 4
                case "q": castling |= 8
                default: break
                }
            }
        }
        ep = parts.count > 3 ? (ChessBoard.square(parts[3]) ?? -1) : -1
        halfmove = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        fullmove = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1
    }

    // MARK: - Notation helpers

    static func piece(from ch: Character) -> Int8? {
        let t: Int8
        switch ch.lowercased() {
        case "p": t = CP.pawn
        case "n": t = CP.knight
        case "b": t = CP.bishop
        case "r": t = CP.rook
        case "q": t = CP.queen
        case "k": t = CP.king
        default: return nil
        }
        return ch.isUppercase ? t : -t
    }

    static func letter(_ p: Int8) -> Character {
        let c = Array(".pnbrqk")[Int(abs(p))]
        return p > 0 ? Character(c.uppercased()) : c
    }

    static func squareName(_ s: Int) -> String {
        "\(Array("abcdefgh")[s & 7])\(s / 8 + 1)"
    }

    static func square(_ name: String) -> Int? {
        let c = Array(name.lowercased())
        guard c.count == 2, let f = "abcdefgh".firstIndex(of: c[0]), let r = c[1].wholeNumberValue, (1...8).contains(r) else { return nil }
        return (r - 1) * 8 + "abcdefgh".distance(from: "abcdefgh".startIndex, to: f)
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = "", empty = 0
            for file in 0..<8 {
                let p = sq[rank * 8 + file]
                if p == 0 { empty += 1; continue }
                if empty > 0 { row += "\(empty)"; empty = 0 }
                row.append(ChessBoard.letter(p))
            }
            if empty > 0 { row += "\(empty)" }
            rows.append(row)
        }
        var c = ""
        if castling & 1 != 0 { c += "K" }
        if castling & 2 != 0 { c += "Q" }
        if castling & 4 != 0 { c += "k" }
        if castling & 8 != 0 { c += "q" }
        return "\(rows.joined(separator: "/")) \(whiteToMove ? "w" : "b") \(c.isEmpty ? "-" : c) \(ep >= 0 ? ChessBoard.squareName(ep) : "-") \(halfmove) \(fullmove)"
    }

    /// Repetition key: placement, side, castling, and en passant only when a capture is possible.
    var repetitionKey: String {
        var k = String(sq.map { Character(UnicodeScalar(UInt8(Int(66) + Int($0)))) })
        k += whiteToMove ? "w" : "b"
        k += String(castling)
        if ep >= 0 && legalMoves().contains(where: { $0.flag == .enPassant }) { k += String(ep) }
        return k
    }

    // MARK: - Attack tables

    static let knightTargets: [[Int]] = (0..<64).map { s in
        let f = s & 7, r = s >> 3
        return [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)].compactMap { d in
            let nf = f + d.0, nr = r + d.1
            return (0..<8).contains(nf) && (0..<8).contains(nr) ? nr * 8 + nf : nil
        }
    }
    static let kingTargets: [[Int]] = (0..<64).map { s in
        let f = s & 7, r = s >> 3
        return [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)].compactMap { d in
            let nf = f + d.0, nr = r + d.1
            return (0..<8).contains(nf) && (0..<8).contains(nr) ? nr * 8 + nf : nil
        }
    }
    static let rookDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let bishopDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    /// rays[dirIndex 0..7][square] -> squares outward. 0-3 rook dirs, 4-7 bishop dirs.
    static let rays: [[[Int]]] = (rookDirs + bishopDirs).map { d in
        (0..<64).map { s in
            var out: [Int] = []
            var f = (s & 7) + d.0, r = (s >> 3) + d.1
            while (0..<8).contains(f) && (0..<8).contains(r) {
                out.append(r * 8 + f)
                f += d.0; r += d.1
            }
            return out
        }
    }
    /// Castling-rights mask applied when a move touches a square.
    static let castleMask: [Int] = (0..<64).map { s in
        switch s {
        case 0: return ~2 & 15
        case 4: return ~3 & 15
        case 7: return ~1 & 15
        case 56: return ~8 & 15
        case 60: return ~12 & 15
        case 63: return ~4 & 15
        default: return 15
        }
    }

    /// Is square `s` attacked by the given side?
    func attacked(_ s: Int, byWhite: Bool) -> Bool {
        let sign: Int8 = byWhite ? 1 : -1
        let f = s & 7
        if byWhite {
            if f > 0, s - 9 >= 0, sq[s - 9] == CP.pawn { return true }
            if f < 7, s - 7 >= 0, sq[s - 7] == CP.pawn { return true }
        } else {
            if f > 0, s + 7 < 64, sq[s + 7] == -CP.pawn { return true }
            if f < 7, s + 9 < 64, sq[s + 9] == -CP.pawn { return true }
        }
        for t in ChessBoard.knightTargets[s] where sq[t] == sign * CP.knight { return true }
        for t in ChessBoard.kingTargets[s] where sq[t] == sign * CP.king { return true }
        for d in 0..<8 {
            let straight = d < 4
            for t in ChessBoard.rays[d][s] {
                let p = sq[t]
                if p == 0 { continue }
                if p == sign * CP.queen || p == sign * (straight ? CP.rook : CP.bishop) { return true }
                break
            }
        }
        return false
    }

    var inCheck: Bool { attacked(kingSq[whiteToMove ? 0 : 1], byWhite: !whiteToMove) }

    // MARK: - Move generation

    /// Pseudo-legal moves (may leave own king in check). Castling is fully checked.
    func pseudoMoves(capturesOnly: Bool = false) -> [ChessMove] {
        var moves: [ChessMove] = []
        moves.reserveCapacity(48)
        let white = whiteToMove
        let sign: Int8 = white ? 1 : -1
        func addPawn(_ from: Int, _ to: Int, _ flag: ChessMove.Flag = .normal) {
            let r = to >> 3
            if r == 7 || r == 0 {
                for p in [CP.queen, CP.rook, CP.bishop, CP.knight] { moves.append(ChessMove(from: from, to: to, promo: p, flag: flag)) }
            } else {
                moves.append(ChessMove(from: from, to: to, flag: flag))
            }
        }
        for s in 0..<64 {
            let p = sq[s]
            if p == 0 || (p > 0) != white { continue }
            let t = abs(p)
            let f = s & 7, r = s >> 3
            switch t {
            case CP.pawn:
                let fwd = white ? 8 : -8
                let one = s + fwd
                let promoRank = white ? 6 : 1
                if sq[one] == 0 && (!capturesOnly || r == promoRank) {
                    addPawn(s, one)
                    let startRank = white ? 1 : 6
                    if !capturesOnly && r == startRank && sq[one + fwd] == 0 { moves.append(ChessMove(from: s, to: one + fwd, flag: .double)) }
                }
                for df in [-1, 1] {
                    let nf = f + df
                    if nf < 0 || nf > 7 { continue }
                    let to = one + df
                    let q = sq[to]
                    if q != 0 && (q > 0) != white { addPawn(s, to) }
                    else if to == ep && q == 0 { moves.append(ChessMove(from: s, to: to, flag: .enPassant)) }
                }
            case CP.knight, CP.king:
                for to in (t == CP.knight ? ChessBoard.knightTargets[s] : ChessBoard.kingTargets[s]) {
                    let q = sq[to]
                    if q == 0 { if !capturesOnly { moves.append(ChessMove(from: s, to: to)) } }
                    else if (q > 0) != white { moves.append(ChessMove(from: s, to: to)) }
                }
            default:
                let dirs: Range<Int> = t == CP.rook ? 0..<4 : (t == CP.bishop ? 4..<8 : 0..<8)
                for d in dirs {
                    for to in ChessBoard.rays[d][s] {
                        let q = sq[to]
                        if q == 0 { if !capturesOnly { moves.append(ChessMove(from: s, to: to)) }; continue }
                        if (q > 0) != white { moves.append(ChessMove(from: s, to: to)) }
                        break
                    }
                }
            }
        }
        if !capturesOnly {
            let base = white ? 0 : 56
            let kRight = white ? 1 : 4, qRight = white ? 2 : 8
            if castling & (kRight | qRight) != 0 && sq[base + 4] == sign * CP.king && !attacked(base + 4, byWhite: !white) {
                if castling & kRight != 0 && sq[base + 7] == sign * CP.rook && sq[base + 5] == 0 && sq[base + 6] == 0
                    && !attacked(base + 5, byWhite: !white) && !attacked(base + 6, byWhite: !white) {
                    moves.append(ChessMove(from: base + 4, to: base + 6, flag: .castleKing))
                }
                if castling & qRight != 0 && sq[base] == sign * CP.rook && sq[base + 1] == 0 && sq[base + 2] == 0 && sq[base + 3] == 0
                    && !attacked(base + 3, byWhite: !white) && !attacked(base + 2, byWhite: !white) {
                    moves.append(ChessMove(from: base + 4, to: base + 2, flag: .castleQueen))
                }
            }
        }
        return moves
    }

    @discardableResult
    mutating func make(_ m: ChessMove) -> ChessUndo {
        let piece = sq[m.from]
        var captured = sq[m.to]
        let undo0 = ChessUndo(move: m, captured: 0, castling: castling, ep: ep, halfmove: halfmove)
        let white = piece > 0
        if m.flag == .enPassant {
            let cs = m.to + (white ? -8 : 8)
            captured = sq[cs]
            sq[cs] = 0
        }
        sq[m.to] = m.promo != 0 ? (white ? m.promo : -m.promo) : piece
        sq[m.from] = 0
        if m.flag == .castleKing { sq[m.from + 1] = sq[m.from + 3]; sq[m.from + 3] = 0 }
        if m.flag == .castleQueen { sq[m.from - 1] = sq[m.from - 4]; sq[m.from - 4] = 0 }
        if abs(piece) == CP.king { kingSq[white ? 0 : 1] = m.to }
        castling &= ChessBoard.castleMask[m.from] & ChessBoard.castleMask[m.to]
        ep = m.flag == .double ? (m.from + m.to) / 2 : -1
        halfmove = (abs(piece) == CP.pawn || captured != 0) ? 0 : halfmove + 1
        if !white { fullmove += 1 }
        whiteToMove.toggle()
        var u = undo0
        u.captured = captured
        return u
    }

    mutating func unmake(_ u: ChessUndo) {
        let m = u.move
        whiteToMove.toggle()
        let white = whiteToMove
        if !white { fullmove -= 1 }
        var piece = sq[m.to]
        if m.promo != 0 { piece = white ? CP.pawn : -CP.pawn }
        sq[m.from] = piece
        if m.flag == .enPassant {
            sq[m.to] = 0
            sq[m.to + (white ? -8 : 8)] = u.captured
        } else {
            sq[m.to] = u.captured
        }
        if m.flag == .castleKing { sq[m.from + 3] = sq[m.from + 1]; sq[m.from + 1] = 0 }
        if m.flag == .castleQueen { sq[m.from - 4] = sq[m.from - 1]; sq[m.from - 1] = 0 }
        if abs(piece) == CP.king { kingSq[white ? 0 : 1] = m.from }
        castling = u.castling
        ep = u.ep
        halfmove = u.halfmove
    }

    /// True if the side that just moved left its own king attacked.
    var lastMoveIllegal: Bool { attacked(kingSq[whiteToMove ? 1 : 0], byWhite: whiteToMove) }

    func legalMoves() -> [ChessMove] {
        var b = self
        return pseudoMoves().filter { m in
            let u = b.make(m)
            defer { b.unmake(u) }
            return !b.lastMoveIllegal
        }
    }

    mutating func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var n = 0
        for m in pseudoMoves() {
            let u = make(m)
            if !lastMoveIllegal { n += depth == 1 ? 1 : perft(depth - 1) }
            unmake(u)
        }
        return n
    }

    // MARK: - SAN

    /// Standard algebraic notation for a legal move in this position.
    func san(_ m: ChessMove, legal: [ChessMove]? = nil) -> String {
        var s: String
        let p = sq[m.from]
        let t = abs(p)
        if m.flag == .castleKing { s = "O-O" }
        else if m.flag == .castleQueen { s = "O-O-O" }
        else {
            let capture = sq[m.to] != 0 || m.flag == .enPassant
            let dest = ChessBoard.squareName(m.to)
            if t == CP.pawn {
                s = capture ? "\(Array("abcdefgh")[m.from & 7])x\(dest)" : dest
                if m.promo != 0 { s += "=" + String(Array("..NBRQ")[Int(m.promo)]) }
            } else {
                s = String(Array("..NBRQK")[Int(t)])
                let others = (legal ?? legalMoves()).filter { $0.to == m.to && $0.from != m.from && sq[$0.from] == p }
                if !others.isEmpty {
                    let sameFile = others.contains { $0.from & 7 == m.from & 7 }
                    let sameRank = others.contains { $0.from >> 3 == m.from >> 3 }
                    let sqn = ChessBoard.squareName(m.from)
                    if !sameFile { s += String(sqn.prefix(1)) }
                    else if !sameRank { s += String(sqn.suffix(1)) }
                    else { s += sqn }
                }
                if capture { s += "x" }
                s += dest
            }
        }
        var b = self
        b.make(m)
        if b.inCheck { s += b.legalMoves().isEmpty ? "#" : "+" }
        return s
    }

    func move(uci: String) -> ChessMove? {
        let u = uci.lowercased()
        return legalMoves().first { $0.uci == u }
    }

    // MARK: - Material

    /// K v K, K+minor v K, or only same-coloured bishops besides kings.
    var insufficientMaterial: Bool {
        var minors: [(Int8, Int)] = []
        for s in 0..<64 {
            let t = abs(sq[s])
            if t == 0 || t == CP.king { continue }
            if t == CP.pawn || t == CP.rook || t == CP.queen { return false }
            minors.append((t, s))
        }
        if minors.count <= 1 { return true }
        if minors.allSatisfy({ $0.0 == CP.bishop }) {
            let colours = Set(minors.map { (($0.1 & 7) + ($0.1 >> 3)) % 2 })
            return colours.count == 1
        }
        return false
    }
}

/// A chess game: board plus history, for the UI and save/resume.
struct ChessGame: Sendable {
    enum Result: Equatable, Sendable {
        case ongoing
        case checkmate(whiteWins: Bool)
        case stalemate, fiftyMove, repetition, insufficient
        case resigned(whiteWins: Bool)

        var isOver: Bool { self != .ongoing }
        /// nil = draw.
        var whiteWins: Bool? {
            switch self {
            case .checkmate(let w), .resigned(let w): return w
            default: return nil
            }
        }
        var text: String {
            switch self {
            case .ongoing: return ""
            case .checkmate(let w): return "Checkmate. \(w ? "White" : "Black") wins."
            case .resigned(let w): return "\(w ? "Black" : "White") resigned. \(w ? "White" : "Black") wins."
            case .stalemate: return "Stalemate. Draw."
            case .fiftyMove: return "50-move rule. Draw."
            case .repetition: return "Threefold repetition. Draw."
            case .insufficient: return "Insufficient material. Draw."
            }
        }
    }

    let startFEN: String
    private(set) var board: ChessBoard
    private(set) var moves: [ChessMove] = []
    private(set) var sans: [String] = []
    private var undos: [ChessUndo] = []
    private var keys: [String] = []
    var resignation: Result?

    init(fen: String = ChessBoard.startFEN) {
        startFEN = fen
        board = ChessBoard(fen: fen) ?? ChessBoard()
        keys = [board.repetitionKey]
    }

    var legalMoves: [ChessMove] { board.legalMoves() }

    mutating func play(_ m: ChessMove) {
        let legal = board.legalMoves()
        guard legal.contains(m) else { return }
        sans.append(board.san(m, legal: legal))
        undos.append(board.make(m))
        moves.append(m)
        keys.append(board.repetitionKey)
    }

    mutating func undo() {
        guard let u = undos.popLast() else { return }
        board.unmake(u)
        moves.removeLast()
        sans.removeLast()
        keys.removeLast()
        resignation = nil
    }

    var result: Result {
        if let r = resignation { return r }
        if board.legalMoves().isEmpty {
            return board.inCheck ? .checkmate(whiteWins: !board.whiteToMove) : .stalemate
        }
        if board.insufficientMaterial { return .insufficient }
        if board.halfmove >= 100 { return .fiftyMove }
        if let last = keys.last, keys.filter({ $0 == last }).count >= 3 { return .repetition }
        return .ongoing
    }

    /// Positions seen so far (for engine repetition avoidance).
    var history: [String] { keys }
}
