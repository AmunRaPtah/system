import Foundation
import SwiftData
import Observation

struct SystemAlert: Identifiable, Equatable {
    enum Style: Equatable { case quest, levelUp, rankUp, penalty, info }
    let id = UUID()
    var style: Style
    var title: String
    var lines: [String]
}

struct PlayerSnapshot {
    var statXP: [Stat: Int] = [:]
    var totalXP = 0
    var level = 1
    var rank: Rank = .E
    var benchmarks = Benchmarks()
    var streak = 0
    var bestStreak = 0

    func xp(_ s: Stat) -> Int { statXP[s] ?? 0 }
    func points(_ s: Stat) -> Int { Leveling.statPoints(xp(s)) }
    /// Rank the level alone would allow; if higher than `rank`, a trial is pending.
    var levelRank: Rank { Leveling.rankByLevel(level) }
    var trialPending: Rank? {
        guard let n = rank.next, level >= n.minLevel else { return nil }
        return n
    }
}

struct LadderState {
    var step: LadderStep?
    var count: Int
    var index: Int
    var total: Int
}

struct DungeonState {
    var block: Int
    var title: String
    var weekInBlock: Int
    var firstKey: String
    var lastKey: String
    var steps: [DungeonStep]
    var bossUnlocked: Bool
    var bossDone: Bool
    var claimed: Bool
    var cleared: Bool { bossDone && steps.allSatisfy(\.done) }
}

enum DefaultsKey {
    static let start = "system.startKey"
    static let lastEval = "system.lastEvaluatedKey"
    static let morning = "system.morningMinutes"
    static let evening = "system.eveningMinutes"
    static let askedPermission = "system.askedNotificationPermission"
    static func drillLevel(_ k: DrillKind) -> String { "system.drillLevel.\(k.rawValue)" }
}

@MainActor
@Observable
final class SystemStore {
    let context: ModelContext
    let defaults = UserDefaults.standard
    let lib = ContentLibrary.shared

    var player = PlayerSnapshot()
    var completed: Set<String> = []
    var revision = 0
    var alerts: [SystemAlert] = []
    private(set) var startKey: String

    init(context: ModelContext) {
        self.context = context
        defaults.register(defaults: [DefaultsKey.morning: 7 * 60, DefaultsKey.evening: 20 * 60])
        if defaults.string(forKey: DefaultsKey.start) == nil {
            let today = DayKey.today
            defaults.set(today, forKey: DefaultsKey.start)
            defaults.set(DayKey.add(-1, to: today), forKey: DefaultsKey.lastEval)
        }
        startKey = defaults.string(forKey: DefaultsKey.start) ?? DayKey.today
        refresh()
    }

    // MARK: - Lifecycle

    /// Launch / foreground / day-change entry point. Missed days are judged here,
    /// from stored data, so nothing depends on the app being open at midnight.
    func tick() {
        refresh()
        evaluateMissedDays()
        _ = plan(DayKey.today)
        save()
        refresh()
        reschedule()
    }

    func requestNotificationsIfNeeded() {
        if !defaults.bool(forKey: DefaultsKey.askedPermission) {
            defaults.set(true, forKey: DefaultsKey.askedPermission)
            Notifier.requestPermission()
        }
    }

    func reschedule() {
        let today = DayKey.today
        var days: [NotificationDay] = []
        for i in 0..<7 {
            let k = DayKey.add(i, to: today)
            let done = i == 0 ? (plan(k, create: false).map { dailiesComplete($0) } ?? false) : false
            days.append(NotificationDay(dayKey: k, complete: done, deload: position(k).isDeload))
        }
        Notifier.reschedule(days: days,
                            morningMinutes: defaults.integer(forKey: DefaultsKey.morning),
                            eveningMinutes: defaults.integer(forKey: DefaultsKey.evening))
    }

    // MARK: - Fetching

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    func save() { try? context.save() }

    func refresh() {
        let events = fetchAll(XPEvent.self)
        var sx: [Stat: Int] = [:]
        var total = 0
        for e in events {
            sx[Stat.parse(e.stat), default: 0] += e.amount
            total += e.amount
        }
        total = max(0, total)
        let level = Leveling.level(for: total)
        let bm = bestBenchmarks()
        var rank = Rank.E
        for r in Rank.allCases.dropFirst() {
            if level >= r.minLevel, let g = r.gate, g.passed(by: bm) { rank = r } else { break }
        }
        completed = Set(fetchAll(QuestCompletion.self).map(\.key))
        var snap = PlayerSnapshot(statXP: sx, totalXP: total, level: level, rank: rank, benchmarks: bm)
        let s = computeStreaks()
        snap.streak = s.0
        snap.bestStreak = s.1
        player = snap
        revision += 1
    }

    func bestBenchmarks() -> Benchmarks {
        let a = fetchAll(AssessmentRecord.self)
        return Benchmarks(
            run1kSec: a.map(\.run1kSec).filter { $0 > 0 }.min(),
            pushups: a.map(\.pushups).filter { $0 > 0 }.max(),
            plankSec: a.map(\.plankSec).filter { $0 > 0 }.max(),
            reactionMs: a.map(\.reactionMs).filter { $0 > 0 }.min()
        )
    }

    // MARK: - Programme

    func position(_ key: String) -> ProgrammeDay {
        TrainingEngine.position(of: key, start: startKey)
    }

    func setStart(_ date: Date) {
        let k = DayKey.key(date)
        startKey = k
        defaults.set(k, forKey: DefaultsKey.start)
        let yesterday = DayKey.add(-1, to: DayKey.today)
        defaults.set(yesterday, forKey: DefaultsKey.lastEval)
        // Today's plan reflects the new programme day.
        if let p = plan(DayKey.today, create: false) {
            let penalty = p.quests.filter { $0.kind == .penalty }
            p.quests = QuestEngine.dailies(questContext(DayKey.today)) + penalty
        }
        save()
        refresh()
        reschedule()
    }

    func ladderState() -> LadderState {
        let steps = lib.training.ladder
        var counts: [String: Int] = [:]
        for r in fetchAll(LadderRecord.self) { counts[r.stepID, default: 0] += 1 }
        for (i, s) in steps.enumerated() {
            let c = counts[s.id] ?? 0
            if c < s.repeats { return LadderState(step: s, count: c, index: i, total: steps.count) }
        }
        return LadderState(step: nil, count: 0, index: steps.count, total: steps.count)
    }

    func ladderCount(_ id: String) -> Int {
        fetchAll(LadderRecord.self).filter { $0.stepID == id }.count
    }

    func completedLessonIDs() -> Set<String> {
        Set(fetchAll(LessonRecord.self).map(\.lessonID))
    }

    func questContext(_ key: String) -> QuestContext {
        let ls = ladderState()
        return QuestContext(dayKey: key, startKey: startKey, allowedDifficulty: player.rank.allowedDifficulty,
                            ladderStep: ls.step, ladderProgress: ls.count,
                            completedLessonIDs: completedLessonIDs())
    }

    // MARK: - Plans and quests

    func plan(_ key: String, create: Bool = true) -> DayPlan? {
        var d = FetchDescriptor<DayPlan>(predicate: #Predicate<DayPlan> { $0.dayKey == key })
        d.fetchLimit = 1
        if let p = (try? context.fetch(d))?.first { return p }
        guard create else { return nil }
        let p = DayPlan(dayKey: key, quests: QuestEngine.dailies(questContext(key)))
        context.insert(p)
        save()
        return p
    }

    func quests(_ key: String = DayKey.today) -> [Quest] {
        _ = revision
        return plan(key, create: false)?.quests ?? []
    }

    func isDone(_ q: Quest, on key: String = DayKey.today) -> Bool {
        completed.contains(key + "|" + q.id)
    }

    func dailiesComplete(_ p: DayPlan) -> Bool {
        let qs = p.quests.filter { $0.kind != .penalty }
        guard !qs.isEmpty else { return false }
        return qs.allSatisfy { completed.contains(p.dayKey + "|" + $0.id) }
    }

    func checkIn(_ key: String) -> CheckIn? {
        var d = FetchDescriptor<CheckIn>(predicate: #Predicate<CheckIn> { $0.dayKey == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func penaltyHalved(_ key: String = DayKey.today) -> Bool {
        (plan(key, create: false)?.penaltyStrained ?? false) || (checkIn(key)?.isStrained ?? false)
    }

    func displayDetail(_ q: Quest, on key: String = DayKey.today) -> String {
        q.kind == .penalty ? QuestEngine.penaltyDetail(halved: penaltyHalved(key)) : q.detail
    }

    // MARK: - XP plumbing

    private typealias Before = (level: Int, rank: Rank)
    private func begin() -> Before { (player.level, player.rank) }

    private func addXP(_ stat: Stat, _ amount: Int, source: String, note: String, key: String = DayKey.today) {
        guard amount != 0 else { return }
        context.insert(XPEvent(dayKey: key, stat: stat, amount: amount, source: source, note: note))
    }

    /// Inserts the completion and its XP. Returns the alert line, or nil if already done.
    @discardableResult
    private func mark(_ q: Quest, key: String, note: String = "") -> String? {
        guard !completed.contains(key + "|" + q.id) else { return nil }
        context.insert(QuestCompletion(questID: q.id, dayKey: key, kind: q.kind.rawValue,
                                       pillar: q.pillar.rawValue, stat: q.stat.rawValue, note: note))
        completed.insert(key + "|" + q.id)
        if q.kind == .ladder { context.insert(LadderRecord(stepID: q.refID, dayKey: key)) }
        addXP(q.stat, q.xp, source: "quest", note: q.title, key: key)
        return "\(q.title)  +\(q.xp) XP \(q.stat.rawValue)"
    }

    private func dailyBonusLine(_ key: String) -> String? {
        guard let p = plan(key, create: false), dailiesComplete(p) else { return nil }
        let ck = "daily-\(key)"
        guard !claimed(ck) else { return nil }
        context.insert(Claim(key: ck))
        addXP(.SOV, 25, source: "daily-clear", note: "All dailies cleared", key: key)
        return "DAILY QUEST CLEARED  +25 XP SOV"
    }

    private func finish(_ b: Before, style: SystemAlert.Style = .quest, title: String, lines: [String]) {
        save()
        refresh()
        if !lines.isEmpty || !title.isEmpty {
            alerts.append(SystemAlert(style: style, title: title, lines: lines))
        }
        if player.level > b.level {
            alerts.append(SystemAlert(style: .levelUp, title: "LEVEL UP",
                                      lines: ["Lv. \(b.level) → Lv. \(player.level)",
                                              "All stats are growing. Keep going."]))
        }
        if player.rank > b.rank {
            alerts.append(SystemAlert(style: .rankUp, title: "RANK UP",
                                      lines: ["\(b.rank.letter)-Rank → \(player.rank.letter)-Rank",
                                              "Title acquired: \(player.rank.title)",
                                              "Harder quests are now available."]))
        }
        reschedule()
    }

    /// Public XP entry for self-contained trainers (poker): award, save, raise alerts.
    func awardXP(_ awards: [(Stat, Int)], source: String, note: String, title: String, lines: [String]) {
        let b = begin()
        for (s, a) in awards { addXP(s, a, source: source, note: note) }
        finish(b, title: title, lines: lines)
    }

    func claimed(_ key: String) -> Bool {
        var d = FetchDescriptor<Claim>(predicate: #Predicate<Claim> { $0.key == key })
        d.fetchLimit = 1
        return ((try? context.fetch(d))?.first) != nil
    }

    // MARK: - Actions

    func complete(_ q: Quest, note: String = "") {
        let key = DayKey.today
        let b = begin()
        guard let line = mark(q, key: key, note: note) else { return }
        var lines = [line]
        if q.kind == .ladder, let step = lib.training.ladder.first(where: { $0.id == q.refID }) {
            let c = ladderCount(step.id) + 1
            if c >= step.repeats { lines.append("Ladder step conquered. Next step unlocked.") }
            else { lines.append("Ladder \(c)/\(step.repeats)") }
        }
        if q.kind == .penalty { lines.append("Penalty cleared. Discipline restored.") }
        if let bonus = dailyBonusLine(key) { lines.append(bonus) }
        finish(b, style: q.kind == .penalty ? .info : .quest, title: "[QUEST COMPLETE]", lines: lines)
    }

    /// Completes today's quests of `kind` whose ref matches, returning alert lines.
    private func autoComplete(_ kind: QuestKind, ref: String?) -> [String] {
        let key = DayKey.today
        guard let p = plan(key, create: false) else { return [] }
        var lines: [String] = []
        for q in p.quests where q.kind == kind && (ref == nil || q.refID == ref) {
            if let l = mark(q, key: key) { lines.append(l) }
        }
        if !lines.isEmpty, let bonus = dailyBonusLine(key) { lines.append(bonus) }
        return lines
    }

    struct LoggedSet {
        var exerciseID: String
        var setIndex: Int
        var reps: Int
        var weight: Double
    }

    func logWorkout(session: SessionTemplate, sets: [LoggedSet], cardioMinutes: Double,
                    distanceKm: Double, rpe: Int, notes: String) {
        let key = DayKey.today
        let b = begin()
        let pos = position(key)
        let w = WorkoutLog(dayKey: key, sessionID: session.id, sessionTitle: session.title,
                           week: pos.week, type: session.type)
        w.cardioMinutes = cardioMinutes
        w.cardioDistanceKm = distanceKm
        w.rpe = rpe
        w.zone2 = session.cardio?.zone2 ?? false
        w.notes = notes
        context.insert(w)
        for s in sets where s.reps > 0 {
            context.insert(SetLog(workoutID: w.uid, exerciseID: s.exerciseID, setIndex: s.setIndex,
                                  reps: s.reps, weight: s.weight))
        }
        var lines: [String] = []
        let done = sets.filter { $0.reps > 0 }.count
        if session.isStrength {
            let xp = 20 + 2 * done
            addXP(session.stat, xp, source: "workout", note: session.title)
            lines.append("\(session.title): \(done) sets  +\(xp) XP \(session.stat.rawValue)")
        }
        if cardioMinutes > 0 {
            let xp = 10 + Int(cardioMinutes / 3)
            addXP(.END, xp, source: "cardio", note: session.title)
            lines.append("\(Fmt.num(cardioMinutes)) min cardio  +\(xp) XP END")
        }
        if session.circuit != nil, !session.isStrength, cardioMinutes == 0 {
            addXP(.AGI, 20, source: "circuit", note: session.title)
            lines.append("Circuit cleared  +20 XP AGI")
        }
        let q = autoComplete(.session, ref: nil)
        finish(b, title: q.isEmpty ? "[SESSION LOGGED]" : "[QUEST COMPLETE]", lines: lines + q)
    }

    func logDrill(_ kind: DrillKind, score: Double, level: Int, detail: String) {
        let b = begin()
        context.insert(DrillResult(drill: kind, dayKey: DayKey.today, score: score, level: level, detail: detail))
        let xp = 8 + 2 * min(level, 10)
        addXP(.PER, xp, source: "drill", note: kind.title)
        var lines = ["\(kind.title): \(detail)  +\(xp) XP PER"]
        let q = autoComplete(.drill, ref: kind.rawValue)
        lines += q
        finish(b, title: q.isEmpty ? "[DRILL COMPLETE]" : "[QUEST COMPLETE]", lines: lines)
    }

    func drillLevel(_ k: DrillKind) -> Int { max(1, defaults.integer(forKey: DefaultsKey.drillLevel(k))) }
    func setDrillLevel(_ k: DrillKind, _ v: Int) { defaults.set(max(1, min(20, v)), forKey: DefaultsKey.drillLevel(k)) }

    func results(_ k: DrillKind) -> [DrillResult] {
        _ = revision
        return fetchAll(DrillResult.self).filter { $0.drill == k.rawValue }.sorted { $0.date < $1.date }
    }

    func lessonDone(_ id: String) -> Bool {
        _ = revision
        return completedLessonIDs().contains(id)
    }

    func completeLesson(game: Game, unit: LessonUnit, lesson: Lesson, quizCorrect: Int, quizTotal: Int, puzzlesSolved: Int) {
        let key = DayKey.today
        let b = begin()
        let lessonID = lesson.id
        var d = FetchDescriptor<LessonRecord>(predicate: #Predicate<LessonRecord> { $0.lessonID == lessonID })
        d.fetchLimit = 1
        var lines: [String] = []
        let discipline = game == .poker && ["disciplin", "tilt", "bankroll", "patience", "emotion", "mindset", "variance"]
            .contains { (unit.title + " " + lesson.title).lowercased().contains($0) }
        let stat: Stat = discipline ? .WIL : .INT
        if let existing = (try? context.fetch(d))?.first {
            existing.quizCorrect = max(existing.quizCorrect, quizCorrect)
            existing.puzzlesSolved = max(existing.puzzlesSolved, puzzlesSolved)
            addXP(stat, 5, source: "lesson-review", note: lesson.title)
            lines.append("Review: \(lesson.title)  +5 XP \(stat.rawValue)")
        } else {
            context.insert(LessonRecord(lessonID: lesson.id, game: game, dayKey: key, quizCorrect: quizCorrect,
                                        quizTotal: quizTotal, puzzlesSolved: puzzlesSolved))
            let xp = 15 + 3 * quizCorrect + 5 * puzzlesSolved
            addXP(stat, xp, source: "lesson", note: lesson.title)
            lines.append("\(lesson.title)  +\(xp) XP \(stat.rawValue)")
            lines.append("Quiz \(quizCorrect)/\(quizTotal)" + (puzzlesSolved > 0 ? " · \(puzzlesSolved) puzzle(s)" : ""))
        }
        let q = autoComplete(.lesson, ref: game.rawValue)
        finish(b, title: q.isEmpty ? "[LESSON COMPLETE]" : "[QUEST COMPLETE]", lines: lines + q)
    }

    func logCheckIn(sleep: Double, soreness: Int, mood: Int) {
        let key = DayKey.today
        let b = begin()
        var lines: [String] = []
        if let c = checkIn(key) {
            c.sleepHours = sleep
            c.soreness = soreness
            c.mood = mood
            lines.append("Status updated.")
        } else {
            context.insert(CheckIn(dayKey: key, sleepHours: sleep, soreness: soreness, mood: mood))
            addXP(.VIT, 5, source: "checkin", note: "Morning status")
            lines.append("Sleep \(Fmt.num(sleep)) h · Soreness \(soreness)/5 · Mood \(mood)/5  +5 XP VIT")
        }
        if sleep < 6 || soreness >= 4 {
            lines.append("Recovery flagged. Penalty load is halved today. Train smart.")
        }
        finish(b, style: .info, title: "[STATUS]", lines: lines)
    }

    func logAssessment(run1kSec: Int, pushups: Int, plankSec: Int, reactionMs: Int) {
        let b = begin()
        let prev = player.benchmarks
        context.insert(AssessmentRecord(dayKey: DayKey.today, run1kSec: run1kSec, pushups: pushups,
                                        plankSec: plankSec, reactionMs: reactionMs))
        addXP(.END, 30, source: "assessment", note: "1 km run")
        addXP(.STR, 30, source: "assessment", note: "Push-up max")
        addXP(.VIT, 20, source: "assessment", note: "Plank hold")
        addXP(.PER, 20, source: "assessment", note: "Reaction baseline")
        var lines = ["1 km \(Fmt.mmss(run1kSec)) · Push-ups \(pushups) · Plank \(Fmt.mmss(plankSec)) · Reaction \(reactionMs) ms",
                     "+100 XP across END STR VIT PER"]
        if let p = prev.run1kSec, run1kSec > 0, run1kSec < p { lines.append("New record: 1 km run (−\(p - run1kSec) s)") }
        if let p = prev.pushups, pushups > p { lines.append("New record: push-ups (+\(pushups - p))") }
        if let p = prev.plankSec, plankSec > p { lines.append("New record: plank (+\(plankSec - p) s)") }
        let q = autoComplete(.assessment, ref: nil)
        finish(b, title: q.isEmpty ? "[ASSESSMENT LOGGED]" : "[BOSS DEFEATED]", lines: lines + q)
    }

    // MARK: - Missed days and penalties

    func evaluateMissedDays() {
        let today = DayKey.today
        let last = defaults.string(forKey: DefaultsKey.lastEval) ?? DayKey.add(-1, to: startKey)
        var d = DayKey.add(1, to: last)
        var missed: [String] = []
        var n = 0
        while DayKey.daysBetween(d, today) > 0 && n < 90 {
            if DayKey.daysBetween(startKey, d) >= 0, let p = plan(d) {
                if !p.evaluated {
                    p.evaluated = true
                    if !position(d).isDeload && !dailiesComplete(p) {
                        p.missed = true
                        missed.append(d)
                    }
                }
            }
            d = DayKey.add(1, to: d)
            n += 1
        }
        defaults.set(DayKey.add(-1, to: today), forKey: DefaultsKey.lastEval)
        if let lastMissed = missed.last {
            issuePenalty(missedDay: lastMissed, count: missed.count)
        }
        save()
    }

    private func issuePenalty(missedDay: String, count: Int) {
        let today = DayKey.today
        guard !position(today).isDeload, let tp = plan(today) else { return }
        // Never stacks: one penalty quest at most, one deduction per issue.
        guard !tp.penaltyIssued else { return }
        let strained = (checkIn(missedDay)?.isStrained ?? false) || (checkIn(today)?.isStrained ?? false)
        var amount = strained ? QuestEngine.penaltyXP / 2 : QuestEngine.penaltyXP
        // Hard but safe: a penalty never costs a level.
        amount = min(amount, max(0, player.totalXP - Leveling.floor(of: player.level)))
        var qs = tp.quests
        qs.append(QuestEngine.penaltyQuest(day: today))
        tp.quests = qs
        tp.penaltyIssued = true
        tp.penaltyDeduction = amount
        tp.penaltyStrained = strained
        if amount > 0 {
            addXP(.WIL, -amount, source: "penalty", note: "Missed \(missedDay)", key: today)
        }
        var lines = [count > 1 ? "Daily Quests were not completed on \(count) days." :
                        "Daily Quest for \(DayKey.pretty(missedDay)) was not completed."]
        if amount > 0 { lines.append("−\(amount) XP WIL") }
        lines.append("A Penalty Quest has been added to today.")
        if strained { lines.append("Recovery flagged: penalty load halved.") }
        save()
        refresh()
        alerts.append(SystemAlert(style: .penalty, title: "[PENALTY]", lines: lines))
    }

    // MARK: - Weekly and monthly

    func weekKeys(_ key: String = DayKey.today) -> [String] {
        let pos = position(key)
        let first = DayKey.add(-pos.dayInWeek, to: key)
        return (0..<7).map { DayKey.add($0, to: first) }
    }

    func weeklyTargets(_ key: String = DayKey.today) -> [WeeklyTarget] {
        _ = revision
        let pos = position(key)
        let keys = Set(weekKeys(key))
        let workouts = fetchAll(WorkoutLog.self).filter { keys.contains($0.dayKey) }
        let comps = fetchAll(QuestCompletion.self).filter { keys.contains($0.dayKey) }
        let program = lib.training
        let strengthGoal = max(1, pos.phase?.schedule.compactMap { lib.session($0.session) }.filter(\.isStrength).count ?? 3)
        let z2Base = Double(pos.phase?.weeklyZone2Minutes ?? 60)
        let z2Goal = pos.isDeload ? (z2Base * program.deload.cardioFactor).rounded() : z2Base
        let drills = fetchAll(DrillResult.self).filter { keys.contains($0.dayKey) }.count
        let lessons = fetchAll(LessonRecord.self).filter { keys.contains($0.dayKey) }.count
        let social = comps.filter { $0.pillar == Pillar.social.rawValue }.count
        let sovereign = comps.filter { $0.pillar == Pillar.sovereign.rawValue }.count

        func t(_ id: String, _ title: String, _ stat: Stat, _ cur: Double, _ goal: Double, _ unit: String, _ xp: Int) -> WeeklyTarget {
            WeeklyTarget(id: id, title: title, stat: stat, current: cur, goal: goal, unit: unit, xp: xp,
                         claimed: claimed("w\(pos.week)-\(id)"))
        }
        var out = [
            t("strength", "Strength sessions", .STR, Double(workouts.filter { lib.session($0.sessionID)?.isStrength ?? false }.count), Double(strengthGoal), "sessions", 60),
            t("zone2", "Zone-2 minutes", .END, workouts.filter(\.zone2).reduce(0) { $0 + $1.cardioMinutes }, z2Goal, "min", 50),
            t("perception", "Perception sessions", .PER, Double(drills), 5, "sessions", 40),
        ]
        if !lib.availableGames.isEmpty {
            out.append(t("lessons", "Game lessons", .INT, Double(lessons), 3, "lessons", 40))
        }
        out.append(t("social", "Social challenges", .CHA, Double(social), 2, "done", 40))
        out.append(t("sovereign", "Sovereign acts", .SOV, Double(sovereign), 3, "done", 40))
        return out
    }

    func claimWeekly(_ target: WeeklyTarget) {
        guard target.done, !target.claimed else { return }
        let b = begin()
        context.insert(Claim(key: "w\(position(DayKey.today).week)-\(target.id)"))
        addXP(target.stat, target.xp, source: "weekly", note: target.title)
        finish(b, title: "[WEEKLY QUEST COMPLETE]", lines: ["\(target.title)  +\(target.xp) XP \(target.stat.rawValue)"])
    }

    static let dungeonNames = ["The Awakening Gate", "The Iron Crypt", "Tower of Trials", "The Red Gate"]

    func dungeon(_ key: String = DayKey.today) -> DungeonState {
        _ = revision
        let pos = position(key)
        let every = max(1, lib.training.deloadEvery)
        let first = DayKey.add((pos.block - 1) * every * 7, to: startKey)
        let last = DayKey.add(every * 7 - 1, to: first)
        let inBlock: (String) -> Bool = { $0 >= first && $0 <= last }
        let workouts = fetchAll(WorkoutLog.self).filter { inBlock($0.dayKey) }.count
        let drills = fetchAll(DrillResult.self).filter { inBlock($0.dayKey) }.count
        let lessons = fetchAll(LessonRecord.self).filter { inBlock($0.dayKey) }.count
        let comps = fetchAll(QuestCompletion.self).filter { inBlock($0.dayKey) }
        let socialSov = comps.filter { $0.pillar == Pillar.social.rawValue || $0.pillar == Pillar.sovereign.rawValue }.count
        let ladder = fetchAll(LadderRecord.self).filter { inBlock($0.dayKey) }.count
        let boss = fetchAll(AssessmentRecord.self).contains { inBlock($0.dayKey) }
        var steps = [
            DungeonStep(id: "train", title: "Clear 10 training sessions", current: workouts, goal: 10),
            DungeonStep(id: "perceive", title: "Complete 12 perception drills", current: drills, goal: 12),
        ]
        if !lib.availableGames.isEmpty {
            steps.append(DungeonStep(id: "study", title: "Finish 6 game lessons", current: lessons, goal: 6))
        }
        steps.append(DungeonStep(id: "world", title: "8 social or sovereign challenges", current: socialSov, goal: 8))
        if !lib.training.ladder.isEmpty {
            steps.append(DungeonStep(id: "ladder", title: "Climb the discomfort ladder 10 times", current: ladder, goal: 10))
        }
        return DungeonState(block: pos.block, title: Self.dungeonNames[(pos.block - 1) % Self.dungeonNames.count],
                            weekInBlock: pos.weekInBlock, firstKey: first, lastKey: last, steps: steps,
                            bossUnlocked: pos.weekInBlock == every, bossDone: boss,
                            claimed: claimed("dungeon-\(pos.block)"))
    }

    func claimDungeon(_ d: DungeonState) {
        guard d.cleared, !d.claimed else { return }
        let b = begin()
        context.insert(Claim(key: "dungeon-\(d.block)"))
        for s in [Stat.STR, .END, .PER, .WIL, .SOV] { addXP(s, 50, source: "dungeon", note: d.title) }
        finish(b, title: "[DUNGEON CLEARED]", lines: [d.title, "+250 XP across STR END PER WIL SOV", "Reward: the System acknowledges your growth."])
    }

    // MARK: - Training history

    func history(_ exerciseID: String) -> [ExerciseHistory] {
        let sets = fetchAll(SetLog.self).filter { $0.exerciseID == exerciseID }
        guard !sets.isEmpty else { return [] }
        let workouts = Dictionary(fetchAll(WorkoutLog.self).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        let grouped = Dictionary(grouping: sets, by: \.workoutID)
        return grouped.compactMap { (uid, s) -> ExerciseHistory? in
            guard let w = workouts[uid] else { return nil }
            return ExerciseHistory(date: w.date, deload: position(w.dayKey).isDeload, sets: s)
        }.sorted { $0.date > $1.date }
    }

    func targets(for session: SessionTemplate, on key: String) -> [ExerciseTarget] {
        _ = revision
        let deload = position(key).isDeload
        return session.exercises.enumerated().compactMap { i, p in
            TrainingEngine.target(for: p, index: i, history: history(p.exercise), deload: deload)
        }
    }

    func workouts() -> [WorkoutLog] {
        _ = revision
        return fetchAll(WorkoutLog.self).sorted { $0.date > $1.date }
    }

    func sets(for w: WorkoutLog) -> [SetLog] {
        let id = w.uid
        return fetchAll(SetLog.self).filter { $0.workoutID == id }.sorted { ($0.exerciseID, $0.setIndex) < ($1.exerciseID, $1.setIndex) }
    }

    func assessments() -> [AssessmentRecord] {
        _ = revision
        return fetchAll(AssessmentRecord.self).sorted { $0.date < $1.date }
    }

    func recentXP(_ n: Int = 40) -> [XPEvent] {
        _ = revision
        var d = FetchDescriptor<XPEvent>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = n
        return (try? context.fetch(d)) ?? []
    }

    /// XP earned per day for the last `days` days.
    func dailyXP(days: Int = 28) -> [(String, Int)] {
        _ = revision
        let today = DayKey.today
        let first = DayKey.add(-(days - 1), to: today)
        var sums: [String: Int] = [:]
        for e in fetchAll(XPEvent.self) where e.dayKey >= first { sums[e.dayKey, default: 0] += e.amount }
        return (0..<days).map { i in
            let k = DayKey.add(i, to: first)
            return (k, sums[k] ?? 0)
        }
    }

    private func computeStreaks() -> (Int, Int) {
        let plans = fetchAll(DayPlan.self)
        var byKey: [String: DayPlan] = [:]
        for p in plans { byKey[p.dayKey] = p }
        let today = DayKey.today
        func done(_ k: String) -> Bool { byKey[k].map { dailiesComplete($0) } ?? false }
        var cur = 0
        var k = done(today) ? today : DayKey.add(-1, to: today)
        while done(k) && cur < 2000 {
            cur += 1
            k = DayKey.add(-1, to: k)
        }
        var best = 0, run = 0
        for key in byKey.keys.sorted() {
            if done(key) { run += 1; best = max(best, run) } else { run = 0 }
        }
        return (cur, max(best, cur))
    }

    // MARK: - Reset

    func resetAll() {
        deleteAll(XPEvent.self); deleteAll(QuestCompletion.self); deleteAll(DayPlan.self)
        deleteAll(CheckIn.self); deleteAll(WorkoutLog.self); deleteAll(SetLog.self)
        deleteAll(DrillResult.self); deleteAll(LessonRecord.self); deleteAll(LadderRecord.self)
        deleteAll(AssessmentRecord.self); deleteAll(Claim.self)
        deleteAll(PokerDrillRecord.self); PokerDrill.resetLevels(defaults)
        save()
        for k in [DefaultsKey.start, DefaultsKey.lastEval] { defaults.removeObject(forKey: k) }
        for d in DrillKind.allCases { defaults.removeObject(forKey: DefaultsKey.drillLevel(d)) }
        let today = DayKey.today
        defaults.set(today, forKey: DefaultsKey.start)
        defaults.set(DayKey.add(-1, to: today), forKey: DefaultsKey.lastEval)
        startKey = today
        alerts = []
        refresh()
        tick()
        alerts.append(SystemAlert(style: .info, title: "[SYSTEM RESET]", lines: ["All records erased.", "Player re-awakened at Lv. 1."]))
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        try? context.delete(model: type)
    }
}
