import SwiftUI

/// Minimal chess position: enough to replay puzzle lines.
/// Handles castling, en passant and promotion. It does not check legality;
/// the puzzle's UCI solution is the only accepted answer.
struct ChessPosition {
    /// board[rank][file], rank 0 = rank 1. Pieces as FEN letters, nil = empty.
    var board: [[Character?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    var whiteToMove = true
    var epSquare: (Int, Int)?

    init(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        let rows = (parts.first ?? "").split(separator: "/")
        for (i, row) in rows.prefix(8).enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue { file += n }
                else if file < 8 { board[rank][file] = ch; file += 1 }
            }
        }
        if parts.count > 1 { whiteToMove = parts[1] != "b" }
        if parts.count > 3, let sq = ChessPosition.square(parts[3]) { epSquare = sq }
    }

    static func square(_ s: String) -> (Int, Int)? {
        let c = Array(s.lowercased())
        guard c.count >= 2, let f = "abcdefgh".firstIndex(of: c[0]), let r = c[1].wholeNumberValue, (1...8).contains(r) else { return nil }
        return (r - 1, "abcdefgh".distance(from: "abcdefgh".startIndex, to: f))
    }

    static func name(_ rank: Int, _ file: Int) -> String {
        let files = Array("abcdefgh")
        return "\(files[file])\(rank + 1)"
    }

    func piece(_ rank: Int, _ file: Int) -> Character? { board[rank][file] }

    static func isWhite(_ p: Character) -> Bool { p.isUppercase }

    /// Apply a UCI move such as "e2e4", "e7e8q", "e1g1".
    mutating func apply(_ uci: String) {
        let s = uci.lowercased()
        guard s.count >= 4 else { return }
        let from = String(s.prefix(2)), to = String(s.dropFirst(2).prefix(2))
        guard let a = ChessPosition.square(from), let b = ChessPosition.square(to), let p = board[a.0][a.1] else { return }
        let lower = Character(p.lowercased())
        // En passant capture.
        if lower == "p", a.1 != b.1, board[b.0][b.1] == nil {
            board[a.0][b.1] = nil
        }
        // Castling: move the rook too.
        if lower == "k", abs(a.1 - b.1) == 2 {
            if b.1 == 6 { board[a.0][5] = board[a.0][7]; board[a.0][7] = nil }
            if b.1 == 2 { board[a.0][3] = board[a.0][0]; board[a.0][0] = nil }
        }
        var moved = p
        if lower == "p", b.0 == 7 || b.0 == 0 {
            let promo = s.count >= 5 ? Character(String(s.suffix(1))) : "q"
            moved = ChessPosition.isWhite(p) ? Character(promo.uppercased()) : promo
        }
        board[b.0][b.1] = moved
        board[a.0][a.1] = nil
        epSquare = (lower == "p" && abs(a.0 - b.0) == 2) ? ((a.0 + b.0) / 2, a.1) : nil
        whiteToMove.toggle()
    }

    static func glyph(_ p: Character) -> String {
        switch p {
        case "K": return "♔"; case "Q": return "♕"; case "R": return "♖"
        case "B": return "♗"; case "N": return "♘"; case "P": return "♙"
        case "k": return "♚"; case "q": return "♛"; case "r": return "♜"
        case "b": return "♝"; case "n": return "♞"; case "p": return "♟"
        default: return ""
        }
    }
}

struct ChessPuzzleView: View {
    let puzzle: Puzzle
    let onSolved: () -> Void

    @State private var pos: ChessPosition
    @State private var step = 0
    @State private var selected: (Int, Int)?
    @State private var message = ""
    @State private var solved = false
    @State private var lastMove: [String] = []

    init(puzzle: Puzzle, onSolved: @escaping () -> Void) {
        self.puzzle = puzzle
        self.onSolved = onSolved
        _pos = State(initialValue: ChessPosition(fen: puzzle.position))
    }

    var flipped: Bool { puzzle.toMove == "b" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(puzzle.goal.isEmpty ? "Find the best move." : puzzle.goal)
                    .font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Tag(text: flipped ? "BLACK" : "WHITE", color: Theme.gold)
            }
            board
            HStack {
                Text(message).font(Theme.mono(11)).foregroundStyle(solved ? Theme.green : Theme.dim)
                Spacer()
                Button("RESET") { reset() }.buttonStyle(.system(Theme.dim))
            }
        }
    }

    var board: some View {
        GeometryReader { g in
            let sq = g.size.width / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let rank = flipped ? row : 7 - row
                            let file = flipped ? 7 - col : col
                            cell(rank, file, size: sq)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.7)))
    }

    func cell(_ rank: Int, _ file: Int, size: CGFloat) -> some View {
        let dark = (rank + file) % 2 == 0
        let name = ChessPosition.name(rank, file)
        let isSel = selected.map { $0.0 == rank && $0.1 == file } ?? false
        let isLast = lastMove.contains(name)
        return ZStack {
            Rectangle().fill(dark ? Color(hex: 0x16305E) : Color(hex: 0x2A4C85))
            if isLast { Rectangle().fill(Theme.gold.opacity(0.25)) }
            if isSel { Rectangle().stroke(Theme.cyan, lineWidth: 3) }
            if let p = pos.piece(rank, file) {
                Text(ChessPosition.glyph(p))
                    .font(.system(size: size * 0.74))
                    .foregroundStyle(ChessPosition.isWhite(p) ? Color.white : Color.black)
                    .shadow(color: ChessPosition.isWhite(p) ? .black : Theme.cyan.opacity(0.6), radius: 1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { tap(rank, file) }
    }

    func tap(_ rank: Int, _ file: Int) {
        guard !solved, step < puzzle.solution.count else { return }
        if let s = selected {
            if s.0 == rank && s.1 == file { selected = nil; return }
            // Re-select another own piece.
            if let p = pos.piece(rank, file), ChessPosition.isWhite(p) == pos.whiteToMove {
                selected = (rank, file); Haptics.tap(); return
            }
            let uci = ChessPosition.name(s.0, s.1) + ChessPosition.name(rank, file)
            selected = nil
            let expected = puzzle.solution[step].lowercased()
            if expected.hasPrefix(uci) {
                play(expected)
                step += 1
                Haptics.tap()
                if step >= puzzle.solution.count { win(); return }
                message = "Correct. Opponent replies…"
                let reply = puzzle.solution[step].lowercased()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    play(reply)
                    step += 1
                    if step >= puzzle.solution.count { win() } else { message = "Your move." }
                }
            } else {
                message = "Not the move. Try again."
                Haptics.warning()
            }
        } else if let p = pos.piece(rank, file), ChessPosition.isWhite(p) == pos.whiteToMove {
            selected = (rank, file)
            Haptics.tap()
        }
    }

    func play(_ uci: String) {
        pos.apply(uci)
        lastMove = [String(uci.prefix(2)), String(uci.dropFirst(2).prefix(2))]
    }

    func win() {
        solved = true
        message = "[SOLVED]"
        Haptics.success()
        onSolved()
    }

    func reset() {
        pos = ChessPosition(fen: puzzle.position)
        step = 0
        selected = nil
        lastMove = []
        message = ""
        solved = false
    }
}
