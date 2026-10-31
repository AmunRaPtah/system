import Foundation
import SwiftData

extension DefaultsKey {
    static let eyePrecautions = "system.eyePrecautions"
    static let vows = "system.vows"
    static let customVow = "system.customVow"
}

/// Canon systems grounded in training science: the tiered Daily Quest, Fatigue,
/// the Shadow Army, Job, vows and the Detoxification skill.
extension SystemStore {

    // MARK: - Preparation to Become Powerful

    func preparationClears() -> Int {
        fetchAll(QuestCompletion.self).filter { $0.kind == QuestKind.preparation.rawValue }.count
    }

    var preparationTier: Int { PreparationLoad.tier(clears: preparationClears()) }

    /// Why today's body load is halved, or nil when it is not.
    func reducedReason(_ key: String = DayKey.today) -> String? {
        if position(key).isDeload { return "deload week" }
        if penaltyHalved(key) { return "poor sleep or soreness logged" }
        let f = fatigue(key)
        if f.high { return "fatigue \(f.value)/100" }
        return nil
    }

    func preparationDetail(_ q: Quest, on key: String) -> String {
        let tier = QuestEngine.tier(of: q)
        let reason = reducedReason(key)
        var load = PreparationLoad.at(tier: tier)
        if reason != nil { load = load.scaled(0.5) }
        return QuestEngine.preparationDetail(load, tier: tier, reduced: reason)
    }

    // MARK: - Precautions

    var eyePrecautions: Bool {
        _ = revision
        return defaults.bool(forKey: DefaultsKey.eyePrecautions)
    }

    func setEyePrecautions(_ on: Bool) {
        defaults.set(on, forKey: DefaultsKey.eyePrecautions)
        revision += 1
    }

    static let precautionNote = "Precautions: breathe out on every effort; never hold your breath or strain. "
        + "Keep your head above your heart and swap any head-down move for an upright one."

    // MARK: - Fatigue

    /// Sleep, soreness and mood from today's check-in, the Apple Health recovery
    /// flag, and session load (count and RPE) over the last three days.
    func fatigue(_ key: String = DayKey.today) -> Fatigue {
        _ = revision
        var v = 0
        var why: [String] = []
        if let c = checkIn(key) {
            if c.sleepHours < 5 { v += 35; why.append("sleep under 5 h") }
            else if c.sleepHours < 6 { v += 25; why.append("sleep under 6 h") }
            else if c.sleepHours < 7 { v += 10 }
            if c.soreness >= 4 { v += 25; why.append("soreness \(c.soreness)/5") }
            else if c.soreness == 3 { v += 10 }
            if c.mood <= 2 { v += 10; why.append("low mood") }
        }
        if healthStrained(key) { v += 20; why.append("Apple Health recovery flag") }
        let recent = Set((0..<3).map { DayKey.add(-$0, to: key) })
        let load = fetchAll(WorkoutLog.self).filter { recent.contains($0.dayKey) }
            .reduce(0) { $0 + 6 + max(0, $1.rpe - 6) * 4 }
        if load > 0 {
            v += min(30, load)
            if load >= 20 { why.append("hard training in the last 3 days") }
        }
        return Fatigue(value: min(100, v), reasons: why)
    }

    // MARK: - Job

    /// Canon: no Job until the Job Change at level 40. Here it also takes three
    /// extracted shadows, and the full army makes the Shadow Monarch.
    var job: String {
        let n = extractedShadowIDs().count
        guard player.level >= 40 else { return "None" }
        if n >= Shadow.all.count { return "Shadow Monarch" }
        if n >= 3 { return "Necromancer" }
        return "None"
    }

    var jobRequirement: String {
        "Job Change: Lv. 40 and 3 shadows (Lv. \(player.level), \(extractedShadowIDs().count) shadows)"
    }

    // MARK: - Shadow Army

    func shadowProgress() -> [String: Int] {
        _ = revision
        let workouts = fetchAll(WorkoutLog.self)
        var by: [ShadowMetric: Int] = [:]
        by[.preparation] = preparationClears()
        by[.strength] = workouts.filter { lib.session($0.sessionID)?.isStrength ?? false }.count
        by[.checkIns] = fetchAll(CheckIn.self).count
        by[.lessons] = fetchAll(LessonRecord.self).count
        by[.vowDays] = fetchAll(VowLog.self).filter { $0.judged && $0.kept }.count
        by[.dungeons] = fetchAll(Claim.self).filter { $0.key.hasPrefix("dungeon-") }.count
        by[.cardioKm] = Int(workouts.reduce(0) { $0 + $1.cardioDistanceKm })
        var out: [String: Int] = [:]
        for s in Shadow.all { out[s.id] = by[s.metric] ?? 0 }
        return out
    }

    func extractedShadowIDs() -> Set<String> {
        _ = revision
        return Set(fetchAll(Claim.self).map(\.key).filter { $0.hasPrefix("shadow-") }.map { String($0.dropFirst(7)) })
    }

    /// Extracts every shadow whose habit has crossed its threshold. Each one is
    /// announced once ("ARISE") and keyed by a `shadow-<id>` claim.
    func checkShadows() {
        let have = extractedShadowIDs()
        let progress = shadowProgress()
        let fresh = Shadow.all.filter { !have.contains($0.id) && (progress[$0.id] ?? 0) >= $0.threshold }
        if !fresh.isEmpty {
            let b = begin()
            for s in fresh {
                context.insert(Claim(key: "shadow-\(s.id)"))
                addXP(s.stat, Shadow.extractionXP, source: "shadow", note: "Arise: \(s.name)")
            }
            func lines(_ s: Shadow) -> [String] {
                ["\(s.name), \(s.epithet), has answered.",
                 s.lore,
                 "\(s.habit): \(progress[s.id] ?? 0) \(s.unit)",
                 "+\(Shadow.extractionXP) XP \(s.stat.rawValue)"]
            }
            for s in fresh.dropLast() {
                alerts.append(SystemAlert(style: .arise, title: "ARISE", lines: lines(s)))
            }
            if let last = fresh.last {
                finish(b, style: .arise, title: "ARISE", lines: lines(last))
            }
        }
        let j = job
        if j != "None", !claimed("job-\(j)") {
            context.insert(Claim(key: "job-\(j)"))
            save()
            alerts.append(SystemAlert(style: .arise, title: "[JOB CHANGE]",
                                      lines: ["Job acquired: \(j).",
                                              "The shadows you raised are the habits you kept."]))
            revision += 1
        }
    }

    // MARK: - Vows and Detoxification

    var activeVowIDs: [String] {
        _ = revision
        return defaults.stringArray(forKey: DefaultsKey.vows) ?? []
    }

    var customVowText: String {
        _ = revision
        return defaults.string(forKey: DefaultsKey.customVow) ?? ""
    }

    func setVow(_ id: String, active: Bool) {
        var ids = defaults.stringArray(forKey: DefaultsKey.vows) ?? []
        ids.removeAll { $0 == id }
        if active { ids.append(id) }
        defaults.set(ids, forKey: DefaultsKey.vows)
        revision += 1
    }

    func setCustomVow(_ text: String) {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        defaults.set(t, forKey: DefaultsKey.customVow)
        if t.isEmpty { setVow(VowPreset.custom, active: false) } else { revision += 1 }
    }

    func activeVows() -> [VowPreset] {
        activeVowIDs.compactMap { id in
            if id == VowPreset.custom {
                let t = customVowText
                return t.isEmpty ? nil : VowPreset(id: id, title: "My vow", detail: t, craving: true)
            }
            return VowPreset.presets.first { $0.id == id }
        }
    }

    func vowLog(_ vowID: String, on key: String = DayKey.today) -> VowLog? {
        _ = revision
        let k = key + "|" + vowID
        var d = FetchDescriptor<VowLog>(predicate: #Predicate<VowLog> { $0.key == k })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private func vowRow(_ vowID: String, on key: String) -> VowLog {
        if let r = vowLog(vowID, on: key) { return r }
        let r = VowLog(dayKey: key, vowID: vowID)
        context.insert(r)
        return r
    }

    func judgeVow(_ v: VowPreset, kept: Bool) {
        let key = DayKey.today
        let b = begin()
        let row = vowRow(v.id, on: key)
        row.judged = true
        row.kept = kept
        save()
        var lines: [String] = []
        let ck = "vow-\(key)-\(v.id)"
        if kept {
            if !claimed(ck) {
                context.insert(Claim(key: ck))
                addXP(.WIL, 10, source: "vow", note: v.title)
                lines.append("Vow kept: \(v.title)  +10 XP WIL")
            } else {
                lines.append("Vow kept: \(v.title)")
            }
            let s = vowStreak(v.id)
            lines.append("Streak \(s.current) day\(s.current == 1 ? "" : "s") · Detoxification Lv. \(detoxification().level)")
        } else {
            lines.append("Vow slipped: \(v.title).")
            lines.append("A slip is data, not a verdict. Skills, once learned, are not lost: Detoxification stays at Lv. \(detoxification().level).")
            lines.append("The streak restarts tomorrow. Never miss twice.")
        }
        finish(b, style: kept ? .quest : .info, title: "[VOW]", lines: lines)
    }

    func resistCraving(_ v: VowPreset) {
        let b = begin()
        let row = vowRow(v.id, on: DayKey.today)
        row.cravingsResisted += 1
        var first = "Craving resisted (\(row.cravingsResisted) today)."
        if row.cravingsResisted <= 5 {
            addXP(.WIL, 3, source: "craving", note: v.title)
            first += "  +3 XP WIL"
        }
        finish(b, style: .quest, title: "[CRAVING RESISTED]",
               lines: [first, "A craving rises, peaks and passes. Drink water, move, wait it out."])
    }

    func vowStreak(_ vowID: String) -> (current: Int, best: Int) {
        _ = revision
        let kept = Set(fetchAll(VowLog.self).filter { $0.vowID == vowID && $0.judged && $0.kept }.map(\.dayKey))
        let today = DayKey.today
        var cur = 0
        var k = kept.contains(today) ? today : DayKey.add(-1, to: today)
        while kept.contains(k) && cur < 5000 {
            cur += 1
            k = DayKey.add(-1, to: k)
        }
        var best = 0, run = 0
        var prev: String?
        for d in kept.sorted() {
            run = (prev.map { DayKey.add(1, to: $0) == d } ?? false) ? run + 1 : 1
            best = max(best, run)
            prev = d
        }
        return (cur, max(best, cur))
    }

    /// The skill level comes from the best streak on any vow, ever held.
    func detoxification() -> (level: Int, best: Int) {
        let ids = Set(fetchAll(VowLog.self).map(\.vowID))
        let best = ids.map { vowStreak($0).best }.max() ?? 0
        return (Detoxification.level(bestStreak: best), best)
    }

    // MARK: - Hidden quest: Courage of the Weak

    /// Days the Daily Quest was cleared straight after two or more missed days.
    func comebackCount() -> Int {
        let missed = Set(fetchAll(DayPlan.self).filter(\.missed).map(\.dayKey))
        return fetchAll(Claim.self).map(\.key).filter { $0.hasPrefix("daily-") }.filter { k in
            let day = String(k.dropFirst(6))
            return missed.contains(DayKey.add(-1, to: day)) && missed.contains(DayKey.add(-2, to: day))
        }.count
    }

    func isComebackDay(_ key: String) -> Bool {
        (plan(DayKey.add(-1, to: key), create: false)?.missed ?? false)
            && (plan(DayKey.add(-2, to: key), create: false)?.missed ?? false)
    }
}
