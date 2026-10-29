import Foundation
import SwiftData

@Model
final class XPEvent {
    var date: Date
    var dayKey: String
    var stat: String
    var amount: Int
    var source: String
    var note: String

    init(date: Date = .now, dayKey: String, stat: Stat, amount: Int, source: String, note: String) {
        self.date = date
        self.dayKey = dayKey
        self.stat = stat.rawValue
        self.amount = amount
        self.source = source
        self.note = note
    }
}

@Model
final class QuestCompletion {
    @Attribute(.unique) var key: String
    var questID: String
    var dayKey: String
    var kind: String
    var pillar: String
    var stat: String
    var note: String
    var date: Date

    init(questID: String, dayKey: String, kind: String, pillar: String, stat: String, note: String = "") {
        self.key = dayKey + "|" + questID
        self.questID = questID
        self.dayKey = dayKey
        self.kind = kind
        self.pillar = pillar
        self.stat = stat
        self.note = note
        self.date = .now
    }
}

@Model
final class DayPlan {
    @Attribute(.unique) var dayKey: String
    var questsData: Data
    var penaltyIssued: Bool
    var penaltyDeduction: Int
    var penaltyStrained: Bool
    var missed: Bool
    var evaluated: Bool
    var created: Date

    init(dayKey: String, quests: [Quest]) {
        self.dayKey = dayKey
        self.questsData = (try? JSONEncoder().encode(quests)) ?? Data()
        self.penaltyIssued = false
        self.penaltyDeduction = 0
        self.penaltyStrained = false
        self.missed = false
        self.evaluated = false
        self.created = .now
    }

    var quests: [Quest] {
        get { (try? JSONDecoder().decode([Quest].self, from: questsData)) ?? [] }
        set { questsData = (try? JSONEncoder().encode(newValue)) ?? questsData }
    }
}

@Model
final class CheckIn {
    @Attribute(.unique) var dayKey: String
    var sleepHours: Double
    var soreness: Int
    var mood: Int
    var date: Date

    init(dayKey: String, sleepHours: Double, soreness: Int, mood: Int) {
        self.dayKey = dayKey
        self.sleepHours = sleepHours
        self.soreness = soreness
        self.mood = mood
        self.date = .now
    }

    /// Poor sleep (<6 h) or high soreness (4-5) halves penalty load.
    var isStrained: Bool { sleepHours < 6 || soreness >= 4 }
}

@Model
final class WorkoutLog {
    var uid: UUID
    var date: Date
    var dayKey: String
    var sessionID: String
    var sessionTitle: String
    var week: Int
    var type: String
    var cardioMinutes: Double
    var cardioDistanceKm: Double
    var rpe: Int
    var zone2: Bool
    var notes: String

    init(dayKey: String, sessionID: String, sessionTitle: String, week: Int, type: String) {
        self.uid = UUID()
        self.date = .now
        self.dayKey = dayKey
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.week = week
        self.type = type
        self.cardioMinutes = 0
        self.cardioDistanceKm = 0
        self.rpe = 0
        self.zone2 = false
        self.notes = ""
    }
}

@Model
final class SetLog {
    var workoutID: UUID
    var date: Date
    var exerciseID: String
    var setIndex: Int
    var reps: Int
    var weight: Double

    init(workoutID: UUID, exerciseID: String, setIndex: Int, reps: Int, weight: Double) {
        self.workoutID = workoutID
        self.date = .now
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
    }
}

@Model
final class DrillResult {
    var drill: String
    var date: Date
    var dayKey: String
    var score: Double
    var level: Int
    var detail: String

    init(drill: DrillKind, dayKey: String, score: Double, level: Int, detail: String) {
        self.drill = drill.rawValue
        self.date = .now
        self.dayKey = dayKey
        self.score = score
        self.level = level
        self.detail = detail
    }
}

@Model
final class LessonRecord {
    @Attribute(.unique) var lessonID: String
    var game: String
    var dayKey: String
    var date: Date
    var quizCorrect: Int
    var quizTotal: Int
    var puzzlesSolved: Int

    init(lessonID: String, game: Game, dayKey: String, quizCorrect: Int, quizTotal: Int, puzzlesSolved: Int) {
        self.lessonID = lessonID
        self.game = game.rawValue
        self.dayKey = dayKey
        self.date = .now
        self.quizCorrect = quizCorrect
        self.quizTotal = quizTotal
        self.puzzlesSolved = puzzlesSolved
    }
}

@Model
final class LadderRecord {
    var stepID: String
    var dayKey: String
    var date: Date

    init(stepID: String, dayKey: String) {
        self.stepID = stepID
        self.dayKey = dayKey
        self.date = .now
    }
}

@Model
final class AssessmentRecord {
    var date: Date
    var dayKey: String
    var run1kSec: Int
    var pushups: Int
    var plankSec: Int
    var reactionMs: Int

    init(dayKey: String, run1kSec: Int, pushups: Int, plankSec: Int, reactionMs: Int) {
        self.date = .now
        self.dayKey = dayKey
        self.run1kSec = run1kSec
        self.pushups = pushups
        self.plankSec = plankSec
        self.reactionMs = reactionMs
    }
}

/// Weekly targets / dungeon steps claimed, keyed so each pays out once.
@Model
final class Claim {
    @Attribute(.unique) var key: String
    var date: Date
    init(key: String) {
        self.key = key
        self.date = .now
    }
}

enum Schema_ {
    static let models: [any PersistentModel.Type] = [
        XPEvent.self, QuestCompletion.self, DayPlan.self, CheckIn.self, WorkoutLog.self,
        SetLog.self, DrillResult.self, LessonRecord.self, LadderRecord.self,
        AssessmentRecord.self, Claim.self,
        PlayResult.self, SavedPlayGame.self,
    ]
}
