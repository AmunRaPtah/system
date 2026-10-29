import SwiftUI
import Charts

/// Entry row for the Mind tab.
struct PokerTrainerRow: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let recs = PokerStats.records(store)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "suit.club.fill").foregroundStyle(Theme.gold).glow(Theme.gold)
                Text("POKER TRAINER").font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(recs.count) sessions").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Text("Pot odds · equity · preflop ranges · outs").font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .systemPanel(Theme.gold)
    }
}

enum PokerStats {
    @MainActor static func records(_ store: SystemStore, _ drill: PokerDrill? = nil) -> [PokerDrillRecord] {
        _ = store.revision
        return store.fetchAll(PokerDrillRecord.self)
            .filter { drill == nil || $0.drill == drill?.rawValue }
            .sorted { $0.date < $1.date }
    }
}

struct PokerTrainerView: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let all = PokerStats.records(store)
        let hands = all.reduce(0) { $0 + $1.total }
        let right = all.reduce(0) { $0 + $1.correct }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    BracketHeader(title: "No-Limit Hold'em", color: Theme.gold)
                    Text("Short scored sessions of \(PokerDrill.hands) hands. Each answer is explained. Levels rise at 80% and fall below 50%.")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    Text(hands == 0 ? "No hands played yet." : "\(hands) hands · \(Int((Double(right) / Double(hands) * 100).rounded()))% correct")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.gold)
                }
                .systemPanel(Theme.gold)
                ForEach(PokerDrill.allCases) { d in
                    NavigationLink { PokerDrillHostView(drill: d) } label: { PokerDrillRow(drill: d) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .systemScreen("POKER")
        .onAppear { assert(PokerSelfTest.run().isEmpty, "Poker evaluator self-test failed: \(PokerSelfTest.run())") }
    }
}

struct PokerDrillRow: View {
    @Environment(SystemStore.self) private var store
    let drill: PokerDrill

    var body: some View {
        let recs = PokerStats.records(store, drill)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: drill.symbol).foregroundStyle(Theme.cyan).glow()
                Text(drill.title.uppercased()).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Tag(text: "LV \(drill.level(store.defaults))", color: Theme.gold)
                if let l = recs.last {
                    Text("\(Int(l.score))%").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            Text(drill.blurb).font(.system(size: 12)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.leading)
            SystemBar(value: (recs.last?.score ?? 0) / 100, color: Theme.cyan, height: 4)
        }
        .systemPanel()
    }
}

struct PokerDrillHostView: View {
    @Environment(SystemStore.self) private var store
    let drill: PokerDrill
    @State private var running = false
    @State private var last: PokerOutcome?
    @State private var lastNext = 1
    @State private var runID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if running {
                    session.id(runID)
                    Button("ABORT") { running = false }.buttonStyle(.system(Theme.red)).frame(maxWidth: .infinity)
                } else {
                    intro
                    if let o = last { results(o) }
                    PokerTrendChart(drill: drill).systemPanel(Theme.blue)
                }
            }
            .padding()
        }
        .systemScreen(drill.title.uppercased())
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: drill.symbol).foregroundStyle(Theme.cyan).glow()
                BracketHeader(title: drill.title)
            }
            Text(drill.blurb).font(.system(size: 13)).foregroundStyle(Theme.dim)
            Text("LEVEL \(drill.level(store.defaults)) · \(PokerDrill.hands) hands · XP to \(drill.stats.0.rawValue) + \(drill.stats.1.rawValue)")
                .font(Theme.mono(11)).foregroundStyle(Theme.gold)
            Button(last == nil ? "DEAL" : "DEAL AGAIN") {
                runID = UUID()
                running = true
                Haptics.impact()
            }
            .buttonStyle(.system(Theme.cyan, filled: true))
        }
        .systemPanel()
    }

    @ViewBuilder var session: some View {
        let level = drill.level(store.defaults)
        switch drill {
        case .potOdds: PotOddsDrill(level: level, finish: finish)
        case .equity: EquityDrill(level: level, finish: finish)
        case .preflop: PreflopDrill(level: level, finish: finish)
        case .outs: OutsDrill(level: level, finish: finish)
        }
    }

    func results(_ o: PokerOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                BracketHeader(title: "Result", color: Theme.green, size: 12)
                Text("\(o.correct)/\(o.total) correct · \(Int(o.pct.rounded()))%").font(Theme.mono(16, .bold)).foregroundStyle(Theme.text)
                Text("Next level: \(lastNext)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .systemPanel(Theme.green)
            BracketHeader(title: "Hand review", size: 12)
            ForEach(Array(o.reviews.enumerated()), id: \.element.id) { i, r in
                VStack(alignment: .leading, spacing: 4) {
                    Text("HAND \(i + 1)").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    PokerReviewPanel(review: r, compact: true)
                }
            }
        }
    }

    func finish(_ o: PokerOutcome) {
        let level = drill.level(store.defaults)
        let next = PokerDrill.nextLevel(level, pct: o.pct)
        drill.setLevel(next, store.defaults)
        let detail = "\(o.correct)/\(o.total) at level \(level)"
        store.context.insert(PokerDrillRecord(drill: drill, dayKey: DayKey.today, level: level,
                                              correct: o.correct, total: o.total, detail: detail))
        let base = 6 + 2 * min(level, 10) + o.correct
        let (primary, secondary) = drill.stats
        store.awardXP([(primary, base), (secondary, base / 3)], source: "poker", note: drill.title,
                      title: "[POKER DRILL COMPLETE]",
                      lines: ["\(drill.title): \(detail)  +\(base) XP \(primary.rawValue) · +\(base / 3) XP \(secondary.rawValue)"])
        lastNext = next
        last = o
        running = false
    }
}

struct PokerTrendChart: View {
    @Environment(SystemStore.self) private var store
    let drill: PokerDrill

    var body: some View {
        let rs = Array(PokerStats.records(store, drill).suffix(30))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TREND · % correct").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                Spacer()
                if let best = rs.map(\.score).max() {
                    Text("BEST \(Int(best))%").font(Theme.mono(10, .bold)).foregroundStyle(Theme.gold)
                }
            }
            if rs.count < 2 {
                Text(rs.isEmpty ? "No sessions yet." : "One session logged. The trend appears after two.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart(Array(rs.enumerated()), id: \.offset) { i, r in
                    LineMark(x: .value("#", i + 1), y: .value("%", r.score))
                        .foregroundStyle(Theme.cyan)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("#", i + 1), y: .value("%", r.score))
                        .foregroundStyle(Theme.cyan)
                        .symbolSize(18)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Theme.blue.opacity(0.2))
                        AxisValueLabel().foregroundStyle(Theme.dim)
                    }
                }
                .frame(height: 140)
            }
        }
    }
}
