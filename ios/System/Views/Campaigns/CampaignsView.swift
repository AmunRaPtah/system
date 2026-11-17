import SwiftUI

/// The War Room: every open campaign, its next gate, days left, whether it moved
/// this week. Stale or paused campaigns are faded.
struct CampaignsView: View {
    @Environment(SystemStore.self) private var store
    @State private var adding = false
    @State private var chooseThree = false
    @State private var suggested = false

    var body: some View {
        let rows = store.warRoom()
        let done = store.campaigns().filter { $0.state == .done }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    BracketHeader(title: "War Room", color: Theme.gold)
                    if rows.isEmpty {
                        Text("No campaigns yet. A campaign is a long arc tied to a real goal; gates are its dated milestones; quests are the actions you write.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                    ForEach(rows) { r in
                        NavigationLink { CampaignDetailView(campaign: r.campaign) } label: { WarRoomCard(row: r) }
                            .buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        Button { adding = true } label: {
                            Label("CAMPAIGN", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.system(Theme.cyan))
                        Button { chooseThree = true } label: {
                            Label("CHOOSE 3", systemImage: "scope").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.system(Theme.gold, filled: store.chooseThreeDue))
                        .disabled(rows.isEmpty)
                    }
                    Button { suggested = true } label: {
                        Label("SUGGESTED GATES", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.system(Theme.violet))
                    if !done.isEmpty {
                        BracketHeader(title: "Completed", color: Theme.dim).padding(.top, 8)
                        ForEach(done) { c in
                            NavigationLink { CampaignDetailView(campaign: c) } label: {
                                Text(c.title).font(Theme.mono(13)).foregroundStyle(Theme.dim)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
            }
            .systemScreen("CAMPAIGNS")
            .sheet(isPresented: $adding) { NewCampaignSheet() }
            .sheet(isPresented: $chooseThree) { ChooseThreeView() }
            .sheet(isPresented: $suggested) { SuggestedGatesSheet() }
        }
    }
}

struct WarRoomCard: View {
    let row: SystemStore.WarRoomRow

    var body: some View {
        let c = row.campaign
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(c.title).font(Theme.mono(15, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                if c.state == .paused { Tag(text: "PAUSED", color: Theme.dim) }
                Tag(text: row.movedThisWeek ? "MOVED" : "STILL", color: row.movedThisWeek ? Theme.green : Theme.red)
            }
            if let g = row.next, let left = row.daysLeft {
                HStack {
                    Image(systemName: "flag.checkered")
                    Text(g.title).lineLimit(1)
                    Spacer()
                    Text(left < 0 ? "\(-left)d OVERDUE" : (left == 0 ? "TODAY" : "\(left)d"))
                        .font(Theme.mono(12, .heavy))
                        .foregroundStyle(left < 0 ? Theme.red : (left <= 7 ? Theme.gold : Theme.cyan))
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dim)
            } else {
                Text("No open gate. Set the next milestone.").font(Theme.mono(11)).foregroundStyle(Theme.gold)
            }
        }
        .systemPanel(row.stale ? Theme.dim : Theme.gold)
        .opacity(row.stale ? 0.4 : 1)
    }
}

struct NewCampaignSheet: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var goal = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Campaign name", text: $title)
                TextField("The real goal it serves", text: $goal)
            }
            .scrollContentBackground(.hidden)
            .background(SystemBackground())
            .navigationTitle("New campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { store.addCampaign(title: title, goal: goal); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Detail

struct CampaignDetailView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let campaign: Campaign
    @State private var gateTitle = ""
    @State private var gateDate = Date().addingTimeInterval(14 * 86_400)
    @State private var questTitle = ""
    @State private var questDomain: Domain = .ambition
    @State private var questGate = ""
    @State private var questToday = true
    @State private var note: String?
    @State private var confirmDelete = false

    var body: some View {
        let id = campaign.uid
        let gates = store.gates(of: id)
        let quests = store.ownerQuests(campaign: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(campaign.title).font(Theme.mono(18, .heavy)).foregroundStyle(Theme.text)
                    if !campaign.goal.isEmpty {
                        Text(campaign.goal).font(.footnote).foregroundStyle(Theme.dim)
                    }
                    Picker("Status", selection: Binding(get: { campaign.state }, set: { store.setStatus(campaign, $0) })) {
                        ForEach(CampaignStatus.allCases, id: \.self) { s in Text(s.rawValue.capitalized).tag(s) }
                    }
                    .pickerStyle(.segmented)
                }
                .systemPanel(Theme.gold)

                VStack(alignment: .leading, spacing: 10) {
                    BracketHeader(title: "Gates", color: Theme.gold)
                    ForEach(gates) { g in
                        let left = DayKey.daysBetween(DayKey.today, g.dateKey)
                        Button { Haptics.tap(); store.toggleGate(g) } label: {
                            HStack {
                                Image(systemName: g.done ? "checkmark.seal.fill" : "seal")
                                    .foregroundStyle(g.done ? Theme.green : Theme.gold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title).font(Theme.mono(13, .bold)).foregroundStyle(g.done ? Theme.dim : Theme.text)
                                        .multilineTextAlignment(.leading)
                                    Text(DayKey.pretty(g.dateKey) + (g.done ? "" : " · \(left)d")
                                         + (g.source.isEmpty ? "" : " · \(g.source)"))
                                        .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete gate", role: .destructive) { store.deleteGate(g) } }
                    }
                    TextField("Next milestone", text: $gateTitle).textFieldStyle(.roundedBorder)
                    HStack {
                        DatePicker("", selection: $gateDate, displayedComponents: .date).labelsHidden()
                        Spacer()
                        Button("ADD GATE") {
                            store.addGate(to: id, title: gateTitle, dateKey: DayKey.key(gateDate))
                            gateTitle = ""
                        }
                        .buttonStyle(.system(Theme.gold))
                        .disabled(gateTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .systemPanel(Theme.gold)

                VStack(alignment: .leading, spacing: 10) {
                    BracketHeader(title: "Quests")
                    ForEach(quests) { q in
                        HStack {
                            Image(systemName: q.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(q.done ? Theme.green : Theme.color(q.dom))
                            Text(q.title).font(Theme.mono(13)).foregroundStyle(q.done ? Theme.dim : Theme.text)
                            Spacer()
                            Text(q.done ? "done" : (q.dayKey.isEmpty ? "backlog" : DayKey.pretty(q.dayKey)))
                                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                        .contextMenu {
                            if !q.done {
                                Button("Do today") {
                                    if !store.schedule(q, on: DayKey.today) {
                                        note = "Today already holds \(Domain.ambitionCap) Ambition quests."
                                    }
                                }
                                Button("Move to backlog") { store.schedule(q, on: "") }
                            }
                            Button("Delete", role: .destructive) { store.deleteOwnerQuest(q) }
                        }
                    }
                    DomainPicker(domain: $questDomain)
                    TextField("One concrete action", text: $questTitle).textFieldStyle(.roundedBorder)
                    if !gates.filter({ !$0.done }).isEmpty {
                        Picker("Gate", selection: $questGate) {
                            Text("No gate").tag("")
                            ForEach(gates.filter { !$0.done }) { g in Text(g.title).tag(g.uid) }
                        }
                    }
                    Toggle("Schedule for today", isOn: $questToday).font(Theme.mono(12))
                    Button {
                        let r = store.addOwnerQuest(title: questTitle, domain: questDomain,
                                                    dayKey: questToday ? DayKey.today : "",
                                                    campaignID: id, gateID: questGate)
                        switch r {
                        case .added: note = nil; questTitle = ""
                        case .backlogged: note = "Today already holds \(Domain.ambitionCap) Ambition quests. Sent to the backlog."; questTitle = ""
                        case .empty: break
                        }
                    } label: {
                        Text("ADD QUEST").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.system(Theme.cyan))
                    .disabled(questTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let note { Text(note).font(Theme.mono(11)).foregroundStyle(Theme.gold) }
                }
                .systemPanel()

                Button("Delete campaign", role: .destructive) { confirmDelete = true }
                    .font(Theme.mono(12))
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .systemScreen("CAMPAIGN")
        .confirmationDialog("Delete this campaign and its gates? Its quests are kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                store.deleteCampaign(campaign)
            }
        }
    }
}

// MARK: - Choose three

/// Sunday ritual: keep up to three campaigns active; the rest are paused.
struct ChooseThreeView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var loaded = false

    var body: some View {
        let open = store.campaigns().filter { $0.state != .done }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick up to three campaigns for the week. The others are paused, not deleted.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                    ForEach(open) { c in
                        let on = picked.contains(c.uid)
                        let full = !on && picked.count >= 3
                        Button {
                            Haptics.tap()
                            if on { picked.remove(c.uid) } else if !full { picked.insert(c.uid) }
                        } label: {
                            HStack {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(Theme.mono(15, .bold))
                                    if let g = store.nextGate(of: c.uid) {
                                        Text("\(g.title) · \(DayKey.pretty(g.dateKey))").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                    }
                                }
                                Spacer()
                            }
                            .foregroundStyle(on ? Theme.gold : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(full ? 0.4 : 1)
                    }
                    Button {
                        Haptics.success()
                        store.chooseThree(picked)
                        dismiss()
                    } label: {
                        Text("COMMIT \(picked.count)/3").font(Theme.mono(16, .heavy)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.system(Theme.gold, filled: true))
                    .disabled(picked.isEmpty)
                }
                .padding()
            }
            .systemScreen("CHOOSE THREE")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            picked = Set(open.filter { $0.state == .active }.prefix(3).map(\.uid))
        }
    }
}

// MARK: - Suggested gates

/// Deadlines parsed by the architect server from the owner's trackers. Each one
/// becomes a gate only when the owner adds it to a campaign.
struct SuggestedGatesSheet: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gates: [SuggestedGate] = []
    @State private var error: String?
    @State private var loading = true
    @State private var target: SuggestedGate?

    var body: some View {
        let accepted = store.acceptedSuggestionIDs()
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Asking architect…").foregroundStyle(Theme.dim) }
                } else if let error {
                    Text(error).foregroundStyle(Theme.red)
                    Text("Campaigns work fully offline; suggestions need the architect server.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                } else if gates.isEmpty {
                    Text("No upcoming deadlines found.").foregroundStyle(Theme.dim)
                }
                ForEach(gates) { g in
                    let taken = accepted.contains(g.id)
                    Button { if !taken { target = g } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(g.title).font(Theme.mono(13, .bold)).foregroundStyle(taken ? Theme.dim : Theme.text)
                                Spacer()
                                if taken { Image(systemName: "checkmark").foregroundStyle(Theme.green) }
                            }
                            Text("\(DayKey.pretty(g.date)) · \(DayKey.daysBetween(DayKey.today, g.date))d · \(g.source)\(g.estimated == true ? " · est." : "")")
                                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SystemBackground())
            .navigationTitle("Suggested gates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Add as a gate to…", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
                                titleVisibility: .visible, presenting: target) { g in
                ForEach(store.campaigns().filter { $0.state != .done }) { c in
                    Button(c.title) { store.addGate(to: c.uid, title: g.title, dateKey: g.date, sourceID: g.id, source: g.source) }
                }
                Button("New campaign: \(String(g.title.prefix(30)))") {
                    if let c = store.addCampaign(title: g.title, goal: g.detail ?? "") {
                        store.addGate(to: c.uid, title: g.title, dateKey: g.date, sourceID: g.id, source: g.source)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @MainActor func load() async {
        loading = true
        defer { loading = false }
        do {
            gates = try await ArchitectClient.shared.fetchSuggestedGates()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
