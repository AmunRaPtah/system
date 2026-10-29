import Foundation
import SwiftData

/// One finished game against the on-device engine (chess or go).
@Model
final class PlayResult {
    var game: String        // Game.rawValue
    var date: Date
    var dayKey: String
    /// "win", "loss" or "draw" from the player's side.
    var outcome: String
    var level: Int
    /// Player colour: "white"/"black" for chess, "black"/"white" for go.
    var colour: String
    var moves: Int
    /// Human-readable result, e.g. "Checkmate. White wins." or "B+3.5".
    var detail: String
    /// Hint or takeback used.
    var assisted: Bool
    var xp: Int

    init(game: Game, dayKey: String, outcome: String, level: Int, colour: String,
         moves: Int, detail: String, assisted: Bool, xp: Int) {
        self.game = game.rawValue
        self.date = .now
        self.dayKey = dayKey
        self.outcome = outcome
        self.level = level
        self.colour = colour
        self.moves = moves
        self.detail = detail
        self.assisted = assisted
        self.xp = xp
    }
}

/// An in-progress game, one per game kind, stored as JSON so it can be resumed.
@Model
final class SavedPlayGame {
    @Attribute(.unique) var key: String
    var data: Data
    var date: Date

    init(key: String, data: Data) {
        self.key = key
        self.data = data
        self.date = .now
    }
}
