import SwiftUI
import SwiftData

@main
struct SystemApp: App {
    let container: ModelContainer
    @State private var store: SystemStore

    init() {
        let schema = Schema(Schema_.models)
        let c: ModelContainer
        do {
            c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            // Never brick the app on a store problem: fall back to memory.
            c = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        container = c
        _store = State(initialValue: SystemStore(context: c.mainContext))

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 5 / 255, green: 11 / 255, blue: 24 / 255, alpha: 1)
        tab.shadowColor = UIColor(red: 59 / 255, green: 167 / 255, blue: 1, alpha: 0.5)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 5 / 255, green: 11 / 255, blue: 24 / 255, alpha: 1)
        let mono = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        nav.titleTextAttributes = [.foregroundColor: UIColor(red: 92 / 255, green: 225 / 255, blue: 1, alpha: 1), .font: mono]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
        .modelContainer(container)
    }
}
