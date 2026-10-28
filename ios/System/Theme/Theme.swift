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
        case .rankUp: return violet
        case .penalty: return red
        }
    }
}

/// Horizontal scanlines, drawn once per panel.
struct Scanlines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.06
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

/// Deep-navy background with a faint grid and glow.
struct SystemBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg2, Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let step: CGFloat = 28
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(Theme.blue.opacity(0.05)), lineWidth: 0.5)
            }
            RadialGradient(colors: [Theme.blue.opacity(0.12), .clear], center: .top, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// The System window look: translucent navy, glowing border, scanlines.
struct SystemPanel: ViewModifier {
    var color: Color = Theme.blue
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 6).fill(Theme.panel)
                    Scanlines().clipShape(RoundedRectangle(cornerRadius: 6))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.85), lineWidth: 1)
                    .shadow(color: color.opacity(0.9), radius: 6)
            )
            .overlay(CornerTicks(color: color))
            .shadow(color: color.opacity(0.25), radius: 12)
    }
}

struct CornerTicks: View {
    var color: Color
    var body: some View {
        GeometryReader { g in
            let l: CGFloat = 10
            Path { p in
                let w = g.size.width, h = g.size.height
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(color, lineWidth: 2)
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

/// "[ TITLE ]" monospace header.
struct BracketHeader: View {
    var title: String
    var color: Color = Theme.cyan
    var size: CGFloat = 13
    var body: some View {
        Text("[ \(title.uppercased()) ]")
            .font(Theme.mono(size, .bold))
            .foregroundStyle(color)
            .glow(color, radius: 4)
            .tracking(1.5)
    }
}

struct SystemBar: View {
    var value: Double
    var color: Color = Theme.cyan
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.blue.opacity(0.15))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * g.size.width)
                    .shadow(color: color, radius: 4)
            }
        }
        .frame(height: height)
    }
}

struct SystemButtonStyle: ButtonStyle {
    var color: Color = Theme.cyan
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(13, .bold))
            .tracking(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(filled ? Theme.bg : color)
            .background(RoundedRectangle(cornerRadius: 4).fill(filled ? color : color.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
            .shadow(color: color.opacity(configuration.isPressed ? 1 : 0.5), radius: configuration.isPressed ? 10 : 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7), lineWidth: 1))
    }
}
