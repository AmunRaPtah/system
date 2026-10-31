import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let bg = Color(hex: 0x050B18)
    static let bg2 = Color(hex: 0x0A1630)
    static let panel = Color(hex: 0x0B1A3A, alpha: 0.78)
    static let blue = Color(hex: 0x3BA7FF)
    static let cyan = Color(hex: 0x5CE1FF)
    static let text = Color(hex: 0xD6E9FF)
    static let dim = Color(hex: 0x7A93B5)
    static let red = Color(hex: 0xFF4D6D)
    static let gold = Color(hex: 0xFFD166)
    static let green = Color(hex: 0x4DFFB8)
    static let violet = Color(hex: 0xA78BFA)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(_ p: Pillar) -> Color {
        switch p {
        case .body: return red
        case .mind: return cyan
        case .social: return gold
        case .sovereign: return violet
        }
    }

    static func color(_ s: SystemAlert.Style) -> Color {
        switch s {
        case .quest, .info: return cyan
        case .levelUp: return gold
        case .rankUp, .arise: return violet
        case .penalty: return red
        case .achievement: return green
        }
    }
}

/// Horizontal scanlines, drawn once per panel.
struct Scanlines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.035
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(opacity)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deep-navy void with a faint perspective grid, a gate glow at the top and
/// slow-rising mana motes.
struct SystemBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg2, Theme.bg, Color(hex: 0x03060F)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let step: CGFloat = 32
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(Theme.blue.opacity(0.045)), lineWidth: 0.5)
            }
            .mask(LinearGradient(colors: [.black, .black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [Theme.blue.opacity(0.22), Theme.violet.opacity(0.05), .clear],
                           center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 460)
            ManaMotes()
        }
        .ignoresSafeArea()
    }
}

/// A few dozen points of light drifting upward. Positions are a pure function of
/// time, so there is no state to keep and nothing to animate between.
struct ManaMotes: View {
    var count = 28
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let fx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let speed = 8 + abs(fx) * 14
                    let phase = (t * speed / Double(size.height) + abs(fx) * 7).truncatingRemainder(dividingBy: 1)
                    let x = abs(fx) * size.width + sin(t * 0.4 + seed) * 12
                    let y = size.height * (1 - phase)
                    let r = 0.8 + abs(fx) * 1.6
                    let a = sin(phase * .pi) * (0.25 + abs(fx) * 0.35)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 2, dy: -r * 2)), with: .color(Theme.cyan.opacity(a * 0.15)))
                    ctx.fill(Path(ellipseIn: rect), with: .color(Theme.cyan.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A rectangle with its corners cut at 45 degrees: the game-UI silhouette used
/// for buttons and tags.
struct Chamfer: Shape {
    var cut: CGFloat = 6
    func path(in r: CGRect) -> Path {
        let c = min(cut, r.height / 2, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

/// The System window look: a translucent pane lit from above, a bright edge that
/// fades down the sides, a glowing top rule and corner brackets.
struct SystemPanel: ViewModifier {
    var color: Color = Theme.blue
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [Color(hex: 0x10244C, alpha: 0.86), Color(hex: 0x081430, alpha: 0.9)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.fill(LinearGradient(colors: [color.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                    Scanlines().clipShape(shape)
                }
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [color, color.opacity(0.35), color.opacity(0.6)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                LinearGradient(colors: [.clear, color, .white.opacity(0.9), color, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1.5)
                    .padding(.horizontal, 18)
                    .shadow(color: color, radius: 4)
                    .allowsHitTesting(false)
            }
            .overlay(CornerTicks(color: color))
            .shadow(color: color.opacity(0.22), radius: 10)
    }
}

struct CornerTicks: View {
    var color: Color
    var body: some View {
        GeometryReader { g in
            let l: CGFloat = 9
            Path { p in
                let w = g.size.width, h = g.size.height
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square))
            .shadow(color: color, radius: 3)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func systemPanel(_ color: Color = Theme.blue, padding: CGFloat = 14) -> some View {
        modifier(SystemPanel(color: color, padding: padding))
    }

    func glow(_ color: Color = Theme.cyan, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.9), radius: radius)
    }

    /// Standard screen chrome: grid background, dark nav bar.
    func systemScreen(_ title: String) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SystemBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// "[ TITLE ]" header with a fading rule after it.
struct BracketHeader: View {
    var title: String
    var color: Color = Theme.cyan
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 8) {
            Text("[ \(title.uppercased()) ]")
                .font(Theme.mono(size, .bold))
                .foregroundStyle(color)
                .glow(color, radius: 4)
                .tracking(1.5)
                .fixedSize()
            LinearGradient(colors: [color.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }
}

/// The canon window title: a boxed "!" and the window name in a framed plate.
struct SystemWindowTitle: View {
    var title: String
    var color: Color = Theme.cyan
    var symbol = "exclamationmark"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1.5))
                .glow(color, radius: 4)
            Text(title.uppercased())
                .font(Theme.mono(12, .bold)).tracking(3)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.8), lineWidth: 1))
                .glow(color, radius: 3)
        }
    }
}

/// A gauge with a glowing head and faint segment ticks.
struct SystemBar: View {
    var value: Double
    var color: Color = Theme.cyan
    var height: CGFloat = 6
    var segments = 20
    var body: some View {
        GeometryReader { g in
            let v = max(0, min(1, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.35))
                Capsule().stroke(color.opacity(0.18), lineWidth: 0.5)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.45), color, .white.opacity(0.95)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: v * g.size.width)
                    .shadow(color: color, radius: 4)
                if height >= 5 {
                    Path { p in
                        for i in 1..<segments {
                            let x = g.size.width * CGFloat(i) / CGFloat(segments)
                            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: height))
                        }
                    }
                    .stroke(Theme.bg.opacity(0.55), lineWidth: 1)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.6), value: value)
    }
}

struct SystemButtonStyle: ButtonStyle {
    var color: Color = Theme.cyan
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = Chamfer(cut: 7)
        configuration.label
            .font(Theme.mono(13, .bold))
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(filled ? Theme.bg : color)
            .background(
                shape.fill(filled
                           ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.04)], startPoint: .top, endPoint: .bottom)))
            )
            .overlay(shape.stroke(color, lineWidth: 1))
            .shadow(color: color.opacity(configuration.isPressed ? 0.9 : 0.35), radius: configuration.isPressed ? 12 : 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SystemButtonStyle {
    static var system: SystemButtonStyle { SystemButtonStyle() }
    static func system(_ color: Color, filled: Bool = false) -> SystemButtonStyle {
        SystemButtonStyle(color: color, filled: filled)
    }
}

struct Tag: View {
    var text: String
    var color: Color = Theme.cyan
    var body: some View {
        Text(text)
            .font(Theme.mono(10, .bold))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Chamfer(cut: 4).fill(color.opacity(0.12)))
            .overlay(Chamfer(cut: 4).stroke(color.opacity(0.75), lineWidth: 1))
    }
}

/// Stat-style readout: a dim label over a bright value.
struct Readout: View {
    var label: String
    var value: String
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.mono(9, .bold)).tracking(1).foregroundStyle(Theme.dim)
            Text(value).font(Theme.mono(15, .heavy)).foregroundStyle(color).glow(color, radius: 3)
        }
    }
}
