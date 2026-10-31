import Foundation

/// Inputs needed to generate a day's quests. Pure data so generation is deterministic.
struct QuestContext {
    var dayKey: String
    var startKey: String
    var allowedDifficulty: Int
    var ladderStep: LadderStep?
    var ladderProgress: Int
    var completedLessonIDs: Set<String>
    /// Tier of the canon daily, from the number of times it has been cleared.
    var preparationTier: Int = 0
}

enum QuestEngine {
    static func dailies(_ ctx: QuestContext) -> [Quest] {
        let lib = ContentLibrary.shared
        var rng = SeededRNG("system|" + ctx.dayKey)
        let pos = TrainingEngine.position(of: ctx.dayKey, start: ctx.startKey)
        let d = ctx.dayKey
        var quests: [Quest] = []

        // BODY 1: boss, session, or active recovery.
        if pos.isAssessmentDay {
            quests.append(Quest(id: "\(d)-boss", kind: .assessment, title: "BOSS: Assessment Day",
                                detail: "1 km run for time, push-up max (one set, chest to fist), plank max hold, then the Reaction drill as your perception baseline. Log the numbers.",
                                pillar: .body, stat: .VIT, xp: 150, refID: "assessment", proof: "count", minutes: 40))
        } else if let s = TrainingEngine.session(for: pos) {
            let deload = pos.isDeload ? " [DELOAD]" : ""
            let detail: String
            if s.isStrength {
                let names = s.exercises.compactMap { lib.exercise($0.exercise)?.name }
                detail = names.joined(separator: " · ") + (s.circuit.map { " + \($0.minutes)-min \($0.format)" } ?? "")
            } else if let c = s.cardio {
                detail = "\(TrainingEngine.cardioMinutes(c, deload: pos.isDeload)) min · " + c.instructions
            } else if let c = s.circuit {
                detail = "\(c.minutes)-min \(c.format): " + c.moves.joined(separator: ", ")
            } else {
                detail = s.notes
            }
            quests.append(Quest(id: "\(d)-session", kind: .session, title: s.title + deload, detail: detail,
                                pillar: .body, stat: s.stat, xp: s.isStrength ? 40 : 35, refID: s.id,
                                proof: "log", minutes: s.minutes))
        } else {
            quests.append(Quest(id: "\(d)-recovery", kind: .recovery, title: "Active Recovery",
                                detail: "30-minute easy walk outdoors plus 10 minutes of mobility: hips, ankles, thoracic spine. Easy pace, nasal breathing.",
                                pillar: .body, stat: .VIT, xp: 20, refID: "recovery", proof: "check", minutes: 40))
        }

        // BODY 2: the canon Daily Quest. Skipped on boss day; the assessment is enough.
        if !pos.isAssessmentDay {
            quests.append(preparationQuest(day: d, tier: ctx.preparationTier))
        }

        // BODY 3: discomfort ladder.
        if let step = ctx.ladderStep {
            quests.append(Quest(id: "\(d)-ladder-\(step.id)", kind: .ladder,
                                title: step.title,
                                detail: step.detail + "  [\(ctx.ladderProgress)/\(step.repeats) to unlock next]",
                                pillar: .body, stat: step.stat, xp: step.xp, refID: step.id, proof: "check", minutes: 10))
        }

        // MIND: alternate perception drill and game lesson.
        let games = lib.availableGames.filter { g in
            lib.allLessons(g).contains { !ctx.completedLessonIDs.contains($0.id) }
        }
        if pos.dayIndex % 2 == 1, !games.isEmpty {
            let g = games[(pos.dayIndex / 2) % games.count]
            let next = lib.allLessons(g).first { !ctx.completedLessonIDs.contains($0.id) }
            quests.append(Quest(id: "\(d)-lesson-\(g.rawValue)", kind: .lesson,
                                title: "\(g.title) Lesson",
                                detail: next.map { "Next up: \($0.title). Read, pass the quiz, solve the puzzles." } ?? "Complete one \(g.title) lesson.",
                                pillar: .mind, stat: .INT, xp: 30, refID: g.rawValue, proof: "lesson", minutes: 15))
        } else {
            let drills = DrillKind.allCases
            let k = drills[(pos.dayIndex / 2 + pos.dayIndex % 2) % drills.count]
            quests.append(Quest(id: "\(d)-drill-\(k.rawValue)", kind: .drill, title: "Perception: \(k.title)",
                                detail: k.blurb, pillar: .mind, stat: .PER, xp: 25, refID: k.rawValue,
                                proof: "drill", minutes: 3))
        }

        // SOCIAL and SOVEREIGN from challenges.json.
        for pillar in [Pillar.social, .sovereign] {
            if let c = pickChallenge(pillar: pillar, maxDifficulty: ctx.allowedDifficulty, rng: &rng) {
                quests.append(quest(from: c, day: d))
            } else {
                quests.append(fallback(pillar, day: d))
            }
        }
        return quests
    }

    static func quest(from c: Challenge, day: String) -> Quest {
        Quest(id: "\(day)-ch-\(c.id)", kind: .challenge, title: c.title, detail: c.instructions,
              pillar: c.pillar, stat: c.stat, xp: 15 + 5 * max(1, min(5, c.difficulty)), refID: c.id,
              proof: c.proof, minutes: c.minutes)
    }

    static func pickChallenge(pillar: Pillar, maxDifficulty: Int, rng: inout SeededRNG) -> Challenge? {
        let all = ContentLibrary.shared.challenges.filter { $0.pillar == pillar }.sorted { $0.id < $1.id }
        let daily = all.filter { $0.cadence == "daily" && $0.difficulty <= maxDifficulty }
        if let c = rng.pick(daily) { return c }
        let any = all.filter { $0.difficulty <= maxDifficulty }
        return rng.pick(any)
    }

    static func fallback(_ pillar: Pillar, day: String) -> Quest {
        switch pillar {
        case .social:
            return Quest(id: "\(day)-fb-social", kind: .challenge, title: "Reach Out",
                         detail: "Message or call one person you have not spoken to this week. Ask one real question and listen to the answer.",
                         pillar: .social, stat: .CHA, xp: 20, refID: "fallback-social", proof: "check", minutes: 10)
        case .sovereign:
            return Quest(id: "\(day)-fb-sovereign", kind: .challenge, title: "Own the Day",
                         detail: "Write tomorrow's three priorities before bed. Do the hardest one first, before checking messages.",
                         pillar: .sovereign, stat: .SOV, xp: 20, refID: "fallback-sovereign", proof: "check", minutes: 10)
        default:
            return Quest(id: "\(day)-fb-\(pillar.rawValue)", kind: .challenge, title: "Ten Quiet Minutes",
                         detail: "Sit for ten minutes with no input. Notice thoughts, let them pass.",
                         pillar: pillar, stat: .WIL, xp: 20, refID: "fallback", proof: "check", minutes: 10)
        }
    }

    // MARK: preparation

    static func preparationQuest(day: String, tier: Int) -> Quest {
        Quest(id: "\(day)-prep", kind: .preparation, title: "Preparation to Become Powerful",
              detail: preparationDetail(PreparationLoad.at(tier: tier), tier: tier, reduced: nil),
              pillar: .body, stat: .STR, xp: 25, refID: "prep-\(tier)", proof: "check", minutes: 30)
    }

    /// The tier a quest was issued at. Older plans have no tier and read as 0.
    static func tier(of q: Quest) -> Int {
        Int(q.refID.split(separator: "-").last ?? "") ?? 0
    }

    static func preparationDetail(_ load: PreparationLoad, tier: Int, reduced: String?) -> String {
        var s = "\(load.reps) push-ups · \(load.reps) sit-ups · \(load.reps) squats · \(Fmt.num(load.km)) km walk or run. "
            + "Any sets, any order, spread across the day. Knee push-ups count; walking counts."
        if let r = reduced { s += "\nLoad halved: \(r)." }
        if tier >= PreparationLoad.maxTier {
            s += "\nCanon load reached: 100 · 100 · 100 · 10 km."
        } else {
            s += "\nTier \(tier)/\(PreparationLoad.maxTier). The load rises every \(PreparationLoad.clearsPerTier) clears."
        }
        return s
    }

    // MARK: penalty

    static func penaltyQuest(day: String, tier: Int) -> Quest {
        Quest(id: "\(day)-penalty", kind: .penalty, title: "PENALTY QUEST: Survive",
              detail: penaltyDetail(tier: tier, halved: false), pillar: .body, stat: .WIL, xp: 20,
              refID: "penalty-\(tier)", proof: "check", minutes: 25)
    }

    /// Half a Daily Quest's reps (a quarter when strained) plus a brisk walk. At the
    /// canon tier that is the old 50-rep make-up set; at the start it is 10 reps.
    static func penaltyDetail(tier: Int, halved: Bool) -> String {
        let reps = PreparationLoad.at(tier: tier).reps
        if halved {
            let r = max(5, reps / 4)
            return "The Penalty Zone, load halved (poor sleep, soreness or fatigue logged): \(r) push-ups, \(r) sit-ups, \(r) squats, then a 10-minute brisk walk. Any sets, knees allowed."
        }
        let r = max(10, reps / 2)
        return "The Penalty Zone. Survive it: \(r) push-ups, \(r) sit-ups, \(r) squats, then a 15-minute brisk walk. Any sets, knees allowed. Hard, not punishing."
    }

    static let penaltyXP = 40
}
