import Foundation
import WidgetKit

extension SystemStore {
    // MARK: - Apple Health

    /// Pulls fresh Health numbers in the background and applies them. No-op when
    /// Health is off, unavailable or already syncing.
    func syncHealth() {
        let hs = HealthService.shared
        guard hs.enabled, hs.isAvailable, !hs.syncing else { return }
        Task { @MainActor in
            guard let day = await hs.sync() else { return }
            self.applyHealth(day)
        }
    }

    /// Poor sleep recorded by Apple Health softens penalties exactly like a
    /// strained morning check-in.
    func healthStrained(_ key: String) -> Bool {
        HealthService.shared.cached(key)?.poorSleep ?? false
    }

    /// Completes today's body quests whose targets Health data already meets.
    func applyHealth(_ day: HealthDay) {
        let key = DayKey.today
        guard day.dayKey == key, let p = plan(key, create: false) else { return }
        let deload = position(key).isDeload
        for q in p.quests where !isDone(q, on: key) {
            guard let ev = HealthRules.evidence(for: q, day: day, deload: deload, lib: lib) else { continue }
            let n = alerts.count
            complete(q, note: "Apple Health: \(ev)")
            if let i = alerts.indices.dropFirst(n).first(where: { alerts[$0].title == "[QUEST COMPLETE]" }) {
                alerts[i].lines.insert("APPLE HEALTH · \(ev)", at: 0)
            }
        }
        // Sleep may have changed the penalty load shown on the board.
        revision += 1
    }

    // MARK: - Widget

    /// Writes the widget snapshot into the App Group container and reloads the
    /// widget when the content changed. Silent when there is no container.
    func publishWidgetSnapshot() {
        let key = DayKey.today
        let quests = plan(key, create: false)?.quests ?? []
        let dailies = quests.filter { $0.kind != .penalty }
        let isDone: (Quest) -> Bool = { self.completed.contains(key + "|" + $0.id) }
        let penalty = quests.filter { $0.kind == .penalty && !isDone($0) }
        let prog = Leveling.progress(for: player.totalXP)
        let snap = WidgetSnapshot(dayKey: key,
                                  done: dailies.filter(isDone).count,
                                  total: dailies.count,
                                  penaltyPending: !penalty.isEmpty,
                                  deload: position(key).isDeload,
                                  streak: player.streak,
                                  level: player.level,
                                  rank: player.rank.letter,
                                  rankTitle: player.rank.title,
                                  xpInto: prog.into,
                                  xpSpan: prog.span,
                                  eveningMinutes: defaults.integer(forKey: DefaultsKey.evening),
                                  pending: Array((penalty + dailies.filter { !isDone($0) }).map(\.title).prefix(4)),
                                  updated: .now)
        WidgetBridge.publish(snap)
    }
}

@MainActor
enum WidgetBridge {
    private static var last: WidgetSnapshot?

    static func publish(_ snap: WidgetSnapshot) {
        guard !snap.sameContent(as: last) else { return }
        guard snap.write() else { return }
        last = snap
        WidgetCenter.shared.reloadAllTimelines()
    }
}
