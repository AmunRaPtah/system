import Foundation
import HealthKit
import Observation

/// One Apple Health workout, reduced to what quest matching needs.
struct HealthWorkout: Codable, Hashable {
    var activity: UInt
    var name: String
    var minutes: Double
    var start: Date
}

/// A day of Apple Health numbers. Cached in UserDefaults so penalty softening and
/// the Quests card work synchronously, before a fresh query returns.
struct HealthDay: Codable, Equatable {
    var dayKey: String
    var steps: Double
    var activeKcal: Double
    /// Asleep hours for the night ending this morning; nil when Health has no sleep data.
    var sleepHours: Double?
    var workouts: [HealthWorkout]
    var fetched: Date

    static let poorSleepHours = 6.0
    /// Same threshold as the morning check-in. Missing data is never "poor".
    var poorSleep: Bool {
        guard let h = sleepHours, h > 0 else { return false }
        return h < Self.poorSleepHours
    }
}

enum HealthKeys {
    static let enabled = "system.health.enabled"
    static let cache = "system.health.cache"
}

/// Read-only HealthKit access: steps, active energy, sleep and workouts. Opt-in;
/// everything degrades to "no data" when Health is unavailable or denied.
@MainActor
@Observable
final class HealthService {
    static let shared = HealthService()

    @ObservationIgnored private let hk: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    @ObservationIgnored private let defaults = UserDefaults.standard

    private(set) var enabled: Bool
    private(set) var cache: [String: HealthDay] = [:]
    var status = ""
    private(set) var syncing = false

    var isAvailable: Bool { hk != nil }
    var today: HealthDay? { cache[DayKey.today] }

    private init() {
        enabled = defaults.bool(forKey: HealthKeys.enabled)
        if let data = defaults.data(forKey: HealthKeys.cache),
           let c = try? JSONDecoder().decode([String: HealthDay].self, from: data) {
            cache = c
        }
    }

    func cached(_ key: String) -> HealthDay? { enabled ? cache[key] : nil }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: HealthKeys.enabled)
        if !on { status = "" }
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
         HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
    }

    /// Shows the Health permission sheet. iOS never reveals whether read access was
    /// denied, so a "success" here only means the sheet was handled.
    @discardableResult
    func requestAccess() async -> Bool {
        guard let hk else {
            status = "Health data is not available on this device."
            return false
        }
        do {
            try await hk.requestAuthorization(toShare: [], read: readTypes)
            status = ""
            return true
        } catch {
            status = "Health access failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Fetches yesterday and today, updates the cache, and returns today.
    func sync() async -> HealthDay? {
        guard enabled, hk != nil, !syncing else { return nil }
        syncing = true
        defer { syncing = false }
        let today = DayKey.today
        var result: HealthDay?
        for key in [DayKey.add(-1, to: today), today] {
            if let d = await fetch(key) {
                cache[key] = d
                if key == today { result = d }
            }
        }
        let keep = DayKey.add(-14, to: today)
        cache = cache.filter { $0.key >= keep }
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: HealthKeys.cache) }
        return result
    }

    private func fetch(_ key: String) async -> HealthDay? {
        guard hk != nil else { return nil }
        let cal = Calendar.current
        let start = DayKey.date(key)
        guard let next = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let end = min(next, Date())
        guard end > start else { return nil }
        let steps = await sum(.stepCount, .count(), start, end)
        let kcal = await sum(.activeEnergyBurned, .kilocalorie(), start, end)
        // Last night: asleep time between 18:00 the evening before and noon.
        let sleepStart = cal.date(byAdding: .hour, value: -6, to: start) ?? start
        let sleepEnd = cal.date(byAdding: .hour, value: 12, to: start) ?? end
        let sleep = await asleepHours(sleepStart, min(sleepEnd, Date()))
        let workouts = await workouts(start, end)
        return HealthDay(dayKey: key, steps: steps, activeKcal: kcal, sleepHours: sleep,
                         workouts: workouts, fetched: .now)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double {
        guard let hk else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: pred),
                                            options: .cumulativeSum)
        do {
            return try await d.result(for: hk)?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch {
            return 0
        }
    }

    private func asleepHours(_ start: Date, _ end: Date) async -> Double? {
        guard let hk, end > start else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: pred)],
                                        sortDescriptors: [])
        guard let samples = try? await d.result(for: hk) else { return nil }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        // Watch and phone often both record the same night; merge overlaps.
        let spans = samples.compactMap { s -> (Date, Date)? in
            guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value), asleep.contains(v) else { return nil }
            let a = max(s.startDate, start), b = min(s.endDate, end)
            return a < b ? (a, b) : nil
        }.sorted { $0.0 < $1.0 }
        guard !spans.isEmpty else { return nil }
        var total: TimeInterval = 0
        var cur = spans[0]
        for s in spans.dropFirst() {
            if s.0 <= cur.1 {
                cur.1 = max(cur.1, s.1)
            } else {
                total += cur.1.timeIntervalSince(cur.0)
                cur = s
            }
        }
        total += cur.1.timeIntervalSince(cur.0)
        return total / 3600
    }

    private func workouts(_ start: Date, _ end: Date) async -> [HealthWorkout] {
        guard let hk else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [])
        guard let ws = try? await d.result(for: hk) else { return [] }
        return ws.map {
            HealthWorkout(activity: $0.workoutActivityType.rawValue, name: Self.name($0.workoutActivityType),
                          minutes: $0.duration / 60, start: $0.startDate)
        }.sorted { $0.start < $1.start }
    }

    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .cycling: return "Cycling"
        case .rowing: return "Rowing"
        case .swimming: return "Swim"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .traditionalStrengthTraining: return "Strength"
        case .functionalStrengthTraining: return "Functional Strength"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .mixedCardio: return "Mixed Cardio"
        case .jumpRope: return "Jump Rope"
        case .yoga: return "Yoga"
        default: return "Workout"
        }
    }
}

/// Which Health evidence satisfies which body quest. Quest XP only: workout XP
/// (sets, cardio minutes) still comes from logging in the Train tab, and a quest
/// is never completed twice, so nothing is double-awarded.
@MainActor
enum HealthRules {
    typealias A = HKWorkoutActivityType
    static func raw(_ t: [A]) -> Set<UInt> { Set(t.map(\.rawValue)) }
    static let strength: Set<UInt> = raw([.traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining])
    static let walk: Set<UInt> = raw([.walking, .hiking])
    static let endurance: Set<UInt> = raw([.running, .walking, .hiking, .cycling, .rowing, .swimming, .elliptical,
                                        .stairClimbing, .mixedCardio])
    static let intervals: Set<UInt> = raw([.running, .cycling, .rowing, .elliptical, .highIntensityIntervalTraining,
                                        .mixedCardio, .jumpRope, .stairClimbing])
    static let conditioning: Set<UInt> = raw([.highIntensityIntervalTraining, .mixedCardio, .functionalStrengthTraining,
                                           .crossTraining, .coreTraining, .jumpRope])
    static let recoverySteps = 7000.0

    /// Returns a short evidence line if `day` satisfies quest `q`, else nil.
    static func evidence(for q: Quest, day: HealthDay, deload: Bool, lib: ContentLibrary) -> String? {
        switch q.kind {
        case .recovery:
            if let w = best(day, walk), w.minutes >= 25 { return line(w) }
            if day.steps >= recoverySteps { return "\(Int(day.steps)) steps" }
            return nil
        case .session:
            guard let s = lib.session(q.refID) else { return nil }
            if s.isStrength {
                let need = Double(max(20, s.minutes / 2))
                return matching(day, strength, need)
            }
            if let c = s.cardio {
                let types: Set<UInt>
                switch c.mode {
                case "intervals": types = intervals
                case "ruck": types = walk
                default: types = endurance
                }
                let need = Double(TrainingEngine.cardioMinutes(c, deload: deload)) * 0.8
                return matching(day, types, need)
            }
            if let c = s.circuit {
                return matching(day, conditioning, Double(c.minutes) * 0.8)
            }
            return nil
        default:
            return nil
        }
    }

    private static func best(_ day: HealthDay, _ types: Set<UInt>) -> HealthWorkout? {
        day.workouts.filter { types.contains($0.activity) }.max { $0.minutes < $1.minutes }
    }

    /// Qualifying workouts summed, so two short runs can cover one session.
    private static func matching(_ day: HealthDay, _ types: Set<UInt>, _ need: Double) -> String? {
        let ws = day.workouts.filter { types.contains($0.activity) }
        let total = ws.reduce(0) { $0 + $1.minutes }
        guard !ws.isEmpty, total >= need else { return nil }
        return ws.count == 1 ? line(ws[0]) : "\(ws.count) workouts, \(Int(total.rounded())) min"
    }

    private static func line(_ w: HealthWorkout) -> String { "\(w.name) \(Int(w.minutes.rounded())) min" }
}
