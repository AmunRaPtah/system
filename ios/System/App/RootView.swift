import SwiftUI

struct RootView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var awakening = false

    var body: some View {
        ZStack {
            TabView {
                QuestsView(showSettings: $showSettings)
                    .tabItem { Label("Quests", systemImage: "scroll.fill") }
                TrainView()
                    .tabItem { Label("Train", systemImage: "figure.run") }
                MindView()
                    .tabItem { Label("Mind", systemImage: "brain.head.profile") }
                StatsView()
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
            if store.needsAwakening() { awakening = true } else { store.requestNotificationsIfNeeded() }
            store.tick()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.tick() }
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

    var color: Color { Theme.color(alert.style) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color).glow(color)
                    Text("NOTIFICATION").font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim).tracking(2)
                }
                Text(alert.title)
                    .font(Theme.mono(alert.style == .levelUp || alert.style == .rankUp ? 26 : 20, .heavy))
                    .foregroundStyle(color)
                    .glow(color, radius: 10)
                    .multilineTextAlignment(.center)
                Rectangle().fill(color.opacity(0.6)).frame(height: 1).glow(color, radius: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(alert.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("CONFIRM") { Haptics.tap(); dismiss() }
                    .buttonStyle(.system(color))
                    .padding(.top, 4)
            }
            .systemPanel(color, padding: 20)
            .padding(28)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { appeared = true }
            switch alert.style {
            case .quest: Haptics.success()
            case .levelUp, .rankUp: Haptics.levelUp()
            case .penalty: Haptics.error()
            case .info: Haptics.impact()
            case .achievement: Haptics.levelUp()
            }
        }
    }

    var icon: String {
        switch alert.style {
        case .quest: return "checkmark.seal.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .rankUp: return "crown.fill"
        case .penalty: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .achievement: return "rosette"
        }
    }
}
