import Foundation
import SwiftData

/// Setup + move list of a chess game vs the engine; also the save/resume format.
struct ChessSave: Codable, Hashable {
    var startFEN = ChessBoard.startFEN
    var moves: [String] = []        // UCI
    var level = 1
    var playerWhite = true
    var assisted = false
}

/// Setup + move list of a go game vs the engine; also the save/resume format.
struct GoSave: Codable, Hashable {
    var size = 9
    var handicap = 0
    var moves: [Int] = []           // point, -1 = pass
    var level = 1
    var playerBlack = true
    var assisted = false
}

enum PlayOutcome: String {
    case win, loss, draw
    var title: String { rawValue.uppercased() }
}

extension SystemStore {
    /// XP for a finished game: win 20+10*level, draw 10+3*level, loss 5; halved if assisted.
    static func playXP(_ outcome: PlayOutcome, level: Int, assisted: Bool) -> Int {
        let base: Int
        switch outcome {
        case .win: base = 20 + 10 * level
        case .draw: base = 10 + 3 * level
        case .loss: base = 5
        }
        return assisted ? max(1, base / 2) : base
    }

    func playResults(_ game: Game) -> [PlayResult] {
        _ = revision
        return fetchAll(PlayResult.self).filter { $0.game == game.rawValue }.sorted { $0.date > $1.date }
    }

    /// Records a finished game and awards INT XP once. Returns the XP awarded.
    @discardableResult
    func recordPlay(_ game: Game, outcome: PlayOutcome, level: Int, colour: String,
                    moves: Int, detail: String, assisted: Bool) -> Int {
        let xp = Self.playXP(outcome, level: level, assisted: assisted)
        let name = game == .chess ? ChessLevel.names[max(0, min(4, level - 1))] : GoLevel.names[max(0, min(4, level - 1))]
        context.insert(PlayResult(game: game, dayKey: DayKey.today, outcome: outcome.rawValue, level: level,
                                  colour: colour, moves: moves, detail: detail, assisted: assisted, xp: xp))
        clearSavedPlay(game)
        var line = "\(game.title) vs \(name): \(outcome.title). \(detail)  +\(xp) XP INT"
        if assisted { line += " (assisted, half XP)" }
        awardXP(.INT, xp, source: "play", note: "\(game.title) \(outcome.rawValue) L\(level)",
                title: outcome == .win ? "[VICTORY]" : (outcome == .draw ? "[DRAW]" : "[DEFEAT]"), lines: [line])
        return xp
    }

    // MARK: - Save / resume

    private func savedRow(_ game: Game) -> SavedPlayGame? {
        let key = game.rawValue
        var d = FetchDescriptor<SavedPlayGame>(predicate: #Predicate<SavedPlayGame> { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func savedPlay<T: Decodable>(_ game: Game, as type: T.Type) -> T? {
        guard let row = savedRow(game) else { return nil }
        return try? JSONDecoder().decode(T.self, from: row.data)
    }

    func savePlay<T: Encodable>(_ game: Game, _ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        if let row = savedRow(game) {
            row.data = data
            row.date = .now
        } else {
            context.insert(SavedPlayGame(key: game.rawValue, data: data))
        }
        save()
    }

    func clearSavedPlay(_ game: Game) {
        if let row = savedRow(game) { context.delete(row) }
        save()
    }
}
