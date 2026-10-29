import SwiftUI

/// Name, equipped title and the way into the achievement list, shown at the top
/// of the Stats status window.
struct PlayerTitleLine: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let unlocked = store.unlockedAchievements().count
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.displayName).font(Theme.mono(14, .heavy)).foregroundStyle(Theme.text).tracking(1)
                Spacer()
                NavigationLink { AchievementsView() } label: {
                    Text("ACHIEVEMENTS \(unlocked)/\(AchievementCatalog.all.count) ›")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                }
            }
            if let t = store.equippedTitle {
                HStack(spacing: 6) {
                    Text("TITLE").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    Text("「\(t.name)」").font(Theme.mono(12, .bold)).foregroundStyle(Theme.green).glow(Theme.green, radius: 3)
                    Tag(text: t.bonusLabel, color: Theme.color(t.stat.pillar))
                }
            } else {
                Text("TITLE  —").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct AchievementsView: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let unlocked = store.unlockedAchievements()
        let metrics = store.achievementMetrics()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitlesCard(unlocked: unlocked)
                group("System", color: Theme.cyan, items: AchievementCatalog.system, unlocked: unlocked, metrics: metrics)
                ForEach(Pillar.allCases) { p in
                    group(p.label, color: Theme.color(p), items: AchievementCatalog.all.filter { $0.pillar == p },
                          unlocked: unlocked, metrics: metrics)
                }
            }
            .padding()
        }
        .systemScreen("ACHIEVEMENTS")
    }

    @ViewBuilder
    func group(_ title: String, color: Color, items: [Achievement], unlocked: [String: Date],
               metrics: [AchievementMetric: Int]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BracketHeader(title: title, color: color, size: 12)
                    Spacer()
                    Text("\(items.filter { unlocked[$0.id] != nil }.count)/\(items.count)")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim)
                }
                ForEach(items) { a in
                    AchievementRow(achievement: a, unlockedOn: unlocked[a.id], value: metrics[a.metric], color: color)
                }
            }
            .systemPanel(color)
        }
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    let unlockedOn: Date?
    let value: Int?
    let color: Color

    var body: some View {
        let done = unlockedOn != nil
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 16))
                .frame(width: 24)
                .foregroundStyle(done ? color : Theme.dim.opacity(0.6))
                .glow(done ? color : .clear, radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.name).font(Theme.mono(12, .bold)).foregroundStyle(done ? Theme.text : Theme.dim)
                    Spacer()
                    if let d = unlockedOn {
                        Text(DayKey.pretty(DayKey.key(d))).font(Theme.mono(10)).foregroundStyle(Theme.green)
                    } else {
                        Text(achievement.progressText(value)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                }
                Text(achievement.detail).font(.system(size: 11)).foregroundStyle(Theme.dim)
                if !done && !achievement.metric.lowerIsBetter {
                    SystemBar(value: achievement.fraction(value), color: color.opacity(0.8), height: 3)
                }
                if let t = achievement.title {
                    Text("TITLE: \(t.name) · \(t.bonusLabel)")
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(done ? Theme.green : Theme.dim.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Unlocked titles, one equippable at a time.
struct TitlesCard: View {
    @Environment(SystemStore.self) private var store
    let unlocked: [String: Date]

    var body: some View {
        let owned = AchievementCatalog.all.filter { $0.title != nil && unlocked[$0.id] != nil }
        let total = AchievementCatalog.all.filter { $0.title != nil }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BracketHeader(title: "Titles", color: Theme.green, size: 12)
                Spacer()
                Text("\(owned.count)/\(total)").font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim)
            }
            if owned.isEmpty {
                Text("No titles yet. Titles are earned through the marked achievements below. An equipped title shows on your status window and adds its bonus to one stat.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            ForEach(owned) { a in
                if let t = a.title {
                    let equipped = store.equippedTitleID == a.id
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("「\(t.name)」").font(Theme.mono(12, .bold))
                                .foregroundStyle(equipped ? Theme.green : Theme.text)
                            Text("\(a.name) · \(t.bonusLabel)").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Button(equipped ? "UNEQUIP" : "EQUIP") {
                            Haptics.tap()
                            store.equipTitle(equipped ? nil : a.id)
                        }
                        .buttonStyle(.system(Theme.green, filled: equipped))
                    }
                }
            }
        }
        .systemPanel(Theme.green)
    }
}
