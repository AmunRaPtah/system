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
        let f = store.fatigue()
        let fColor = f.high ? Theme.red : (f.value >= 30 ? Theme.gold : Theme.green)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                LevelEmblem(level: p.level, progress: Double(prog.into) / Double(max(1, prog.span)))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(p.rank.letter)-RANK").font(Theme.mono(18, .heavy)).foregroundStyle(Theme.gold).glow(Theme.gold, radius: 5)
                        Spacer(minLength: 0)
                        Label("\(p.streak)", systemImage: "flame.fill")
                            .font(Theme.mono(13, .heavy))
                            .foregroundStyle(p.streak > 0 ? Theme.gold : Theme.dim)
                            .glow(p.streak > 0 ? Theme.gold : .clear, radius: 4)
                    }
                    Text(p.rank.title.uppercased()).font(Theme.mono(10, .bold)).tracking(1).foregroundStyle(Theme.dim)
                    HStack(spacing: 14) {
                        Readout(label: "Job", value: store.job.uppercased(), color: store.job == "None" ? Theme.dim : Theme.violet)
                        Readout(label: "XP", value: "\(prog.into)/\(prog.span)", color: Theme.cyan)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("FATIGUE").font(Theme.mono(9, .bold)).tracking(1).foregroundStyle(Theme.dim)
                SystemBar(value: Double(f.value) / 100, color: fColor, height: 4)
                Text("\(f.value) \(f.label)").font(Theme.mono(10, .bold)).foregroundStyle(f.high ? Theme.red : Theme.dim)
            }
            if let trial = p.trialPending {
                Text("Rank-up trial open: \(trial.letter)-Rank. Pass the benchmarks on Train → Assessment.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.gold)
            }
        }
        .systemPanel()
    }
}

/// The level inside a ring that fills with XP towards the next level.
struct LevelEmblem: View {
    var level: Int
    var progress: Double
    var size: CGFloat = 78
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.blue.opacity(0.35), Theme.bg.opacity(0.2)], center: .center, startRadius: 2, endRadius: size / 2))
            Circle().stroke(Theme.blue.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: [Theme.blue, Theme.cyan, .white], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .glow(Theme.cyan, radius: 5)
            Circle().stroke(Theme.cyan.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 4])).padding(8)
            VStack(spacing: -2) {
                Text("LV").font(Theme.mono(10, .bold)).tracking(2).foregroundStyle(Theme.dim)
                Text("\(level)").font(Theme.mono(level >= 100 ? 22 : 28, .heavy)).foregroundStyle(Theme.text).glow(Theme.cyan, radius: 6)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.8), value: progress)
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
            if let signal = store.supportSignal() { SupportCard(signal: signal) }
            HealthTodayCard()
            VowCard()

            ForEach(quests) { q in
                QuestCard(quest: q, done: store.isDone(q, on: today))
            }
            if quests.isEmpty {
                Text("Generating quests…").font(Theme.mono(12)).foregroundStyle(Theme.dim)
            }
            Text("Missed dailies are judged when you next open the app. One Penalty Quest at most, never on deload weeks. A single miss costs no XP: never miss twice.")
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

    var color: Color {
        switch quest.kind {
        case .penalty: return Theme.red
        case .assessment, .preparation: return Theme.gold
        default: return Theme.color(quest.pillar)
        }
    }

    var tag: String {
        switch quest.kind {
        case .penalty: return "PENALTY"
        case .preparation: return "DAILY QUEST"
        default: return quest.pillar.label
        }
    }

    var body: some View {
        let accent = done ? Theme.green : color
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Tag(text: tag, color: color)
                Tag(text: quest.stat.rawValue, color: Theme.dim)
                if quest.minutes > 0 && !done { Tag(text: "\(quest.minutes) MIN", color: Theme.dim) }
                Spacer()
                Text(done ? "CLEARED" : "+\(quest.xp) XP")
                    .font(Theme.mono(12, .heavy))
                    .foregroundStyle(done ? Theme.green : Theme.gold)
                    .glow(done ? Theme.green : Theme.gold, radius: 3)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent).glow(accent, radius: 3)
                    .contentTransition(.symbolEffect(.replace))
                Text(quest.title).font(Theme.mono(15, .bold)).foregroundStyle(done ? Theme.dim : Theme.text)
                    .strikethrough(done, color: Theme.dim)
            }
            if !done {
                Text(store.displayDetail(quest))
                    .font(.system(size: 13.5)).foregroundStyle(Theme.text.opacity(0.72))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                action
            }
        }
        .padding(.leading, 6)
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2).glow(accent, radius: 4).padding(.vertical, 2).offset(x: -4)
        }
        .systemPanel(done ? Theme.green.opacity(0.45) : color)
        .opacity(done ? 0.8 : 1)
        .animation(.easeOut(duration: 0.3), value: done)
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
        case .practice:
            let p = MindPractice(rawValue: quest.refID) ?? .breath
            NavigationLink { PracticeView(practice: p) } label: { Text("BEGIN ›") }
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

// MARK: - Vows

/// Today's vows: mark each kept or slipped, and log cravings resisted.
struct VowCard: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let vows = store.activeVows()
        if !vows.isEmpty {
            let detox = store.detoxification()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BracketHeader(title: "Vows", color: Theme.violet, size: 12)
                    Spacer()
                    Text("DETOXIFICATION LV. \(detox.level)").font(Theme.mono(10, .bold)).foregroundStyle(Theme.violet)
                }
                ForEach(vows) { v in row(v) }
                Text("Skills, once learned, are not lost. A slip resets the streak, never the skill.")
                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            .systemPanel(Theme.violet)
        }
    }

    func row(_ v: VowPreset) -> some View {
        let log = store.vowLog(v.id)
        let streak = store.vowStreak(v.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(v.title).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(streak.current)d · BEST \(streak.best)d").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            Text(v.detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
            HStack(spacing: 8) {
                if let l = log, l.judged {
                    Text(l.kept ? "KEPT" : "SLIPPED").font(Theme.mono(11, .bold))
                        .foregroundStyle(l.kept ? Theme.green : Theme.dim)
                    Button(l.kept ? "UNDO: SLIPPED" : "UNDO: KEPT") { store.judgeVow(v, kept: !l.kept) }
                        .buttonStyle(.system(Theme.dim))
                } else {
                    Button("KEPT") { store.judgeVow(v, kept: true) }.buttonStyle(.system(Theme.green, filled: true))
                    Button("SLIPPED") { store.judgeVow(v, kept: false) }.buttonStyle(.system(Theme.dim))
                }
            }
            if v.craving {
                Button("I RESISTED A CRAVING" + ((log?.cravingsResisted ?? 0) > 0 ? " (\(log?.cravingsResisted ?? 0))" : "")) {
                    store.resistCraving(v)
                }
                .buttonStyle(.system(Theme.violet))
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
                Text("Last day of week \(store.lib.training.deloadEvery). 1 km run for time, push-up max, plank max, reaction baseline. The boss falls only to a new record in at least one of them.")
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
