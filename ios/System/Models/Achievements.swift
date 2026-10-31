import Foundation
import SwiftData

/// One row per achievement the player has earned. Written once, never re-fired.
@Model
final class AchievementUnlock {
    @Attribute(.unique) var achievementID: String
    var date: Date

    init(achievementID: String, date: Date = .now) {
        self.achievementID = achievementID
        self.date = date
    }
}

/// What an achievement measures. Every value is derived from records that
/// already exist (XP events, completions, logs, claims), so nothing new has to
/// be tracked for an achievement to count retroactively.
enum AchievementMetric: String {
    case awakened, level, rank, bestStreak, dailyClears, weeklyClaims, dungeons, penaltiesCleared
    case workouts, cardioMinutes, assessments, pushups, plankSec, run1kSec, checkIns, ladder
    case drills, drillLevel, reactionMs, lessons, chessLessons, goLessons, pokerLessons, puzzles, perfectQuizzes
    case socialDone, sovereignDone
    case preparation, preparationTier, comebacks, shadows, vowDays
    case practiceDays, focusBlocks

    /// Benchmarks where a smaller number is the better result.
    var lowerIsBetter: Bool { self == .run1kSec || self == .reactionMs }

    func format(_ v: Int) -> String {
        switch self {
        case .rank: return (Rank(rawValue: v) ?? .E).letter
        case .run1kSec, .plankSec: return Fmt.mmss(v)
        case .reactionMs: return "\(v) ms"
        case .cardioMinutes: return "\(v) min"
        case .awakened: return v > 0 ? "yes" : "no"
        default: return "\(v)"
        }
    }
}

/// An equippable title. The bonus is added to the displayed stat points while equipped.
struct PlayerTitle: Equatable {
    var name: String
    var stat: Stat
    var bonus: Int
    var bonusLabel: String { "+\(bonus) \(stat.rawValue)" }
}

struct Achievement: Identifiable {
    var id: String
    var name: String
    var detail: String
    /// nil = a System milestone (levels, ranks, awakening) rather than one pillar.
    var pillar: Pillar?
    var symbol: String
    var metric: AchievementMetric
    var goal: Int
    var title: PlayerTitle? = nil

    func met(_ value: Int?) -> Bool {
        guard let v = value else { return false }
        return metric.lowerIsBetter ? (v > 0 && v <= goal) : v >= goal
    }

    /// 0...1 progress for the bar. Lower-is-better metrics show as met or not.
    func fraction(_ value: Int?) -> Double {
        guard let v = value else { return 0 }
        if metric.lowerIsBetter { return met(v) ? 1 : 0 }
        return goal > 0 ? min(1, Double(max(0, v)) / Double(goal)) : 1
    }

    func progressText(_ value: Int?) -> String {
        let goalText = (metric.lowerIsBetter ? "≤ " : "") + metric.format(goal)
        guard let v = value else { return "— / \(goalText)" }
        if metric.lowerIsBetter { return "\(metric.format(v)) / \(goalText)" }
        return "\(metric.format(min(v, goal))) / \(goalText)"
    }
}

/// The catalogue. IDs are stable forever: they key AchievementUnlock rows and the
/// equipped title. Goals are set for a beginner: the first of each line comes
/// within a week or two, the titled ones take months.
enum AchievementCatalog {
    static let all: [Achievement] = system + body + mind + social + sovereign

    static func find(_ id: String) -> Achievement? { all.first { $0.id == id } }

    static let system: [Achievement] = [
        Achievement(id: "sys-awakened", name: "Player Awakening", detail: "Accept the System's call.",
                    pillar: nil, symbol: "sparkles", metric: .awakened, goal: 1),
        Achievement(id: "sys-level-5", name: "First Threshold", detail: "Reach level 5.",
                    pillar: nil, symbol: "arrow.up.circle", metric: .level, goal: 5),
        Achievement(id: "sys-level-10", name: "Climber", detail: "Reach level 10.",
                    pillar: nil, symbol: "arrow.up.circle.fill", metric: .level, goal: 10),
        Achievement(id: "sys-level-25", name: "Ascendant", detail: "Reach level 25.",
                    pillar: nil, symbol: "arrow.up.forward.circle.fill", metric: .level, goal: 25,
                    title: PlayerTitle(name: "The Ascendant", stat: .WIL, bonus: 2)),
        Achievement(id: "sys-rank-d", name: "Trial Passed", detail: "Earn D-Rank.",
                    pillar: nil, symbol: "shield", metric: .rank, goal: Rank.D.rawValue),
        Achievement(id: "sys-rank-c", name: "Proven Hunter", detail: "Earn C-Rank.",
                    pillar: nil, symbol: "shield.lefthalf.filled", metric: .rank, goal: Rank.C.rawValue,
                    title: PlayerTitle(name: "Gate-Tested", stat: .END, bonus: 2)),
        Achievement(id: "sys-rank-a", name: "Above the Many", detail: "Earn A-Rank.",
                    pillar: nil, symbol: "shield.fill", metric: .rank, goal: Rank.A.rawValue,
                    title: PlayerTitle(name: "Lord of the High Gates", stat: .STR, bonus: 3)),
        Achievement(id: "sys-comeback", name: "Courage of the Weak", detail: "Hidden quest: clear the Daily Quest after missing two days or more.",
                    pillar: nil, symbol: "arrow.uturn.up.circle.fill", metric: .comebacks, goal: 1,
                    title: PlayerTitle(name: "The One Who Overcame Adversity", stat: .WIL, bonus: 2)),
        Achievement(id: "sys-arise", name: "Arise", detail: "Extract your first shadow.",
                    pillar: nil, symbol: "moon.stars", metric: .shadows, goal: 1),
        Achievement(id: "sys-army", name: "Shadow Army", detail: "Extract all seven shadows.",
                    pillar: nil, symbol: "moon.stars.fill", metric: .shadows, goal: Shadow.all.count,
                    title: PlayerTitle(name: "Monarch of Shadows", stat: .SOV, bonus: 3)),
    ]

    static let body: [Achievement] = [
        Achievement(id: "body-prep-1", name: "Preparation Begins", detail: "Clear Preparation to Become Powerful once.",
                    pillar: .body, symbol: "figure.strengthtraining.functional", metric: .preparation, goal: 1),
        Achievement(id: "body-prep-tier-6", name: "Half the Road", detail: "Reach Daily Quest tier 6: 40 reps each and 4 km.",
                    pillar: .body, symbol: "figure.walk", metric: .preparationTier, goal: 6),
        Achievement(id: "body-prep-canon", name: "Preparation Complete", detail: "Reach the canon load: 100 push-ups, 100 sit-ups, 100 squats, 10 km.",
                    pillar: .body, symbol: "bolt.fill", metric: .preparationTier, goal: PreparationLoad.maxTier,
                    title: PlayerTitle(name: "The One Who Became Powerful", stat: .STR, bonus: 3)),
        Achievement(id: "body-workout-1", name: "First Rep", detail: "Log your first workout.",
                    pillar: .body, symbol: "dumbbell", metric: .workouts, goal: 1),
        Achievement(id: "body-workout-10", name: "Iron Habit", detail: "Log 10 workouts.",
                    pillar: .body, symbol: "dumbbell.fill", metric: .workouts, goal: 10),
        Achievement(id: "body-workout-50", name: "Forged in Repetition", detail: "Log 50 workouts.",
                    pillar: .body, symbol: "flame", metric: .workouts, goal: 50,
                    title: PlayerTitle(name: "Ironbound", stat: .STR, bonus: 2)),
        Achievement(id: "body-cardio-300", name: "Long Road", detail: "300 minutes of cardio.",
                    pillar: .body, symbol: "figure.run", metric: .cardioMinutes, goal: 300),
        Achievement(id: "body-cardio-1500", name: "Tireless", detail: "1,500 minutes of cardio.",
                    pillar: .body, symbol: "figure.run.circle.fill", metric: .cardioMinutes, goal: 1500,
                    title: PlayerTitle(name: "Roadwalker", stat: .END, bonus: 2)),
        Achievement(id: "body-assess-3", name: "Measured Thrice", detail: "Log 3 assessments.",
                    pillar: .body, symbol: "ruler", metric: .assessments, goal: 3),
        Achievement(id: "body-pushups-20", name: "Twenty Strong", detail: "Best push-up set of 20.",
                    pillar: .body, symbol: "figure.strengthtraining.traditional", metric: .pushups, goal: 20),
        Achievement(id: "body-plank-120", name: "Stone Core", detail: "Hold a plank for 2:00.",
                    pillar: .body, symbol: "square.stack.3d.down.forward", metric: .plankSec, goal: 120),
        Achievement(id: "body-run-330", name: "Windstride", detail: "Run 1 km in 5:30 or less.",
                    pillar: .body, symbol: "wind", metric: .run1kSec, goal: 330,
                    title: PlayerTitle(name: "Windstrider", stat: .AGI, bonus: 2)),
        Achievement(id: "body-checkin-30", name: "Body Listener", detail: "Log 30 morning check-ins.",
                    pillar: .body, symbol: "heart.text.square", metric: .checkIns, goal: 30,
                    title: PlayerTitle(name: "Keeper of the Vessel", stat: .VIT, bonus: 2)),
        Achievement(id: "body-ladder-10", name: "Discomfort Eater", detail: "Climb the discomfort ladder 10 times.",
                    pillar: .body, symbol: "snowflake", metric: .ladder, goal: 10),
    ]

    static let mind: [Achievement] = [
        Achievement(id: "mind-drill-1", name: "Opened Eyes", detail: "Finish a perception drill.",
                    pillar: .mind, symbol: "eye", metric: .drills, goal: 1),
        Achievement(id: "mind-drill-50", name: "Unblinking", detail: "Finish 50 perception drills.",
                    pillar: .mind, symbol: "eye.fill", metric: .drills, goal: 50,
                    title: PlayerTitle(name: "The Unblinking", stat: .PER, bonus: 2)),
        Achievement(id: "mind-drill-level-10", name: "Sharpened Senses", detail: "Reach drill level 10.",
                    pillar: .mind, symbol: "scope", metric: .drillLevel, goal: 10),
        Achievement(id: "mind-reaction-250", name: "Lightning Nerve", detail: "Reaction benchmark of 250 ms or less.",
                    pillar: .mind, symbol: "bolt.fill", metric: .reactionMs, goal: 250),
        Achievement(id: "mind-lesson-1", name: "Student of the Board", detail: "Finish a game lesson.",
                    pillar: .mind, symbol: "book", metric: .lessons, goal: 1),
        Achievement(id: "mind-lesson-25", name: "Tactician", detail: "Finish 25 game lessons.",
                    pillar: .mind, symbol: "book.fill", metric: .lessons, goal: 25,
                    title: PlayerTitle(name: "Grand Tactician", stat: .INT, bonus: 2)),
        Achievement(id: "mind-chess-10", name: "Knight's Path", detail: "Finish 10 chess lessons.",
                    pillar: .mind, symbol: "crown", metric: .chessLessons, goal: 10),
        Achievement(id: "mind-go-10", name: "Stone Reader", detail: "Finish 10 go lessons.",
                    pillar: .mind, symbol: "circle.grid.3x3.fill", metric: .goLessons, goal: 10),
        Achievement(id: "mind-poker-10", name: "Cold Read", detail: "Finish 10 poker lessons.",
                    pillar: .mind, symbol: "suit.spade.fill", metric: .pokerLessons, goal: 10,
                    title: PlayerTitle(name: "The Cold Reader", stat: .WIL, bonus: 1)),
        Achievement(id: "mind-puzzle-20", name: "Puzzle Breaker", detail: "Solve 20 puzzles.",
                    pillar: .mind, symbol: "puzzlepiece.fill", metric: .puzzles, goal: 20),
        Achievement(id: "mind-quiz-10", name: "Flawless Recall", detail: "Ace 10 lesson quizzes.",
                    pillar: .mind, symbol: "checkmark.seal", metric: .perfectQuizzes, goal: 10),
        Achievement(id: "mind-practice-1", name: "Still Water", detail: "Log a mental training practice.",
                    pillar: .mind, symbol: "wind", metric: .practiceDays, goal: 1),
        Achievement(id: "mind-practice-30", name: "Tenacity", detail: "Train the mind on 30 days.",
                    pillar: .mind, symbol: "flame", metric: .practiceDays, goal: 30,
                    title: PlayerTitle(name: "The Unbroken", stat: .WIL, bonus: 2)),
        Achievement(id: "mind-practice-100", name: "Iron Mind", detail: "Train the mind on 100 days.",
                    pillar: .mind, symbol: "flame.fill", metric: .practiceDays, goal: 100),
        Achievement(id: "mind-focus-20", name: "Instant Dungeon", detail: "Clear 20 focus blocks.",
                    pillar: .mind, symbol: "door.left.hand.open", metric: .focusBlocks, goal: 20,
                    title: PlayerTitle(name: "Dungeon Diver", stat: .INT, bonus: 2)),
    ]

    static let social: [Achievement] = [
        Achievement(id: "social-1", name: "First Contact", detail: "Complete a social challenge.",
                    pillar: .social, symbol: "person.wave.2", metric: .socialDone, goal: 1),
        Achievement(id: "social-10", name: "Open Door", detail: "Complete 10 social challenges.",
                    pillar: .social, symbol: "person.2", metric: .socialDone, goal: 10),
        Achievement(id: "social-40", name: "Voice in the Hall", detail: "Complete 40 social challenges.",
                    pillar: .social, symbol: "person.3.fill", metric: .socialDone, goal: 40,
                    title: PlayerTitle(name: "Voice of the Hall", stat: .CHA, bonus: 2)),
    ]

    static let sovereign: [Achievement] = [
        Achievement(id: "sov-vow-7", name: "Detoxification", detail: "Keep a vow on 7 days.",
                    pillar: .sovereign, symbol: "leaf", metric: .vowDays, goal: 7),
        Achievement(id: "sov-vow-100", name: "Poison Immunity", detail: "Keep a vow on 100 days.",
                    pillar: .sovereign, symbol: "leaf.fill", metric: .vowDays, goal: 100,
                    title: PlayerTitle(name: "The Unpoisoned", stat: .WIL, bonus: 2)),
        Achievement(id: "sov-1", name: "Self-Ruled", detail: "Complete a sovereign challenge.",
                    pillar: .sovereign, symbol: "crown", metric: .sovereignDone, goal: 1),
        Achievement(id: "sov-40", name: "Own Court", detail: "Complete 40 sovereign challenges.",
                    pillar: .sovereign, symbol: "crown.fill", metric: .sovereignDone, goal: 40,
                    title: PlayerTitle(name: "Sovereign of One", stat: .SOV, bonus: 2)),
        Achievement(id: "sov-daily-7", name: "Seven Dawns", detail: "Clear every daily quest on 7 days.",
                    pillar: .sovereign, symbol: "sunrise", metric: .dailyClears, goal: 7),
        Achievement(id: "sov-streak-3", name: "Kindling", detail: "A 3-day daily streak.",
                    pillar: .sovereign, symbol: "flame", metric: .bestStreak, goal: 3),
        Achievement(id: "sov-streak-7", name: "Week Unbroken", detail: "A 7-day daily streak.",
                    pillar: .sovereign, symbol: "flame.fill", metric: .bestStreak, goal: 7),
        Achievement(id: "sov-streak-30", name: "Relentless", detail: "A 30-day daily streak.",
                    pillar: .sovereign, symbol: "flame.circle.fill", metric: .bestStreak, goal: 30,
                    title: PlayerTitle(name: "The Relentless", stat: .WIL, bonus: 2)),
        Achievement(id: "sov-streak-100", name: "Hundred Dawns", detail: "A 100-day daily streak.",
                    pillar: .sovereign, symbol: "infinity", metric: .bestStreak, goal: 100,
                    title: PlayerTitle(name: "Monarch of Habit", stat: .SOV, bonus: 3)),
        Achievement(id: "sov-weekly-10", name: "Week Warden", detail: "Claim 10 weekly quests.",
                    pillar: .sovereign, symbol: "calendar.badge.checkmark", metric: .weeklyClaims, goal: 10),
        Achievement(id: "sov-penalty-1", name: "Penalty Survivor", detail: "Clear a penalty quest.",
                    pillar: .sovereign, symbol: "exclamationmark.triangle", metric: .penaltiesCleared, goal: 1),
        Achievement(id: "sov-penalty-5", name: "Returned", detail: "Clear 5 penalty quests. Falling is allowed; staying down is not.",
                    pillar: .sovereign, symbol: "arrow.uturn.up", metric: .penaltiesCleared, goal: 5,
                    title: PlayerTitle(name: "Back from the Penalty Zone", stat: .WIL, bonus: 1)),
        Achievement(id: "sov-dungeon-1", name: "Gatebreaker", detail: "Clear a monthly dungeon.",
                    pillar: .sovereign, symbol: "door.left.hand.open", metric: .dungeons, goal: 1,
                    title: PlayerTitle(name: "Gatebreaker", stat: .SOV, bonus: 1)),
        Achievement(id: "sov-dungeon-4", name: "Red Gate Conqueror", detail: "Clear 4 monthly dungeons.",
                    pillar: .sovereign, symbol: "door.right.hand.closed", metric: .dungeons, goal: 4,
                    title: PlayerTitle(name: "Conqueror of the Red Gate", stat: .STR, bonus: 2)),
    ]
}
