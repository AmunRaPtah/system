import Foundation
import SwiftData

extension DefaultsKey {
    static let awakened = "system.awakened"
    static let playerName = "system.playerName"
    static let equippedTitle = "system.equippedTitle"
    static let achievementsSeeded = "system.achievementsSeeded"
}

/// Awakening onboarding, player identity, achievements and titles.
extension SystemStore {

    // MARK: - Awakening

    var isAwakened: Bool { defaults.bool(forKey: DefaultsKey.awakened) }

    /// True only on a fresh install. Installs that already hold data are marked
    /// awakened here so they never see the first-launch sequence.
    func needsAwakening() -> Bool {
        if isAwakened { return false }
        let hasData = hasAny(XPEvent.self) || hasAny(QuestCompletion.self) || hasAny(WorkoutLog.self)
            || hasAny(AssessmentRecord.self) || hasAny(DrillResult.self) || hasAny(LessonRecord.self)
        if hasData {
            defaults.set(true, forKey: DefaultsKey.awakened)
            return false
        }
        return true
    }

    func completeAwakening() {
        defaults.set(true, forKey: DefaultsKey.awakened)
        revision += 1
        checkAchievements()
    }

    var playerName: String {
        _ = revision
        return defaults.string(forKey: DefaultsKey.playerName) ?? ""
    }

    var displayName: String {
        let n = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "PLAYER" : n.uppercased()
    }

    func setPlayerName(_ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        defaults.set(n, forKey: DefaultsKey.playerName)
        revision += 1
    }

    // MARK: - Titles

    var equippedTitle: PlayerTitle? {
        _ = revision
        guard let id = defaults.string(forKey: DefaultsKey.equippedTitle),
              let a = AchievementCatalog.find(id), a.title != nil, isUnlocked(id) else { return nil }
        return a.title
    }

    var equippedTitleID: String? {
        _ = revision
        return defaults.string(forKey: DefaultsKey.equippedTitle)
    }

    /// Pass nil to unequip.
    func equipTitle(_ achievementID: String?) {
        if let id = achievementID {
            guard AchievementCatalog.find(id)?.title != nil, isUnlocked(id) else { return }
            defaults.set(id, forKey: DefaultsKey.equippedTitle)
        } else {
            defaults.removeObject(forKey: DefaultsKey.equippedTitle)
        }
        revision += 1
    }

    /// Stat points the equipped title adds to the status window.
    func titleBonus(_ s: Stat) -> Int {
        guard let t = equippedTitle, t.stat == s else { return 0 }
        return t.bonus
    }

    // MARK: - Achievements

    func unlockedAchievements() -> [String: Date] {
        _ = revision
        var out: [String: Date] = [:]
        for u in fetchAll(AchievementUnlock.self) { out[u.achievementID] = u.date }
        return out
    }

    func isUnlocked(_ id: String) -> Bool {
        var d = FetchDescriptor<AchievementUnlock>(predicate: #Predicate<AchievementUnlock> { $0.achievementID == id })
        d.fetchLimit = 1
        return ((try? context.fetch(d))?.first) != nil
    }

    /// Current value of every metric, computed from stored records.
    func achievementMetrics() -> [AchievementMetric: Int] {
        _ = revision
        var m: [AchievementMetric: Int] = [:]
        let p = player
        m[.awakened] = isAwakened ? 1 : 0
        m[.level] = p.level
        m[.rank] = p.rank.rawValue
        m[.bestStreak] = p.bestStreak

        let claims = fetchAll(Claim.self).map(\.key)
        m[.dailyClears] = claims.filter { $0.hasPrefix("daily-") }.count
        m[.dungeons] = claims.filter { $0.hasPrefix("dungeon-") }.count
        m[.weeklyClaims] = claims.filter { k in
            k.hasPrefix("w") && k.dropFirst().first?.isNumber == true
        }.count

        let comps = fetchAll(QuestCompletion.self)
        m[.penaltiesCleared] = comps.filter { $0.kind == QuestKind.penalty.rawValue }.count
        m[.socialDone] = comps.filter { $0.pillar == Pillar.social.rawValue }.count
        m[.sovereignDone] = comps.filter { $0.pillar == Pillar.sovereign.rawValue }.count

        let workouts = fetchAll(WorkoutLog.self)
        m[.workouts] = workouts.count
        m[.cardioMinutes] = Int(workouts.reduce(0) { $0 + $1.cardioMinutes })
        m[.assessments] = fetchAll(AssessmentRecord.self).count
        m[.checkIns] = fetchAll(CheckIn.self).count
        m[.ladder] = fetchAll(LadderRecord.self).count
        let bm = p.benchmarks
        if let v = bm.pushups { m[.pushups] = v }
        if let v = bm.plankSec { m[.plankSec] = v }
        if let v = bm.run1kSec { m[.run1kSec] = v }
        if let v = bm.reactionMs { m[.reactionMs] = v }

        let drills = fetchAll(DrillResult.self)
        m[.drills] = drills.count
        m[.drillLevel] = drills.map(\.level).max() ?? 0

        let lessons = fetchAll(LessonRecord.self)
        m[.lessons] = lessons.count
        m[.chessLessons] = lessons.filter { $0.game == Game.chess.rawValue }.count
        m[.goLessons] = lessons.filter { $0.game == Game.go.rawValue }.count
        m[.pokerLessons] = lessons.filter { $0.game == Game.poker.rawValue }.count
        m[.puzzles] = lessons.reduce(0) { $0 + $1.puzzlesSolved }
        m[.perfectQuizzes] = lessons.filter { $0.quizTotal > 0 && $0.quizCorrect >= $0.quizTotal }.count

        let prep = comps.filter { $0.kind == QuestKind.preparation.rawValue }.count
        m[.preparation] = prep
        m[.preparationTier] = PreparationLoad.tier(clears: prep)
        m[.comebacks] = comebackCount()
        m[.shadows] = claims.filter { $0.hasPrefix("shadow-") }.count
        m[.vowDays] = fetchAll(VowLog.self).filter { $0.judged && $0.kept }.count
        return m
    }

    /// Unlocks anything newly met and queues one alert per unlock. The very first
    /// check on an install that already has history unlocks silently and posts a
    /// single summary, so an update does not bury the player in alerts.
    func checkAchievements() {
        let metrics = achievementMetrics()
        let have = Set(fetchAll(AchievementUnlock.self).map(\.achievementID))
        let fresh = AchievementCatalog.all.filter { !have.contains($0.id) && $0.met(metrics[$0.metric]) }
        let seeded = defaults.bool(forKey: DefaultsKey.achievementsSeeded)
        defaults.set(true, forKey: DefaultsKey.achievementsSeeded)
        guard !fresh.isEmpty else { return }
        for a in fresh { context.insert(AchievementUnlock(achievementID: a.id)) }
        save()

        var autoEquipped: PlayerTitle?
        if defaults.string(forKey: DefaultsKey.equippedTitle) == nil, let first = fresh.first(where: { $0.title != nil }) {
            defaults.set(first.id, forKey: DefaultsKey.equippedTitle)
            autoEquipped = first.title
        }
        revision += 1

        if !seeded {
            var lines = ["The System has reviewed your records.",
                         "\(fresh.count) achievement\(fresh.count == 1 ? "" : "s") recognised."]
            let titles = fresh.compactMap(\.title)
            if !titles.isEmpty { lines.append("Titles: " + titles.map(\.name).joined(separator: ", ")) }
            if let t = autoEquipped { lines.append("Equipped: \(t.name) (\(t.bonusLabel))") }
            alerts.append(SystemAlert(style: .achievement, title: "[ACHIEVEMENTS]", lines: lines))
            return
        }
        if fresh.count > 3 {
            var lines = fresh.map { "◆ \($0.name)" }
            if let t = autoEquipped { lines.append("Title equipped: \(t.name) (\(t.bonusLabel))") }
            alerts.append(SystemAlert(style: .achievement, title: "[ACHIEVEMENTS]", lines: lines))
            return
        }
        for a in fresh {
            var lines = [a.name, a.detail]
            if let t = a.title {
                lines.append("Title acquired: \(t.name)  \(t.bonusLabel) while equipped")
                if autoEquipped == t { lines.append("Title equipped.") }
            }
            alerts.append(SystemAlert(style: .achievement,
                                      title: a.title == nil ? "[ACHIEVEMENT]" : "[TITLE ACQUIRED]",
                                      lines: lines))
        }
    }

    /// Part of a full reset: achievements and the equipped title go with the records.
    func resetAchievements() {
        try? context.delete(model: AchievementUnlock.self)
        defaults.removeObject(forKey: DefaultsKey.equippedTitle)
        // Unlocks after a reset are earned live, so announce them one by one.
        defaults.set(true, forKey: DefaultsKey.achievementsSeeded)
    }

    private func hasAny<T: PersistentModel>(_ type: T.Type) -> Bool {
        var d = FetchDescriptor<T>()
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }
}
