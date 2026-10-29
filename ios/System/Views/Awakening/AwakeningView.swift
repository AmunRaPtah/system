import SwiftUI

/// First-launch "Player Awakening": accept the call, name, programme start,
/// optional initial assessment, notification permission, then the status reveal.
/// Every step can be skipped; replaying it from Settings changes nothing unless
/// the player edits something.
struct AwakeningView: View {
    var replay = false

    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable { case call, name, start, trial, alerts, reveal }

    @State private var step: Step = .call
    @State private var declined = 0
    @State private var name = ""
    @State private var start = Date()
    @State private var loaded = false
    @State private var assessmentsAtStart = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                SystemBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        progressDots
                        content
                            .id(step)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                    removal: .opacity))
                    }
                    .padding()
                    .padding(.top, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .animation(.easeOut(duration: 0.3), value: step)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step != .reveal {
                        Button("SKIP") { skipAll() }
                            .font(Theme.mono(12, .bold))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    // MARK: - Steps

    @ViewBuilder
    var content: some View {
        switch step {
        case .call: callStep
        case .name: nameStep
        case .start: startStep
        case .trial: trialStep
        case .alerts: alertsStep
        case .reveal: AwakeningReveal(name: store.displayName) { finish() }
        }
    }

    var callStep: some View {
        window(Theme.cyan) {
            TypewriterText(text: declined == 0
                           ? "You have acquired the qualifications to be a Player."
                           : "Refusal is not recognised. The System has already chosen you.",
                           font: Theme.mono(15, .bold), color: Theme.text)
            TypewriterText(text: "Will you accept?", font: Theme.mono(20, .heavy), color: Theme.cyan, delay: 1.6)
                .glow(Theme.cyan, radius: 6)
            HStack(spacing: 12) {
                Button("ACCEPT") { Haptics.levelUp(); go(.name) }
                    .buttonStyle(.system(Theme.cyan, filled: true))
                if declined < 2 {
                    Button("DECLINE") { Haptics.warning(); declined += 1 }
                        .buttonStyle(.system(Theme.dim))
                }
            }
            .padding(.top, 6)
        }
    }

    var nameStep: some View {
        window(Theme.cyan) {
            TypewriterText(text: "Identify yourself, Player.", font: Theme.mono(15, .bold), color: Theme.text)
            TextField("", text: $name, prompt: Text("NAME").foregroundColor(Theme.dim))
                .font(Theme.mono(18, .bold))
                .foregroundStyle(Theme.cyan)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($nameFocused)
                .onSubmit { saveName(); go(.start) }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.7), lineWidth: 1))
            Text("Shown on your status window. Leave blank to stay \"Player\".")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
            Button("CONFIRM") { saveName(); go(.start) }
                .buttonStyle(.system(Theme.cyan, filled: true))
        }
    }

    var startStep: some View {
        window(Theme.blue) {
            TypewriterText(text: "Set the day your training begins.", font: Theme.mono(15, .bold), color: Theme.text)
            Text("The programme runs in weeks of three sessions, with a lighter deload week every few weeks. Daily quests are judged from this day. Days before it are never penalised.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            DatePicker("Start", selection: $start, displayedComponents: .date)
                .font(Theme.mono(13, .bold))
                .tint(Theme.cyan)
            Button("CONFIRM") {
                if DayKey.key(start) != store.startKey { store.setStart(start) }
                go(.trial)
            }
            .buttonStyle(.system(Theme.cyan, filled: true))
        }
    }

    var trialStep: some View {
        let done = store.assessments().count > assessmentsAtStart
        return window(Theme.red) {
            BracketHeader(title: "Initial Assessment", color: Theme.red)
            TypewriterText(text: "The System must measure your current strength.", font: Theme.mono(15, .bold), color: Theme.text)
            Text("A 1 km run, one set of push-ups, a plank and a reaction test. This is a baseline, not a test you can fail: every later rank is measured against it. Go at your own pace and stop if anything hurts. You can also do it later from Train.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            if done {
                Label("Baseline recorded", systemImage: "checkmark.seal.fill")
                    .font(Theme.mono(13, .bold)).foregroundStyle(Theme.green)
                Button("CONTINUE") { go(.alerts) }
                    .buttonStyle(.system(Theme.cyan, filled: true))
            } else {
                HStack(spacing: 12) {
                    NavigationLink { AssessmentView() } label: { Text("ENTER THE BOSS ROOM ›") }
                        .buttonStyle(.system(Theme.red, filled: true))
                    Button("LATER") { go(.alerts) }
                        .buttonStyle(.system(Theme.dim))
                }
            }
        }
    }

    var alertsStep: some View {
        window(Theme.gold) {
            TypewriterText(text: "The System will brief you each morning and warn you each evening before a day is lost.",
                           font: Theme.mono(15, .bold), color: Theme.text)
            Text("Two notifications a day. A penalty notice follows a missed day. Change the times in Settings.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            HStack(spacing: 12) {
                Button("ALLOW") { store.requestNotificationsIfNeeded(); go(.reveal) }
                    .buttonStyle(.system(Theme.gold, filled: true))
                Button("NOT NOW") { go(.reveal) }
                    .buttonStyle(.system(Theme.dim))
            }
        }
    }

    // MARK: - Chrome

    var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.cyan : Theme.blue.opacity(0.25))
                    .frame(width: s == step ? 18 : 6, height: 6)
                    .glow(s == step ? Theme.cyan : .clear, radius: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func window<C: View>(_ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.square.fill").foregroundStyle(color).glow(color)
                Text("NOTIFICATION").font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim).tracking(2)
            }
            Rectangle().fill(color.opacity(0.6)).frame(height: 1).glow(color, radius: 3)
            content()
        }
        .systemPanel(color, padding: 20)
    }

    // MARK: - Actions

    func load() {
        guard !loaded else { return }
        loaded = true
        name = store.playerName
        start = DayKey.date(store.startKey)
        assessmentsAtStart = store.assessments().count
    }

    func go(_ s: Step) {
        nameFocused = false
        step = s
    }

    func saveName() {
        store.setPlayerName(name)
    }

    func skipAll() {
        saveName()
        if !replay { store.requestNotificationsIfNeeded() }
        finish()
    }

    func finish() {
        store.completeAwakening()
        dismiss()
    }
}

/// The closing status window: name, level, rank, title and stats, revealed line by line.
struct AwakeningReveal: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    var onBegin: () -> Void
    @State private var shown = 0

    var body: some View {
        let p = store.player
        let rows = Stat.allCases
        VStack(alignment: .leading, spacing: 12) {
            TypewriterText(text: "Welcome, Player.", font: Theme.mono(13, .bold), color: Theme.dim)
            Text(name).font(Theme.mono(24, .heavy)).foregroundStyle(Theme.cyan).glow(Theme.cyan, radius: 8)
                .opacity(shown > 0 ? 1 : 0)
            HStack {
                Text("LV \(p.level)").font(Theme.mono(18, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(p.rank.letter)-RANK · \(p.rank.title.uppercased())").font(Theme.mono(13, .bold)).foregroundStyle(Theme.gold)
            }
            .opacity(shown > 1 ? 1 : 0)
            Text("TITLE  \(store.equippedTitle.map { "「\($0.name)」" } ?? "—")")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                .opacity(shown > 1 ? 1 : 0)
            Rectangle().fill(Theme.cyan.opacity(0.6)).frame(height: 1).glow(Theme.cyan, radius: 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, s in
                StatBarRow(stat: s, points: p.points(s) + store.titleBonus(s), xp: p.xp(s),
                           maxPoints: rows.map { p.points($0) + store.titleBonus($0) }.max() ?? 10)
                    .opacity(shown > i + 2 ? 1 : 0)
                    .offset(x: shown > i + 2 ? 0 : -8)
            }
            Text("Every stat starts at 10. Each one grows only from what you actually do.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                .opacity(shown > rows.count + 2 ? 1 : 0)
            Button("BEGIN") { Haptics.success(); onBegin() }
                .buttonStyle(.system(Theme.cyan, filled: true))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .opacity(shown > rows.count + 2 ? 1 : 0.4)
        }
        .systemPanel(Theme.cyan, padding: 20)
        .contentShape(Rectangle())
        .onTapGesture { shown = rows.count + 3 }
        .task {
            let total = rows.count + 3
            if reduceMotion { shown = total; return }
            Haptics.levelUp()
            try? await Task.sleep(nanoseconds: 700_000_000)
            for i in 1...total {
                if shown >= total { break }
                withAnimation(.easeOut(duration: 0.25)) { shown = max(shown, i) }
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }
    }
}

/// Text that types itself out. Tap to finish instantly; static under Reduce Motion.
struct TypewriterText: View {
    let text: String
    var font: Font = Theme.mono(14)
    var color: Color = Theme.text
    var delay: Double = 0
    var speed: Double = 0.028

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var count = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Full text reserves the final layout so nothing jumps while typing.
            Text(text).opacity(0)
            Text(String(text.prefix(count)))
        }
        .font(font)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { count = text.count }
        .accessibilityLabel(text)
        .task(id: text) {
            if reduceMotion { count = text.count; return }
            count = 0
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            for i in 0...text.count {
                if Task.isCancelled || count >= text.count { break }
                count = max(count, i)
                try? await Task.sleep(nanoseconds: UInt64(speed * 1_000_000_000))
            }
        }
    }
}
