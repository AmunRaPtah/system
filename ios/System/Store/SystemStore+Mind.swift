import Foundation
import SwiftData

extension DefaultsKey {
    static let supportName = "system.supportName"
    static let supportPhone = "system.supportPhone"
    static let moodPatternAlerts = "system.moodPatternAlerts"
}

/// Mental training, the Tenacity skill and the support layer. Nothing here costs
/// XP or is gamified around mood: mood is observed so the app can be gentler.
extension SystemStore {

    // MARK: - Practice log

    func mindLogs(_ key: String? = nil) -> [MindLog] {
        _ = revision
        let all = fetchAll(MindLog.self)
        return (key.map { k in all.filter { $0.dayKey == k } } ?? all).sorted { $0.date > $1.date }
    }

    func practiceDayKeys() -> Set<String> {
        Set(fetchAll(MindLog.self).map(\.dayKey))
    }

    /// Canon passive skill. Levels from total days trained; a gap never lowers it.
    func tenacity() -> (level: Int, days: Int, next: Int?) {
        _ = revision
        let n = practiceDayKeys().count
        return (Tenacity.level(days: n), n, Tenacity.next(days: n))
    }

    /// The last `days` days of logged mood, oldest first. nil where nothing was logged.
    func moodTrend(days: Int = 14) -> [(key: String, mood: Int?)] {
        _ = revision
        let today = DayKey.today
        return (0..<days).reversed().map { i in
            let k = DayKey.add(-i, to: today)
            return (k, checkIn(k)?.mood)
        }
    }

    // MARK: - Support

    var supportName: String {
        _ = revision
        return defaults.string(forKey: DefaultsKey.supportName) ?? ""
    }

    var supportPhone: String {
        _ = revision
        return defaults.string(forKey: DefaultsKey.supportPhone) ?? ""
    }

    func setSupport(name: String, phone: String) {
        defaults.set(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)), forKey: DefaultsKey.supportName)
        defaults.set(String(phone.filter { $0.isNumber || $0 == "+" }.prefix(20)), forKey: DefaultsKey.supportPhone)
        revision += 1
    }

    var moodPatternAlerts: Bool {
        _ = revision
        return defaults.bool(forKey: DefaultsKey.moodPatternAlerts)
    }

    func setMoodPatternAlerts(_ on: Bool) {
        defaults.set(on, forKey: DefaultsKey.moodPatternAlerts)
        revision += 1
    }

    /// What, if anything, the daily board should gently surface. Low mood is
    /// always watched; the elevated-mood with short-sleep pattern is opt-in.
    func supportSignal() -> SupportSignal? {
        _ = revision
        let today = DayKey.today
        let recent = (0..<5).compactMap { checkIn(DayKey.add(-$0, to: today)) }
        if checkIn(today)?.mood == 1 { return .veryLowToday }
        let low = recent.filter { $0.mood <= 2 }.count
        if low >= 3 { return .lowStretch(days: low) }
        if moodPatternAlerts {
            let last4 = (0..<4).compactMap { checkIn(DayKey.add(-$0, to: today)) }
            let flagged = last4.filter { $0.mood >= 5 && $0.sleepHours < 6 }.count
            if flagged >= 3 { return .elevatedShortSleep(days: flagged) }
        }
        return nil
    }

    var moodIsLowToday: Bool { (checkIn(DayKey.today)?.mood ?? 3) <= 2 }
}
