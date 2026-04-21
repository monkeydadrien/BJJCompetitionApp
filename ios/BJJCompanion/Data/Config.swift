import Foundation

enum Config {
    /// Published events.json from GitHub Pages (updated daily by GitHub Actions)
    static let eventsURL = URL(string: "https://monkeydadrien.github.io/BJJCompetitionApp/events.json")!

    /// Athlete registry (bjjcompsystem-derived). Published manually after a one-off backfill.
    static let athletesURL = URL(string: "https://monkeydadrien.github.io/BJJCompetitionApp/athletes.json")!

    /// On-demand bracket proxy.
    ///
    /// DEBUG builds target a local uvicorn instance for fast iteration:
    ///     cd backend && uvicorn proxy:app --reload --port 8000
    ///
    /// Release builds hit the Fly.io-hosted proxy. Replace the URL below with
    /// your deployed app's URL (from `fly deploy` output) — e.g.
    ///     https://bjj-companion-proxy.fly.dev
    /// Later, swap to a custom domain once certs are issued:
    ///     https://api.yourdomain.com
    #if DEBUG
    static let proxyBaseURL = URL(string: "http://localhost:8000")!
    #else
    static let proxyBaseURL = URL(string: "https://bjj-companion-proxy.fly.dev")!
    #endif

    /// Refresh if cached data is older than this
    static let staleDuration: TimeInterval = 20 * 60 * 60  // 20 hours
}
