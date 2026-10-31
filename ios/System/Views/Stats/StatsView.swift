import SwiftUI
import Charts

struct StatsView: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let p = store.player
        let prog = Leveling.progress(for: p.totalXP)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        PlayerTitleLine()
                        HStack(alignment: .firstTextBaseline) {
                            Text("LV \(p.level)").font(Theme.mono(30, .heavy)).foregroundStyle(Theme.cyan).glow()
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("RANK \(p.rank.letter)").font(Theme.mono(20, .bold)).foregroundStyle(Theme.gold).glow(Theme.gold)
                                Text(p.rank.title).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            }
                        }
                        SystemBar(value: prog.span > 0 ? Double(prog.into) / Double(prog.span) : 0)
                        HStack {
                            Text("XP \(prog.into)/\(prog.span)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                            Spacer()
                            Text("TOTAL \(p.totalXP)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                        HStack {
                            Label("STREAK \(p.streak)", systemImage: "flame.fill").foregroundStyle(Theme.gold)
                            Spacer()
                            Text("BEST \(p.bestStreak)").foregroundStyle(Theme.dim)
                        }
                        .font(Theme.mono(12, .bold))
                        let f = store.fatigue()
                        let job = store.job
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("JOB  \(job.uppercased())").foregroundStyle(job == "None" ? Theme.dim : Theme.violet)
                                Spacer()
                                Text("FATIGUE \(f.value) · \(f.label)").foregroundStyle(f.high ? Theme.red : Theme.dim)
                            }
                            .font(Theme.mono(12, .bold))
                            if job == "None" {
                                Text(store.jobRequirement).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            }
                            if !f.reasons.isEmpty {
                                Text("Fatigue: " + f.reasons.joined(separator: ", ") + (f.high ? ". Load halved." : "."))
                                    .font(Theme.mono(10)).foregroundStyle(f.high ? Theme.red : Theme.dim)
                            }
                            NavigationLink { ShadowArmyView() } label: {
                                Text("[SHADOW ARMY · \(store.extractedShadowIDs().count)/\(Shadow.all.count)] ›")
                                    .font(Theme.mono(12, .bold)).foregroundStyle(Theme.violet)
                            }
                        }
                        if let t = p.trialPending {
                            NavigationLink { AssessmentView() } label: {
                                Text("[RANK-UP TRIAL AVAILABLE: \(t.letter)]").font(Theme.mono(12, .bold)).foregroundStyle(Theme.red)
                            }
                        }
                    }
                    .systemPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        BracketHeader(title: "Status", size: 13)
                        StatRadar(values: Stat.allCases.map { Double(p.points($0) + store.titleBonus($0)) })
                            .frame(height: 260)
                        ForEach(Stat.allCases) { s in
                            StatBarRow(stat: s, points: p.points(s) + store.titleBonus(s), xp: p.xp(s), maxPoints: Stat.allCases.map { p.points($0) + store.titleBonus($0) }.max() ?? 10)
                        }
                    }
                    .systemPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        BracketHeader(title: "XP · 28 days", size: 13)
                        let daily = store.dailyXP(days: 28)
                        Chart(Array(daily.enumerated()), id: \.offset) { i, d in
                            BarMark(x: .value("Day", i), y: .value("XP", d.1))
                                .foregroundStyle(d.1 < 0 ? Theme.red : Theme.cyan)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Theme.blue.opacity(0.2))
                                AxisValueLabel().foregroundStyle(Theme.dim)
                            }
                        }
                        .frame(height: 140)
                    }
                    .systemPanel()

                    RankGatesCard()

                    VStack(alignment: .leading, spacing: 6) {
                        BracketHeader(title: "Log", size: 13)
                        let events = store.recentXP(30)
                        if events.isEmpty {
                            Text("No XP yet. Complete a quest.").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                        ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .top) {
                                Text(e.dayKey.suffix(5)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                Text(e.note.isEmpty ? e.source : e.note).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Text("\(e.amount >= 0 ? "+" : "")\(e.amount) \(e.stat)")
                                    .font(Theme.mono(11, .bold))
                                    .foregroundStyle(e.amount >= 0 ? Theme.green : Theme.red)
                            }
                        }
                    }
                    .systemPanel()
                }
                .padding()
            }
            .systemScreen("STATUS")
        }
    }
}

struct StatBarRow: View {
    let stat: Stat
    let points: Int
    let xp: Int
    let maxPoints: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(stat.rawValue).font(Theme.mono(12, .bold)).foregroundStyle(Theme.color(stat.pillar)).frame(width: 36, alignment: .leading)
            SystemBar(value: Double(points) / Double(max(maxPoints, 20)), color: Theme.color(stat.pillar), height: 6)
            Text("\(points)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 30, alignment: .trailing)
        }
    }
}

/// Nine-axis radar drawn with Canvas.
struct StatRadar: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            let n = values.count
            guard n > 2 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 22
            let top = max(20, values.max() ?? 20)
            func pt(_ i: Int, _ f: Double) -> CGPoint {
                let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
                return CGPoint(x: c.x + CGFloat(cos(a) * f) * r, y: c.y + CGFloat(sin(a) * f) * r)
            }
            for ring in 1...4 {
                var p = Path()
                for i in 0..<n {
                    let q = pt(i, Double(ring) / 4)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath()
                ctx.stroke(p, with: .color(Theme.blue.opacity(0.25)), lineWidth: 1)
            }
            for i in 0..<n {
                var spoke = Path()
                spoke.move(to: c)
                spoke.addLine(to: pt(i, 1))
                ctx.stroke(spoke, with: .color(Theme.blue.opacity(0.2)), lineWidth: 1)
                let label = Text(Stat.allCases[i % Stat.allCases.count].rawValue)
                    .font(Theme.mono(10, .bold))
                    .foregroundColor(Theme.dim)
                ctx.draw(label, at: pt(i, 1.14))
            }
            var shape = Path()
            for i in 0..<n {
                let q = pt(i, values[i] / top)
                if i == 0 { shape.move(to: q) } else { shape.addLine(to: q) }
            }
            shape.closeSubpath()
            ctx.fill(shape, with: .color(Theme.cyan.opacity(0.22)))
            ctx.stroke(shape, with: .color(Theme.cyan), lineWidth: 2)
        }
    }
}
