import SwiftUI

struct RootView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var awakening = false
    @State private var tab = DemoMode.tab

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                QuestsView(showSettings: $showSettings)
                    .tag(0)
                    .tabItem { Label("Quests", systemImage: "scroll.fill") }
                TrainView()
                    .tag(1)
                    .tabItem { Label("Train", systemImage: "figure.run") }
                MindView()
                    .tag(2)
                    .tabItem { Label("Mind", systemImage: "brain.head.profile") }
                StatsView()
                    .tag(3)
                    .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            }
            if let alert = store.alerts.first {
                SystemAlertOverlay(alert: alert) {
                    if !store.alerts.isEmpty { store.alerts.removeFirst() }
                }
                .id(alert.id)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.22), value: store.alerts.first?.id)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $awakening) { AwakeningView() }
        .onAppear {
            // A fresh install asks for notifications inside the Awakening instead.
            if DemoMode.isOn { return }
            if store.needsAwakening() { awakening = true } else { store.requestNotificationsIfNeeded() }
            if !DemoMode.isOn { store.tick() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !DemoMode.isOn { store.tick() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.tick()
        }
    }
}

/// The centred System window shown on quest completion, level-up, penalties.
struct SystemAlertOverlay: View {
    let alert: SystemAlert
    var dismiss: () -> Void
    @State private var appeared = false
    @State private var shown = 0

    var big: Bool { alert.style == .levelUp || alert.style == .rankUp || alert.style == .arise }

    var color: Color { Theme.color(alert.style) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 16) {
                SystemWindowTitle(title: "Notification", color: color, symbol: icon)
                Text(alert.title)
                    .font(Theme.mono(big ? 28 : 20, .heavy))
                    .tracking(big ? 4 : 1)
                    .foregroundStyle(big ? Theme.text : color)
                    .shadow(color: color, radius: 10)
                    .shadow(color: color.opacity(0.6), radius: 24)
                    .multilineTextAlignment(.center)
                    .scaleEffect(appeared ? 1 : 1.25)
                LinearGradient(colors: [.clear, color, .white, color, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1).glow(color, radius: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(alert.lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(shown > i ? 1 : 0)
                            .offset(x: shown > i ? 0 : -8)
                    }
                }
                Button("CONFIRM") { Haptics.tap(); dismiss() }
                    .buttonStyle(.system(color))
                    .padding(.top, 4)
            }
            .systemPanel(color, padding: 20)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18)).blur(radius: 30)
                    .scaleEffect(appeared ? 1.08 : 0.8)
            )
            .padding(28)
            .scaleEffect(x: appeared ? 1 : 0.7, y: appeared ? 1 : 0.02)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { appeared = true }
            for i in alert.lines.indices {
                withAnimation(.easeOut(duration: 0.25).delay(0.25 + Double(i) * 0.12)) { shown = i + 1 }
            }
            switch alert.style {
            case .quest: Haptics.success()
            case .levelUp, .rankUp: Haptics.levelUp()
            case .penalty: Haptics.error()
            case .info: Haptics.impact()
            case .achievement, .arise: Haptics.levelUp()
            }
        }
    }

    var icon: String {
        switch alert.style {
        case .quest: return "checkmark"
        case .levelUp: return "arrow.up"
        case .rankUp: return "crown"
        case .penalty: return "exclamationmark.triangle"
        case .info: return "exclamationmark"
        case .achievement: return "rosette"
        case .arise: return "moon.stars"
        }
    }
}
