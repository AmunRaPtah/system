import SwiftUI

struct GameLessonsView: View {
    @Environment(SystemStore.self) private var store
    let game: Game
    private let lib = ContentLibrary.shared

    var body: some View {
        let units = lib.lessons[game]?.units ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if units.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        BracketHeader(title: "No lessons loaded", color: Theme.gold)
                        Text("Add \(game.fileName).json to Resources/Content and rebuild.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }
                    .systemPanel(Theme.gold)
                }
                ForEach(units) { unit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            BracketHeader(title: unit.title, size: 13)
                            Spacer()
                            let done = unit.lessons.filter { store.lessonDone($0.id) }.count
                            Text("\(done)/\(unit.lessons.count)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                        ForEach(unit.lessons) { lesson in
                            NavigationLink {
                                LessonView(game: game, unit: unit, lesson: lesson)
                            } label: {
                                HStack {
                                    Image(systemName: store.lessonDone(lesson.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(store.lessonDone(lesson.id) ? Theme.green : Theme.dim)
                                    Text(lesson.title).font(.system(size: 14)).foregroundStyle(Theme.text)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if !lesson.puzzles.isEmpty {
                                        Image(systemName: "puzzlepiece.fill").font(.system(size: 11)).foregroundStyle(Theme.violet)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .systemPanel()
                }
            }
            .padding()
        }
        .systemScreen(game.title.uppercased())
    }
}

struct LessonView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let unit: LessonUnit
    let lesson: Lesson

    @State private var picks: [Int: Int] = [:]
    @State private var solved: Set<String> = []
    @State private var submitted = false

    var quizCorrect: Int { lesson.quiz.indices.filter { picks[$0] == lesson.quiz[$0].answer }.count }
    var quizAnswered: Bool { picks.count >= lesson.quiz.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    BracketHeader(title: lesson.title)
                    MarkdownText(lesson.body)
                }
                .systemPanel()

                if !lesson.quiz.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        BracketHeader(title: "Quiz", color: Theme.violet, size: 13)
                        ForEach(Array(lesson.quiz.enumerated()), id: \.offset) { i, q in
                            QuizCard(item: q, pick: picks[i]) { picks[i] = $0 }
                        }
                    }
                    .systemPanel(Theme.violet)
                }

                ForEach(lesson.puzzles) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            BracketHeader(title: "Puzzle", color: Theme.gold, size: 13)
                            Spacer()
                            if solved.contains(p.id) { Tag(text: "SOLVED", color: Theme.green) }
                        }
                        if game == .chess {
                            ChessPuzzleView(puzzle: p) { solved.insert(p.id) }
                        } else if game == .go {
                            GoPuzzleView(puzzle: p) { solved.insert(p.id) }
                        }
                    }
                    .systemPanel(Theme.gold)
                }

                Button(submitted ? "RECORDED" : "COMPLETE LESSON") {
                    store.completeLesson(game: game, unit: unit, lesson: lesson,
                                         quizCorrect: quizCorrect, quizTotal: lesson.quiz.count,
                                         puzzlesSolved: solved.count)
                    submitted = true
                    Haptics.success()
                }
                .buttonStyle(.system(Theme.cyan, filled: true))
                .disabled(submitted || !quizAnswered)
                .frame(maxWidth: .infinity)
                if !quizAnswered {
                    Text("Answer every quiz question to complete.").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .systemScreen(unit.title.uppercased())
    }
}

struct QuizCard: View {
    let item: QuizItem
    let pick: Int?
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.prompt).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            ForEach(Array(item.choices.enumerated()), id: \.offset) { i, choice in
                Button {
                    if pick == nil { choose(i); if i == item.answer { Haptics.tap() } else { Haptics.warning() } }
                } label: {
                    HStack(alignment: .top) {
                        Text(i < 8 ? String(Array("ABCDEFGH")[i]) : "\(i + 1)").font(Theme.mono(12, .bold))
                        Text(choice).font(.system(size: 13)).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .foregroundStyle(color(i))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(color(i).opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
            if pick != nil, !item.explain.isEmpty {
                Text(item.explain).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
    }

    func color(_ i: Int) -> Color {
        guard let p = pick else { return Theme.text }
        if i == item.answer { return Theme.green }
        if i == p { return Theme.red }
        return Theme.dim
    }
}

/// Renders markdown paragraph by paragraph. Headings and bullets are handled
/// per line; inline styling goes through AttributedString(markdown:).
struct MarkdownText: View {
    let source: String
    init(_ s: String) { source = s }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                line(raw)
            }
        }
    }

    @ViewBuilder func line(_ raw: String) -> some View {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            EmptyView()
        } else if t.hasPrefix("#") {
            let text = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            Text(inline(text)).font(Theme.mono(14, .bold)).foregroundStyle(Theme.cyan).padding(.top, 4)
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("▸").foregroundStyle(Theme.cyan)
                Text(inline(String(t.dropFirst(2)))).foregroundStyle(Theme.text)
            }
            .font(.system(size: 14))
        } else {
            Text(inline(t)).font(.system(size: 14)).foregroundStyle(Theme.text)
        }
    }

    func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
