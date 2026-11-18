import Foundation
import SwiftData

// MARK: - Domains (v3)

/// The six v3 domains. Sovereignty is not a domain: it is the overall rank.
enum Domain: String, Codable, CaseIterable, Identifiable {
    case body, mind, bonds, ambition, wealth, ground
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .body: return "figure.strengthtraining.traditional"
        case .mind: return "brain.head.profile"
        case .bonds: return "person.2.fill"
        case .ambition: return "flag.fill"
        case .wealth: return "banknote.fill"
        case .ground: return "house.fill"
        }
    }

    /// Old pillars map onto domains; `sovereign` feeds the overall rank instead.
    static func from(_ p: Pillar) -> Domain? {
        switch p {
        case .body: return .body
        case .mind: return .mind
        case .social: return .bonds
        case .sovereign: return nil
        }
    }

    static func parse(_ s: String) -> Domain { Domain(rawValue: s.lowercased()) ?? .ambition }

    /// At most this many Ambition quests may be scheduled on one day.
    static let ambitionCap = V3Rules.ambitionCap
}

enum CampaignStatus: String, Codable, CaseIterable {
    case active, paused, done
}

// MARK: - Campaign -> Gate -> Quest

/// A long arc tied to a real goal. Written by the owner.
@Model
final class Campaign {
    var uid: String
    var title: String
    var goal: String
    var status: String
    var created: Date
    /// Monday day key of the week it was last picked in "Choose three" ("" = never).
    var chosenWeek: String

    init(title: String, goal: String = "") {
        self.uid = UUID().uuidString
        self.title = title
        self.goal = goal
        self.status = CampaignStatus.active.rawValue
        self.created = .now
        self.chosenWeek = ""
    }

    var state: CampaignStatus { CampaignStatus(rawValue: status) ?? .active }
}

/// A dated milestone inside a campaign. "Gate" in the UI; named apart from the
/// daily morning/evening gates (`DayGate`).
@Model
final class CampaignGate {
    var uid: String
    var campaignID: String
    var title: String
    var dateKey: String
    var done: Bool
    var doneDate: Date?
    /// Suggested-gate id from architect when accepted from a suggestion, else "".
    var sourceID: String
    var source: String
    var created: Date

    init(campaignID: String, title: String, dateKey: String, sourceID: String = "", source: String = "") {
        self.uid = UUID().uuidString
        self.campaignID = campaignID
        self.title = title
        self.dateKey = dateKey
        self.done = false
        self.doneDate = nil
        self.sourceID = sourceID
        self.source = source
        self.created = .now
    }
}

/// A concrete action the owner wrote. Nothing in the app or server generates these.
@Model
final class OwnerQuest {
    var uid: String
    var title: String
    var domain: String
    /// "" when standalone.
    var campaignID: String
    var gateID: String
    /// Day it is scheduled for ("" = backlog).
    var dayKey: String
    var done: Bool
    var doneKey: String
    var doneDate: Date?
    var created: Date

    init(title: String, domain: Domain, campaignID: String = "", gateID: String = "", dayKey: String = "") {
        self.uid = UUID().uuidString
        self.title = title
        self.domain = domain.rawValue
        self.campaignID = campaignID
        self.gateID = gateID
        self.dayKey = dayKey
        self.done = false
        self.doneKey = ""
        self.doneDate = nil
        self.created = .now
    }

    var dom: Domain { Domain.parse(domain) }
}

// MARK: - Daily gates

enum DayGateKind: String, Codable {
    case morning, evening
    /// The one-tap "I'm here" from collapsed mode. Counts as presence.
    case here
}

/// One completed daily gate. Morning carries energy and intention; evening the line.
@Model
final class DayGate {
    var dayKey: String
    var kind: String
    var energy: Int
    var line: String
    var questsDone: Int
    var questsTotal: Int
    var date: Date

    init(dayKey: String, kind: DayGateKind, energy: Int = 0, line: String = "", questsDone: Int = 0, questsTotal: Int = 0) {
        self.dayKey = dayKey
        self.kind = kind.rawValue
        self.energy = energy
        self.line = line
        self.questsDone = questsDone
        self.questsTotal = questsTotal
        self.date = .now
    }
}
