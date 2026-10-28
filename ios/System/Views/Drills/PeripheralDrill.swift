import SwiftUI

/// Fixate the centre; a letter flashes near the edge. Flash time shortens and
/// eccentricity grows with level.
struct PeripheralDrill: View {
    let level: Int
    let finish: (DrillOutcome) -> Void

    static let letters = Array("AEHKMNRSTXZ").map(String.init)
    let rounds = 12

    @State private var round = 0
    @State private var correct = 0
    @State private var shown: String?
    @State private var position = CGPoint(x: 0.5, y: 0.5)
    @State private var answer = ""
    @State private var choices: [String] = []
    @State private var awaiting = false
    @State private var flash: String?
    @State private var started = false

    var flashMs: Double { max(50, 320 - 22 * Double(level - 1)) }
    var eccentricity: CGFloat { min(0.46, 0.28 + 0.02 * CGFloat(level)) }

    var body: some View {
        DrillArena(status: "ROUND \(min(round + 1, rounds))/\(rounds) · \(Int(flashMs)) ms FLASH · \(correct) HIT") {
            GeometryReader { g in
                ZStack {
                    Circle().fill(Theme.cyan).frame(width: 10, height: 10).glow()
                        .position(x: g.size.width / 2, y: g.size.height / 2)
                    if let s = shown {
                        Text(s).font(Theme.mono(30, .heavy)).foregroundStyle(Theme.text)
                            .position(x: position.x * g.size.width, y: position.y * g.size.height)
                    }
                    if let f = flash {
                        Text(f).font(Theme.mono(14, .bold)).foregroundStyle(f == "HIT" ? Theme.green : Theme.red)
                            .position(x: g.size.width / 2, y: g.size.height / 2 + 30)
                    }
                    if !started {
                        VStack(spacing: 10) {
                            Text("Eyes on the dot. Do not move them.").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                            Button("READY") { started = true; next() }.buttonStyle(.system)
                        }
                        .position(x: g.size.width / 2, y: g.size.height / 2 + 60)
                    }
                    if awaiting {
                        HStack(spacing: 10) {
                            ForEach(choices, id: \.self) { c in
                                Button(c) { pick(c) }.buttonStyle(.system(Theme.cyan))
                            }
                        }
                        .position(x: g.size.width / 2, y: g.size.height - 40)
                    }
                }
            }
        }
    }

    func next() {
        guard round < rounds else { return complete() }
        flash = nil
        awaiting = false
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = eccentricity
        position = CGPoint(x: 0.5 + r * CGFloat(cos(angle)), y: 0.5 + r * 0.85 * CGFloat(sin(angle)))
        answer = Self.letters.randomElement() ?? "A"
        var c = Set([answer])
        while c.count < 4 { c.insert(Self.letters.randomElement() ?? "X") }
        choices = Array(c).shuffled()
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.7...1.6)) {
            shown = answer
            DispatchQueue.main.asyncAfter(deadline: .now() + flashMs / 1000) {
                shown = nil
                awaiting = true
            }
        }
    }

    func pick(_ c: String) {
        guard awaiting else { return }
        awaiting = false
        if c == answer { correct += 1; flash = "HIT"; Haptics.tap() } else { flash = "MISS: \(answer)"; Haptics.warning() }
        round += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
    }

    func complete() {
        let pct = Double(correct) / Double(rounds) * 100
        var n = level
        if pct >= 80 { n += 1 } else if pct < 50 { n -= 1 }
        finish(DrillOutcome(score: pct.rounded(), detail: "\(correct)/\(rounds) letters at \(Int(flashMs)) ms (\(Int(pct))%)", nextLevel: max(1, n)))
    }
}
