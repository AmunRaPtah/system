import SwiftUI

/// Row shown in the Mind tab: one per playable game.
struct PlayRow: View {
    @Environment(SystemStore.self) private var store
    let game: Game
    var body: some View {
        let rs = store.playResults(game)
        let w = rs.filter { $0.outcome == PlayOutcome.win.rawValue }.count
        let d = rs.filter { $0.outcome == PlayOutcome.draw.rawValue }.count
        HStack {
            Image(systemName: game.symbol).foregroundStyle(Theme.gold).glow(Theme.gold)
            Text("PLAY \(game.title.uppercased())").font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
            Spacer()
            Text(rs.isEmpty ? "vs engine" : "W\(w) D\(d) L\(rs.count - w - d)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .systemPanel(Theme.gold)
    }
}

/// Setup screen for a game against the engine, with resume and recent results.
struct PlayHubView: View {
    @Environment(SystemStore.self) private var store
    let game: Game

    @AppStorage("play.level.chess") private var chessLevel = 1
    @AppStorage("play.level.go") private var goLevel = 1
    @AppStorage("play.chess.white") private var playWhite = true
    @AppStorage("play.go.size") private var goSize = 9
    @AppStorage("play.go.handicap") private var handicap = 0
    @AppStorage("play.go.black") private var playBlack = true

    @State private var chessGame: ChessSave?
    @State private var goGame: GoSave?
    @State private var savedChess: ChessSave?
    @State private var savedGo: GoSave?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = savedChess, game == .chess {
                    resumePanel("\(s.moves.count) moves, \(ChessLevel.names[s.level - 1]), you play \(s.playerWhite ? "white" : "black")") {
                        chessGame = s
                    }
                }
                if let s = savedGo, game == .go {
                    resumePanel("\(s.size)x\(s.size), \(s.moves.count) moves, \(GoLevel.names[s.level - 1])") {
                        goGame = s
                    }
                }
                setupPanel
                historyPanel
            }
            .padding()
        }
        .systemScreen("PLAY \(game.title.uppercased())")
        .onAppear(perform: refreshSaved)
        .navigationDestination(item: $chessGame) { s in ChessPlayView(setup: s) }
        .navigationDestination(item: $goGame) { s in GoPlayView(setup: s) }
    }

    private func refreshSaved() {
        savedChess = store.savedPlay(.chess, as: ChessSave.self)
        savedGo = store.savedPlay(.go, as: GoSave.self)
    }

    private func resumePanel(_ text: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BracketHeader(title: "Game in progress", color: Theme.gold, size: 12)
            Text(text).font(Theme.mono(12)).foregroundStyle(Theme.text)
            Button("RESUME", action: action).buttonStyle(.system(Theme.gold, filled: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel(Theme.gold)
    }

    private var levelBinding: Binding<Int> { game == .chess ? $chessLevel : $goLevel }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            BracketHeader(title: "New game", size: 12)
            Text("DIFFICULTY").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
            Picker("Level", selection: levelBinding) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Text(levelDescription).font(.system(size: 12)).foregroundStyle(Theme.dim)

            if game == .chess {
                Text("YOUR COLOUR").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                Picker("Colour", selection: $playWhite) {
                    Text("White").tag(true); Text("Black").tag(false)
                }
                .pickerStyle(.segmented)
            } else {
                Text("BOARD").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                Picker("Size", selection: $goSize) {
                    Text("9 x 9").tag(9); Text("13 x 13").tag(13)
                }
                .pickerStyle(.segmented)
                Text("YOUR COLOUR").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                Picker("Colour", selection: $playBlack) {
                    Text("Black").tag(true); Text("White").tag(false)
                }
                .pickerStyle(.segmented)
                if playBlack {
                    Text("HANDICAP STONES").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                    Picker("Handicap", selection: $handicap) {
                        Text("None").tag(0)
                        ForEach(2...(goSize >= 13 ? 9 : 5), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(handicap >= 2 ? "You start with \(handicap) stones; white moves first, komi 0.5." : "Even game, komi 7.5 to white.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }

            Button(hasSaved ? "NEW GAME (REPLACES SAVED)" : "START") { start() }
                .buttonStyle(.system(Theme.cyan, filled: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel()
    }

    private var hasSaved: Bool { game == .chess ? savedChess != nil : savedGo != nil }

    private var levelDescription: String {
        let l = levelBinding.wrappedValue
        if game == .chess {
            let p = ChessLevel.preset(l)
            let d = ["Plays loose, often misses captures.", "Sees one move ahead, still blunders.",
                     "Sees short tactics, rare mistakes.", "Solid tactics, no deliberate mistakes.",
                     "Full strength, up to \(Int(p.seconds))s per move."]
            return "\(ChessLevel.names[l - 1]): \(d[l - 1])"
        }
        let p = GoLevel.preset(l, size: goSize)
        return "\(GoLevel.names[l - 1]): \(p.playouts) simulated games per move."
    }

    private func start() {
        if game == .chess {
            store.clearSavedPlay(.chess)
            chessGame = ChessSave(level: chessLevel, playerWhite: playWhite)
        } else {
            store.clearSavedPlay(.go)
            let h = playBlack ? min(handicap, goSize >= 13 ? 9 : 5) : 0
            goGame = GoSave(size: goSize, handicap: h, level: goLevel, playerBlack: playBlack)
        }
        Haptics.impact()
    }

    private var historyPanel: some View {
        let rs = store.playResults(game)
        return VStack(alignment: .leading, spacing: 8) {
            BracketHeader(title: "Record", size: 12)
            if rs.isEmpty {
                Text("No games yet. Wins give INT XP: 20 + 10 x level. Using hint or undo halves it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            ForEach(1...5, id: \.self) { l in
                let at = rs.filter { $0.level == l }
                if !at.isEmpty {
                    let w = at.filter { $0.outcome == PlayOutcome.win.rawValue }.count
                    HStack {
                        Text("L\(l)").font(Theme.mono(11, .bold)).foregroundStyle(Theme.gold)
                        Text("\(w)/\(at.count) won").font(Theme.mono(11)).foregroundStyle(Theme.text)
                        Spacer()
                        SystemBar(value: Double(w) / Double(at.count), color: Theme.gold).frame(width: 120)
                    }
                }
            }
            ForEach(rs.prefix(8)) { r in
                HStack {
                    Text(r.outcome.uppercased()).font(Theme.mono(11, .bold))
                        .foregroundStyle(r.outcome == "win" ? Theme.green : (r.outcome == "draw" ? Theme.cyan : Theme.red))
                    Text("L\(r.level) \(r.colour)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    Text(r.detail).font(.system(size: 11)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text("+\(r.xp)").font(Theme.mono(11)).foregroundStyle(Theme.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel()
    }
}
