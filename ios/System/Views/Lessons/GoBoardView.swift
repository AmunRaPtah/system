import SwiftUI

/// 9x9 go position. grid[row][col], row 0 = top (row 9), col 0 = column "a".
struct GoPosition {
    static let size = 9
    static let columns = Array("abcdefghj")   // no "i"
    var grid: [[Character]] = Array(repeating: Array(repeating: ".", count: 9), count: 9)

    init(_ s: String) {
        let rows = s.split(separator: "/")
        for (r, row) in rows.prefix(9).enumerated() {
            for (c, ch) in Array(row.lowercased()).prefix(9).enumerated() where ch == "b" || ch == "w" {
                grid[r][c] = ch
            }
        }
    }

    static func coord(_ s: String) -> (Int, Int)? {
        let c = Array(s.lowercased())
        guard c.count >= 2, let col = columns.firstIndex(of: c[0]), let n = Int(String(c.dropFirst())), (1...9).contains(n) else { return nil }
        return (9 - n, col)
    }

    static func name(_ r: Int, _ c: Int) -> String { "\(columns[c])\(9 - r)" }

    func neighbours(_ r: Int, _ c: Int) -> [(Int, Int)] {
        [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)].filter { $0.0 >= 0 && $0.0 < 9 && $0.1 >= 0 && $0.1 < 9 }
    }

    /// Stones in the group at (r, c) and whether it has any liberty.
    func group(_ r: Int, _ c: Int) -> (stones: [(Int, Int)], hasLiberty: Bool) {
        let colour = grid[r][c]
        var seen = Set<Int>([r * 9 + c])
        var stack = [(r, c)]
        var stones: [(Int, Int)] = []
        var liberty = false
        while let p = stack.popLast() {
            stones.append(p)
            for n in neighbours(p.0, p.1) {
                let v = grid[n.0][n.1]
                if v == "." { liberty = true }
                else if v == colour && !seen.contains(n.0 * 9 + n.1) {
                    seen.insert(n.0 * 9 + n.1)
                    stack.append(n)
                }
            }
        }
        return (stones, liberty)
    }

    /// Place a stone and remove captured opponent groups. Returns stones captured.
    @discardableResult
    mutating func play(_ r: Int, _ c: Int, _ colour: Character) -> Int {
        grid[r][c] = colour
        let other: Character = colour == "b" ? "w" : "b"
        var captured = 0
        for n in neighbours(r, c) where grid[n.0][n.1] == other {
            let g = group(n.0, n.1)
            if !g.hasLiberty {
                for s in g.stones { grid[s.0][s.1] = "." }
                captured += g.stones.count
            }
        }
        // Suicide: remove own group if it has no liberty after captures.
        let own = group(r, c)
        if !own.hasLiberty { for s in own.stones { grid[s.0][s.1] = "." } }
        return captured
    }
}

struct GoPuzzleView: View {
    let puzzle: Puzzle
    let onSolved: () -> Void

    @State private var pos: GoPosition
    @State private var step = 0
    @State private var message = ""
    @State private var solved = false
    @State private var last: String?

    init(puzzle: Puzzle, onSolved: @escaping () -> Void) {
        self.puzzle = puzzle
        self.onSolved = onSolved
        _pos = State(initialValue: GoPosition(puzzle.position))
    }

    var first: Character { puzzle.toMove == "w" ? "w" : "b" }
    func colour(at step: Int) -> Character { step % 2 == 0 ? first : (first == "b" ? "w" : "b") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(puzzle.goal.isEmpty ? "Find the vital point." : puzzle.goal)
                    .font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Tag(text: first == "b" ? "BLACK" : "WHITE", color: Theme.gold)
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
            let cell = g.size.width / 9
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0x1B2A44))
                Path { p in
                    for i in 0..<9 {
                        let o = cell / 2 + CGFloat(i) * cell
                        p.move(to: CGPoint(x: cell / 2, y: o)); p.addLine(to: CGPoint(x: g.size.width - cell / 2, y: o))
                        p.move(to: CGPoint(x: o, y: cell / 2)); p.addLine(to: CGPoint(x: o, y: g.size.width - cell / 2))
                    }
                }
                .stroke(Theme.cyan.opacity(0.45), lineWidth: 1)
                ForEach(0..<81, id: \.self) { i in
                    let r = i / 9, c = i % 9
                    let v = pos.grid[r][c]
                    ZStack {
                        Color.clear
                        if v != "." {
                            Circle()
                                .fill(v == "b" ? Color.black : Color.white)
                                .overlay(Circle().stroke(Theme.cyan.opacity(v == "b" ? 0.7 : 0.2)))
                                .padding(cell * 0.06)
                            if last == GoPosition.name(r, c) {
                                Circle().stroke(Theme.gold, lineWidth: 2).frame(width: cell * 0.35, height: cell * 0.35)
                            }
                        }
                    }
                    .frame(width: cell, height: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { tap(r, c) }
                    .offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.7)))
    }

    func tap(_ r: Int, _ c: Int) {
        guard !solved, step < puzzle.solution.count, pos.grid[r][c] == "." else { return }
        let name = GoPosition.name(r, c)
        let expected = puzzle.solution[step].lowercased()
        guard name == expected else {
            message = "Not the point. Try again."
            Haptics.warning()
            return
        }
        place(r, c)
        step += 1
        if step >= puzzle.solution.count { win(); return }
        message = "Correct. Opponent replies…"
        let reply = puzzle.solution[step]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let rc = GoPosition.coord(reply) { place(rc.0, rc.1) }
            step += 1
            if step >= puzzle.solution.count { win() } else { message = "Your move." }
        }
    }

    func place(_ r: Int, _ c: Int) {
        let n = pos.play(r, c, colour(at: step))
        last = GoPosition.name(r, c)
        if n > 0 { Haptics.impact() } else { Haptics.tap() }
    }

    func win() {
        solved = true
        message = "[SOLVED]"
        Haptics.success()
        onSolved()
    }

    func reset() {
        pos = GoPosition(puzzle.position)
        step = 0
        last = nil
        message = ""
        solved = false
    }
}
