import Foundation
import SwiftData

// MARK: - Preparation to Become Powerful

/// The canon daily quest (100 push-ups, 100 sit-ups, 100 squats, 10 km), reached
/// gradually. The tier rises by one for every five clears, so the load follows
/// what the player has actually done rather than the calendar. Tier 18 is canon.
struct PreparationLoad: Equatable {
    var reps: Int
    var km: Double

    static let maxTier = 18
    static let clearsPerTier = 5

    static func tier(clears: Int) -> Int { max(0, min(maxTier, clears / clearsPerTier)) }

    static func at(tier: Int) -> PreparationLoad {
        let t = max(0, min(maxTier, tier))
        return PreparationLoad(reps: 10 + 5 * t, km: 1 + 0.5 * Double(t))
    }

    /// Scales the load, rounding reps to whole numbers and distance to half kilometres.
    func scaled(_ f: Double) -> PreparationLoad {
        PreparationLoad(reps: max(5, Int((Double(reps) * f).rounded())),
                        km: max(0.5, (km * f * 2).rounded() / 2))
    }

    var isCanon: Bool { reps >= 100 && km >= 10 }
}

// MARK: - Fatigue

/// 0-100, from today's check-in, Apple Health and the last three days of training.
struct Fatigue {
    var value: Int
    var reasons: [String]

    /// At or above this, the Daily Quest load is halved.
    static let highThreshold = 60

    var high: Bool { value >= Self.highThreshold }
    var label: String { value >= Self.highThreshold ? "FATIGUED" : value >= 30 ? "LOADED" : "FRESH" }
}

// MARK: - Shadow Army

enum ShadowGrade: Int, CaseIterable {
    case normal, elite, knight, eliteKnight, commander, marshal, grandMarshal

    var title: String {
        ["Normal", "Elite", "Knight", "Elite Knight", "Commander", "Marshal", "Grand Marshal"][rawValue]
    }

    /// Multiples of the extraction threshold needed for each grade.
    static let multiples = [1, 2, 3, 5, 8, 12, 20]

    static func grade(progress: Int, threshold: Int) -> ShadowGrade? {
        guard threshold > 0, progress >= threshold else { return nil }
        let m = progress / threshold
        let i = multiples.lastIndex { m >= $0 } ?? 0
        return ShadowGrade(rawValue: i)
    }
}

enum ShadowMetric {
    case preparation, strength, checkIns, lessons, vowDays, dungeons, cardioKm
}

/// A shadow is extracted when a habit has been sustained long enough to stand on
/// its own. Each one is a record of repetition, not a reward for a single effort.
struct Shadow: Identifiable {
    var id: String
    var name: String
    var epithet: String
    var lore: String
    var habit: String
    var stat: Stat
    var metric: ShadowMetric
    var threshold: Int
    var unit: String
    var symbol: String

    static let all: [Shadow] = [
        Shadow(id: "igris", name: "Igris", epithet: "the Blood-Red Commander",
               lore: "The knight who guarded the Job Change gate. He kneels to the one who did not stop.",
               habit: "Clear Preparation to Become Powerful", stat: .WIL, metric: .preparation,
               threshold: 30, unit: "clears", symbol: "shield.lefthalf.filled"),
        Shadow(id: "tank", name: "Tank", epithet: "the Ice Bear",
               lore: "Raw strength, built one session at a time.",
               habit: "Log strength sessions", stat: .STR, metric: .strength,
               threshold: 12, unit: "sessions", symbol: "dumbbell.fill"),
        Shadow(id: "iron", name: "Iron", epithet: "the Shield",
               lore: "He holds the line. A hunter who knows their condition is hard to break.",
               habit: "Log your morning status", stat: .VIT, metric: .checkIns,
               threshold: 30, unit: "check-ins", symbol: "shield.fill"),
        Shadow(id: "tusk", name: "Tusk", epithet: "the High Orc Shaman",
               lore: "Knowledge turned into power.",
               habit: "Finish game lessons", stat: .INT, metric: .lessons,
               threshold: 20, unit: "lessons", symbol: "book.closed.fill"),
        Shadow(id: "kaisel", name: "Kaisel", epithet: "the Wyvern",
               lore: "Distance covered becomes speed.",
               habit: "Log cardio distance", stat: .AGI, metric: .cardioKm,
               threshold: 50, unit: "km", symbol: "wind"),
        Shadow(id: "beru", name: "Beru", epithet: "the Ant King",
               lore: "The worst enemy, made loyal. What once consumed you now serves you.",
               habit: "Keep your vows", stat: .WIL, metric: .vowDays,
               threshold: 30, unit: "vow-days", symbol: "ant.fill"),
        Shadow(id: "bellion", name: "Bellion", epithet: "the Grand Marshal",
               lore: "The first and strongest. He answers only to a sovereign.",
               habit: "Clear monthly dungeons", stat: .SOV, metric: .dungeons,
               threshold: 3, unit: "dungeons", symbol: "crown.fill"),
    ]

    static let extractionXP = 50
}

// MARK: - Vows

/// A daily vow the player chooses on the device. Nothing personal is built in:
/// the presets are generic and the custom vow is the player's own words.
struct VowPreset: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    /// Vows against a substance or urge get a "craving resisted" button.
    var craving: Bool

    static let custom = "custom"

    static let presets: [VowPreset] = [
        VowPreset(id: "smoke-free", title: "Smoke-free",
                  detail: "No cigarettes, vapes or nicotine today.", craving: true),
        VowPreset(id: "sober", title: "Sober",
                  detail: "No alcohol or recreational drugs today.", craving: true),
        VowPreset(id: "no-sugar-drinks", title: "No sugary drinks",
                  detail: "Water, tea or coffee without sugar. No soda, juice or energy drinks.", craving: true),
        VowPreset(id: "out-of-bed", title: "Feet on the floor",
                  detail: "Out of bed within 10 minutes of waking. The phone charges across the room.", craving: false),
        VowPreset(id: "phone-free-hour", title: "Phone-free first hour",
                  detail: "No feeds or messages for the first hour awake.", craving: false),
        VowPreset(id: "sleep-anchor", title: "Sleep anchor",
                  detail: "Lights out at the same time every night, screens away 30 minutes before.", craving: false),
    ]
}

/// "Skills, once learned, are not lost." The Detoxification level is set by the
/// best streak ever held, so a slip resets the streak but never the skill.
enum Detoxification {
    static let thresholds = [1, 3, 7, 14, 30, 60, 90, 180, 365]

    static func level(bestStreak: Int) -> Int { thresholds.filter { bestStreak >= $0 }.count }

    static func nextThreshold(bestStreak: Int) -> Int? { thresholds.first { bestStreak < $0 } }
}

/// One row per vow per day. A craving can be logged before the day is judged,
/// so `judged` says whether `kept` has been set yet.
@Model
final class VowLog {
    @Attribute(.unique) var key: String
    var dayKey: String
    var vowID: String
    var judged: Bool
    var kept: Bool
    var cravingsResisted: Int
    var date: Date

    init(dayKey: String, vowID: String) {
        self.key = dayKey + "|" + vowID
        self.dayKey = dayKey
        self.vowID = vowID
        self.judged = false
        self.kept = false
        self.cravingsResisted = 0
        self.date = .now
    }
}
