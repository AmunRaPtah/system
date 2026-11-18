import SwiftUI

/// Morning gate: energy, one line, accept quests. Built to finish in under 30 s.
struct MorningGateView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 0
    @State private var intention = ""
    @State private var accepted: Set<String> = []
    @State private var loaded = false

    var body: some View {
        let today = DayKey.today
        let todays = store.ownerQuests(on: today).filter { !$0.done }
        let candidates = todays + store.backlog()
        // Done Ambition quests still hold their slot, exactly as the store counts them.
        let ambitionDone = store.ownerQuests(on: today).filter { $0.done && $0.dom == .ambition }.count
        let ambitionPicked = ambitionDone + candidates.filter { $0.dom == .ambition && accepted.contains($0.uid) }.count
        let discipline = store.quests(today).filter { $0.kind != .penalty }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BracketHeader(title: "Energy", color: Theme.gold)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { n in
                            Button { energy = n; Haptics.tap() } label: {
                                Text("\(n)").font(Theme.mono(22, .heavy)).frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(.system(Theme.gold, filled: energy == n))
                        }
                    }
                    BracketHeader(title: "Intention", color: Theme.cyan)
                    TextField("One line for today", text: $intention)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                    BracketHeader(title: "Accept quests", color: Theme.green)
                    if discipline > 0 {
                        Text("The Discipline: \(discipline) quest\(discipline == 1 ? "" : "s"), always on.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }
                    if candidates.isEmpty {
                        Text("No quests written yet. Add them on Today or in a campaign.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                    ForEach(candidates) { q in
                        let on = accepted.contains(q.uid)
                        let blocked = !on && q.dom == .ambition && ambitionPicked >= Domain.ambitionCap
                        Button {
                            Haptics.tap()
                            if on { accepted.remove(q.uid) } else if !blocked { accepted.insert(q.uid) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                                Text(q.title).font(Theme.mono(14, .bold)).multilineTextAlignment(.leading)
                                Spacer()
                                Tag(text: q.dom.label, color: Theme.color(q.dom))
                            }
                            .foregroundStyle(on ? Theme.green : (blocked ? Theme.dim : Theme.text))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(blocked ? 0.45 : 1)
                    }
                    if ambitionPicked >= Domain.ambitionCap {
                        Text("Ambition is capped at \(Domain.ambitionCap) a day.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.gold)
                    }
                    Button {
                        Haptics.success()
                        store.completeMorningGate(energy: energy, intention: intention, accepted: accepted)
                        dismiss()
                    } label: {
                        Text("OPEN THE DAY").font(Theme.mono(17, .heavy)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.system(Theme.cyan, filled: true))
                    .disabled(energy == 0)
                }
                .padding()
            }
            .systemScreen("MORNING GATE")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let g = store.dayGate(today, .morning) {
                energy = g.energy
                intention = g.line
            }
            accepted = Set(todays.map(\.uid))
        }
    }
}

/// Evening gate: each quest done or not, and one line.
struct EveningGateView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var done: Set<String> = []
    @State private var marked: Set<String> = []
    @State private var line = ""
    @State private var loaded = false
    /// Fixed when the sheet opens, so closing after midnight still records that evening.
    @State private var day = V3Rules.eveningKey()

    /// System dailies the owner can tick by hand; the rest complete from their logs.
    static let manual: Set<QuestKind> = [.recovery, .ladder, .challenge, .preparation]

    var body: some View {
        let today = day
        // System dailies complete only on the live day; after midnight they are read-only.
        let live = today == DayKey.today
        let owner = store.ownerQuests(on: today)
        let sys = store.quests(today).filter { $0.kind != .penalty }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BracketHeader(title: "Done or not", color: Theme.violet)
                    if owner.isEmpty && sys.isEmpty {
                        Text("Nothing was on today.").font(.footnote).foregroundStyle(Theme.dim)
                    }
                    ForEach(owner) { q in
                        toggleRow(title: q.title, tag: q.dom.label, color: Theme.color(q.dom),
                                  on: done.contains(q.uid), locked: false) {
                            if done.contains(q.uid) { done.remove(q.uid) } else { done.insert(q.uid) }
                        }
                    }
                    ForEach(sys) { q in
                        let already = store.isDone(q, on: today)
                        let d = Domain.from(q.pillar)
                        let canTick = live && !already && Self.manual.contains(q.kind)
                        toggleRow(title: q.title, tag: d?.label ?? "RANK", color: d.map { Theme.color($0) } ?? Theme.gold,
                                  on: already || marked.contains(q.id), locked: !canTick) {
                            if marked.contains(q.id) { marked.remove(q.id) } else { marked.insert(q.id) }
                        }
                    }
                    BracketHeader(title: "One line", color: Theme.cyan)
                    TextField("What happened today", text: $line)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                    Button(action: close) {
                        Text("CLOSE THE DAY").font(Theme.mono(17, .heavy)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.system(Theme.violet, filled: true))
                }
                .padding()
            }
            .systemScreen("EVENING GATE")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            day = V3Rules.eveningKey()
            done = Set(store.ownerQuests(on: day).filter(\.done).map(\.uid))
            line = store.dayGate(today, .evening)?.line ?? ""
        }
    }

    func toggleRow(title: String, tag: String, color: Color, on: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !locked else { return }
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : (locked ? "minus.square" : "square")).font(.title3)
                Text(title).font(Theme.mono(14, .bold)).multilineTextAlignment(.leading)
                Spacer()
                Tag(text: tag, color: color)
            }
            .foregroundStyle(on ? Theme.green : (locked ? Theme.dim : Theme.text))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func close() {
        for q in store.ownerQuests(on: day) { store.setOwnerQuest(q, done: done.contains(q.uid), on: day) }
        if day == DayKey.today {
            for q in store.quests(day) where marked.contains(q.id) && !store.isDone(q, on: day) {
                store.complete(q)
            }
        }
        Haptics.success()
        store.completeEveningGate(line: line, key: day)
        dismiss()
    }
}
