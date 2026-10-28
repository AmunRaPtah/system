import Foundation

/// Read-only content bundled in System.app/Content/. Every file is optional:
/// a missing or malformed file yields an empty collection, never a crash.
final class ContentLibrary {
    static let shared = ContentLibrary()

    let challenges: [Challenge]
    let lessons: [Game: LessonFile]
    let training: TrainingProgram
    private(set) var status: [String: String] = [:]

    private init() {
        var status: [String: String] = [:]

        func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Content")
                ?? Bundle.main.url(forResource: name, withExtension: "json")
            guard let url else {
                status[name] = "missing"
                return nil
            }
            do {
                let data = try Data(contentsOf: url)
                let v = try JSONDecoder().decode(T.self, from: data)
                status[name] = "loaded"
                return v
            } catch {
                status[name] = "error: \(error.localizedDescription)"
                return nil
            }
        }

        let ch = load("challenges", as: ChallengeFile.self)
        challenges = ch?.challenges ?? []
        if ch != nil { status["challenges"] = "\(challenges.count) challenges" }

        var lessons: [Game: LessonFile] = [:]
        for g in Game.allCases {
            if let f = load(g.fileName, as: LessonFile.self) {
                lessons[g] = f
                let n = f.units.reduce(0) { $0 + $1.lessons.count }
                status[g.fileName] = "\(f.units.count) units, \(n) lessons"
            }
        }
        self.lessons = lessons

        let t = load("training", as: TrainingProgram.self)
        training = t ?? TrainingProgram()
        if let t { status["training"] = "\(t.sessions.count) sessions, \(t.ladder.count) ladder steps" }

        self.status = status
    }

    // MARK: lookups

    func exercise(_ id: String) -> Exercise? { training.exercises.first { $0.id == id } }
    func session(_ id: String) -> SessionTemplate? { training.sessions.first { $0.id == id } }
    func challenge(_ id: String) -> Challenge? { challenges.first { $0.id == id } }

    func allLessons(_ game: Game) -> [Lesson] {
        lessons[game]?.units.flatMap { $0.lessons } ?? []
    }

    func lesson(_ id: String) -> (Game, LessonUnit, Lesson)? {
        for (g, f) in lessons {
            for u in f.units {
                if let l = u.lessons.first(where: { $0.id == id }) { return (g, u, l) }
            }
        }
        return nil
    }

    var availableGames: [Game] {
        Game.allCases.filter { !(allLessons($0).isEmpty) }
    }
}
