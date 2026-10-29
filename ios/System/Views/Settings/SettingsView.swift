import SwiftUI

struct SettingsView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var morning = Date()
    @State private var evening = Date()
    @State private var start = Date()
    @State private var confirmReset = false
    @State private var loaded = false
    @State private var replayAwakening = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    DatePicker("Morning brief", selection: $morning, displayedComponents: .hourAndMinute)
                    DatePicker("Evening warning", selection: $evening, displayedComponents: .hourAndMinute)
                    Text("A penalty notice fires the morning after a missed day.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Section("Programme") {
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                    let pos = store.position(DayKey.today)
                    Text("Week \(pos.week) · day \(pos.dayInWeek + 1)\(pos.isDeload ? " · deload" : "")")
                        .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                }
                HealthSettingsSection()
                Section("Content") {
                    let status = ContentLibrary.shared.status
                    ForEach(status.keys.sorted(), id: \.self) { k in
                        HStack {
                            Text(k).font(Theme.mono(12))
                            Spacer()
                            Text(status[k] ?? "").font(Theme.mono(11)).foregroundStyle(Theme.dim).multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Player") {
                    Button("Replay the Awakening") { replayAwakening = true }
                }
                Section {
                    Button("Reset all progress", role: .destructive) { confirmReset = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SystemBackground())
            .navigationTitle("[SETTINGS]")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .confirmationDialog("Erase every quest, log and XP point?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    store.resetAll()
                    Haptics.heavy()
                    dismiss()
                }
            }
            .onAppear(perform: load)
            // The Awakening can move the start date; keep Done from reverting it.
            .fullScreenCover(isPresented: $replayAwakening, onDismiss: { start = DayKey.date(store.startKey) }) {
                AwakeningView(replay: true)
            }
        }
        .preferredColorScheme(.dark)
    }

    func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func date(_ minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        let d = UserDefaults.standard
        morning = date(d.integer(forKey: DefaultsKey.morning))
        evening = date(d.integer(forKey: DefaultsKey.evening))
        start = DayKey.date(store.startKey)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(minutes(morning), forKey: DefaultsKey.morning)
        d.set(minutes(evening), forKey: DefaultsKey.evening)
        if DayKey.key(start) != store.startKey { store.setStart(start) }
        store.reschedule()
    }
}
