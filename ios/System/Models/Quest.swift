import Foundation

enum QuestKind: String, Codable {
    case session      // today's training session, completes when a workout is logged
    case recovery     // rest-day active recovery, manual
    case ladder       // discomfort ladder step, manual
    case drill        // perception drill, completes when that drill is finished
    case lesson       // game lesson, completes when a lesson of that game is finished
    case challenge    // from challenges.json, manual
    case penalty      // make-up set after a missed day, manual
    case assessment   // boss: benchmark day, completes when an assessment is logged
}

/// A single daily quest. Plans are generated once per day and persisted, so the
/// set never shifts under the user if rank or content changes mid-day.
struct Quest: Codable, Identifiable, Hashable {
    var id: String
    var kind: QuestKind
    var title: String
    var detail: String
    var pillar: Pillar
    var stat: Stat
    var xp: Int
    var refID: String
    var proof: String
    var minutes: Int
}

enum DrillKind: String, Codable, CaseIterable, Identifiable {
    case reaction, peripheral, tracking, kims
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reaction: return "Reaction"
        case .peripheral: return "Peripheral Vision"
        case .tracking: return "Object Tracking"
        case .kims: return "Kim's Game"
        }
    }
    var symbol: String {
        switch self {
        case .reaction: return "bolt.fill"
        case .peripheral: return "eye.fill"
        case .tracking: return "circle.hexagongrid.fill"
        case .kims: return "square.grid.3x3.fill"
        }
    }
    var blurb: String {
        switch self {
        case .reaction: return "Tap the instant the field turns cyan. Early taps are false starts."
        case .peripheral: return "Hold your eyes on the centre. Name the letter that flashes at the edge."
        case .tracking: return "Track the marked targets as they move among decoys."
        case .kims: return "Memorise the grid. Find what changed."
        }
    }
    /// Unit for the score shown in charts.
    var unit: String {
        switch self {
        case .reaction: return "ms"
        default: return "%"
        }
    }
    /// Lower is better for reaction time.
    var lowerIsBetter: Bool { self == .reaction }
}

/// Weekly volume target shown on the Weekly tab.
struct WeeklyTarget: Identifiable {
    var id: String
    var title: String
    var stat: Stat
    var current: Double
    var goal: Double
    var unit: String
    var xp: Int
    var claimed: Bool
    var done: Bool { current >= goal }
}

struct DungeonStep: Identifiable {
    var id: String
    var title: String
    var current: Int
    var goal: Int
    var done: Bool { current >= goal }
}
