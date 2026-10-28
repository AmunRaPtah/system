import SwiftUI
import Charts

/// What a finished drill reports back.
struct DrillOutcome {
    var score: Double
    var detail: String
    var nextLevel: Int
}

struct DrillHostView: View {
    @Environment(SystemStore.self) private var store
    let kind: DrillKind
    @State private var running = false
    @State private var last: DrillOutcome?
    @State private var runID = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if running {
                    drill
                        .id(runID)
                        .frame(height: 440)
                    Button("ABORT") { running = false }.buttonStyle(.system(Theme.red))
                } else {
                    intro
                    if let o = last {
                        VStack(alignment: .leading, spacing: 6) {
                            BracketHeader(title: "Result", color: Theme.green, size: 12)
                            Text(o.detail).font(Theme.mono(14, .bold)).foregroundStyle(Theme.text)
                            Text("Next level: \(o.nextLevel)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                        .systemPanel(Theme.green)
                    }
                    DrillTrendChart(kind: kind, height: 180)
                        .systemPanel(Theme.blue)
                }
            }
            .padding()
        }
        .systemScreen(kind.title.uppercased())
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: kind.symbol).foregroundStyle(Theme.cyan).glow()
                BracketHeader(title: kind.title)
            }
            Text(kind.blurb).font(.system(size: 13)).foregroundStyle(Theme.dim)
            Text("LEVEL \(store.drillLevel(kind)) · adapts to your results").font(Theme.mono(11)).foregroundStyle(Theme.gold)
            Button(last == nil ? "BEGIN" : "AGAIN") {
                runID = UUID()
                running = true
                Haptics.impact()
            }
            .buttonStyle(.system(Theme.cyan, filled: true))
        }
        .systemPanel()
    }

    @ViewBuilder var drill: some View {
        let level = store.drillLevel(kind)
        switch kind {
        case .reaction: ReactionDrill(level: level, finish: finish)
        case .peripheral: PeripheralDrill(level: level, finish: finish)
        case .tracking: TrackingDrill(level: level, finish: finish)
        case .kims: KimsDrill(level: level, finish: finish)
        }
    }

    func finish(_ o: DrillOutcome) {
        let level = store.drillLevel(kind)
        store.setDrillLevel(kind, o.nextLevel)
        store.logDrill(kind, score: o.score, level: level, detail: o.detail)
        last = o
        running = false
    }
}

struct DrillTrendChart: View {
    @Environment(SystemStore.self) private var store
    let kind: DrillKind
    var height: CGFloat = 120

    var body: some View {
        let rs = Array(store.results(kind).suffix(30))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TREND · \(kind.unit)\(kind.lowerIsBetter ? " (lower is better)" : "")").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                Spacer()
                if let best = kind.lowerIsBetter ? rs.map(\.score).min() : rs.map(\.score).max() {
                    Text("BEST \(Int(best))\(kind.unit)").font(Theme.mono(10, .bold)).foregroundStyle(Theme.gold)
                }
            }
            if rs.count < 2 {
                Text(rs.isEmpty ? "No sessions yet." : "One session logged. The trend appears after two.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: height / 2)
            } else {
                Chart(Array(rs.enumerated()), id: \.offset) { i, r in
                    LineMark(x: .value("#", i + 1), y: .value(kind.unit, r.score))
                        .foregroundStyle(Theme.cyan)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("#", i + 1), y: .value(kind.unit, r.score))
                        .foregroundStyle(Theme.cyan)
                        .symbolSize(18)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Theme.blue.opacity(0.2))
                        AxisValueLabel().foregroundStyle(Theme.dim)
                    }
                }
                .frame(height: height)
            }
        }
    }
}

/// Shared drill frame.
struct DrillArena<Content: View>: View {
    var status: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 8) {
            Text(status).font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.blue.opacity(0.6)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
