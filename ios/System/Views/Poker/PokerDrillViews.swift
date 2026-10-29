import SwiftUI

struct PotOddsDrill: View {
    let level: Int
    let finish: (PokerOutcome) -> Void

    var body: some View {
        PokerSession(level: level, make: PotOddsQuestion.make, finish: finish) { q, submit in
            PotOddsCard(q: q, submit: submit)
        }
    }
}

private struct PotOddsCard: View {
    let q: PotOddsQuestion
    let submit: (PokerReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: "\(q.street) · villain all in", color: Theme.gold, size: 12)
            HStack(spacing: 10) {
                stat("POT", "\(q.pot)", Theme.cyan)
                stat("BET", "\(q.bet)", Theme.red)
                stat("OUTS", "\(q.outs)", Theme.green)
            }
            Text("You hold a \(q.draw) (\(q.outs) clean outs) with \(q.cardsToCome) card\(q.cardsToCome == 2 ? "s" : "") to come. No more betting after this call.")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            PokerChoiceButtons(left: ("FOLD", Theme.red), right: ("CALL \(q.bet)", Theme.green)) { call in
                submit(q.review(call: call))
            }
        }
        .systemPanel()
    }

    func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            Text(value).font(Theme.mono(22, .bold)).foregroundStyle(color).glow(color, radius: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4)))
    }
}

struct EquityDrill: View {
    let level: Int
    let finish: (PokerOutcome) -> Void

    var body: some View {
        PokerSession(level: level, make: EquityQuestion.make, finish: finish) { q, submit in
            EquityCard(q: q, submit: submit)
        }
    }
}

private struct EquityCard: View {
    let q: EquityQuestion
    let submit: (PokerReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: q.board.isEmpty ? "preflop" : (q.board.count == 3 ? "flop" : "turn"), color: Theme.gold, size: 12)
            PokerCardRow(label: "YOU", cards: q.hero)
            if !q.board.isEmpty { PokerCardRow(label: "BOARD", cards: q.board, slots: 5, width: 34) }
            Text("Against \(q.opponent), all in now. What is your equity?")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: q.buckets.count > 5 ? 5 : q.buckets.count)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(q.buckets.enumerated()), id: \.offset) { _, b in
                    Button { submit(q.review(b)) } label: {
                        Text("\(Int((b.lowerBound * 100).rounded()))-\(Int((b.upperBound * 100).rounded()))")
                            .font(Theme.mono(11, .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Theme.cyan)
                            .background(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Buckets are % equity.").font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .systemPanel()
    }
}

struct PreflopDrill: View {
    let level: Int
    let finish: (PokerOutcome) -> Void

    var body: some View {
        PokerSession(level: level, make: PreflopQuestion.make, finish: finish) { q, submit in
            PreflopCard(q: q, submit: submit)
        }
    }
}

private struct PreflopCard: View {
    let q: PreflopQuestion
    let submit: (PokerReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Seat.allCases) { s in
                    Text(s.rawValue).font(Theme.mono(11, .bold))
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .foregroundStyle(s == q.seat ? Theme.bg : Theme.dim)
                        .background(RoundedRectangle(cornerRadius: 3).fill(s == q.seat ? Theme.gold : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.dim.opacity(0.4)))
                }
                Text("BB").font(Theme.mono(11)).foregroundStyle(Theme.dim.opacity(0.6))
            }
            PokerCardRow(label: q.seat.rawValue, cards: q.hand, width: 52)
            Text("6-max, 100bb. Folded to you in the \(q.seat.name.lowercased()). Raise first in, or fold?")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            PokerChoiceButtons(left: ("FOLD", Theme.red), right: ("OPEN", Theme.green)) { open in
                submit(q.review(open: open))
            }
        }
        .systemPanel()
    }
}

struct OutsDrill: View {
    let level: Int
    let finish: (PokerOutcome) -> Void

    var body: some View {
        PokerSession(level: level, make: OutsQuestion.make, finish: finish) { q, submit in
            OutsCard(q: q, submit: submit)
        }
    }
}

private struct OutsCard: View {
    let q: OutsQuestion
    let submit: (PokerReview) -> Void
    @State private var guess = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: q.board.count == 3 ? "flop · rule of 4" : "turn · rule of 2", color: Theme.gold, size: 12)
            PokerCardRow(label: "YOU", cards: q.hero)
            PokerCardRow(label: "VILLAIN", cards: q.villain)
            PokerCardRow(label: "BOARD", cards: q.board, slots: 5, width: 34)
            Text("You are behind. How many cards on the next street put you ahead of this exact hand?")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button { guess = max(0, guess - 1); Haptics.tap() } label: { Image(systemName: "minus").frame(width: 28) }
                    .buttonStyle(.system(Theme.cyan))
                Text("\(guess)").font(Theme.mono(34, .bold)).foregroundStyle(Theme.cyan).glow().frame(minWidth: 60)
                Button { guess = min(25, guess + 1); Haptics.tap() } label: { Image(systemName: "plus").frame(width: 28) }
                    .buttonStyle(.system(Theme.cyan))
                Spacer()
                Button("LOCK IN") { submit(q.review(guess)) }.buttonStyle(.system(Theme.green, filled: true))
            }
        }
        .systemPanel()
    }
}
