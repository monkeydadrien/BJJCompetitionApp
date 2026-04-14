import Foundation

enum Config {
    /// Published events.json from GitHub Pages (updated daily by GitHub Actions)
    static let eventsURL = URL(string: "https://monkeydadrien.github.io/BJJCompetitionApp/events.json")!

    /// Published athletes.json from GitHub Pages (updated monthly)
    static let athletesURL = URL(string: "https://monkeydadrien.github.io/BJJCompetitionApp/athletes.json")!

    /// On-demand bracket proxy (run locally or deploy to Fly.io)
    static let proxyBaseURL = URL(string: "http://localhost:8000")!

    /// Refresh if cached data is older than this
    static let staleDuration: TimeInterval = 20 * 60 * 60  // 20 hours
}
