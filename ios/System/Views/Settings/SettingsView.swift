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
                VowSettingsSection()
                Section {
                    Toggle("Eye-pressure precautions", isOn: Binding(
                        get: { store.eyePrecautions },
                        set: { store.setEyePrecautions($0) }))
                } header: {
                    Text("Precautions")
                } footer: {
                    Text("For glaucoma or raised eye pressure. Adds breathing cues to every body quest: exhale on effort, no breath-holding, head above heart. Check with your eye doctor what is safe for you.")
                }
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

/// Choose the vows shown on the Daily board. Stored on this device only.
struct VowSettingsSection: View {
    @Environment(SystemStore.self) private var store
    @State private var custom = ""

    var body: some View {
        Section {
            ForEach(VowPreset.presets) { v in
                Toggle(isOn: Binding(
                    get: { store.activeVowIDs.contains(v.id) },
                    set: { store.setVow(v.id, active: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title)
                        Text(v.detail).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
            TextField("Your own vow", text: $custom)
                .onSubmit(commit)
            Toggle("Use my own vow", isOn: Binding(
                get: { store.activeVowIDs.contains(VowPreset.custom) },
                set: { on in
                    commit()
                    store.setVow(VowPreset.custom, active: on && !store.customVowText.isEmpty)
                }))
        } header: {
            Text("Vows")
        } footer: {
            Text("Mark each vow kept or slipped on the Daily board. A slip never costs XP or the Detoxification skill, only the streak.")
        }
        .onAppear { custom = store.customVowText }
    }

    func commit() { store.setCustomVow(custom) }
}
