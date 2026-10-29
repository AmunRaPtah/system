import SwiftUI

/// Full chess game against the on-device engine.
struct ChessPlayView: View {
    @Environment(SystemStore.self) private var store
    let setup: ChessSave

    @State private var game = ChessGame()
    @State private var loaded = false
    @State private var selected: Int?
    @State private var thinking = false
    @State private var generation = 0
    @State private var hint: ChessMove?
    @State private var assisted = false
    @State private var promotion: [ChessMove] = []
    @State private var showPromotion = false
    @State private var recordedXP: Int?
    @State private var confirmResign = false

    private var playerWhite: Bool { setup.playerWhite }
    private var playerToMove: Bool { game.board.whiteToMove == playerWhite }
    private var level: ChessLevel { .preset(setup.level) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                board
                controls
                if game.result.isOver { resultPanel }
                moveList
            }
            .padding()
        }
        .systemScreen("CHESS")
        .onAppear(perform: load)
        .onDisappear(perform: persist)
        .confirmationDialog("Promote to", isPresented: $showPromotion, titleVisibility: .visible) {
            ForEach(promotion, id: \.self) { m in
                Button(promoName(m.promo)) { playerMove(m) }
            }
            Button("Cancel", role: .cancel) { promotion = [] }
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { resign() }
        }
    }

    // MARK: - Pieces of UI

    private var header: some View {
        HStack {
            Tag(text: ChessLevel.names[setup.level - 1], color: Theme.gold)
            Tag(text: playerWhite ? "YOU: WHITE" : "YOU: BLACK", color: Theme.cyan)
            if assisted { Tag(text: "ASSISTED", color: Theme.violet) }
            Spacer()
            Text(status).font(Theme.mono(11, .bold)).foregroundStyle(statusColor)
        }
    }

    private var status: String {
        let r = game.result
        if r.isOver { return r.text.uppercased() }
        if thinking { return "ENGINE THINKING..." }
        return (game.board.inCheck ? "CHECK. " : "") + (playerToMove ? "YOUR MOVE" : "ENGINE")
    }

    private var statusColor: Color {
        if game.result.isOver { return Theme.gold }
        return game.board.inCheck ? Theme.red : (playerToMove ? Theme.cyan : Theme.dim)
    }

    private var board: some View {
        let legal = game.legalMoves
        let targets = selected.map { s in legal.filter { $0.from == s } } ?? []
        let last = game.moves.last
        let checkSq = game.board.inCheck ? game.board.kingSq[game.board.whiteToMove ? 0 : 1] : nil
        return GeometryReader { geo in
            let cell = geo.size.width / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let sq = square(row: row, col: col)
                            squareView(sq, cell: cell, row: row, col: col,
                                       isLast: last.map { $0.from == sq || $0.to == sq } ?? false,
                                       isHint: hint.map { $0.from == sq || $0.to == sq } ?? false,
                                       target: targets.first { $0.to == sq },
                                       inCheck: checkSq == sq)
                                .onTapGesture { tap(sq) }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
        .glow(Theme.cyan, radius: 3)
    }

    private func square(row: Int, col: Int) -> Int {
        playerWhite ? (7 - row) * 8 + col : row * 8 + (7 - col)
    }

    @ViewBuilder
    private func squareView(_ sq: Int, cell: CGFloat, row: Int, col: Int, isLast: Bool, isHint: Bool,
                            target: ChessMove?, inCheck: Bool) -> some View {
        let dark = (sq / 8 + sq % 8) % 2 == 0
        let p = game.board.sq[sq]
        ZStack {
            Rectangle().fill(dark ? Color(hex: 0x16305E) : Color(hex: 0x2A4C85))
            if isLast { Rectangle().fill(Theme.gold.opacity(0.25)) }
            if inCheck { Rectangle().fill(Theme.red.opacity(0.45)) }
            if isHint { Rectangle().stroke(Theme.violet, lineWidth: 3) }
            if selected == sq { Rectangle().stroke(Theme.cyan, lineWidth: 3) }
            if p != 0 {
                Text(ChessPosition.glyph(ChessBoard.letter(p)))
                    .font(.system(size: cell * 0.78))
                    .foregroundStyle(p > 0 ? Color.white : Color.black)
                    .shadow(color: p > 0 ? .black : Theme.cyan.opacity(0.8), radius: 1.5)
            }
            if target != nil {
                if p != 0 || target?.flag == .enPassant {
                    Circle().stroke(Theme.cyan.opacity(0.8), lineWidth: 3).padding(cell * 0.06)
                } else {
                    Circle().fill(Theme.cyan.opacity(0.6)).frame(width: cell * 0.28, height: cell * 0.28)
                }
            }
            if col == 0 {
                Text("\(sq / 8 + 1)").font(Theme.mono(8)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(2)
            }
            if row == 7 {
                Text(String("abcdefgh"[String.Index(utf16Offset: sq % 8, in: "abcdefgh")]))
                    .font(Theme.mono(8)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(2)
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("UNDO") { undo() }
                .buttonStyle(.system(Theme.cyan))
                .disabled(game.moves.isEmpty || recordedXP != nil)
            Button("HINT") { askHint() }
                .buttonStyle(.system(Theme.violet))
                .disabled(!playerToMove || thinking || game.result.isOver)
            Button("RESIGN") { confirmResign = true }
                .buttonStyle(.system(Theme.red))
                .disabled(game.result.isOver)
        }
    }

    private var resultPanel: some View {
        let r = game.result
        let outcome = outcomeFor(r)
        return VStack(alignment: .leading, spacing: 6) {
            Text(outcome.title).font(Theme.mono(18, .bold)).foregroundStyle(outcome == .win ? Theme.gold : (outcome == .draw ? Theme.cyan : Theme.red))
            Text(r.text).font(.system(size: 13)).foregroundStyle(Theme.text)
            if let xp = recordedXP {
                Text("+\(xp) XP INT" + (assisted ? " (assisted, half XP)" : "")).font(Theme.mono(12)).foregroundStyle(Theme.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel(Theme.gold)
    }

    private var moveList: some View {
        let sans = game.sans
        let text = stride(from: 0, to: sans.count, by: 2).map { i in
            "\(i / 2 + 1). \(sans[i])" + (i + 1 < sans.count ? " \(sans[i + 1])" : "")
        }.joined(separator: "  ")
        return VStack(alignment: .leading, spacing: 6) {
            BracketHeader(title: "Moves", size: 11)
            Text(text.isEmpty ? "No moves yet." : text)
                .font(Theme.mono(12)).foregroundStyle(text.isEmpty ? Theme.dim : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel()
    }

    // MARK: - Game flow

    private func load() {
        guard !loaded else { return }
        loaded = true
        var g = ChessGame(fen: setup.startFEN)
        for u in setup.moves { if let m = g.board.move(uci: u) { g.play(m) } }
        game = g
        assisted = setup.assisted
        if game.result.isOver { finishIfNeeded() } else { engineTurnIfNeeded() }
    }

    private func persist() {
        guard recordedXP == nil, !game.result.isOver, !game.moves.isEmpty else { return }
        var s = setup
        s.moves = game.moves.map(\.uci)
        s.assisted = assisted
        store.savePlay(.chess, s)
    }

    private func tap(_ sq: Int) {
        guard playerToMove, !thinking, !game.result.isOver else { return }
        let p = game.board.sq[sq]
        if let from = selected {
            let ms = game.legalMoves.filter { $0.from == from && $0.to == sq }
            if ms.count > 1 {
                promotion = ms.sorted { $0.promo > $1.promo }
                showPromotion = true
                return
            }
            if let m = ms.first { playerMove(m); return }
        }
        let own = p != 0 && (p > 0) == playerWhite
        selected = own && selected != sq ? sq : nil
        if own { Haptics.tap() }
    }

    private func playerMove(_ m: ChessMove) {
        game.play(m)
        selected = nil
        hint = nil
        promotion = []
        Haptics.impact()
        persist()
        if game.result.isOver { finishIfNeeded() } else { engineTurnIfNeeded() }
    }

    private func engineTurnIfNeeded() {
        guard !playerToMove, !game.result.isOver, !thinking else { return }
        thinking = true
        let board = game.board, hist = game.history, lvl = level, gen = generation
        Task {
            let started = Date()
            let mv = await Task.detached(priority: .userInitiated) { () -> ChessMove? in
                var rng = SystemRandomNumberGenerator()
                return ChessEngine(board: board, seenKeys: hist).bestMove(level: lvl, rng: &rng)
            }.value
            // A short floor so instant replies at low levels still read as a move.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.35 { try? await Task.sleep(nanoseconds: UInt64((0.35 - elapsed) * 1e9)) }
            guard gen == generation else { return }
            thinking = false
            if let mv { game.play(mv); Haptics.tap() }
            persist()
            if game.result.isOver { finishIfNeeded() }
        }
    }

    private func undo() {
        generation += 1
        thinking = false
        hint = nil
        selected = nil
        game.undo()
        while !playerToMove && !game.moves.isEmpty { game.undo() }
        assisted = true
        persist()
        engineTurnIfNeeded()
    }

    private func askHint() {
        let board = game.board, gen = generation
        assisted = true
        thinking = true
        Task {
            let mv = await Task.detached(priority: .userInitiated) {
                ChessEngine(board: board).think(seconds: 1.0, maxDepth: 6)
            }.value
            guard gen == generation else { return }
            thinking = false
            hint = mv
            if let mv { selected = mv.from }
        }
    }

    private func resign() {
        generation += 1
        thinking = false
        game.resignation = .resigned(whiteWins: !playerWhite)
        finishIfNeeded()
    }

    private func outcomeFor(_ r: ChessGame.Result) -> PlayOutcome {
        guard let w = r.whiteWins else { return .draw }
        return w == playerWhite ? .win : .loss
    }

    private func finishIfNeeded() {
        let r = game.result
        guard r.isOver, recordedXP == nil else { return }
        let outcome = outcomeFor(r)
        outcome == .win ? Haptics.success() : Haptics.warning()
        recordedXP = store.recordPlay(.chess, outcome: outcome, level: setup.level,
                                      colour: playerWhite ? "white" : "black",
                                      moves: game.moves.count, detail: r.text, assisted: assisted)
    }

    private func promoName(_ p: Int8) -> String {
        switch abs(Int(p)) {
        case 5: return "Queen"
        case 4: return "Rook"
        case 3: return "Bishop"
        default: return "Knight"
        }
    }
}
