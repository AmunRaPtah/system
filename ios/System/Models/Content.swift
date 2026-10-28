import Foundation

// MARK: - Lossy decoding helpers

/// Decodes an array, silently dropping elements that fail to decode, so one bad
/// entry in a content file never blanks the whole file.
struct LossyArray<Element: Decodable>: Decodable {
    var items: [Element]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !c.isAtEnd {
            if let v = try? c.decode(Element.self) {
                out.append(v)
            } else {
                _ = try? c.decode(Skip.self)
            }
        }
        items = out
    }
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}

extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (try? decodeIfPresent(LossyArray<T>.self, forKey: key))?.items ?? []
    }
}

// MARK: - challenges.json

struct ChallengeFile: Decodable {
    var version: Int
    var challenges: [Challenge]
    enum CodingKeys: String, CodingKey { case version, challenges }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        challenges = c.lossy(Challenge.self, .challenges)
    }
}

struct Challenge: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var pillar: Pillar
    var stat: Stat
    var cadence: String
    var difficulty: Int
    var minutes: Int
    var instructions: String
    var why: String
    var source: String
    var proof: String

    enum CodingKeys: String, CodingKey {
        case id, title, pillar, stat, cadence, difficulty, minutes, instructions, why, source, proof
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        pillar = Pillar(rawValue: (try c.decode(String.self, forKey: .pillar)).lowercased()) ?? .mind
        stat = Stat.parse((try? c.decode(String.self, forKey: .stat)) ?? "WIL")
        cadence = ((try? c.decode(String.self, forKey: .cadence)) ?? "daily").lowercased()
        difficulty = (try? c.decode(Int.self, forKey: .difficulty)) ?? 1
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 10
        instructions = (try? c.decode(String.self, forKey: .instructions)) ?? ""
        why = (try? c.decode(String.self, forKey: .why)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? "general"
        proof = (try? c.decode(String.self, forKey: .proof)) ?? "check"
    }
}

// MARK: - lessons-*.json

enum Game: String, Codable, CaseIterable, Identifiable {
    case chess, go, poker
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .chess: return "crown"
        case .go: return "circle.grid.3x3.fill"
        case .poker: return "suit.spade.fill"
        }
    }
    var fileName: String { "lessons-\(rawValue)" }
}

struct LessonFile: Decodable {
    var version: Int
    var game: Game
    var units: [LessonUnit]
    enum CodingKeys: String, CodingKey { case version, game, units }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        game = (try? c.decode(Game.self, forKey: .game)) ?? .chess
        units = c.lossy(LessonUnit.self, .units).sorted { $0.order < $1.order }
    }
}

struct LessonUnit: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var order: Int
    var difficulty: Int
    var lessons: [Lesson]
    enum CodingKeys: String, CodingKey { case id, title, order, difficulty, lessons }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        difficulty = (try? c.decode(Int.self, forKey: .difficulty)) ?? 1
        lessons = c.lossy(Lesson.self, .lessons)
    }
}

struct Lesson: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
    var quiz: [QuizItem]
    var puzzles: [Puzzle]
    enum CodingKeys: String, CodingKey { case id, title, body, quiz, puzzles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        quiz = c.lossy(QuizItem.self, .quiz)
        puzzles = c.lossy(Puzzle.self, .puzzles)
    }
}

struct QuizItem: Decodable, Hashable {
    var prompt: String
    var choices: [String]
    var answer: Int
    var explain: String
    enum CodingKeys: String, CodingKey { case prompt, choices, answer, explain }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try c.decode(String.self, forKey: .prompt)
        choices = try c.decode([String].self, forKey: .choices)
        answer = (try? c.decode(Int.self, forKey: .answer)) ?? 0
        explain = (try? c.decode(String.self, forKey: .explain)) ?? ""
    }
}

struct Puzzle: Decodable, Identifiable, Hashable {
    var id: String
    var position: String
    var toMove: String
    var solution: [String]
    var goal: String
    var rating: Int
    enum CodingKeys: String, CodingKey { case id, position, toMove, solution, goal, rating }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        position = try c.decode(String.self, forKey: .position)
        toMove = ((try? c.decode(String.self, forKey: .toMove)) ?? "w").lowercased()
        solution = (try? c.decode([String].self, forKey: .solution)) ?? []
        goal = (try? c.decode(String.self, forKey: .goal)) ?? "Find the best move"
        rating = (try? c.decode(Int.self, forKey: .rating)) ?? 0
    }
}

// MARK: - training.json

struct TrainingProgram: Decodable {
    var version: Int
    var title: String
    var totalWeeks: Int
    var deloadEvery: Int
    var progression: ProgressionRule
    var deload: DeloadRule
    var exercises: [Exercise]
    var sessions: [SessionTemplate]
    var phases: [Phase]
    var ladder: [LadderStep]

    enum CodingKeys: String, CodingKey {
        case version, title, totalWeeks, deloadEvery, progression, deload, exercises, sessions, phases, ladder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        title = (try? c.decode(String.self, forKey: .title)) ?? "Programme"
        totalWeeks = (try? c.decode(Int.self, forKey: .totalWeeks)) ?? 12
        deloadEvery = (try? c.decode(Int.self, forKey: .deloadEvery)) ?? 4
        progression = (try? c.decode(ProgressionRule.self, forKey: .progression))
            ?? ProgressionRule(rule: "double-progression", consecutiveSessions: 2, note: "")
        deload = (try? c.decode(DeloadRule.self, forKey: .deload))
            ?? DeloadRule(setFactor: 0.6, loadFactor: 0.9, cardioFactor: 0.7, note: "")
        exercises = c.lossy(Exercise.self, .exercises)
        sessions = c.lossy(SessionTemplate.self, .sessions)
        phases = c.lossy(Phase.self, .phases)
        ladder = c.lossy(LadderStep.self, .ladder)
    }

    init() {
        version = 1; title = "Programme"; totalWeeks = 12; deloadEvery = 4
        progression = ProgressionRule(rule: "double-progression", consecutiveSessions: 2, note: "")
        deload = DeloadRule(setFactor: 0.6, loadFactor: 0.9, cardioFactor: 0.7, note: "")
        exercises = []; sessions = []; phases = []; ladder = []
    }
}

struct ProgressionRule: Decodable {
    var rule: String
    var consecutiveSessions: Int
    var note: String
}

struct DeloadRule: Decodable {
    var setFactor: Double
    var loadFactor: Double
    var cardioFactor: Double
    var note: String
}

struct Exercise: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String       // load | bodyweight | timed
    var stat: Stat
    var gym: String
    var home: String
    var cue: String
    var increment: Double
    var startHint: String

    enum CodingKeys: String, CodingKey { case id, name, kind, stat, gym, home, cue, increment, startHint }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "load"
        stat = Stat.parse((try? c.decode(String.self, forKey: .stat)) ?? "STR")
        gym = (try? c.decode(String.self, forKey: .gym)) ?? ""
        home = (try? c.decode(String.self, forKey: .home)) ?? ""
        cue = (try? c.decode(String.self, forKey: .cue)) ?? ""
        increment = (try? c.decode(Double.self, forKey: .increment)) ?? 2.5
        startHint = (try? c.decode(String.self, forKey: .startHint)) ?? ""
    }
    var isTimed: Bool { kind == "timed" }
    var isLoaded: Bool { kind == "load" }
}

struct Prescription: Decodable, Hashable {
    var exercise: String
    var sets: Int
    var repMin: Int
    var repMax: Int
    var restSec: Int
}

struct CardioBlock: Decodable, Hashable {
    var mode: String
    var minutes: Int
    var instructions: String
    var zone2: Bool
}

struct Circuit: Decodable, Hashable {
    var title: String
    var minutes: Int
    var format: String
    var moves: [String]
}

struct SessionTemplate: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var type: String
    var stat: Stat
    var minutes: Int
    var notes: String
    var exercises: [Prescription]
    var cardio: CardioBlock?
    var circuit: Circuit?

    enum CodingKeys: String, CodingKey { case id, title, type, stat, minutes, notes, exercises, cardio, circuit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        type = (try? c.decode(String.self, forKey: .type)) ?? "strength"
        stat = Stat.parse((try? c.decode(String.self, forKey: .stat)) ?? "STR")
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 45
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        exercises = c.lossy(Prescription.self, .exercises)
        cardio = try? c.decodeIfPresent(CardioBlock.self, forKey: .cardio)
        circuit = try? c.decodeIfPresent(Circuit.self, forKey: .circuit)
    }
    var isStrength: Bool { !exercises.isEmpty }
}

struct ScheduleSlot: Decodable, Hashable {
    var day: Int
    var session: String
}

struct Phase: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var weeks: [Int]
    var focus: String
    var weeklyZone2Minutes: Int
    var schedule: [ScheduleSlot]
    enum CodingKeys: String, CodingKey { case id, title, weeks, focus, weeklyZone2Minutes, schedule }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        weeks = (try? c.decode([Int].self, forKey: .weeks)) ?? []
        focus = (try? c.decode(String.self, forKey: .focus)) ?? ""
        weeklyZone2Minutes = (try? c.decode(Int.self, forKey: .weeklyZone2Minutes)) ?? 60
        schedule = c.lossy(ScheduleSlot.self, .schedule)
    }
}

struct LadderStep: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var category: String
    var stat: Stat
    var repeats: Int
    var xp: Int
    enum CodingKeys: String, CodingKey { case id, title, detail, category, stat, repeats, xp }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? "other"
        stat = Stat.parse((try? c.decode(String.self, forKey: .stat)) ?? "WIL")
        repeats = max(1, (try? c.decode(Int.self, forKey: .repeats)) ?? 3)
        xp = (try? c.decode(Int.self, forKey: .xp)) ?? 20
    }
}
