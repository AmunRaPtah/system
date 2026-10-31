import SwiftUI

/// The Shadow Army: one shadow per sustained habit, graded by how far past the
/// extraction threshold the habit has gone.
struct ShadowArmyView: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        let have = store.extractedShadowIDs()
        let progress = store.shadowProgress()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    BracketHeader(title: "Shadow Army", color: Theme.violet)
                    Text("\(have.count)/\(Shadow.all.count) EXTRACTED · JOB \(store.job.uppercased())")
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim)
                    Text("A shadow rises when a habit has been kept long enough to stand on its own. It grows in grade as the habit continues.")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                }
                .systemPanel(Theme.violet)

                ForEach(Shadow.all) { s in
                    card(s, extracted: have.contains(s.id), value: progress[s.id] ?? 0)
                }
            }
            .padding()
        }
        .systemScreen("SHADOWS")
    }

    func card(_ s: Shadow, extracted: Bool, value: Int) -> some View {
        let grade = ShadowGrade.grade(progress: value, threshold: s.threshold)
        let nextMultiple = ShadowGrade.multiples.first { value < $0 * s.threshold }
        let goal = (nextMultiple ?? ShadowGrade.multiples.last ?? 1) * s.threshold
        let color = extracted ? Theme.violet : Theme.dim
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: s.symbol).foregroundStyle(color).glow(color, radius: extracted ? 6 : 0)
                Text(extracted ? s.name.uppercased() : "???").font(Theme.mono(15, .heavy)).foregroundStyle(extracted ? Theme.text : Theme.dim)
                Spacer()
                Tag(text: grade?.title.uppercased() ?? "DORMANT", color: color)
                Tag(text: s.stat.rawValue, color: Theme.dim)
            }
            if extracted {
                Text(s.epithet.capitalized).font(Theme.mono(11)).foregroundStyle(Theme.violet)
                Text(s.lore).font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            Text("\(s.habit): \(value) \(s.unit)").font(Theme.mono(11)).foregroundStyle(Theme.text)
            SystemBar(value: Double(value) / Double(max(1, goal)), color: color, height: 4)
            Text(nextMultiple == nil ? "Highest grade reached."
                 : (extracted ? "Next grade at \(goal) \(s.unit)." : "Extraction at \(s.threshold) \(s.unit)."))
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .systemPanel(color)
    }
}
