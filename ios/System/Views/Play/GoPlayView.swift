import SwiftUI

/// Go game against the on-device MCTS engine, with a dead-stone marking phase at the end.
struct GoPlayView: View {
    @Environment(SystemStore.self) private var store
    let setup: GoSave

    @State private var game = GoGame(size: 9, handicap: 0)
    @State private var loaded = false
    @State private var thinking = false
    @State private var generation = 0
    @State private var hint: Int?
    @State private var assisted = false
    @State private var dead: Set<Int> = []
    @State private var scoring = false
    @State private var resigned = false
    @State private var recordedXP: Int?
    @State private var engineNote = ""
    @State private var confirmResign = false

    private var playerColour: Int8 { setup.playerBlack ? GoStone.black : GoStone.white }
    private var playerToMove: Bool { game.board.toPlay == playerColour }
    private var finished: Bool { recordedXP != nil }
    private var n: Int { game.size }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                board
                if scoring && !finished { scoringPanel } else if !finished { controls }
                if finished { resultPanel }
                infoPanel
            }
            .padding()
        }
        .systemScreen("GO")
        .onAppear(perform: load)
        .onDisappear(perform: persist)
        .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { resign() }
        }
    }

    // MARK: - UI

    private var header: some View {
        HStack {
            Tag(text: GoLevel.names[setup.level - 1], color: Theme.gold)
            Tag(text: setup.playerBlack ? "YOU: BLACK" : "YOU: WHITE", color: Theme.cyan)
            if game.handicap >= 2 { Tag(text: "H\(game.handicap)", color: Theme.violet) }
            if assisted { Tag(text: "ASSISTED", color: Theme.violet) }
            Spacer()
            Text(status).font(Theme.mono(11, .bold)).foregroundStyle(playerToMove && !scoring ? Theme.cyan : Theme.dim)
        }
    }

    private var status: String {
        if finished { return "GAME OVER" }
        if scoring { return "MARK DEAD STONES" }
        if thinking { return "ENGINE THINKING..." }
        if game.lastWasPass && playerToMove { return "ENGINE PASSED" }
        return playerToMove ? "YOUR MOVE" : "ENGINE"
    }

    private var board: some View {
        let owner = scoring || finished ? game.board.ownership(dead: dead) : []
        return GeometryReader { geo in
            let cell = geo.size.width / CGFloat(n)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0x1B2A44))
                Canvas { ctx, size in
                    var path = Path()
                    for i in 0..<n {
                        let c = cell * (CGFloat(i) + 0.5)
                        path.move(to: CGPoint(x: cell / 2, y: c)); path.addLine(to: CGPoint(x: size.width - cell / 2, y: c))
                        path.move(to: CGPoint(x: c, y: cell / 2)); path.addLine(to: CGPoint(x: c, y: size.height - cell / 2))
                    }
                    ctx.stroke(path, with: .color(Theme.cyan.opacity(0.45)), lineWidth: 1)
                    for p in starPoints {
                        let r = CGRect(x: cell * (CGFloat(p % n) + 0.5) - 3, y: cell * (CGFloat(p / n) + 0.5) - 3, width: 6, height: 6)
                        ctx.fill(Path(ellipseIn: r), with: .color(Theme.cyan.opacity(0.6)))
                    }
                }
                ForEach(0..<(n * n), id: \.self) { p in
                    point(p, cell: cell, owner: owner.isEmpty ? 0 : owner[p])
                        .position(x: cell * (CGFloat(p % n) + 0.5), y: cell * (CGFloat(p / n) + 0.5))
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { e in
                let c = Int(e.location.x / cell), r = Int(e.location.y / cell)
                guard r >= 0, r < n, c >= 0, c < n else { return }
                tap(r * n + c)
            })
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
        .glow(Theme.cyan, radius: 3)
    }

    private var starPoints: [Int] {
        n >= 13 ? GoBoard.handicapPoints(size: n, count: 5)
                : [2 * n + 2, 2 * n + 6, 6 * n + 2, 6 * n + 6, 4 * n + 4]
    }

    @ViewBuilder
    private func point(_ p: Int, cell: CGFloat, owner: Int8) -> some View {
        let v = game.board.cells[p]
        let d = cell * 0.9
        ZStack {
            if v != 0 {
                Circle()
                    .fill(v == GoStone.black ? Color.black : Color.white)
                    .overlay(Circle().stroke(Theme.cyan.opacity(v == GoStone.black ? 0.7 : 0.4), lineWidth: 1))
                    .frame(width: d, height: d)
                    .opacity(dead.contains(p) ? 0.35 : 1)
                if dead.contains(p) {
                    Image(systemName: "xmark").font(.system(size: cell * 0.4, weight: .bold)).foregroundStyle(Theme.red)
                }
                if p == game.lastMove && !scoring && !finished {
                    Circle().stroke(Theme.gold, lineWidth: 2).frame(width: d * 0.5, height: d * 0.5)
                }
            }
            if owner != 0 && (v == 0 || dead.contains(p)) {
                Rectangle().fill(owner == GoStone.black ? Color.black : Color.white)
                    .frame(width: cell * 0.3, height: cell * 0.3)
                    .overlay(Rectangle().stroke(Theme.cyan.opacity(0.5), lineWidth: 0.5))
            }
            if hint == p {
                Circle().stroke(Theme.violet, lineWidth: 3).frame(width: d, height: d)
            }
        }
        .frame(width: cell, height: cell)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("PASS") { playerPass() }
                .buttonStyle(.system(Theme.gold))
                .disabled(!playerToMove || thinking)
            Button("UNDO") { undo() }
                .buttonStyle(.system(Theme.cyan))
                .disabled(game.moves.isEmpty)
            Button("HINT") { askHint() }
                .buttonStyle(.system(Theme.violet))
                .disabled(!playerToMove || thinking)
            Button("RESIGN") { confirmResign = true }
                .buttonStyle(.system(Theme.red))
        }
    }

    private var scoreLine: String {
        let s = game.board.areaScore(dead: dead)
        let m = game.margin(dead: dead)
        let komi = String(format: "%.1f", game.komi)
        let res = m > 0 ? "B+\(String(format: "%.1f", m))" : "W+\(String(format: "%.1f", -m))"
        return "Black \(s.black)  White \(s.white) + \(komi) komi  ->  \(res)"
    }

    private var scoringPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Both players passed. Tap a group to mark it dead or alive; the engine's guess is pre-marked. Score is area scoring: stones plus surrounded empty points.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            Text(scoreLine).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                Button("CONFIRM SCORE") { confirmScore() }.buttonStyle(.system(Theme.gold, filled: true))
                Button("KEEP PLAYING") { resumePlay() }.buttonStyle(.system(Theme.cyan))
            }
        }
        .systemPanel(Theme.gold)
    }

    private var resultPanel: some View {
        let outcome = currentOutcome
        return VStack(alignment: .leading, spacing: 6) {
            Text(outcome.title).font(Theme.mono(18, .bold)).foregroundStyle(outcome == .win ? Theme.gold : Theme.red)
            Text(resultText).font(.system(size: 13)).foregroundStyle(Theme.text)
            if let xp = recordedXP {
                Text("+\(xp) XP INT" + (assisted ? " (assisted, half XP)" : "")).font(Theme.mono(12)).foregroundStyle(Theme.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel(Theme.gold)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Captures  B \(game.board.capturedBy[1])  W \(game.board.capturedBy[2])  |  Moves \(game.moves.count)  |  Komi \(String(format: "%.1f", game.komi))")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            if !engineNote.isEmpty { Text(engineNote).font(Theme.mono(10)).foregroundStyle(Theme.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel()
    }

    // MARK: - Flow

    private func load() {
        guard !loaded else { return }
        loaded = true
        var g = GoGame(size: setup.size, handicap: setup.handicap)
        for m in setup.moves {
            if m < 0 { g.pass() } else if g.play(m) == nil { break }
        }
        game = g
        assisted = setup.assisted
        if game.isOver { enterScoring() } else { engineTurnIfNeeded() }
    }

    private func persist() {
        guard !finished, !game.moves.isEmpty else { return }
        var s = setup
        s.moves = game.moves
        s.assisted = assisted
        store.savePlay(.go, s)
    }

    private func tap(_ p: Int) {
        if finished { return }
        if scoring { toggleDead(p); return }
        guard playerToMove, !thinking else { return }
        if game.play(p) != nil {
            hint = nil
            Haptics.tap()
            persist()
            engineTurnIfNeeded()
        } else {
            Haptics.warning()
        }
    }

    private func playerPass() {
        game.pass()
        hint = nil
        persist()
        if game.isOver { enterScoring() } else { engineTurnIfNeeded() }
    }

    private func engineTurnIfNeeded() {
        guard !playerToMove, !game.isOver, !thinking, !finished else { return }
        thinking = true
        let board = game.board, komi = game.komi, gen = generation
        let lvl = GoLevel.preset(setup.level, size: n)
        let opponentPassed = game.lastWasPass
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                GoMCTS(board: board, komi: komi).search(level: lvl, opponentPassed: opponentPassed)
            }.value
            guard gen == generation else { return }
            thinking = false
            engineNote = "Engine: \(r.playouts) playouts, \(Int(r.winRate * 100))% win estimate"
            if let m = r.move, game.play(m) != nil { Haptics.tap() } else { game.pass() }
            persist()
            if game.isOver { enterScoring() }
        }
    }

    private func undo() {
        generation += 1
        thinking = false
        hint = nil
        game.undo()
        while !playerToMove && !game.moves.isEmpty { game.undo() }
        assisted = true
        persist()
        engineTurnIfNeeded()
    }

    private func askHint() {
        let board = game.board, komi = game.komi, gen = generation
        let lvl = GoLevel.preset(4, size: n)
        assisted = true
        thinking = true
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                GoMCTS(board: board, komi: komi).search(level: lvl, opponentPassed: false)
            }.value
            guard gen == generation else { return }
            thinking = false
            hint = r.move
            engineNote = r.move == nil ? "Hint: pass" : "Hint: violet ring"
        }
    }

    private func enterScoring() {
        scoring = true
        let board = game.board, komi = game.komi
        Task {
            dead = await Task.detached(priority: .userInitiated) { GoMCTS.suggestDead(board, komi: komi) }.value
        }
    }

    private func toggleDead(_ p: Int) {
        guard game.board.cells[p] != 0 else { return }
        var b = game.board
        let g = b.group(p)
        if dead.contains(p) { dead.subtract(g) } else { dead.formUnion(g) }
        Haptics.tap()
    }

    private func resumePlay() {
        scoring = false
        dead = []
        // Take back the passes so play continues with the player to move.
        while game.lastWasPass { game.undo() }
        while !playerToMove && !game.moves.isEmpty { game.undo() }
        persist()
        engineTurnIfNeeded()
    }

    private var currentOutcome: PlayOutcome {
        if resigned { return .loss }
        let m = game.margin(dead: dead)
        return (m > 0) == setup.playerBlack ? .win : .loss
    }

    private var resultText: String {
        if resigned { return "\(setup.playerBlack ? "Black" : "White") resigned." }
        return scoreLine
    }

    private func confirmScore() {
        scoring = false
        record()
    }

    private func resign() {
        generation += 1
        thinking = false
        scoring = false
        resigned = true
        record()
    }

    private func record() {
        guard recordedXP == nil else { return }
        let outcome = currentOutcome
        outcome == .win ? Haptics.success() : Haptics.warning()
        let m = game.margin(dead: dead)
        let detail = resigned ? "Resigned." : (m > 0 ? "B+" : "W+") + String(format: "%.1f", abs(m)) + " (\(n)x\(n))"
        recordedXP = store.recordPlay(.go, outcome: outcome, level: setup.level,
                                      colour: setup.playerBlack ? "black" : "white",
                                      moves: game.moves.count, detail: detail, assisted: assisted)
    }
}
