import SwiftUI

struct MindView: View {
    @Environment(SystemStore.self) private var store
    private let lib = ContentLibrary.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BracketHeader(title: "Perception", size: 13)
                    ForEach(DrillKind.allCases) { kind in
                        NavigationLink { DrillHostView(kind: kind) } label: { DrillRow(kind: kind) }
                            .buttonStyle(.plain)
                    }
                    Text("Audio direction drill: not in v1.").font(Theme.mono(10)).foregroundStyle(Theme.dim)

                    BracketHeader(title: "Strategy", size: 13).padding(.top, 6)
                    if lib.availableGames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("[NO LESSON FILES FOUND]").font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
                            Text("Lessons load from Resources/Content/lessons-chess.json, lessons-go.json and lessons-poker.json. Add them and rebuild.")
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                        .systemPanel(Theme.gold)
                    }
                    ForEach(lib.availableGames) { game in
                        NavigationLink { GameLessonsView(game: game) } label: { GameRow(game: game) }
                            .buttonStyle(.plain)
                    }

                    BracketHeader(title: "Play vs Engine", size: 13).padding(.top, 6)
                    ForEach([Game.chess, Game.go]) { game in
                        NavigationLink { PlayHubView(game: game) } label: { PlayRow(game: game) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .systemScreen("MIND")
        }
    }
}

struct DrillRow: View {
    @Environment(SystemStore.self) private var store
    let kind: DrillKind
    var body: some View {
        let rs = store.results(kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: kind.symbol).foregroundStyle(Theme.cyan).glow()
                Text(kind.title.uppercased()).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Tag(text: "LV \(store.drillLevel(kind))", color: Theme.gold)
                if let l = rs.last {
                    Text("\(Int(l.score))\(kind.unit)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            DrillTrendChart(kind: kind, height: 70)
        }
        .systemPanel()
    }
}

struct GameRow: View {
    @Environment(SystemStore.self) private var store
    let game: Game
    var body: some View {
        let all = ContentLibrary.shared.allLessons(game)
        let done = all.filter { store.lessonDone($0.id) }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: game.symbol).foregroundStyle(Theme.violet).glow(Theme.violet)
                Text(game.title.uppercased()).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(done)/\(all.count)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            SystemBar(value: all.isEmpty ? 0 : Double(done) / Double(all.count), color: Theme.violet)
        }
        .systemPanel(Theme.violet)
    }
}
