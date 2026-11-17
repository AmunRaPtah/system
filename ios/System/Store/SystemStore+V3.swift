import Foundation
import SwiftData

/// v3: campaigns, owner-written quests, daily gates and disuse detection.
/// Nothing here generates quests: every OwnerQuest is typed by the owner.
extension SystemStore {

    enum V3Key {
        static let firstSeen = "v3.firstSeen"
        static let chooseThreeWeek = "v3.chooseThreeWeek"
    }

    /// Days without a completed gate before Today collapses to one-tap mode.
    static let disuseDays = 3
    /// A campaign that has not moved for this many days is faded in the War Room.
    static let staleDays = 14
    static let ownerQuestXP = 20

    // MARK: - Campaigns

    func campaigns() -> [Campaign] {
        _ = revision
        return fetchAll(Campaign.self).sorted { a, b in
            if a.state != b.state { return order(a.state) < order(b.state) }
            return a.created < b.created
        }
    }

    private func order(_ s: CampaignStatus) -> Int {
        switch s { case .active: return 0; case .paused: return 1; case .done: return 2 }
    }

    func campaign(_ uid: String) -> Campaign? {
        guard !uid.isEmpty else { return nil }
        return fetchAll(Campaign.self).first { $0.uid == uid }
    }

    @discardableResult
    func addCampaign(title: String, goal: String) -> Campaign? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let c = Campaign(title: t, goal: goal.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(c)
        commitV3()
        return c
    }

    func setStatus(_ c: Campaign, _ s: CampaignStatus) {
        c.status = s.rawValue
        commitV3()
    }

    func deleteCampaign(_ c: Campaign) {
        let id = c.uid
        for g in fetchAll(CampaignGate.self) where g.campaignID == id { context.delete(g) }
        for q in fetchAll(OwnerQuest.self) where q.campaignID == id {
            q.campaignID = ""
            q.gateID = ""
        }
        context.delete(c)
        commitV3()
    }

    // MARK: - Campaign gates

    func gates(of campaignID: String) -> [CampaignGate] {
        _ = revision
        return fetchAll(CampaignGate.self).filter { $0.campaignID == campaignID }.sorted { $0.dateKey < $1.dateKey }
    }

    func nextGate(of campaignID: String) -> CampaignGate? {
        gates(of: campaignID).first { !$0.done }
    }

    @discardableResult
    func addGate(to campaignID: String, title: String, dateKey: String, sourceID: String = "", source: String = "") -> CampaignGate? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !campaignID.isEmpty else { return nil }
        let g = CampaignGate(campaignID: campaignID, title: t, dateKey: dateKey, sourceID: sourceID, source: source)
        context.insert(g)
        commitV3()
        return g
    }

    /// Suggestion ids already accepted, so the sheet can mark them.
    func acceptedSuggestionIDs() -> Set<String> {
        _ = revision
        return Set(fetchAll(CampaignGate.self).map(\.sourceID).filter { !$0.isEmpty })
    }

    func toggleGate(_ g: CampaignGate) {
        g.done.toggle()
        g.doneDate = g.done ? .now : nil
        commitV3()
    }

    func deleteGate(_ g: CampaignGate) {
        let id = g.uid
        for q in fetchAll(OwnerQuest.self) where q.gateID == id { q.gateID = "" }
        context.delete(g)
        commitV3()
    }

    // MARK: - Owner quests

    func ownerQuests(on key: String) -> [OwnerQuest] {
        _ = revision
        return fetchAll(OwnerQuest.self).filter { $0.dayKey == key }.sorted { $0.created < $1.created }
    }

    func backlog() -> [OwnerQuest] {
        _ = revision
        return fetchAll(OwnerQuest.self).filter { $0.dayKey.isEmpty && !$0.done }.sorted { $0.created < $1.created }
    }

    func ownerQuests(campaign id: String) -> [OwnerQuest] {
        _ = revision
        return fetchAll(OwnerQuest.self).filter { $0.campaignID == id }.sorted { $0.created < $1.created }
    }

    func ambitionCount(on key: String, excluding uid: String = "") -> Int {
        fetchAll(OwnerQuest.self).filter { $0.dayKey == key && $0.dom == .ambition && $0.uid != uid }.count
    }

    /// True when one more Ambition quest still fits on `key`.
    func ambitionRoom(on key: String, excluding uid: String = "") -> Bool {
        ambitionCount(on: key, excluding: uid) < Domain.ambitionCap
    }

    enum QuestAddResult { case added, backlogged, empty }

    /// Adds an owner-written quest. An Ambition quest that would exceed the daily
    /// cap goes to the backlog instead of today.
    @discardableResult
    func addOwnerQuest(title: String, domain: Domain, dayKey: String, campaignID: String = "", gateID: String = "") -> QuestAddResult {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .empty }
        var day = dayKey
        var result = QuestAddResult.added
        if !day.isEmpty, domain == .ambition, !ambitionRoom(on: day) {
            day = ""
            result = .backlogged
        }
        context.insert(OwnerQuest(title: t, domain: domain, campaignID: campaignID, gateID: gateID, dayKey: day))
        commitV3()
        return result
    }

    /// Schedules a quest for `key`. Returns false when the Ambition cap blocks it.
    @discardableResult
    func schedule(_ q: OwnerQuest, on key: String) -> Bool {
        if !key.isEmpty, q.dom == .ambition, !ambitionRoom(on: key, excluding: q.uid) { return false }
        q.dayKey = key
        commitV3()
        return true
    }

    func setOwnerQuest(_ q: OwnerQuest, done: Bool) {
        guard q.done != done else { return }
        q.done = done
        q.doneKey = done ? DayKey.today : ""
        q.doneDate = done ? .now : nil
        // XP once per quest, never taken back, so toggling cannot farm it.
        let claim = "owner-\(q.uid)"
        if done, !claimed(claim) {
            context.insert(Claim(key: claim))
            addXP(Self.stat(for: q.dom), Self.ownerQuestXP, source: "owner", note: q.title)
        }
        commitV3()
    }

    func deleteOwnerQuest(_ q: OwnerQuest) {
        context.delete(q)
        commitV3()
    }

    /// Domain → stat for XP. Ambition, Wealth and Ground feed Sovereignty, the overall rank.
    static func stat(for d: Domain) -> Stat {
        switch d {
        case .body: return .VIT
        case .mind: return .WIL
        case .bonds: return .CHA
        case .ambition, .wealth, .ground: return .SOV
        }
    }

    // MARK: - Daily gates

    func dayGate(_ key: String, _ kind: DayGateKind) -> DayGate? {
        _ = revision
        let k = kind.rawValue
        return fetchAll(DayGate.self).first { $0.dayKey == key && $0.kind == k }
    }

    /// Morning: energy, one line, and the quests accepted for today. Unaccepted
    /// owner quests on today return to the backlog.
    func completeMorningGate(energy: Int, intention: String, accepted: Set<String>) {
        let key = DayKey.today
        let open = fetchAll(OwnerQuest.self).filter { !$0.done }
        // Release first so the Ambition cap counts only what stays on today.
        for q in open where q.dayKey == key && !accepted.contains(q.uid) { q.dayKey = "" }
        for q in open where accepted.contains(q.uid) && q.dayKey != key { _ = scheduleNoCommit(q, key) }
        let total = ownerQuests(on: key).count
        upsertGate(key, .morning, energy: energy, line: intention, done: 0, total: total)
        commitV3()
        alerts.append(SystemAlert(style: .info, title: "[MORNING GATE]",
                                  lines: ["Energy \(energy)/5 · \(total) quest\(total == 1 ? "" : "s") accepted.",
                                          intention.isEmpty ? "The day is open." : "“\(intention)”"]))
        ArchitectClient.shared.syncSoon(self)
    }

    private func scheduleNoCommit(_ q: OwnerQuest, _ key: String) -> Bool {
        if q.dom == .ambition, !ambitionRoom(on: key, excluding: q.uid) { return false }
        q.dayKey = key
        return true
    }

    /// Evening: what got done, and one line. Done flags are set by the caller
    /// through `setOwnerQuest` / `complete`; this records the gate itself.
    func completeEveningGate(line: String) {
        let key = DayKey.today
        let owner = ownerQuests(on: key)
        let sys = quests(key).filter { $0.kind != .penalty }
        let done = owner.filter(\.done).count + sys.filter { isDone($0, on: key) }.count
        let total = owner.count + sys.count
        upsertGate(key, .evening, energy: 0, line: line, done: done, total: total)
        commitV3()
        alerts.append(SystemAlert(style: .info, title: "[EVENING GATE]",
                                  lines: ["\(done)/\(total) quests done.", line.isEmpty ? "Rest. Tomorrow opens at dawn." : "“\(line)”"]))
        ArchitectClient.shared.syncSoon(self)
    }

    /// One tap from collapsed mode: presence counts as a gate and lifts the collapse.
    func imHere() {
        upsertGate(DayKey.today, .here, energy: 0, line: "", done: 0, total: 0)
        commitV3()
        ArchitectClient.shared.syncSoon(self)
    }

    private func upsertGate(_ key: String, _ kind: DayGateKind, energy: Int, line: String, done: Int, total: Int) {
        let trimmed = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        if let g = dayGate(key, kind) {
            g.energy = energy
            g.line = trimmed
            g.questsDone = done
            g.questsTotal = total
            g.date = .now
        } else {
            context.insert(DayGate(dayKey: key, kind: kind, energy: energy, line: trimmed, questsDone: done, questsTotal: total))
        }
    }

    // MARK: - Disuse

    /// Day key of the last completed gate, or the day v3 was first opened.
    func lastPresenceKey() -> String {
        _ = revision
        if defaults.string(forKey: V3Key.firstSeen) == nil {
            defaults.set(DayKey.today, forKey: V3Key.firstSeen)
        }
        let first = defaults.string(forKey: V3Key.firstSeen) ?? DayKey.today
        let last = fetchAll(DayGate.self).map(\.dayKey).max() ?? ""
        return max(first, last)
    }

    /// No gate for `disuseDays` days: Today shows only "I'm here" and one quest.
    var isCollapsed: Bool {
        DayKey.daysBetween(lastPresenceKey(), DayKey.today) >= Self.disuseDays
    }

    /// The single quest offered in collapsed mode: first open owner quest today,
    /// else the first open system daily.
    enum TopQuest { case owner(OwnerQuest), system(Quest) }

    func topQuest() -> TopQuest? {
        let key = DayKey.today
        if let q = ownerQuests(on: key).first(where: { !$0.done }) { return .owner(q) }
        if let q = quests(key).first(where: { $0.kind != .penalty && !isDone($0, on: key) }) { return .system(q) }
        return nil
    }

    // MARK: - War Room

    struct WarRoomRow: Identifiable {
        var campaign: Campaign
        var next: CampaignGate?
        var daysLeft: Int?
        var movedThisWeek: Bool
        var stale: Bool
        var id: String { campaign.uid }
    }

    /// Last day anything in the campaign moved: a quest or gate done, or creation.
    func lastMoved(_ c: Campaign) -> Date {
        var d = c.created
        for g in gates(of: c.uid) { if let x = g.doneDate, x > d { d = x } }
        for q in ownerQuests(campaign: c.uid) { if let x = q.doneDate, x > d { d = x } }
        return d
    }

    func warRoom() -> [WarRoomRow] {
        let today = DayKey.today
        let now = Date.now
        return campaigns().filter { $0.state != .done }.map { c in
            let next = nextGate(of: c.uid)
            let moved = lastMoved(c)
            let age = Calendar.current.dateComponents([.day], from: moved, to: now).day ?? 0
            return WarRoomRow(campaign: c, next: next,
                              daysLeft: next.map { DayKey.daysBetween(today, $0.dateKey) },
                              movedThisWeek: age < 7 && moved > c.created.addingTimeInterval(1),
                              stale: c.state == .paused || age >= Self.staleDays)
        }
    }

    // MARK: - Choose three

    /// Monday of the calendar week containing `key`.
    static func mondayKey(_ key: String = DayKey.today) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let d = DayKey.date(key)
        let start = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        return DayKey.key(start)
    }

    var isSunday: Bool { Calendar.current.component(.weekday, from: .now) == 1 }

    /// Sunday and this week's three not yet chosen.
    var chooseThreeDue: Bool {
        _ = revision
        guard isSunday else { return false }
        let next = Self.mondayKey(DayKey.add(1, to: DayKey.today))
        return defaults.string(forKey: V3Key.chooseThreeWeek) != next
            && campaigns().contains { $0.state != .done }
    }

    /// Keeps up to three campaigns active; every other open campaign is paused.
    func chooseThree(_ uids: Set<String>) {
        let picked = Set(uids.prefix(3))
        // Chosen on Sunday counts for the coming week.
        let week = Self.mondayKey(isSunday ? DayKey.add(1, to: DayKey.today) : DayKey.today)
        for c in fetchAll(Campaign.self) where c.state != .done {
            if picked.contains(c.uid) {
                c.status = CampaignStatus.active.rawValue
                c.chosenWeek = week
            } else {
                c.status = CampaignStatus.paused.rawValue
            }
        }
        defaults.set(week, forKey: V3Key.chooseThreeWeek)
        commitV3()
    }

    // MARK: - Snapshot for architect

    func v3Snapshot() -> [String: Any] {
        let today = DayKey.today
        let cs = fetchAll(Campaign.self)
        let titles = Dictionary(cs.map { ($0.uid, $0.title) }, uniquingKeysWith: { a, _ in a })
        let iso = ISO8601DateFormatter()
        var qs: [[String: Any]] = fetchAll(OwnerQuest.self)
            .filter { !$0.dayKey.isEmpty || !$0.done }
            .map { q -> [String: Any] in
                ["id": q.uid, "title": q.title, "domain": q.domain, "dayKey": q.dayKey,
                 "done": q.done, "doneKey": q.doneKey, "campaignID": q.campaignID,
                 "campaignTitle": titles[q.campaignID] ?? "", "source": "owner"]
            }
        for q in self.quests(today) where q.kind != .penalty {
            qs.append(["id": "sys-\(today)-\(q.id)", "title": q.title,
                           "domain": (Domain.from(q.pillar) ?? .ground).rawValue,
                           "dayKey": today, "done": isDone(q, on: today), "source": "discipline"])
        }
        let gates: [[String: Any]] = fetchAll(CampaignGate.self).map { g -> [String: Any] in
            ["id": g.uid, "title": g.title, "date": g.dateKey, "done": g.done,
             "campaignID": g.campaignID, "campaignTitle": titles[g.campaignID] ?? "",
             "sourceID": g.sourceID]
        }
        let since = DayKey.add(-30, to: today)
        let checkins: [[String: Any]] = fetchAll(DayGate.self).filter { $0.dayKey >= since }.map { d -> [String: Any] in
            ["dayKey": d.dayKey, "kind": d.kind, "energy": d.energy, "line": d.line,
             "questsDone": d.questsDone, "questsTotal": d.questsTotal, "at": iso.string(from: d.date)]
        }
        let p = player
        return [
            "schema": 1,
            "sentAt": iso.string(from: .now),
            "today": today,
            "player": ["level": p.level, "rank": p.rank.letter, "streak": p.streak,
                       "fatigue": fatigue(today).value, "collapsed": isCollapsed,
                       "lastPresence": lastPresenceKey()] as [String: Any],
            "campaigns": cs.map { c -> [String: Any] in
                ["id": c.uid, "title": c.title, "goal": c.goal, "status": c.status,
                 "chosenWeek": c.chosenWeek, "created": iso.string(from: c.created)]
            },
            "gates": gates,
            "quests": qs,
            "checkins": checkins,
        ]
    }

    // MARK: -

    func commitV3() {
        save()
        refresh()
    }
}
