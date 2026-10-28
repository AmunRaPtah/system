import SwiftUI

struct SetEntry: Identifiable {
    let id = UUID()
    var reps: Int
    var weight: Double
    var done: Bool = false
}

struct WorkoutLoggerView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sessionID = ""
    @State private var entries: [String: [SetEntry]] = [:]   // key = target.id
    @State private var targets: [ExerciseTarget] = []
    @State private var cardioMinutes: Double = 0
    @State private var distance: Double = 0
    @State private var rpe = 6
    @State private var notes = ""
    @State private var useHome = false
    @State private var saved = false

    var session: SessionTemplate? { store.lib.session(sessionID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                picker
                if let s = session {
                    header(s)
                    ForEach(targets) { t in exerciseBlock(t) }
                    if let c = s.circuit { circuitBlock(c) }
                    cardioBlock(s)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        TextField("How did it feel?", text: $notes, axis: .vertical)
                            .font(Theme.mono(13)).lineLimit(1...4)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bg.opacity(0.7)))
                    }
                    .systemPanel(Theme.blue)
                    if saved {
                        Text("SESSION LOGGED").font(Theme.mono(14, .bold)).foregroundStyle(Theme.green)
                    } else {
                        Button("LOG SESSION") { save(s) }
                            .buttonStyle(.system(Theme.cyan, filled: true))
                    }
                    nextTargets(s)
                } else {
                    Text("No sessions in training.json.").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                }
            }
            .padding()
        }
        .systemScreen("SESSION")
        .onAppear(perform: setup)
    }

    var picker: some View {
        Menu {
            ForEach(store.lib.training.sessions) { s in
                Button(s.title) { sessionID = s.id; loadTargets() }
            }
        } label: {
            HStack {
                Text("SESSION: \(session?.title ?? "choose")").font(Theme.mono(12, .bold))
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(Theme.cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func header(_ s: SessionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BracketHeader(title: s.title)
            HStack {
                Tag(text: s.type.uppercased())
                Tag(text: s.stat.rawValue, color: Theme.dim)
                Tag(text: "\(s.minutes) MIN", color: Theme.dim)
                if store.position(DayKey.today).isDeload { Tag(text: "DELOAD", color: Theme.green) }
            }
            if !s.notes.isEmpty { Text(s.notes).font(.system(size: 12)).foregroundStyle(Theme.dim) }
            if s.isStrength {
                Toggle(isOn: $useHome) { Text("HOME ALTERNATIVES").font(Theme.mono(11)).foregroundStyle(Theme.dim) }
                    .tint(Theme.cyan)
            }
        }
        .systemPanel()
    }

    func exerciseBlock(_ t: ExerciseTarget) -> some View {
        let ex = t.exercise
        let variant = useHome ? ex.home : ex.gym
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ex.name).font(Theme.mono(14, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(TargetRow(t: t).prescription).font(Theme.mono(12)).foregroundStyle(Theme.cyan)
            }
            if !variant.isEmpty { Text(variant).font(.system(size: 12)).foregroundStyle(Theme.dim) }
            if !ex.cue.isEmpty { Text("Cue: \(ex.cue)").font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.8)) }
            Text(t.note).font(.system(size: 11)).foregroundStyle(t.progressed ? Theme.green : Theme.gold.opacity(0.8))
            HStack {
                Text("SET").frame(width: 34, alignment: .leading)
                if ex.isLoaded { Text("KG").frame(width: 70) }
                Text(ex.isTimed ? "SEC" : "REPS").frame(width: 60)
                Spacer()
            }
            .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            ForEach(Array((entries[t.id] ?? []).enumerated()), id: \.element.id) { i, _ in
                setRow(t, i)
            }
            HStack {
                Button("+ SET") { entries[t.id, default: []].append(SetEntry(reps: t.repMin, weight: t.weight ?? 0)) }
                    .buttonStyle(.system(Theme.dim))
                Spacer()
                Text("Rest \(t.restSec) s").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
        }
        .systemPanel(t.progressed ? Theme.green : Theme.blue)
    }

    func setRow(_ t: ExerciseTarget, _ i: Int) -> some View {
        let binding = Binding<SetEntry>(
            get: { (entries[t.id] ?? [])[safe: i] ?? SetEntry(reps: 0, weight: 0) },
            set: { v in if entries[t.id]?.indices.contains(i) == true { entries[t.id]?[i] = v } }
        )
        return HStack {
            Text("\(i + 1)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.dim).frame(width: 34, alignment: .leading)
            if t.exercise.isLoaded {
                TextField("kg", value: binding.weight, format: .number)
                    .keyboardType(.decimalPad).numberField().frame(width: 70)
            }
            TextField("reps", value: binding.reps, format: .number)
                .keyboardType(.numberPad).numberField().frame(width: 60)
            Spacer()
            Button {
                binding.wrappedValue.done.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: binding.wrappedValue.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(binding.wrappedValue.done ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)
        }
    }

    func circuitBlock(_ c: Circuit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BracketHeader(title: c.title, color: Theme.gold, size: 12)
            Text("\(c.minutes) min · \(c.format)").font(Theme.mono(12)).foregroundStyle(Theme.text)
            ForEach(c.moves, id: \.self) { m in
                Text("· " + m).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
        .systemPanel(Theme.gold)
    }

    func cardioBlock(_ s: SessionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BracketHeader(title: "Cardio", color: Theme.blue, size: 12)
            if let c = s.cardio {
                let mins = TrainingEngine.cardioMinutes(c, deload: store.position(DayKey.today).isDeload)
                Text("\(c.mode.uppercased()) · target \(mins) min\(c.zone2 ? " · ZONE 2 (can talk in sentences)" : "")")
                    .font(Theme.mono(12)).foregroundStyle(Theme.cyan)
                Text(c.instructions).font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                Text("Optional: log any conditioning done.").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            HStack {
                Text("MIN").font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 40, alignment: .leading)
                TextField("0", value: $cardioMinutes, format: .number).keyboardType(.decimalPad).numberField().frame(width: 70)
                Text("KM").font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 30)
                TextField("0", value: $distance, format: .number).keyboardType(.decimalPad).numberField().frame(width: 70)
            }
            HStack {
                Text("RPE").font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 40, alignment: .leading)
                Stepper(value: $rpe, in: 1...10) {
                    Text("\(rpe)/10 · \(rpeLabel)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                }
            }
        }
        .systemPanel(Theme.blue)
    }

    var rpeLabel: String {
        switch rpe {
        case ...3: return "easy"
        case 4...6: return "moderate"
        case 7...8: return "hard"
        default: return "max"
        }
    }

    func nextTargets(_ s: SessionTemplate) -> some View {
        let _ = store.revision
        let next = store.targets(for: s, on: DayKey.add(1, to: DayKey.today))
        return Group {
            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    BracketHeader(title: "Next time: \(s.title)", color: Theme.green, size: 12)
                    ForEach(next) { TargetRow(t: $0) }
                }
                .systemPanel(Theme.green)
            }
        }
    }

    // MARK: - Logic

    func setup() {
        guard sessionID.isEmpty else { return }
        let today = DayKey.today
        if let s = TrainingEngine.session(for: store.position(today)) {
            sessionID = s.id
        } else if let n = TrainingEngine.nextSession(from: today, start: store.startKey) {
            sessionID = n.1.id
        } else {
            sessionID = store.lib.training.sessions.first?.id ?? ""
        }
        loadTargets()
    }

    func loadTargets() {
        guard let s = session else { return }
        saved = false
        targets = store.targets(for: s, on: DayKey.today)
        var e: [String: [SetEntry]] = [:]
        for t in targets {
            e[t.id] = (0..<t.sets).map { _ in SetEntry(reps: t.repMax == t.repMin ? t.repMin : t.repMin, weight: t.weight ?? 0) }
        }
        entries = e
        if let c = s.cardio {
            cardioMinutes = Double(TrainingEngine.cardioMinutes(c, deload: store.position(DayKey.today).isDeload))
        } else {
            cardioMinutes = 0
        }
        distance = 0
    }

    func save(_ s: SessionTemplate) {
        var logged: [SystemStore.LoggedSet] = []
        for t in targets {
            for (i, e) in (entries[t.id] ?? []).enumerated() where e.done {
                logged.append(.init(exerciseID: t.exercise.id, setIndex: i, reps: e.reps, weight: e.weight))
            }
        }
        store.logWorkout(session: s, sets: logged, cardioMinutes: cardioMinutes, distanceKm: distance, rpe: rpe, notes: notes)
        saved = true
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension View {
    func numberField() -> some View {
        self.font(Theme.mono(14, .bold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bg.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.blue.opacity(0.5)))
    }
}
