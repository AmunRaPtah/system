import SwiftUI

/// Multiple-object tracking. Positions are a closed-form function of time
/// (bounce = triangle-wave reflection), so no per-frame state is needed.
struct TrackingDrill: View {
    let level: Int
    let finish: (DrillOutcome) -> Void

    struct Ball { var p: CGPoint; var v: CGVector }

    enum Phase { case intro, cue, move, select, reveal }

    let rounds = 3
    @State private var round = 0
    @State private var phase: Phase = .intro
    @State private var balls: [Ball] = []
    @State private var targets: Set<Int> = []
    @State private var picked: Set<Int> = []
    @State private var moveStart = Date()
    @State private var hits = 0
    @State private var totalTargets = 0

    var count: Int { min(12, 6 + level / 2) }
    var targetCount: Int { min(5, 2 + level / 3) }
    var speed: Double { 0.18 + 0.03 * Double(level) }     // fraction of the box per second
    let cueTime = 2.0
    let moveTime = 7.0

    var body: some View {
        DrillArena(status: "ROUND \(min(round + 1, rounds))/\(rounds) · TRACK \(targetCount) OF \(count)") {
            GeometryReader { g in
                TimelineView(.animation(paused: phase != .move)) { tl in
                    let t = phase == .move ? min(moveTime, tl.date.timeIntervalSince(moveStart)) : (phase == .cue || phase == .intro ? 0 : moveTime)
                    ZStack {
                        ForEach(balls.indices, id: \.self) { i in
                            let pt = position(balls[i], t: t)
                            Circle()
                                .fill(fill(i))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Theme.cyan.opacity(0.6)))
                                .shadow(color: fill(i), radius: 6)
                                .position(x: 14 + pt.x * (g.size.width - 28), y: 14 + pt.y * (g.size.height - 28))
                                .onTapGesture { tap(i) }
                        }
                        overlay(g.size)
                    }
                }
            }
        }
    }

    @ViewBuilder func overlay(_ size: CGSize) -> some View {
        switch phase {
        case .intro:
            VStack(spacing: 10) {
                Text("Remember the gold targets. Track them as they move. Then tap them.")
                    .font(Theme.mono(12)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Button("READY") { startRound() }.buttonStyle(.system)
            }
            .padding()
            .background(Theme.bg.opacity(0.85))
        case .select:
            Text("TAP THE \(targetCount) TARGETS · \(picked.count)/\(targetCount)")
                .font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
                .position(x: size.width / 2, y: 16)
        case .reveal:
            Text("\(picked.intersection(targets).count)/\(targetCount) FOUND")
                .font(Theme.mono(14, .bold)).foregroundStyle(Theme.green)
                .position(x: size.width / 2, y: 16)
        default:
            EmptyView()
        }
    }

    func fill(_ i: Int) -> Color {
        switch phase {
        case .cue: return targets.contains(i) ? Theme.gold : Theme.blue.opacity(0.5)
        case .select: return picked.contains(i) ? Theme.cyan : Theme.blue.opacity(0.5)
        case .reveal:
            if targets.contains(i) { return picked.contains(i) ? Theme.green : Theme.gold }
            return picked.contains(i) ? Theme.red : Theme.blue.opacity(0.5)
        default: return Theme.blue.opacity(0.5)
        }
    }

    func position(_ b: Ball, t: Double) -> CGPoint {
        func reflect(_ x: Double) -> Double {
            let m = x.truncatingRemainder(dividingBy: 2)
            let r = m < 0 ? m + 2 : m
            return r > 1 ? 2 - r : r
        }
        return CGPoint(x: reflect(Double(b.p.x) + Double(b.v.dx) * t), y: reflect(Double(b.p.y) + Double(b.v.dy) * t))
    }

    func startRound() {
        balls = (0..<count).map { _ in
            let a = Double.random(in: 0..<(2 * .pi))
            let s = speed * Double.random(in: 0.8...1.2)
            return Ball(p: CGPoint(x: .random(in: 0.05...0.95), y: .random(in: 0.05...0.95)),
                        v: CGVector(dx: cos(a) * s, dy: sin(a) * s))
        }
        targets = Set((0..<count).shuffled().prefix(targetCount))
        picked = []
        phase = .cue
        DispatchQueue.main.asyncAfter(deadline: .now() + cueTime) {
            moveStart = Date()
            phase = .move
            DispatchQueue.main.asyncAfter(deadline: .now() + moveTime) {
                phase = .select
            }
        }
    }

    func tap(_ i: Int) {
        guard phase == .select else { return }
        if picked.contains(i) { picked.remove(i) } else { picked.insert(i) }
        Haptics.tap()
        if picked.count == targetCount {
            hits += picked.intersection(targets).count
            totalTargets += targetCount
            phase = .reveal
            round += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if round >= rounds { complete() } else { startRound() }
            }
        }
    }

    func complete() {
        let pct = Double(hits) / Double(max(1, totalTargets)) * 100
        var n = level
        if pct >= 85 { n += 1 } else if pct < 55 { n -= 1 }
        finish(DrillOutcome(score: pct.rounded(), detail: "\(hits)/\(totalTargets) targets tracked among \(count) (\(Int(pct))%)", nextLevel: max(1, n)))
    }
}
