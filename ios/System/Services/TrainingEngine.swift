import Foundation

/// Where a given day sits inside the 12-week programme.
struct ProgrammeDay {
    var dayIndex: Int          // days since programme start (>= 0)
    var week: Int              // 1-based calendar week of the programme (keeps counting after 12)
    var effectiveWeek: Int     // week used for phase lookup (cycles 9-12 after the programme ends)
    var dayInWeek: Int         // 0-6
    var isDeload: Bool
    var phase: Phase?
    var block: Int             // 4-week dungeon block, 1-based
    var weekInBlock: Int       // 1-4
    var isAssessmentDay: Bool  // last day of the 4th week of each block
}

struct ExerciseTarget: Identifiable {
    var id: String { exercise.id + "-\(index)" }
    var index: Int
    var exercise: Exercise
    var sets: Int
    var repMin: Int
    var repMax: Int
    var restSec: Int
    var weight: Double?
    var note: String
    var progressed: Bool
}

/// One past session's sets for a single exercise.
struct ExerciseHistory {
    var date: Date
    var deload: Bool
    var sets: [SetLog]
}

enum TrainingEngine {
    static var program: TrainingProgram { ContentLibrary.shared.training }

    static func position(of dayKey: String, start: String) -> ProgrammeDay {
        let p = program
        let idx = max(0, DayKey.daysBetween(start, dayKey))
        let week = idx / 7 + 1
        let total = max(1, p.totalWeeks)
        let every = max(1, p.deloadEvery)
        var eff = week
        if week > total {
            // After the programme, keep cycling the final block.
            let blockStart = max(1, total - every + 1)
            eff = blockStart + ((week - total - 1) % every)
        }
        let phase = p.phases.first { $0.weeks.contains(eff) } ?? p.phases.last
        let deload = eff % every == 0
        let block = (week - 1) / every + 1
        let wib = (week - 1) % every + 1
        let dow = idx % 7
        return ProgrammeDay(dayIndex: idx, week: week, effectiveWeek: eff, dayInWeek: dow,
                            isDeload: deload, phase: phase, block: block, weekInBlock: wib,
                            isAssessmentDay: wib == every && dow == 6)
    }

    static func session(for pos: ProgrammeDay) -> SessionTemplate? {
        guard let slot = pos.phase?.schedule.first(where: { $0.day == pos.dayInWeek }) else { return nil }
        return ContentLibrary.shared.session(slot.session)
    }

    /// Next scheduled session on or after `dayKey` (up to two weeks ahead).
    static func nextSession(from dayKey: String, start: String) -> (String, SessionTemplate)? {
        for i in 0..<14 {
            let k = DayKey.add(i, to: dayKey)
            let pos = position(of: k, start: start)
            if pos.isAssessmentDay { continue }
            if let s = session(for: pos) { return (k, s) }
        }
        return nil
    }

    static func roundLoad(_ w: Double) -> Double { (w * 2).rounded() / 2 }

    /// Double progression. `history` is newest first.
    static func target(for presc: Prescription, index: Int, history: [ExerciseHistory], deload: Bool) -> ExerciseTarget? {
        guard let ex = ContentLibrary.shared.exercise(presc.exercise) else { return nil }
        let rule = program.progression
        let dl = program.deload
        var sets = presc.sets
        if deload { sets = max(1, Int((Double(presc.sets) * dl.setFactor).rounded())) }

        var t = ExerciseTarget(index: index, exercise: ex, sets: sets, repMin: presc.repMin, repMax: presc.repMax,
                               restSec: presc.restSec, weight: nil, note: ex.startHint, progressed: false)

        let real = history.filter { !$0.deload && !$0.sets.isEmpty }
        guard let last = real.first else {
            if deload { t.note = "Deload: easy, crisp reps. " + ex.startHint }
            return t
        }
        let working = last.sets.map(\.weight).max() ?? 0
        let need = max(1, rule.consecutiveSessions)
        let topHit: (ExerciseHistory) -> Bool = { h in
            let w = h.sets.map(\.weight).max() ?? 0
            return abs(w - working) < 0.01 && h.sets.allSatisfy { $0.reps >= presc.repMax }
        }
        let ready = real.count >= need && real.prefix(need).allSatisfy(topHit)
        let lastReps = last.sets.sorted { $0.setIndex < $1.setIndex }.map { String($0.reps) }.joined(separator: "/")

        if ex.isLoaded {
            if ready {
                t.weight = roundLoad(working + ex.increment)
                t.progressed = true
                t.note = "Top of range hit \(need)x. Load up +\(Fmt.num(ex.increment)) kg, restart at \(presc.repMin) reps."
            } else {
                t.weight = working
                t.note = "Last: \(Fmt.kg(working)) × \(lastReps). Beat it: add a rep on any set."
            }
            if deload, let w = t.weight {
                t.weight = roundLoad(w * dl.loadFactor)
                t.note = "Deload: \(Int(dl.loadFactor * 100))% load, fewer sets. Leave reps in the tank."
            }
        } else if ex.isTimed {
            let best = last.sets.map(\.reps).max() ?? presc.repMin
            if ready {
                t.repMin = min(presc.repMax + Int(ex.increment), best + Int(ex.increment))
                t.repMax = t.repMin
                t.progressed = true
                t.note = "Top hit \(need)x. Hold \(t.repMin) s, or move to a harder variation."
            } else {
                t.note = "Last: \(lastReps) s. Add time on any set."
            }
            if deload { t.note = "Deload: easy holds." }
        } else {
            if ready {
                t.progressed = true
                t.note = "Top hit \(need)x. Use a harder variation or add a slow 3 s lowering."
            } else {
                t.note = "Last: \(lastReps). Add a rep on any set."
            }
            if deload { t.note = "Deload: stop 3+ reps short of failure." }
        }
        return t
    }

    static func cardioMinutes(_ c: CardioBlock, deload: Bool) -> Int {
        deload ? max(10, Int((Double(c.minutes) * program.deload.cardioFactor).rounded())) : c.minutes
    }
}
