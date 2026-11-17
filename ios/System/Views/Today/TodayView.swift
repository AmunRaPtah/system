import SwiftUI

extension Theme {
    static func color(_ d: Domain) -> Color {
        switch d {
        case .body: return Theme.red
        case .mind: return Theme.violet
        case .bonds: return Theme.gold
        case .ambition: return Theme.cyan
        case .wealth: return Theme.green
        case .ground: return Theme.blue
        }
    }
}

/// v3 home: status window, the two daily gates, today's quests across domains.
/// Collapses to one tap after `disuseDays` without a gate.
struct TodayView: View {
    @Environment(SystemStore.self) private var store
    @Binding var showSettings: Bool
    @State private var morning = false
    @State private var evening = false
    @State private var chooseThree = false
    // Stats keeps its own NavigationStack, so it opens as a sheet, not a push.
    @State private var stats = DemoMode.screen == "stats" || DemoMode.screen == "shadows"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.isCollapsed {
                        CollapsedToday()
                    } else {
                        PlayerHeader()
                        if store.chooseThreeDue {
                            Button { chooseThree = true } label: {
                                Label("SUNDAY · CHOOSE THREE CAMPAIGNS", systemImage: "scope")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.system(Theme.gold, filled: true))
                        }
                        GateStrip(morning: $morning, evening: $evening)
                        TodayQuests()
                        QuickAddQuest()
                    }
                }
                .padding()
            }
            .systemScreen("TODAY")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { stats = true } label: { Image(systemName: "chart.bar.xaxis") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $morning) { MorningGateView() }
            .sheet(isPresented: $evening) { EveningGateView() }
            .sheet(isPresented: $chooseThree) { ChooseThreeView() }
            .sheet(isPresented: $stats) { StatsView() }
        }
    }
}

// MARK: - Collapsed (disuse)

struct CollapsedToday: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let away = DayKey.daysBetween(store.lastPresenceKey(), DayKey.today)
        VStack(spacing: 22) {
            Text("\(away) days since the last gate.")
                .font(Theme.mono(13)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            Button {
                Haptics.success()
                store.imHere()
            } label: {
                Text("I'M HERE")
                    .font(Theme.mono(24, .heavy))
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .buttonStyle(.system(Theme.cyan, filled: true))
            if let top = store.topQuest() {
                VStack(alignment: .leading, spacing: 10) {
                    BracketHeader(title: "One quest", color: Theme.gold)
                    switch top {
                    case .owner(let q):
                        Button {
                            Haptics.success()
                            store.setOwnerQuest(q, done: true)
                            store.imHere()
                        } label: {
                            Label(q.title, systemImage: q.dom.symbol)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        }
                        .buttonStyle(.system(Theme.color(q.dom)))
                    case .system(let q):
                        Text(q.title).font(Theme.mono(15, .bold)).foregroundStyle(Theme.text)
                        Text(q.detail).font(.footnote).foregroundStyle(Theme.dim).lineLimit(3)
                    }
                }
                .systemPanel(Theme.gold)
            }
        }
        .padding(.top, 40)
    }
}

// MARK: - Gates

struct GateStrip: View {
    @Environment(SystemStore.self) private var store
    @Binding var morning: Bool
    @Binding var evening: Bool

    var body: some View {
        let key = DayKey.today
        let m = store.dayGate(key, .morning)
        let e = store.dayGate(key, .evening)
        HStack(spacing: 10) {
            gateButton(title: "MORNING", symbol: "sunrise.fill", color: Theme.gold,
                       summary: m.map { "Energy \($0.energy)/5" + ($0.line.isEmpty ? "" : " · \($0.line)") }) { morning = true }
            gateButton(title: "EVENING", symbol: "moon.stars.fill", color: Theme.violet,
                       summary: e.map { "\($0.questsDone)/\($0.questsTotal) done" + ($0.line.isEmpty ? "" : " · \($0.line)") }) { evening = true }
        }
    }

    func gateButton(title: String, symbol: String, color: Color, summary: String?, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: summary == nil ? symbol : "checkmark.seal.fill")
                    Text(title)
                }
                .font(Theme.mono(14, .heavy))
                Text(summary ?? "Open the gate")
                    .font(Theme.mono(10))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .buttonStyle(.system(color, filled: summary == nil))
    }
}

// MARK: - Today's quests

struct TodayQuests: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let key = DayKey.today
        let owner = store.ownerQuests(on: key)
        let sys = store.quests(key).filter { $0.kind != .penalty }
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: "Today's quests")
            if owner.isEmpty {
                Text("No quests of yours today. Write one below or plan them in Campaigns.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            ForEach(owner) { q in OwnerQuestRow(quest: q) }
            if !sys.isEmpty {
                Text("THE DISCIPLINE").font(Theme.mono(10, .bold)).tracking(1).foregroundStyle(Theme.dim).padding(.top, 4)
                ForEach(sys) { q in
                    let d = Domain.from(q.pillar)
                    let done = store.isDone(q, on: key)
                    HStack(spacing: 10) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(done ? Theme.green : Theme.dim)
                        Text(q.title).font(Theme.mono(13)).foregroundStyle(done ? Theme.dim : Theme.text)
                            .strikethrough(done)
                        Spacer()
                        Tag(text: d?.label ?? "RANK", color: d.map { Theme.color($0) } ?? Theme.gold)
                    }
                }
            }
        }
        .systemPanel()
    }
}

struct OwnerQuestRow: View {
    @Environment(SystemStore.self) private var store
    let quest: OwnerQuest

    var body: some View {
        let d = quest.dom
        Button {
            Haptics.tap()
            store.setOwnerQuest(quest, done: !quest.done)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: quest.done ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(quest.done ? Theme.green : Theme.color(d))
                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.title).font(Theme.mono(14, .bold))
                        .foregroundStyle(quest.done ? Theme.dim : Theme.text)
                        .strikethrough(quest.done)
                        .multilineTextAlignment(.leading)
                    if let c = store.campaign(quest.campaignID) {
                        Text(c.title).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
                Tag(text: d.label, color: Theme.color(d))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Move to backlog") { store.schedule(quest, on: "") }
            Button("Delete", role: .destructive) { store.deleteOwnerQuest(quest) }
        }
    }
}

/// One line and a domain: the owner writes the quest. Nothing is generated.
struct QuickAddQuest: View {
    @Environment(SystemStore.self) private var store
    @State private var text = ""
    @State private var domain: Domain = .ambition
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: "Write a quest", color: Theme.dim)
            DomainPicker(domain: $domain)
            HStack {
                TextField("One concrete action", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("ADD", action: add)
                    .buttonStyle(.system(Theme.color(domain)))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let note {
                Text(note).font(Theme.mono(11)).foregroundStyle(Theme.gold)
            }
        }
        .systemPanel(Theme.dim)
    }

    func add() {
        switch store.addOwnerQuest(title: text, domain: domain, dayKey: DayKey.today) {
        case .added:
            Haptics.success(); text = ""; note = nil
        case .backlogged:
            Haptics.warning(); text = ""
            note = "Today already holds \(Domain.ambitionCap) Ambition quests. Sent to the backlog."
        case .empty:
            break
        }
    }
}

/// Six big domain chips.
struct DomainPicker: View {
    @Binding var domain: Domain
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Domain.allCases) { d in
                let on = d == domain
                Button { domain = d; Haptics.tap() } label: {
                    Label(d.title, systemImage: d.symbol)
                        .font(Theme.mono(11, .bold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Theme.bg : Theme.color(d))
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.color(d) : Theme.color(d).opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.color(d).opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
