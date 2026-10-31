import SwiftUI
import UIKit

// MARK: - Mind tab section

struct MentalTrainingSection: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let t = store.tenacity()
        let todays = Set(store.mindLogs(DayKey.today).map(\.practice))
        let low = store.moodIsLowToday
        let order = low ? MindPractice.gentle + MindPractice.allCases.filter { !MindPractice.gentle.contains($0) }
                        : MindPractice.allCases
        VStack(alignment: .leading, spacing: 12) {
            BracketHeader(title: "Mental Training", color: Theme.violet, size: 13)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "flame").foregroundStyle(Theme.violet).glow(Theme.violet)
                    Text("TENACITY").font(Theme.mono(14, .heavy)).foregroundStyle(Theme.text)
                    Tag(text: "PASSIVE", color: Theme.dim)
                    Spacer()
                    Text("LV. \(t.level)").font(Theme.mono(18, .heavy)).foregroundStyle(Theme.violet).glow(Theme.violet, radius: 4)
                }
                SystemBar(value: t.next.map { Double(t.days) / Double($0) } ?? 1, color: Theme.violet, height: 6)
                Text(t.next.map { "\(t.days) days trained · next level at \($0)" } ?? "\(t.days) days trained · maximum level")
                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                Text("A mind is trained like a body: small doses, often. Days add up and are never taken away.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text.opacity(0.7))
                MoodTrend()
            }
            .systemPanel(Theme.violet)

            if low {
                Text("Today's status was low. Gentler practices are first. Doing one small thing is enough.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.violet)
            }
            ForEach(order) { p in
                NavigationLink { PracticeView(practice: p) } label: { PracticeRow(practice: p, done: todays.contains(p.rawValue)) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct PracticeRow: View {
    let practice: MindPractice
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: practice.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(done ? Theme.green : Theme.violet)
                .frame(width: 34, height: 34)
                .background(Chamfer(cut: 6).fill((done ? Theme.green : Theme.violet).opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(practice.title.uppercased()).font(Theme.mono(12.5, .bold)).foregroundStyle(Theme.text)
                Text(practice.minutes > 0 ? "\(practice.minutes) MIN · \(practice.stat.rawValue)" : "WRITTEN · \(practice.stat.rawValue)")
                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            Spacer()
            if done { Tag(text: "TODAY ✓", color: Theme.green) }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .systemPanel(done ? Theme.green.opacity(0.5) : Theme.violet.opacity(0.7), padding: 10)
    }
}

/// Mood from the morning status over two weeks, as a quiet bar strip. No score.
struct MoodTrend: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let trend = store.moodTrend(days: 14)
        VStack(alignment: .leading, spacing: 4) {
            Text("MOOD · 14 DAYS").font(Theme.mono(9, .bold)).foregroundStyle(Theme.dim)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(trend.indices, id: \.self) { i in
                    let d = trend[i]
                    let m = d.mood ?? 0
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(m == 0 ? Theme.dim.opacity(0.15) : color(m))
                        .frame(height: m == 0 ? 3 : CGFloat(6 + m * 6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36, alignment: .bottom)
        }
    }

    func color(_ m: Int) -> Color {
        m <= 2 ? Theme.dim.opacity(0.8) : m == 3 ? Theme.blue.opacity(0.7) : Theme.cyan
    }
}

// MARK: - The practice tool

struct PracticeView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let practice: MindPractice

    @State private var fields: [String] = []
    @State private var afterFields: [String] = []
    @State private var before = 5.0
    @State private var after = 5.0
    @State private var keep = true
    @State private var focusMinutes = 25
    @State private var started: Date?
    @State private var stopped: TimeInterval?

    var target: Int { practice == .focus ? focusMinutes : practice.minutes }
    var timed: Bool { target > 0 }

    func elapsed(_ now: Date) -> TimeInterval {
        stopped ?? started.map { now.timeIntervalSince($0) } ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    SystemWindowTitle(title: practice.title, color: Theme.violet, symbol: practice.symbol)
                    Text(practice.detail).font(.system(size: 14)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    Text(practice.canon).font(Theme.mono(11)).foregroundStyle(Theme.violet).fixedSize(horizontal: false, vertical: true)
                }
                .systemPanel(Theme.violet)

                if !practice.before.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(practice.before.indices, id: \.self) { i in
                            field(practice.before[i], text: binding(i, in: $fields), tall: practice == .unload || practice == .reframe)
                        }
                        if practice == .unload {
                            Toggle("Keep what I wrote", isOn: $keep).font(Theme.mono(12)).tint(Theme.violet)
                            Text("Off by default. Writing it out is the point; it does not need to be saved.")
                                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                    }
                    .systemPanel()
                }

                if practice.ratesFeeling {
                    VStack(alignment: .leading, spacing: 8) {
                        rating("FEELING BEFORE", $before)
                        rating("FEELING AFTER", $after)
                        Text("0 is calm, 10 is the strongest it gets.").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                    .systemPanel()
                }

                if timed { timer }

                if !practice.after.isEmpty, started != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(practice.after.indices, id: \.self) { i in
                            field(practice.after[i], text: binding(i, in: $afterFields), tall: false)
                        }
                    }
                    .systemPanel()
                }

                Button("COMPLETE") { complete() }
                    .buttonStyle(.system(Theme.violet, filled: true))
                    .disabled(!canComplete)

                Text(practice.evidence).font(Theme.mono(10)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .systemScreen("MIND")
        .onAppear {
            fields = Array(repeating: "", count: practice.before.count)
            afterFields = Array(repeating: "", count: practice.after.count)
            keep = practice.keepsTextByDefault
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    var canComplete: Bool {
        let filled = fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if practice == .focus { return started != nil && filled }
        if timed { return started != nil }
        return practice.before.isEmpty || filled
    }

    @ViewBuilder var timer: some View {
        VStack(spacing: 14) {
            if practice == .focus && started == nil {
                Picker("Length", selection: $focusMinutes) {
                    Text("25 MIN").tag(25)
                    Text("50 MIN").tag(50)
                }
                .pickerStyle(.segmented)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let e = elapsed(ctx.date)
                let total = Double(target * 60)
                VStack(spacing: 12) {
                    if practice == .breath { BreathPacer(running: started != nil && stopped == nil) }
                    Text(Fmt.mmss(Int(max(0, total - e))))
                        .font(Theme.mono(40, .heavy)).foregroundStyle(e >= total ? Theme.green : Theme.text)
                        .glow(e >= total ? Theme.green : Theme.violet, radius: 6)
                        .monospacedDigit()
                    SystemBar(value: min(1, e / max(1, total)), color: e >= total ? Theme.green : Theme.violet, height: 5)
                    if e >= total, started != nil {
                        Text(practice == .focus ? "GATE CLEARED. Write where to resume, then complete." : "TIME. Complete when ready.")
                            .font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                    }
                }
            }
            HStack(spacing: 10) {
                if started == nil {
                    Button(practice == .focus ? "ENTER THE GATE" : "BEGIN") {
                        started = .now
                        UIApplication.shared.isIdleTimerDisabled = true
                        Haptics.impact()
                    }
                    .buttonStyle(.system(Theme.violet, filled: true))
                } else if stopped == nil {
                    Button("STOP") {
                        stopped = elapsed(.now)
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                    .buttonStyle(.system(Theme.dim))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .systemPanel(Theme.violet)
    }

    func complete() {
        let mins = timed ? max(1, Int((elapsed(.now) / 60).rounded())) : 5
        let entries = keep ? (fields + afterFields).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } : []
        store.logPractice(practice, minutes: mins, entries: entries,
                          feelingBefore: practice.ratesFeeling ? Int(before) : -1,
                          feelingAfter: practice.ratesFeeling ? Int(after) : -1)
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.success()
        dismiss()
    }

    func binding(_ i: Int, in arr: Binding<[String]>) -> Binding<String> {
        Binding(get: { i < arr.wrappedValue.count ? arr.wrappedValue[i] : "" },
                set: { if i < arr.wrappedValue.count { arr.wrappedValue[i] = $0 } })
    }

    func field(_ label: String, text: Binding<String>, tall: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
            TextField("", text: text, axis: .vertical)
                .lineLimit(tall ? 3...10 : 1...4)
                .font(.system(size: 14))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bg.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.violet.opacity(0.45)))
        }
    }

    func rating(_ label: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(label).font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim).frame(width: 120, alignment: .leading)
            Slider(value: v, in: 0...10, step: 1).tint(Theme.violet)
            Text("\(Int(v.wrappedValue))").font(Theme.mono(14, .bold)).foregroundStyle(Theme.text).frame(width: 28)
        }
    }
}

/// Six breaths a minute: five seconds in, five seconds out.
struct BreathPacer: View {
    var running: Bool
    @State private var origin = Date()

    var body: some View {
        TimelineView(.animation(paused: !running)) { ctx in
            let t = ctx.date.timeIntervalSince(origin).truncatingRemainder(dividingBy: 10)
            let inhale = t < 5
            let x = inhale ? t / 5 : 1 - (t - 5) / 5
            let s = 0.45 + 0.55 * (0.5 - 0.5 * cos(x * .pi))
            ZStack {
                Circle().stroke(Theme.violet.opacity(0.25), lineWidth: 1).frame(width: 170, height: 170)
                Circle()
                    .fill(RadialGradient(colors: [Theme.cyan.opacity(0.55), Theme.violet.opacity(0.25), .clear],
                                         center: .center, startRadius: 4, endRadius: 85))
                    .frame(width: 170, height: 170)
                    .scaleEffect(s)
                    .glow(Theme.violet, radius: 10)
                Text(running ? (inhale ? "IN" : "OUT") : "READY")
                    .font(Theme.mono(15, .heavy)).foregroundStyle(Theme.text)
            }
            .frame(height: 180)
        }
        .onChange(of: running) { _, on in if on { origin = .now } }
    }
}

// MARK: - Support

/// Shown on the Daily board when the morning status suggests a hard stretch.
/// Deliberately not a quest: no XP, no timer, no streak.
struct SupportCard: View {
    @Environment(SystemStore.self) private var store
    let signal: SupportSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BracketHeader(title: heading, color: Theme.cyan, size: 12)
            ForEach(lines, id: \.self) { l in
                Text(l).font(.system(size: 13.5)).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !store.supportPhone.isEmpty, let url = URL(string: "tel:\(store.supportPhone)") {
                    Link(destination: url) { Text("CALL \(store.supportName.isEmpty ? "CONTACT" : store.supportName.uppercased())") }
                        .buttonStyle(.system(Theme.cyan, filled: true))
                }
                if let url = URL(string: "https://findahelpline.com") {
                    Link(destination: url) { Text("FIND A HELPLINE") }
                        .buttonStyle(.system(Theme.cyan))
                }
            }
            Text("If you are in danger or thinking of harming yourself, call your local emergency number now.")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .systemPanel(Theme.cyan)
    }

    var heading: String {
        if case .elevatedShortSleep = signal { return "Pattern Notice" }
        return "Status Check"
    }

    var lines: [String] {
        switch signal {
        case .veryLowToday:
            return ["Today's status was very low. That matters more than any quest.",
                    "Nothing here is required today. If you can, reach out to someone, eat something and get some daylight."]
        case .lowStretch(let n):
            return ["Low mood on \(n) of your last 5 check-ins.",
                    "Stretches like this pass faster with company. Consider telling someone you trust or speaking to a doctor or counsellor. Missed quests on low days cost nothing."]
        case .elevatedShortSleep(let n):
            return ["Very high mood with under 6 h sleep on \(n) of the last 4 days.",
                    "If this pattern is familiar, protect sleep tonight and consider checking in with your care plan or someone you trust."]
        }
    }
}
