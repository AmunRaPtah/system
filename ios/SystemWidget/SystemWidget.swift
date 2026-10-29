import WidgetKit
import SwiftUI

// Palette mirrored from the app's Theme (the widget does not compile Theme.swift).
private enum W {
    static let bg = Color(red: 5 / 255, green: 11 / 255, blue: 24 / 255)
    static let bg2 = Color(red: 10 / 255, green: 22 / 255, blue: 48 / 255)
    static let blue = Color(red: 59 / 255, green: 167 / 255, blue: 1)
    static let cyan = Color(red: 92 / 255, green: 225 / 255, blue: 1)
    static let text = Color(red: 214 / 255, green: 233 / 255, blue: 1)
    static let dim = Color(red: 122 / 255, green: 147 / 255, blue: 181 / 255)
    static let red = Color(red: 1, green: 77 / 255, blue: 109 / 255)
    static let gold = Color(red: 1, green: 209 / 255, blue: 102 / 255)
    static let green = Color(red: 77 / 255, green: 1, blue: 184 / 255)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snap: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, snap: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }

    /// The app reloads timelines whenever its state changes; the timeline itself
    /// only has to flip the evening warning on and roll over at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let midnight = cal.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        var dates = [now]
        if let s = snap, let warn = cal.date(byAdding: .minute, value: s.eveningMinutes, to: start), warn > now {
            dates.append(warn)
        }
        dates.append(midnight)
        let entries = dates.map { StatusEntry(date: $0, snap: snap) }
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(3600))))
    }
}

/// What the widget shows at a given moment, derived from the snapshot.
struct StatusModel {
    var snap: WidgetSnapshot
    var stale: Bool
    var warning: Bool

    init?(_ entry: StatusEntry) {
        guard let s = entry.snap else { return nil }
        snap = s
        stale = s.dayKey != WidgetSnapshot.dayKey(entry.date)
        let cal = Calendar.current
        let minutes = cal.component(.hour, from: entry.date) * 60 + cal.component(.minute, from: entry.date)
        warning = !stale && !s.deload && !s.complete && s.total > 0 && minutes >= s.eveningMinutes
    }

    var progress: Double { stale || snap.total == 0 ? 0 : Double(snap.done) / Double(snap.total) }
    var countText: String { stale ? "--" : "\(snap.done)/\(snap.total)" }
    var accent: Color { warning || (!stale && snap.penaltyPending) ? W.red : (!stale && snap.complete ? W.green : W.cyan) }
}

// MARK: - Views

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    WidgetPanelBackground(color: StatusModel(entry)?.accent ?? W.blue)
                }
            }
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    @ViewBuilder private var content: some View {
        if let m = StatusModel(entry) {
            switch family {
            case .accessoryCircular: CircularView(m: m)
            case .accessoryRectangular: RectangularView(m: m)
            case .accessoryInline: Text("DAILY \(m.countText) · Lv \(m.snap.level)")
            case .systemMedium: MediumView(m: m)
            default: SmallView(m: m)
            }
        } else {
            EmptyStateView(compact: isAccessory)
        }
    }
}

struct WidgetPanelBackground: View {
    var color: Color
    var body: some View {
        ZStack {
            LinearGradient(colors: [W.bg2, W.bg, W.bg], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var p = Path()
                var y: CGFloat = 0
                while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
                ctx.fill(p, with: .color(.white.opacity(0.04)))
            }
            RadialGradient(colors: [W.blue.opacity(0.18), .clear], center: .top, startRadius: 4, endRadius: 220)
            ContainerRelativeShape()
                .inset(by: 4)
                .stroke(color.opacity(0.85), lineWidth: 1)
                .shadow(color: color.opacity(0.9), radius: 4)
        }
    }
}

struct Header: View {
    var body: some View {
        Text("[ SYSTEM ]")
            .font(W.mono(10, .bold)).tracking(1.5)
            .foregroundStyle(W.cyan)
            .shadow(color: W.cyan.opacity(0.9), radius: 3)
    }
}

struct Bar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(W.blue.opacity(0.18))
                Capsule().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
                    .shadow(color: color, radius: 3)
            }
        }
        .frame(height: 4)
    }
}

struct SmallView: View {
    let m: StatusModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Header()
                Spacer()
                Text("\(m.snap.rank)").font(W.mono(13, .heavy)).foregroundStyle(W.gold)
            }
            Text("Lv. \(m.snap.level)").font(W.mono(15, .heavy)).foregroundStyle(W.text)
            Spacer(minLength: 0)
            Text("DAILY QUEST").font(W.mono(9)).foregroundStyle(W.dim)
            Text(m.countText).font(W.mono(26, .heavy)).foregroundStyle(m.accent)
                .shadow(color: m.accent.opacity(0.8), radius: 4)
            Bar(value: m.progress, color: m.accent)
            StatusLine(m: m)
        }
    }
}

struct StatusLine: View {
    let m: StatusModel
    var body: some View {
        Group {
            if m.stale {
                Text("NEW DAY · OPEN").foregroundStyle(W.cyan)
            } else if m.snap.penaltyPending {
                Text("PENALTY ACTIVE").foregroundStyle(W.red)
            } else if m.warning {
                Text("⚠ PENALTY AT 00:00").foregroundStyle(W.red)
            } else if m.snap.complete {
                Text("CLEARED · \(m.snap.streak)d").foregroundStyle(W.green)
            } else {
                Text("STREAK \(m.snap.streak)d").foregroundStyle(m.snap.streak > 0 ? W.cyan : W.dim)
            }
        }
        .font(W.mono(9, .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct MediumView: View {
    let m: StatusModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SmallView(m: m).frame(maxWidth: 130)
            Rectangle().fill(W.blue.opacity(0.4)).frame(width: 1)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(m.snap.rank)-RANK · \(m.snap.rankTitle.uppercased())")
                    .font(W.mono(9, .bold)).foregroundStyle(W.gold).lineLimit(1)
                Bar(value: Double(m.snap.xpInto) / Double(max(1, m.snap.xpSpan)), color: W.blue)
                Text("XP \(m.snap.xpInto)/\(m.snap.xpSpan)").font(W.mono(9)).foregroundStyle(W.dim)
                if m.warning {
                    Text("WARNING: Daily Quest incomplete. Failure to complete it will result in a penalty.")
                        .font(W.mono(9, .bold)).foregroundStyle(W.red).lineLimit(3)
                } else if m.stale {
                    Text("A new day has begun. Open the System to receive today's quests.")
                        .font(W.mono(9)).foregroundStyle(W.text).lineLimit(3)
                }
                if !m.stale {
                    ForEach(Array(m.snap.pending.prefix(m.warning ? 1 : 3).enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 4) {
                            Image(systemName: "square").font(.system(size: 8)).foregroundStyle(W.cyan)
                            Text(t).font(W.mono(10)).foregroundStyle(W.text).lineLimit(1)
                        }
                    }
                    if m.snap.complete {
                        Text("All dailies cleared.").font(W.mono(10, .bold)).foregroundStyle(W.green)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct CircularView: View {
    let m: StatusModel
    var body: some View {
        Gauge(value: m.progress) {
            Text("Q")
        } currentValueLabel: {
            Text(m.countText).font(W.mono(12, .bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

struct RectangularView: View {
    let m: StatusModel
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SYSTEM · Lv \(m.snap.level) \(m.snap.rank)").font(W.mono(11, .bold)).widgetAccentable()
            Text("DAILY \(m.countText) · \(m.snap.streak)d").font(W.mono(12, .heavy))
            if m.warning || (!m.stale && m.snap.penaltyPending) {
                Text(m.snap.penaltyPending ? "PENALTY ACTIVE" : "PENALTY AT 00:00").font(W.mono(10, .bold))
            } else if m.stale {
                Text("New day: open").font(W.mono(10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    var compact: Bool
    var body: some View {
        if compact {
            Text("SYSTEM").font(W.mono(11, .bold))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Header()
                Spacer(minLength: 0)
                Text("Open the System to sync your status.")
                    .font(W.mono(11)).foregroundStyle(W.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget

struct SystemStatusWidget: Widget {
    let kind = "SystemStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("System Status")
        .description("Daily quests, streak, level and penalty warnings.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SystemWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemStatusWidget()
    }
}
