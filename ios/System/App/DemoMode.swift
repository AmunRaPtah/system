import Foundation
import SwiftData

/// Launch arguments for CI screenshots: `-demo` runs on an in-memory store seeded
/// with a mid-game player, `-tab N` opens a tab, `-screen shadows` pushes a
/// screen and `-alert` shows an ARISE notification. Never used in normal launches.
enum DemoMode {
    static let args = ProcessInfo.processInfo.arguments
    static let isOn = args.contains("-demo")

    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var tab: Int { Int(value("-tab") ?? "") ?? 0 }
    static var screen: String? { value("-screen") }
    static var showAlert: Bool { args.contains("-alert") }

    /// Runs before the store reads its start key, so the programme is mid-way.
    static func prepareDefaults() {
        let d = UserDefaults.standard
        d.set(DayKey.add(-40, to: DayKey.today), forKey: DefaultsKey.start)
        d.set(DayKey.add(-1, to: DayKey.today), forKey: DefaultsKey.lastEval)
        d.set(true, forKey: "system.awakened")
        d.set(true, forKey: "system.askedPermission")
        d.set(["smoke-free", "sleep-anchor"], forKey: "system.vows")
    }
}

extension SystemStore {
    func seedDemo() {
        let today = DayKey.today
        let stats = Stat.allCases
        let strength = lib.training.sessions.first { $0.isStrength }
        for i in 1...40 {
            let k = DayKey.add(-i, to: today)
            for (j, s) in stats.enumerated() where (i + j) % 3 != 0 {
                addXP(s, 30 + (i * 7 + j * 11) % 50, source: "quest", note: "Demo", key: k)
            }
            if i <= 36 {
                context.insert(QuestCompletion(questID: "\(k)-prep", dayKey: k, kind: QuestKind.preparation.rawValue,
                                               pillar: Pillar.body.rawValue, stat: Stat.STR.rawValue))
            }
            if i <= 12 { context.insert(Claim(key: "daily-\(k)")) }
            if i <= 32 { context.insert(CheckIn(dayKey: k, sleepHours: 7.5, soreness: 2, mood: 2 + (i * 5) % 4)) }
            if i <= 24, i % 4 != 0 {
                context.insert(MindLog(dayKey: k, practice: MindPractice.forDay(i), minutes: 10, entries: []))
            }
            if let s = strength, i % 3 == 0 {
                let w = WorkoutLog(dayKey: k, sessionID: s.id, sessionTitle: s.title, week: 1, type: "strength")
                w.rpe = 7
                w.cardioDistanceKm = 3
                context.insert(w)
            }
            if i <= 18 {
                let v = VowLog(dayKey: k, vowID: "smoke-free")
                v.judged = true
                v.kept = true
                context.insert(v)
            }
        }
        context.insert(CheckIn(dayKey: today, sleepHours: 6.5, soreness: 3, mood: DemoMode.screen == "support" ? 1 : 3))
        seedDemoCampaigns(today)
        _ = plan(today)
        save()
        refresh()
        checkAchievements()
        checkShadows()
        alerts.removeAll()
        if DemoMode.showAlert, let igris = Shadow.all.first {
            alerts.append(SystemAlert(style: .arise, title: "[SWORN IN]",
                                      lines: ["\(igris.name), \(igris.epithet), has been sworn in.", igris.lore,
                                              "+\(Shadow.extractionXP) XP \(igris.stat.rawValue)"]))
        }
    }
}

extension SystemStore {
    /// Sample campaigns for screenshots only; real installs start empty.
    func seedDemoCampaigns(_ today: String) {
        let specs: [(String, String, [(String, Int, Bool)], Int)] = [
            ("Ship the novel", "Finished draft to the editor", [("Draft act two", -6, true), ("Full draft", 12, false)], 1),
            ("Postdoc applications", "Two strong applications out", [("Research statement", 9, false)], 3),
            ("Strength base", "Squat bodyweight for 5", [("Assessment day", 20, false)], 2),
            ("Kitchen rebuild", "", [("Order cabinets", 30, false)], 40),
        ]
        for (title, goal, gates, idle) in specs {
            let c = Campaign(title: title, goal: goal)
            c.created = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
            context.insert(c)
            for (g, offset, done) in gates {
                let gate = CampaignGate(campaignID: c.uid, title: g, dateKey: DayKey.add(offset, to: today))
                gate.done = done
                if done { gate.doneDate = Calendar.current.date(byAdding: .day, value: -idle, to: .now) }
                context.insert(gate)
            }
            let q = OwnerQuest(title: "Move \(title.lowercased())", domain: .ambition, campaignID: c.uid, dayKey: DayKey.add(-idle, to: today))
            q.done = true
            q.doneKey = q.dayKey
            q.doneDate = Calendar.current.date(byAdding: .day, value: -idle, to: .now)
            context.insert(q)
        }
        context.insert(OwnerQuest(title: "Write 800 words", domain: .ambition, dayKey: today))
        context.insert(OwnerQuest(title: "Call Mum", domain: .bonds, dayKey: today))
        context.insert(OwnerQuest(title: "Pay the invoice", domain: .wealth, dayKey: today))
        context.insert(DayGate(dayKey: today, kind: .morning, energy: 4, line: "One clean page before noon."))
    }
}
