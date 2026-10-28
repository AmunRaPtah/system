import SwiftUI
import Charts

struct AssessmentView: View {
    @Environment(SystemStore.self) private var store
    @State private var runMin = 6
    @State private var runSec = 30
    @State private var pushups = 15
    @State private var plankSec = 60
    @State private var reactionMs = 350
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    BracketHeader(title: "Boss Room", color: Theme.red)
                    Text("Warm up 10 min. Run 1 km all-out on flat ground. Rest 5 min. One set of push-ups to failure, chest to fist, full lockout. Rest 3 min. Forearm plank to form failure. Finish with the Reaction drill for a perception baseline.")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                }
                .systemPanel(Theme.red)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1 KM RUN").font(Theme.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                        Stepper("\(runMin) min", value: $runMin, in: 2...15).font(Theme.mono(12))
                    }
                    HStack {
                        Spacer().frame(width: 110)
                        Stepper("\(runSec) s", value: $runSec, in: 0...59).font(Theme.mono(12))
                    }
                    row("PUSH-UPS", $pushups, 0...150, 1, "")
                    row("PLANK", $plankSec, 0...900, 5, " s")
                    row("REACTION", $reactionMs, 150...800, 5, " ms")
                    if let best = store.results(.reaction).suffix(5).map(\.score).min() {
                        Button("Use best recent reaction (\(Int(best)) ms)") { reactionMs = Int(best) }
                            .font(Theme.mono(11)).foregroundStyle(Theme.cyan)
                    }
                    NavigationLink { DrillHostView(kind: .reaction) } label: { Text("RUN REACTION DRILL ›") }
                        .buttonStyle(.system(Theme.cyan))
                }
                .systemPanel()

                if logged {
                    Text("ASSESSMENT LOGGED").font(Theme.mono(14, .bold)).foregroundStyle(Theme.green)
                } else {
                    Button("SUBMIT RESULTS") {
                        store.logAssessment(run1kSec: runMin * 60 + runSec, pushups: pushups, plankSec: plankSec, reactionMs: reactionMs)
                        logged = true
                    }
                    .buttonStyle(.system(Theme.red, filled: true))
                }

                RankGatesCard()
                AssessmentHistory()
            }
            .padding()
        }
        .systemScreen("ASSESSMENT")
        .onAppear {
            let b = store.player.benchmarks
            if let r = b.run1kSec { runMin = r / 60; runSec = r % 60 }
            if let p = b.pushups { pushups = p }
            if let p = b.plankSec { plankSec = p }
            if let r = b.reactionMs { reactionMs = r }
        }
    }

    func row(_ label: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, _ unit: String) -> some View {
        HStack {
            Text(label).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
            Stepper("\(v.wrappedValue)\(unit)", value: v, in: range, step: step).font(Theme.mono(12))
        }
    }
}

struct RankGatesCard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let p = store.player
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: "Rank Trials", color: Theme.gold, size: 12)
            Text("A rank opens at its level threshold, then every benchmark must be met in an assessment. Best values count.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
            ForEach(Rank.allCases.dropFirst()) { r in
                if let g = r.gate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(r.letter)-RANK").font(Theme.mono(13, .heavy))
                                .foregroundStyle(p.rank >= r ? Theme.green : (p.level >= r.minLevel ? Theme.gold : Theme.dim))
                            Text(r.title.uppercased()).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            Spacer()
                            Text("Lv. \(r.minLevel)+").font(Theme.mono(11)).foregroundStyle(p.level >= r.minLevel ? Theme.cyan : Theme.dim)
                        }
                        ForEach(Array(g.checks(p.benchmarks).enumerated()), id: \.offset) { _, c in
                            HStack {
                                Image(systemName: c.ok ? "checkmark" : "xmark").font(.system(size: 9))
                                    .foregroundStyle(c.ok ? Theme.green : Theme.red.opacity(0.7))
                                Text(c.label).font(Theme.mono(10)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("need \(c.need)").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                Text(c.have).font(Theme.mono(10, .bold)).foregroundStyle(c.ok ? Theme.green : Theme.text).frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .systemPanel(Theme.gold)
    }
}

struct AssessmentHistory: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let a = store.assessments()
        if !a.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                BracketHeader(title: "Benchmark History", color: Theme.blue, size: 12)
                Chart(a) { r in
                    LineMark(x: .value("Date", r.date), y: .value("Push-ups", r.pushups))
                        .foregroundStyle(by: .value("Metric", "Push-ups"))
                    LineMark(x: .value("Date", r.date), y: .value("Plank (s/4)", r.plankSec / 4))
                        .foregroundStyle(by: .value("Metric", "Plank s/4"))
                }
                .chartForegroundStyleScale(["Push-ups": Theme.red, "Plank s/4": Theme.gold])
                .frame(height: 140)
                ForEach(a.reversed()) { r in
                    Text("\(DayKey.pretty(r.dayKey))  1k \(Fmt.mmss(r.run1kSec)) · PU \(r.pushups) · PL \(Fmt.mmss(r.plankSec)) · RT \(r.reactionMs)ms")
                        .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                }
            }
            .systemPanel(Theme.blue)
        }
    }
}
