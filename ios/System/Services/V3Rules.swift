import Foundation

/// Pure v3 rules (Foundation only, no SwiftData) so CI can test them with plain
/// `swiftc` next to the engine self-tests. The store calls these; it does not
/// re-implement them.
enum V3Rules {
    /// At most this many Ambition quests may sit on one day.
    static let ambitionCap = 3
    /// Days without a completed gate before Today collapses to one-tap mode.
    static let disuseDays = 3
    /// A campaign that has not moved for this many days is faded in the War Room.
    static let staleDays = 14
    /// Before this hour the evening gate still belongs to the previous day.
    static let eveningRolloverHour = 4

    /// One more Ambition quest fits when fewer than the cap already sit on the day
    /// (done or not: a done quest still used its slot).
    static func ambitionRoom(count: Int) -> Bool { count < ambitionCap }

    /// No gate for `disuseDays` days.
    static func isCollapsed(lastPresence: String, today: String) -> Bool {
        DayKey.daysBetween(lastPresence, today) >= disuseDays
    }

    /// An open quest dated before today goes back to the backlog instead of vanishing.
    static func carriesOver(dayKey: String, done: Bool, today: String) -> Bool {
        !done && !dayKey.isEmpty && dayKey < today
    }

    /// A done quest keeps its day: moving it would free a cap slot it already used.
    static func canReschedule(done: Bool) -> Bool { !done }

    /// The day an evening gate opened at `now` belongs to: just after midnight it
    /// is still yesterday's evening.
    static func eveningKey(now: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        let today = DayKey.key(now)
        return hour < eveningRolloverHour ? DayKey.add(-1, to: today) : today
    }

    /// Monday of the calendar week containing `key`.
    static func mondayKey(_ key: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2
        let d = DayKey.date(key)
        let start = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        return DayKey.key(start)
    }

    /// Moved this calendar week (Monday start), not just "was created".
    static func movedThisWeek(movedKey: String?, today: String) -> Bool {
        guard let m = movedKey else { return false }
        return m >= mondayKey(today)
    }

    static func isStale(lastMovedKey: String, today: String) -> Bool {
        DayKey.daysBetween(lastMovedKey, today) >= staleDays
    }
}
