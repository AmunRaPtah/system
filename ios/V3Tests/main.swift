import Foundation

// Self-tests for V3Rules, compiled with plain swiftc in CI (no Xcode project needed).
var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what) (line \(line))") }
}
func at(_ key: String, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: DayKey.date(key))!
}

// Ambition cap: three a day, done quests keep their slot.
check(V3Rules.ambitionRoom(count: 2), "room for a third Ambition quest")
check(!V3Rules.ambitionRoom(count: 3), "no room for a fourth")
check(!V3Rules.canReschedule(done: true), "done quest cannot move (would free a cap slot)")
check(V3Rules.canReschedule(done: false), "open quest can move")

// Disuse: three days without a gate collapses Today.
check(!V3Rules.isCollapsed(lastPresence: "2026-11-16", today: "2026-11-18"), "2 days: not collapsed")
check(V3Rules.isCollapsed(lastPresence: "2026-11-15", today: "2026-11-18"), "3 days: collapsed")
check(!V3Rules.isCollapsed(lastPresence: "2026-11-18", today: "2026-11-18"), "gate today: not collapsed")

// Carry-over: open past quests return to the backlog; done, undated and today's stay.
check(V3Rules.carriesOver(dayKey: "2026-11-17", done: false, today: "2026-11-18"), "open quest from yesterday carries over")
check(!V3Rules.carriesOver(dayKey: "2026-11-17", done: true, today: "2026-11-18"), "done quest stays on its day")
check(!V3Rules.carriesOver(dayKey: "", done: false, today: "2026-11-18"), "backlog quest untouched")
check(!V3Rules.carriesOver(dayKey: "2026-11-18", done: false, today: "2026-11-18"), "today's quest untouched")
check(V3Rules.carriesOver(dayKey: "2026-12-31", done: false, today: "2027-01-01"), "carries over across a year boundary")

// Evening gate: just after midnight it still belongs to yesterday.
check(V3Rules.eveningKey(now: at("2026-11-18", 23, 58)) == "2026-11-18", "23:58 is tonight")
check(V3Rules.eveningKey(now: at("2026-11-19", 0, 1)) == "2026-11-18", "00:01 is still last night")
check(V3Rules.eveningKey(now: at("2026-11-19", 3, 59)) == "2026-11-18", "03:59 is still last night")
check(V3Rules.eveningKey(now: at("2026-11-19", 4, 0)) == "2026-11-19", "04:00 is the new day")
check(V3Rules.eveningKey(now: at("2027-01-01", 0, 30)) == "2026-12-31", "New Year's night belongs to 31 Dec")

// Weeks start on Monday.
check(V3Rules.mondayKey("2026-11-18") == "2026-11-16", "Wednesday -> Monday")
check(V3Rules.mondayKey("2026-11-16") == "2026-11-16", "Monday -> itself")
check(V3Rules.mondayKey("2026-11-22") == "2026-11-16", "Sunday belongs to the week that started Monday")
check(V3Rules.mondayKey("2026-11-23") == "2026-11-23", "next Monday starts a new week")

// War Room.
check(V3Rules.movedThisWeek(movedKey: "2026-11-16", today: "2026-11-18"), "moved Monday counts this week")
check(!V3Rules.movedThisWeek(movedKey: "2026-11-15", today: "2026-11-18"), "moved last Sunday does not")
check(!V3Rules.movedThisWeek(movedKey: nil, today: "2026-11-18"), "never moved does not")
check(V3Rules.isStale(lastMovedKey: "2026-11-04", today: "2026-11-18"), "14 days still: stale")
check(!V3Rules.isStale(lastMovedKey: "2026-11-05", today: "2026-11-18"), "13 days: not stale")

print(failures == 0 ? "ALL V3 RULE TESTS PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
