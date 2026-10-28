import Foundation

/// Local-calendar day keys ("yyyy-MM-dd"). Everything date-bucketed uses these.
enum DayKey {
    static var calendar: Calendar { Calendar.current }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date = .now) -> String {
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    static func date(_ key: String) -> Date {
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: .now)
    }

    static func add(_ days: Int, to key: String) -> String {
        let d = calendar.date(byAdding: .day, value: days, to: date(key)) ?? date(key)
        return self.key(d)
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }

    static var today: String { key(.now) }

    static func pretty(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date(key))
    }
}

/// Stable FNV-1a hash; Swift's Hasher is randomised per launch so it cannot seed
/// anything that must be the same tomorrow.
enum StableHash {
    static func of(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }
}

/// SplitMix64, deterministic from a seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    init(_ key: String) { self.init(seed: StableHash.of(key)) }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[Int(next() % UInt64(items.count))]
    }
}
