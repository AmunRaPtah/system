import SwiftUI

struct QuestsView: View {
    @Environment(SystemStore.self) private var store
    @Binding var showSettings: Bool
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PlayerHeader()
                    Picker("", selection: $tab) {
                        Text("DAILY").tag(0)
                        Text("WEEKLY").tag(1)
                        Text("MONTHLY").tag(2)
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case 0: DailyBoard()
                    case 1: WeeklyBoard()
                    default: DungeonBoard()
                    }
                }
                .padding()
            }
            .systemScreen("QUESTS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        }
    }
}

struct PlayerHeader: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let p = store.player
        let prog = Leveling.progress(for: p.totalXP)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lv. \(p.level)").font(Theme.mono(26, .heavy)).foregroundStyle(Theme.text).glow(Theme.blue, radius: 6)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(p.rank.letter)-RANK").font(Theme.mono(16, .heavy)).foregroundStyle(Theme.gold).glow(Theme.gold, radius: 4)
                    Text(p.rank.title.uppercased()).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                }
            }
            SystemBar(value: Double(prog.into) / Double(max(1, prog.span)))
            HStack {
                Text("XP \(prog.into)/\(prog.span)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Spacer()
                Text("STREAK \(p.streak)d").font(Theme.mono(11, .bold)).foregroundStyle(p.streak > 0 ? Theme.cyan : Theme.dim)
            }
            if let trial = p.trialPending {
                Text("Rank-up trial open: \(trial.letter)-Rank. Pass the benchmarks on Train → Assessment.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.gold)
            }
        }
        .systemPanel()
    }
}

// MARK: - Daily

struct DailyBoard: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let today = DayKey.today
        let pos = store.position(today)
        let quests = store.quests(today)
        let done = quests.filter { store.isDone($0, on: today) }.count
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                BracketHeader(title: "Daily Quest")
                Text(DayKey.pretty(today).uppercased() + " · WEEK \(pos.week) · \(pos.phase?.title.uppercased() ?? "PROGRAMME")")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                if pos.isDeload {
                    Text("DELOAD WEEK: lighter loads, no penalties. Recover and consolidate.")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                }
                SystemBar(value: quests.isEmpty ? 0 : Double(done) / Double(quests.count), color: Theme.green, height: 4)
                Text("\(done)/\(quests.count) COMPLETE").font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
            }
            .systemPanel()

            if store.checkIn(today) == nil { CheckInCard() }

            ForEach(quests) { q in
                QuestCard(quest: q, done: store.isDone(q, on: today))
            }
            if quests.isEmpty {
                Text("Generating quests…").font(Theme.mono(12)).foregroundStyle(Theme.dim)
            }
            Text("Missed dailies are judged when you next open the app. One Penalty Quest at most, never on deload weeks.")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
    }
}

struct CheckInCard: View {
    @Environment(SystemStore.self) private var store
    @State private var sleep = 7.5
    @State private var soreness = 2
    @State private var mood = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: "Morning Status", color: Theme.blue, size: 12)
            HStack {
                Text("SLEEP").font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 74, alignment: .leading)
                Slider(value: $sleep, in: 3...11, step: 0.5)
                Text("\(Fmt.num(sleep)) h").font(Theme.mono(12, .bold)).foregroundStyle(sleep < 6 ? Theme.red : Theme.text).frame(width: 48)
            }
            scale("SORENESS", $soreness, warn: soreness >= 4)
            scale("MOOD", $mood, warn: mood <= 1)
            Button("LOG STATUS") { store.logCheckIn(sleep: sleep, soreness: soreness, mood: mood) }
                .buttonStyle(.system)
        }
        .systemPanel(Theme.blue)
    }

    func scale(_ label: String, _ v: Binding<Int>, warn: Bool) -> some View {
        HStack {
            Text(label).font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 74, alignment: .leading)
            ForEach(1...5, id: \.self) { i in
                Button {
                    v.wrappedValue = i
                    Haptics.tap()
                } label: {
                    Text("\(i)").font(Theme.mono(13, .bold))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(v.wrappedValue == i ? Theme.bg : Theme.text)
                        .background(RoundedRectangle(cornerRadius: 3).fill(v.wrappedValue == i ? (warn ? Theme.red : Theme.cyan) : Theme.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct QuestCard: View {
    @Environment(SystemStore.self) private var store
    let quest: Quest
    let done: Bool
    @State private var note = ""

    var color: Color { quest.kind == .penalty ? Theme.red : (quest.kind == .assessment ? Theme.gold : Theme.color(quest.pillar)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Tag(text: quest.kind == .penalty ? "PENALTY" : quest.pillar.label, color: color)
                Tag(text: quest.stat.rawValue, color: Theme.dim)
                if quest.minutes > 0 { Tag(text: "\(quest.minutes) MIN", color: Theme.dim) }
                Spacer()
                Text("+\(quest.xp) XP").font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
            }
            HStack(alignment: .top) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Theme.green : color).glow(done ? Theme.green : color, radius: 3)
                Text(quest.title).font(Theme.mono(15, .bold)).foregroundStyle(done ? Theme.dim : Theme.text)
                    .strikethrough(done, color: Theme.dim)
            }
            Text(store.displayDetail(quest))
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if !done { action }
        }
        .systemPanel(done ? Theme.green.opacity(0.6) : color)
    }

    @ViewBuilder var action: some View {
        switch quest.kind {
        case .session:
            NavigationLink { WorkoutLoggerView() } label: { Text("OPEN SESSION ›") }
                .buttonStyle(.system(color))
        case .drill:
            if let k = DrillKind(rawValue: quest.refID) {
                NavigationLink { DrillHostView(kind: k) } label: { Text("START DRILL ›") }
                    .buttonStyle(.system(color))
            }
        case .lesson:
            if let g = Game(rawValue: quest.refID) {
                NavigationLink { GameLessonsView(game: g) } label: { Text("OPEN \(g.title.uppercased()) ›") }
                    .buttonStyle(.system(color))
            }
        case .assessment:
            NavigationLink { AssessmentView() } label: { Text("ENTER THE BOSS ROOM ›") }
                .buttonStyle(.system(color))
        default:
            VStack(alignment: .leading, spacing: 8) {
                if quest.proof == "note" || quest.proof == "count" {
                    TextField(quest.proof == "count" ? "How many?" : "One line: what happened?", text: $note)
                        .keyboardType(quest.proof == "count" ? .numberPad : .default)
                        .font(Theme.mono(13))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bg.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.blue.opacity(0.5)))
                }
                Button("COMPLETE") { store.complete(quest, note: note) }
                    .buttonStyle(.system(color, filled: true))
                    .disabled((quest.proof == "note" || quest.proof == "count") && note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Weekly

struct WeeklyBoard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let pos = store.position(DayKey.today)
        let keys = store.weekKeys()
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                BracketHeader(title: "Weekly Quest")
                Text("WEEK \(pos.week) · \(DayKey.pretty(keys.first ?? "").uppercased()) – \(DayKey.pretty(keys.last ?? "").uppercased())")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                if pos.isDeload { Text("Deload week: zone-2 target scaled down.").font(Theme.mono(11)).foregroundStyle(Theme.green) }
            }
            .systemPanel()
            ForEach(store.weeklyTargets()) { t in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t.title).font(Theme.mono(14, .bold)).foregroundStyle(Theme.text)
                        Spacer()
                        Tag(text: t.stat.rawValue, color: Theme.color(t.stat.pillar))
                    }
                    SystemBar(value: t.current / max(1, t.goal), color: t.done ? Theme.green : Theme.cyan)
                    HStack {
                        Text("\(Fmt.num(t.current))/\(Fmt.num(t.goal)) \(t.unit)").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                        Spacer()
                        if t.claimed {
                            Text("CLAIMED").font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                        } else if t.done {
                            Button("CLAIM +\(t.xp) XP") { store.claimWeekly(t) }.buttonStyle(.system(Theme.gold, filled: true))
                        } else {
                            Text("+\(t.xp) XP").font(Theme.mono(11)).foregroundStyle(Theme.gold.opacity(0.7))
                        }
                    }
                }
                .systemPanel(t.done ? Theme.green : Theme.blue)
            }
        }
    }
}

// MARK: - Monthly dungeon

struct DungeonBoard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let d = store.dungeon()
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                BracketHeader(title: "Dungeon", color: Theme.violet)
                Text(d.title.uppercased()).font(Theme.mono(20, .heavy)).foregroundStyle(Theme.text).glow(Theme.violet, radius: 8)
                Text("BLOCK \(d.block) · WEEK \(d.weekInBlock)/\(max(1, store.lib.training.deloadEvery)) · \(DayKey.pretty(d.firstKey)) – \(DayKey.pretty(d.lastKey))")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .systemPanel(Theme.violet)
            ForEach(d.steps) { s in
                HStack {
                    Image(systemName: s.done ? "checkmark.diamond.fill" : "diamond").foregroundStyle(s.done ? Theme.green : Theme.violet)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                        SystemBar(value: Double(s.current) / Double(max(1, s.goal)), color: s.done ? Theme.green : Theme.violet, height: 4)
                    }
                    Text("\(min(s.current, s.goal))/\(s.goal)").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                }
                .systemPanel(s.done ? Theme.green.opacity(0.7) : Theme.violet.opacity(0.7), padding: 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.red).glow(Theme.red)
                    Text("BOSS: ASSESSMENT DAY").font(Theme.mono(15, .heavy)).foregroundStyle(Theme.red)
                }
                Text("Last day of week \(store.lib.training.deloadEvery). 1 km run for time, push-up max, plank max, reaction baseline.")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                if d.bossDone {
                    Text("BOSS DEFEATED").font(Theme.mono(13, .bold)).foregroundStyle(Theme.green)
                } else if d.bossUnlocked {
                    NavigationLink { AssessmentView() } label: { Text("ENTER THE BOSS ROOM ›") }
                        .buttonStyle(.system(Theme.red))
                } else {
                    Text("LOCKED until week \(store.lib.training.deloadEvery)").font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim)
                }
            }
            .systemPanel(Theme.red)
            if d.claimed {
                Text("[ DUNGEON CLEARED ]").font(Theme.mono(14, .bold)).foregroundStyle(Theme.green)
            } else if d.cleared {
                Button("CLAIM DUNGEON REWARD +250 XP") { store.claimDungeon(d) }.buttonStyle(.system(Theme.gold, filled: true))
            }
        }
    }
}
