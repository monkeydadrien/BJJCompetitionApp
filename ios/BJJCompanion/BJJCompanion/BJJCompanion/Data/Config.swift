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
    /// Release builds hit the Fly.io-hosted proxy via the Pinnacle AppDev
    /// custom domain (TLS via Let's Encrypt, backed by `bjj-companion-proxy`).
    #if DEBUG
    static let proxyBaseURL = URL(string: "http://localhost:8000")!
    #else
    static let proxyBaseURL = URL(string: "https://api.pinnacleapp.dev")!
    #endif

    /// Refresh if cached data is older than this
    static let staleDuration: TimeInterval = 20 * 60 * 60  // 20 hours

    /// Sentry DSN (write-only client telemetry key — safe to commit).
    /// Crash reporting is gated to release builds only; debug builds stay silent.
    static let sentryDSN = "https://949b2d2da956630dbb940ff9f200afc5@o4511258629636096.ingest.us.sentry.io/4511258632650757"
}
