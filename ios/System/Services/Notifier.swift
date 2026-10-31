import Foundation
import UserNotifications

struct NotificationDay {
    var dayKey: String
    var complete: Bool
    var deload: Bool
}

enum Notifier {
    static func requestPermission() {
        guard !DemoMode.isOn else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Rebuilds the next week of notifications. Called on launch, foreground and
    /// whenever quest state changes, so a finished day drops its warnings.
    static func reschedule(days: [NotificationDay], morningMinutes: Int, eveningMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let cal = Calendar.current

        func at(_ key: String, minutes: Int, dayOffset: Int = 0) -> Date? {
            let base = DayKey.date(key)
            guard let d = cal.date(byAdding: .day, value: dayOffset, to: base) else { return nil }
            return cal.date(byAdding: .minute, value: minutes, to: d)
        }

        func add(_ id: String, _ title: String, _ body: String, _ date: Date) {
            guard date > now else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        }

        for day in days {
            if let m = at(day.dayKey, minutes: morningMinutes) {
                add("morning-\(day.dayKey)", "[SYSTEM] Daily Quest has arrived",
                    "Your quests for today are ready. Preparation to become strong begins now.", m)
            }
            guard !day.complete else { continue }
            if let e = at(day.dayKey, minutes: eveningMinutes) {
                let body = day.deload
                    ? "Daily Quest incomplete. Deload week: no penalty, but finish what you can."
                    : "Daily Quest incomplete. Failure to complete by midnight will issue a Penalty Quest."
                add("evening-\(day.dayKey)", "[WARNING] Daily Quest incomplete", body, e)
            }
            if !day.deload, let p = at(day.dayKey, minutes: 5, dayOffset: 1) {
                add("penalty-\(day.dayKey)", "[PENALTY] Daily Quest failed",
                    "Yesterday's quests were not completed. A Penalty Quest awaits. Open the System.", p)
            }
        }
    }
}
