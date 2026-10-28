import SwiftUI

struct TrainView: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TodaySessionCard()
                    NextTargetsCard()
                    LadderCard()
                    NavigationLink { AssessmentView() } label: {
                        HStack {
                            Image(systemName: "flame.fill").foregroundStyle(Theme.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ASSESSMENT / RANK TRIAL").font(Theme.mono(14, .bold)).foregroundStyle(Theme.text)
                                Text("1 km run · push-up max · plank · reaction").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                        }
                        .systemPanel(Theme.red)
                    }
                    .buttonStyle(.plain)
                    WorkoutHistoryCard()
                    if store.lib.training.sessions.isEmpty {
                        Text("training.json not found in the bundle. The programme is empty.")
                            .font(Theme.mono(11)).foregroundStyle(Theme.red)
                    }
                }
                .padding()
            }
            .systemScreen("TRAIN")
        }
    }
}

struct TodaySessionCard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let today = DayKey.today
        let pos = store.position(today)
        let session = TrainingEngine.session(for: pos)
        VStack(alignment: .leading, spacing: 8) {
            BracketHeader(title: "Today")
            Text("WEEK \(pos.effectiveWeek == pos.week ? "\(pos.week)" : "\(pos.week) (cycle \(pos.effectiveWeek))") · DAY \(pos.dayInWeek + 1) · \(pos.phase?.title.uppercased() ?? "")")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            if let f = pos.phase?.focus, !f.isEmpty {
                Text(f).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            if pos.isDeload { Text("DELOAD WEEK").font(Theme.mono(12, .bold)).foregroundStyle(Theme.green) }
            if pos.isAssessmentDay {
                Text("BOSS DAY: assessment instead of training.").font(Theme.mono(14, .bold)).foregroundStyle(Theme.red)
            } else if let s = session {
                Text(s.title).font(Theme.mono(18, .heavy)).foregroundStyle(Theme.text).glow(Theme.blue, radius: 4)
                Text(s.notes).font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                Text("Rest day. Active recovery: walk and mobility.").font(Theme.mono(13)).foregroundStyle(Theme.text)
            }
            NavigationLink { WorkoutLoggerView() } label: { Text(session == nil ? "LOG A SESSION ›" : "START SESSION ›") }
                .buttonStyle(.system(Theme.cyan, filled: session != nil))
        }
        .systemPanel()
    }
}

struct NextTargetsCard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let tomorrow = DayKey.add(1, to: DayKey.today)
        if let next = TrainingEngine.nextSession(from: tomorrow, start: store.startKey) {
            let key = next.0
            let s = next.1
            let targets = store.targets(for: s, on: key)
            VStack(alignment: .leading, spacing: 6) {
                BracketHeader(title: "Next Session", color: Theme.blue, size: 12)
                Text("\(DayKey.pretty(key).uppercased()) · \(s.title)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
                ForEach(targets) { t in
                    TargetRow(t: t)
                }
                if let c = s.cardio {
                    Text("\(c.mode.uppercased()) \(TrainingEngine.cardioMinutes(c, deload: store.position(key).isDeload)) min\(c.zone2 ? " · zone 2" : "")")
                        .font(Theme.mono(12)).foregroundStyle(Theme.cyan)
                }
            }
            .systemPanel(Theme.blue)
        }
    }
}

struct TargetRow: View {
    let t: ExerciseTarget
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(t.exercise.name).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                if t.progressed { Tag(text: "▲ PROGRESS", color: Theme.green) }
                Spacer()
                Text(prescription).font(Theme.mono(12)).foregroundStyle(Theme.cyan)
            }
            Text(t.note).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 2)
    }

    var prescription: String {
        let reps = t.repMin == t.repMax ? "\(t.repMin)" : "\(t.repMin)-\(t.repMax)"
        let unit = t.exercise.isTimed ? " s" : ""
        let w = t.weight.map { " @ \(Fmt.kg($0))" } ?? ""
        return "\(t.sets)×\(reps)\(unit)\(w)"
    }
}

struct LadderCard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let _ = store.revision
        let ls = store.ladderState()
        let steps = store.lib.training.ladder
        VStack(alignment: .leading, spacing: 8) {
            BracketHeader(title: "Discomfort Ladder", color: Theme.gold, size: 12)
            Text("Step \(min(ls.index + 1, ls.total))/\(ls.total)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            if let s = ls.step {
                Text(s.title).font(Theme.mono(15, .bold)).foregroundStyle(Theme.text)
                Text(s.detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
                SystemBar(value: Double(ls.count) / Double(s.repeats), color: Theme.gold)
                Text("\(ls.count)/\(s.repeats) completions to unlock the next step. It appears in your Daily Quest.")
                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            } else if steps.isEmpty {
                Text("No ladder loaded.").font(Theme.mono(12)).foregroundStyle(Theme.dim)
            } else {
                Text("Ladder complete. Keep the habits.").font(Theme.mono(13, .bold)).foregroundStyle(Theme.green)
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 8) {
                    Image(systemName: i < ls.index ? "checkmark.circle.fill" : (i == ls.index ? "circle.dotted" : "lock.fill"))
                        .font(.system(size: 11))
                        .foregroundStyle(i < ls.index ? Theme.green : (i == ls.index ? Theme.gold : Theme.dim.opacity(0.6)))
                    Text(i <= ls.index ? s.title : "???").font(Theme.mono(11)).foregroundStyle(i <= ls.index ? Theme.text : Theme.dim.opacity(0.6))
                    Spacer()
                    Text(s.category.uppercased()).font(Theme.mono(9)).foregroundStyle(Theme.dim.opacity(0.7))
                }
            }
        }
        .systemPanel(Theme.gold)
    }
}

struct WorkoutHistoryCard: View {
    @Environment(SystemStore.self) private var store
    var body: some View {
        let ws = Array(store.workouts().prefix(12))
        if !ws.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                BracketHeader(title: "Log", color: Theme.blue, size: 12)
                ForEach(ws) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(w.sessionTitle).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(DayKey.pretty(w.dayKey)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                        Text(summary(w)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .systemPanel(Theme.blue)
        }
    }

    func summary(_ w: WorkoutLog) -> String {
        let sets = store.sets(for: w)
        var parts: [String] = []
        if !sets.isEmpty {
            let vol = sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
            parts.append("\(sets.count) sets" + (vol > 0 ? " · \(Int(vol)) kg vol" : ""))
        }
        if w.cardioMinutes > 0 { parts.append("\(Fmt.num(w.cardioMinutes)) min") }
        if w.cardioDistanceKm > 0 { parts.append("\(Fmt.num(w.cardioDistanceKm)) km") }
        if w.rpe > 0 { parts.append("RPE \(w.rpe)") }
        return parts.joined(separator: " · ")
    }
}
