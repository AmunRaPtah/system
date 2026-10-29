import SwiftUI

/// Settings section: opt-in toggle for Apple Health.
struct HealthSettingsSection: View {
    @Environment(SystemStore.self) private var store
    private var health: HealthService { .shared }

    var body: some View {
        Section("Apple Health") {
            if health.isAvailable {
                Toggle("Read from Apple Health", isOn: Binding(
                    get: { health.enabled },
                    set: { on in
                        health.setEnabled(on)
                        guard on else { store.revision += 1; return }
                        Task { @MainActor in
                            await health.requestAccess()
                            store.syncHealth()
                        }
                    }))
                Text("Read-only, on this device. Steps, active energy, sleep and workouts can auto-complete matching body quests (quest XP only: log sets in Train for workout XP). Under 6 h of sleep halves the penalty load, same as the morning check-in. The app works the same with this off or denied.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                if health.enabled {
                    Text("iOS does not tell apps when read access is denied. If numbers stay at zero, allow System under Settings › Health › Data Access & Devices.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                if !health.status.isEmpty {
                    Text(health.status).font(.footnote).foregroundStyle(Theme.red)
                }
            } else {
                Text("Health data is not available on this device.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Today's Apple Health numbers on the daily board. Hidden when Health is off.
struct HealthTodayCard: View {
    private var health: HealthService { .shared }

    var body: some View {
        if health.enabled, let d = health.today {
            VStack(alignment: .leading, spacing: 8) {
                BracketHeader(title: "Vitals · Apple Health", color: Theme.green, size: 12)
                HStack(spacing: 8) {
                    metric("STEPS", "\(Int(d.steps))", warn: false)
                    metric("ACTIVE", "\(Int(d.activeKcal)) kcal", warn: false)
                    metric("SLEEP", d.sleepHours.map { Fmt.num(($0 * 10).rounded() / 10) + " h" } ?? "--", warn: d.poorSleep)
                }
                if !d.workouts.isEmpty {
                    Text(d.workouts.map { "\($0.name) \(Int($0.minutes.rounded())) min" }.joined(separator: " · "))
                        .font(Theme.mono(11)).foregroundStyle(Theme.text)
                }
                if d.poorSleep {
                    Text("Under 6 h sleep recorded. Penalty load is halved today.")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.red)
                }
            }
            .systemPanel(Theme.green)
        }
    }

    func metric(_ label: String, _ value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            Text(value).font(Theme.mono(14, .bold)).foregroundStyle(warn ? Theme.red : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
