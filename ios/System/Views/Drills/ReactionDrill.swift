import SwiftUI

/// Simple reaction time with false-start detection. From level 3, red "no-go"
/// catch trials appear; tapping one counts as a false start.
struct ReactionDrill: View {
    let level: Int
    let finish: (DrillOutcome) -> Void

    enum Phase { case ready, waiting, go, nogo, feedback(String), done }

    @State private var phase: Phase = .ready
    @State private var times: [Double] = []
    @State private var falseStarts = 0
    @State private var goAt = Date()
    @State private var token = UUID()
    @State private var trialsRun = 0

    var trials: Int { 7 }
    var catchRate: Double { level >= 3 ? min(0.35, 0.1 + 0.05 * Double(level - 3)) : 0 }

    var body: some View {
        DrillArena(status: "TRIAL \(min(times.count + 1, trials))/\(trials) · FALSE STARTS \(falseStarts)") {
            ZStack {
                color.animation(nil, value: label)
                VStack(spacing: 8) {
                    Text(label).font(Theme.mono(30, .heavy)).foregroundStyle(phaseIsGo ? Theme.bg : Theme.text)
                    if case .ready = phase {
                        Text(level >= 3 ? "Tap on CYAN. Do not tap on RED." : "Tap the moment it turns CYAN.")
                            .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { tap() }
        }
    }

    var phaseIsGo: Bool { if case .go = phase { return true }; return false }

    var color: Color {
        switch phase {
        case .go: return Theme.cyan
        case .nogo: return Theme.red
        case .waiting: return Theme.bg2
        default: return Theme.bg
        }
    }

    var label: String {
        switch phase {
        case .ready: return "TAP TO START"
        case .waiting: return "WAIT…"
        case .go: return "TAP!"
        case .nogo: return "HOLD"
        case .feedback(let s): return s
        case .done: return "DONE"
        }
    }

    func tap() {
        switch phase {
        case .ready, .feedback:
            arm()
        case .waiting:
            falseStarts += 1
            Haptics.error()
            phase = .feedback("FALSE START")
            token = UUID()
        case .go:
            let ms = Date().timeIntervalSince(goAt) * 1000
            if ms < 100 {
                falseStarts += 1
                Haptics.error()
                phase = .feedback("ANTICIPATED")
            } else {
                times.append(ms)
                Haptics.tap()
                phase = .feedback("\(Int(ms)) ms")
                if times.count >= trials { complete(); return }
            }
            token = UUID()
        case .nogo:
            falseStarts += 1
            Haptics.error()
            phase = .feedback("NO-GO: FALSE START")
            token = UUID()
        case .done:
            break
        }
    }

    func arm() {
        phase = .waiting
        let t = UUID()
        token = t
        trialsRun += 1
        let delay = Double.random(in: 1.2...3.8)
        let isCatch = Double.random(in: 0...1) < catchRate
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == t else { return }
            if isCatch {
                phase = .nogo
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard token == t else { return }
                    phase = .feedback("GOOD HOLD")
                }
            } else {
                goAt = Date()
                phase = .go
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard token == t, case .go = phase else { return }
                    phase = .feedback("TOO SLOW")
                }
            }
        }
    }

    func complete() {
        phase = .done
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2]
        var next = level
        if falseStarts == 0 && median < 330 { next += 1 }
        if falseStarts >= 3 { next -= 1 }
        let detail = "Median \(Int(median)) ms · best \(Int(sorted.first ?? median)) ms · \(falseStarts) false start\(falseStarts == 1 ? "" : "s")"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            finish(DrillOutcome(score: median.rounded(), detail: detail, nextLevel: max(1, next)))
        }
    }
}
