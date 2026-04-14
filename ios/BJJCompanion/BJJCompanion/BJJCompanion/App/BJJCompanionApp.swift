import SwiftUI

@main
struct BJJCompanionApp: App {

    @State private var eventsRepo     = EventsRepository()
    @State private var bracketRepo    = BracketRepository()
    @State private var athletesRepo   = AthletesRepository()
    @State private var divisionsStore = DivisionsStore()
    @State private var trackingStore  = TrackingStore()

    init() {
        configureNavigationBar()
        configureTabBar()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(eventsRepo)
                .environment(bracketRepo)
                .environment(athletesRepo)
                .environment(divisionsStore)
                .environment(trackingStore)
                .task { await eventsRepo.loadIfNeeded() }
                .task { await athletesRepo.loadIfNeeded() }
        }
    }

    // MARK: - UIKit global appearance

    private func configureNavigationBar() {
        // Use explicit UIColor to avoid SwiftUI Color conversion timing issues
        let bg   = UIColor(red: 0.031, green: 0.047, blue: 0.063, alpha: 1) // #080C10
        let gold = UIColor(red: 0.227, green: 0.557, blue: 1.000, alpha: 1) // #3A8EFF

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().tintColor            = gold
    }

    private func configureTabBar() {
        let bg = UIColor(red: 0.031, green: 0.047, blue: 0.063, alpha: 1) // #080C10

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.shadowColor = .clear

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
