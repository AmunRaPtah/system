import SwiftUI

extension Suit {
    var color: Color {
        switch self {
        case .spades: return Theme.text
        case .hearts: return Theme.red
        case .diamonds: return Theme.cyan
        case .clubs: return Theme.green
        }
    }
}

/// Four-colour card face; nil draws a card back.
struct PokerCardView: View {
    var card: Card?
    var width: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(card == nil ? Theme.blue.opacity(0.18) : Theme.bg2)
            RoundedRectangle(cornerRadius: 5).stroke(card?.suit.color.opacity(0.8) ?? Theme.blue.opacity(0.6), lineWidth: 1)
            if let c = card {
                VStack(spacing: 0) {
                    Text(Card.rankChar(c.rank)).font(Theme.mono(width * 0.42, .bold))
                    Text(c.suit.symbol).font(.system(size: width * 0.36))
                }
                .foregroundStyle(c.suit.color)
            } else {
                Image(systemName: "suit.spade.fill").font(.system(size: width * 0.3)).foregroundStyle(Theme.blue.opacity(0.5))
            }
        }
        .frame(width: width, height: width * 1.4)
        .shadow(color: (card?.suit.color ?? Theme.blue).opacity(0.35), radius: 3)
    }
}

struct PokerCardRow: View {
    var label: String
    var cards: [Card]
    var slots = 0
    var width: CGFloat = 40

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim).frame(width: 52, alignment: .leading)
            ForEach(cards) { PokerCardView(card: $0, width: width) }
            ForEach(0..<max(0, slots - cards.count), id: \.self) { _ in PokerCardView(card: nil, width: width).opacity(0.4) }
            Spacer(minLength: 0)
        }
    }
}

struct PokerReviewPanel: View {
    let review: PokerReview
    var compact = false

    var body: some View {
        let color = review.correct ? Theme.green : Theme.red
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: review.correct ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(color)
                Text(review.headline.uppercased()).font(Theme.mono(12, .bold)).foregroundStyle(color)
            }
            if compact && !(review.hero.isEmpty && review.board.isEmpty) {
                HStack(spacing: 4) {
                    ForEach(review.hero) { PokerCardView(card: $0, width: 24) }
                    if !review.villain.isEmpty {
                        Text("vs").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        ForEach(review.villain) { PokerCardView(card: $0, width: 24) }
                    }
                    if !review.board.isEmpty {
                        Text("|").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        ForEach(review.board) { PokerCardView(card: $0, width: 24) }
                    }
                }
            }
            ForEach(Array(review.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 12)).foregroundStyle(Theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemPanel(color, padding: 10)
    }
}

/// Runs `PokerDrill.hands` questions: show, answer, explain, next.
struct PokerSession<Q, Content: View>: View {
    let level: Int
    let make: (Int) -> Q
    let finish: (PokerOutcome) -> Void
    let question: (Q, @escaping (PokerReview) -> Void) -> Content

    init(level: Int, make: @escaping (Int) -> Q, finish: @escaping (PokerOutcome) -> Void,
         @ViewBuilder question: @escaping (Q, @escaping (PokerReview) -> Void) -> Content) {
        self.level = level
        self.make = make
        self.finish = finish
        self.question = question
    }

    @State private var current: Q?
    @State private var index = 0
    @State private var reviews: [PokerReview] = []
    @State private var answered: PokerReview?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HAND \(index + 1)/\(PokerDrill.hands)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.cyan)
                Spacer()
                Text("✓ \(reviews.filter(\.correct).count)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.green)
                Tag(text: "LV \(level)", color: Theme.gold)
            }
            SystemBar(value: Double(reviews.count) / Double(PokerDrill.hands), color: Theme.cyan, height: 4)
            if let q = current {
                question(q) { r in
                    guard answered == nil else { return }
                    answered = r
                    reviews.append(r)
                    if r.correct { Haptics.success() } else { Haptics.warning() }
                }
                .disabled(answered != nil)
                .id(index)
            } else {
                ProgressView().tint(Theme.cyan).frame(maxWidth: .infinity, minHeight: 160)
            }
            if let r = answered {
                PokerReviewPanel(review: r)
                Button(index + 1 < PokerDrill.hands ? "NEXT HAND" : "FINISH") { advance() }
                    .buttonStyle(.system(Theme.cyan, filled: true))
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { if current == nil { current = make(level) } }
    }

    func advance() {
        Haptics.tap()
        if index + 1 >= PokerDrill.hands {
            finish(PokerOutcome(reviews: reviews))
            return
        }
        answered = nil
        index += 1
        current = make(level)
    }
}

/// Big two-way choice used by pot odds and preflop.
struct PokerChoiceButtons: View {
    let left: (String, Color)
    let right: (String, Color)
    let pick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { pick(false) } label: { Text(left.0).frame(maxWidth: .infinity) }
                .buttonStyle(.system(left.1))
            Button { pick(true) } label: { Text(right.0).frame(maxWidth: .infinity) }
                .buttonStyle(.system(right.1, filled: true))
        }
    }
}
