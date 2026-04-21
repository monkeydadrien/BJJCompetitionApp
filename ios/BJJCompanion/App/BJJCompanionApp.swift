import SwiftUI
#if canImport(Sentry)
import Sentry
#endif

@main
struct BJJCompanionApp: App {

    @State private var eventsRepo     = EventsRepository()
    @State private var bracketRepo    = BracketRepository()
    @State private var divisionsStore = DivisionsStore()
    @State private var trackingStore  = TrackingStore()
    @State private var athletesRepo   = AthletesRepository()
    @State private var homeCityStore  = HomeCityStore()

    init() {
        configureNavigationBar()
        configureTabBar()
        configureSentry()
    }

    // MARK: - Sentry

    private func configureSentry() {
        #if canImport(Sentry) && !DEBUG
        SentrySDK.start { options in
            options.dsn = Config.sentryDSN

            // Release + environment metadata
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let build   = info["CFBundleVersion"] as? String ?? "0"
            options.releaseName = "bjjcompanion@\(version)+\(build)"
            options.environment = "production"

            // Attach a stack trace to every event, including captured messages
            options.attachStacktrace = true

            // 10% sampling for performance traces — well inside free-tier budget
            options.tracesSampleRate = 0.1
            options.enableAutoPerformanceTracing = true

            // Strip device identifiers we don't need; keep reasonable defaults otherwise
            options.sendDefaultPii = false
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(eventsRepo)
                .environment(bracketRepo)
                .environment(divisionsStore)
                .environment(trackingStore)
                .environment(athletesRepo)
                .environment(homeCityStore)
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
