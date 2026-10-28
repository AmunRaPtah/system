import SwiftUI

/// Kim's game: memorise a grid of symbols, then find the cell that changed.
struct KimsDrill: View {
    let level: Int
    let finish: (DrillOutcome) -> Void

    static let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "moon.fill",
                          "drop.fill", "key.fill", "bell.fill", "crown.fill", "eye.fill", "hare.fill",
                          "tortoise.fill", "anchor", "scissors", "flag.fill"]

    enum Phase { case intro, study, blank, find, reveal }

    let rounds = 5
    @State private var phase: Phase = .intro
    @State private var round = 0
    @State private var correct = 0
    @State private var grid: [String?] = []
    @State private var changed = -1
    @State private var tapped = -1

    var side: Int { level >= 6 ? 5 : 4 }
    var items: Int { min(side * side - 2, 4 + level) }
    var studyTime: Double { max(1.5, 4.0 - 0.25 * Double(level - 1)) }

    var body: some View {
        DrillArena(status: "ROUND \(min(round + 1, rounds))/\(rounds) · \(items) ITEMS · \(String(format: "%.1f", studyTime)) s") {
            VStack(spacing: 12) {
                Text(prompt).font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
                let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: side)
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(0..<(side * side), id: \.self) { i in
                        cell(i)
                    }
                }
                .padding(10)
                if phase == .intro {
                    Button("READY") { startRound() }.buttonStyle(.system)
                }
            }
        }
    }

    var prompt: String {
        switch phase {
        case .intro: return "MEMORISE THE GRID, THEN FIND THE CHANGE"
        case .study: return "MEMORISE"
        case .blank: return "…"
        case .find: return "WHICH CELL CHANGED?"
        case .reveal: return tapped == changed ? "CORRECT" : "IT WAS HERE"
        }
    }

    func cell(_ i: Int) -> some View {
        let sym = i < grid.count ? grid[i] : nil
        let visible = phase == .study || phase == .find || phase == .reveal
        let border: Color = phase == .reveal && i == changed ? Theme.green : (phase == .reveal && i == tapped ? Theme.red : Theme.blue.opacity(0.4))
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Theme.bg2)
            RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: phase == .reveal && (i == changed || i == tapped) ? 2 : 1)
            if visible, let s = sym {
                Image(systemName: s).font(.system(size: side == 5 ? 20 : 26)).foregroundStyle(Theme.cyan).glow(Theme.cyan, radius: 3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { pick(i) }
    }

    func startRound() {
        let n = side * side
        var g = [String?](repeating: nil, count: n)
        let cells = Array(0..<n).shuffled()
        for c in cells.prefix(items) { g[c] = Self.symbols.randomElement() }
        grid = g
        phase = .study
        DispatchQueue.main.asyncAfter(deadline: .now() + studyTime) {
            phase = .blank
            // One change: swap a symbol, add one, or remove one.
            var g2 = grid
            let filled = g2.indices.filter { g2[$0] != nil }
            let empty = g2.indices.filter { g2[$0] == nil }
            let mode = Int.random(in: 0..<3)
            if mode == 0, let c = filled.randomElement() {
                g2[c] = Self.symbols.filter { $0 != g2[c] }.randomElement()
                changed = c
            } else if mode == 1, let c = empty.randomElement() {
                g2[c] = Self.symbols.randomElement()
                changed = c
            } else if let c = filled.randomElement() {
                g2[c] = nil
                changed = c
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                grid = g2
                tapped = -1
                phase = .find
            }
        }
    }

    func pick(_ i: Int) {
        guard phase == .find else { return }
        tapped = i
        if i == changed { correct += 1; Haptics.tap() } else { Haptics.warning() }
        phase = .reveal
        round += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if round >= rounds { complete() } else { startRound() }
        }
    }

    func complete() {
        let pct = Double(correct) / Double(rounds) * 100
        var n = level
        if correct >= 4 { n += 1 } else if correct <= 2 { n -= 1 }
        finish(DrillOutcome(score: pct.rounded(), detail: "\(correct)/\(rounds) changes found, \(items) items (\(Int(pct))%)", nextLevel: max(1, n)))
    }
}
